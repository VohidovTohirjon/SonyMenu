import AppKit
import ApplicationServices
import CoreGraphics
import SwiftUI

/// A headphone gesture the Mac can actually see.
///
/// The WH-1000XM5 turns right-earcup touches into Bluetooth AVRCP commands that macOS
/// delivers as media keys (play/pause, next, previous). The left NC/AMB button changes
/// the mode inside the headphones and they report it over the control channel.
enum Gesture: String, CaseIterable, Identifiable {
    case doubleTap, swipeForward, swipeBackward, leftButton

    var id: String { rawValue }

    var title: String {
        switch self {
        case .doubleTap: return "Right: double tap"
        case .swipeForward: return "Right: swipe forward"
        case .swipeBackward: return "Right: swipe backward"
        case .leftButton: return "Left: NC/AMB button press"
        }
    }

    var detail: String {
        switch self {
        case .doubleTap: return "Arrives as the Play/Pause media key."
        case .swipeForward: return "Arrives as the Next Track media key."
        case .swipeBackward: return "Arrives as the Previous Track media key."
        case .leftButton: return "The headphones switch modes first; this adds a Mac action on top."
        }
    }

    var defaultTitle: String {
        switch self {
        case .doubleTap: return "Default (Play/Pause)"
        case .swipeForward: return "Default (Next track)"
        case .swipeBackward: return "Default (Previous track)"
        case .leftButton: return "Nothing extra"
        }
    }

    /// Media key that carries this gesture, if any.
    var mediaKey: Int32? {
        switch self {
        case .doubleTap: return MediaKey.play
        case .swipeForward: return MediaKey.next
        case .swipeBackward: return MediaKey.previous
        case .leftButton: return nil
        }
    }
}

/// Gestures the XM5 has but that can't be remapped from a Mac, and why.
struct UnavailableGesture: Identifiable {
    let id = UUID()
    let title: String
    let reason: String

    static let all: [UnavailableGesture] = [
        .init(title: "Right: two-finger tap",
              reason: "The WH-1000XM5 has no two-finger gesture, so the headphones never send one. Use double tap → Pause instead."),
        .init(title: "Right: swipe up / down",
              reason: "Volume changes go to the Mac as absolute volume, not as keys, so they can't be redirected."),
        .init(title: "Right: touch and hold",
              reason: "Starts the voice assistant (Siri) through the Bluetooth hands-free profile; the Mac can't intercept it. Turn it on or off under Controls."),
        .init(title: "Right: cover with palm (Quick Attention)",
              reason: "Handled entirely inside the headphones; nothing is sent to the Mac."),
        .init(title: "Left: double / triple press (Quick Access)",
              reason: "Launches Spotify Tap or Endel through Sony's phone app only; the Mac never sees it."),
    ]
}

enum MacAction: String, CaseIterable, Identifiable {
    case keepDefault, nothing, playPause, pause, next, previous
    case volumeUp, volumeDown, mute, cycleNoise, noiseCancelling, ambient, speakToChat

    var id: String { rawValue }

    var title: String {
        switch self {
        case .keepDefault: return "Default"
        case .nothing: return "Do nothing"
        case .playPause: return "Play / Pause"
        case .pause: return "Pause (stop playback)"
        case .next: return "Next track"
        case .previous: return "Previous track"
        case .volumeUp: return "Mac volume up"
        case .volumeDown: return "Mac volume down"
        case .mute: return "Mute / unmute Mac"
        case .cycleNoise: return "Cycle NC / Ambient / Off"
        case .noiseCancelling: return "Noise cancelling"
        case .ambient: return "Ambient sound"
        case .speakToChat: return "Toggle Speak-to-Chat"
        }
    }
}

enum MediaKey {
    static let soundUp: Int32 = 0
    static let soundDown: Int32 = 1
    static let mute: Int32 = 7
    static let play: Int32 = 16
    static let next: Int32 = 17
    static let previous: Int32 = 18
}

/// Remembers the gesture map and runs it.
@MainActor
final class GestureController: ObservableObject {
    static let shared = GestureController()

    @Published private(set) var map: [Gesture: MacAction] = [:]
    /// Also remap the Mac keyboard's media keys (they arrive the same way as headphone taps).
    @Published var includeKeyboard: Bool {
        didSet { UserDefaults.standard.set(includeKeyboard, forKey: "gestures.includeKeyboard") }
    }
    @Published private(set) var accessibilityGranted = AXIsProcessTrusted()
    @Published private(set) var tapActive = false
    @Published private(set) var lastEvent: String?

    weak var headphones: Headphones?
    var log: (String) -> Void = { _ in }

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var permissionTimer: Timer?
    /// Marks key events this app posts, so the tap lets them through.
    nonisolated fileprivate static let syntheticMark: Int64 = 0x534F4E59

    private init() {
        includeKeyboard = UserDefaults.standard.bool(forKey: "gestures.includeKeyboard")
        for g in Gesture.allCases {
            let raw = UserDefaults.standard.string(forKey: "gesture.\(g.rawValue)") ?? ""
            map[g] = MacAction(rawValue: raw) ?? .keepDefault
        }
    }

    func action(for g: Gesture) -> MacAction { map[g] ?? .keepDefault }

    func set(_ action: MacAction, for g: Gesture) {
        map[g] = action
        UserDefaults.standard.set(action.rawValue, forKey: "gesture.\(g.rawValue)")
        refresh()
    }

    /// True when some right-earcup gesture needs the media-key tap.
    private var needsTap: Bool {
        Gesture.allCases.contains { $0.mediaKey != nil && action(for: $0) != .keepDefault }
    }

    func start() {
        headphones?.onLeftButton = { [weak self] _ in
            guard let self else { return }
            let a = self.action(for: .leftButton)
            self.lastEvent = "Left button → \(a == .keepDefault ? "mode switch only" : a.title)"
            if a != .keepDefault { self.perform(a) }
        }
        refresh()
    }

    func refresh() {
        accessibilityGranted = AXIsProcessTrusted()
        if needsTap, accessibilityGranted { installTap() } else { removeTap() }
        if needsTap, !accessibilityGranted, permissionTimer == nil {
            // Pick the permission up as soon as the user grants it in System Settings.
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] t in
                Task { @MainActor in
                    guard let self else { t.invalidate(); return }
                    if AXIsProcessTrusted() || !self.needsTap {
                        t.invalidate(); self.permissionTimer = nil; self.refresh()
                    }
                }
            }
        }
    }

    func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        refresh()
    }

    // MARK: Media-key tap

    private func installTap() {
        guard tap == nil else { tapActive = true; return }
        let mask = CGEventMask(1 << 14) // NSEventTypeSystemDefined
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                           options: .defaultTap, eventsOfInterest: mask,
                                           callback: mediaKeyCallback, userInfo: refcon) else {
            log("Media key tap could not be created")
            tapActive = false
            return
        }
        tap = port
        runLoopSource = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        tapActive = true
        log("Media key tap on")
    }

    private func removeTap() {
        if let port = tap { CGEvent.tapEnable(tap: port, enable: false) }
        if let src = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
        tap = nil
        runLoopSource = nil
        if tapActive { log("Media key tap off") }
        tapActive = false
    }

    fileprivate func reenable() {
        if let port = tap { CGEvent.tapEnable(tap: port, enable: true) }
    }

    /// Returns true when the key event should be swallowed.
    fileprivate func handleMediaKey(_ key: Int32, down: Bool, sourcePID: Int64) -> Bool {
        guard let g = Gesture.allCases.first(where: { $0.mediaKey == key }) else { return false }
        if down {
            let name = sourcePID > 0 ? Self.processName(pid_t(sourcePID)) : "system"
            log("Media key \(key) from pid \(sourcePID) (\(name))")
        }
        let a = action(for: g)
        guard a != .keepDefault else { return false }
        // Only while the headphones are connected, unless keyboard keys are included too.
        guard headphones?.isPresent == true || includeKeyboard else { return false }
        if !includeKeyboard, Self.isKeyboard(pid: sourcePID) { return false }
        if down {
            lastEvent = "\(g.title) → \(a.title)"
            log("Gesture \(g.rawValue) (source pid \(sourcePID)) → \(a.rawValue)")
            perform(a)
        }
        return true
    }

    /// Keyboard media keys are posted by the HID system (pid 0 or WindowServer); Bluetooth
    /// headphone commands come from bluetoothd / the AVRCP stack.
    private static func isKeyboard(pid: Int64) -> Bool {
        if pid <= 0 { return true }
        let name = NSRunningApplication(processIdentifier: pid_t(pid))?.executableURL?.lastPathComponent
            ?? processName(pid_t(pid))
        return name == "WindowServer"
    }

    private static func processName(_ pid: pid_t) -> String {
        var buf = [CChar](repeating: 0, count: 1024)
        let n = proc_name(pid, &buf, UInt32(buf.count))
        return n > 0 ? String(cString: buf) : ""
    }

    // MARK: Actions

    func perform(_ a: MacAction) {
        switch a {
        case .keepDefault, .nothing: break
        case .playPause: Self.postKey(MediaKey.play)
        case .pause:
            if !MediaRemote.send(.pause) { Self.postKey(MediaKey.play) }
        case .next: Self.postKey(MediaKey.next)
        case .previous: Self.postKey(MediaKey.previous)
        case .volumeUp: Self.postKey(MediaKey.soundUp)
        case .volumeDown: Self.postKey(MediaKey.soundDown)
        case .mute: Self.postKey(MediaKey.mute)
        case .cycleNoise: headphones?.cycleMode()
        case .noiseCancelling: headphones?.setMode(.noiseCancelling)
        case .ambient: headphones?.setMode(.ambient)
        case .speakToChat:
            if let hp = headphones, let on = hp.speakToChat { hp.setSpeakToChat(!on) }
        }
    }

    /// Posts a media key press, so browsers (YouTube) and music apps get it via Now Playing.
    static func postKey(_ key: Int32) {
        for down in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
            let data1 = Int((key << 16) | ((down ? 0xA : 0xB) << 8))
            guard let ev = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags,
                                              timestamp: 0, windowNumber: 0, context: nil,
                                              subtype: 8, data1: data1, data2: -1),
                  let cg = ev.cgEvent else { continue }
            cg.setIntegerValueField(.eventSourceUserData, value: syntheticMark)
            cg.post(tap: .cghidEventTap)
        }
    }
}

private func mediaKeyCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                              refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let controller = Unmanaged<GestureController>.fromOpaque(refcon).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated { controller.reenable() }
        return Unmanaged.passUnretained(event)
    }
    guard type.rawValue == 14,
          event.getIntegerValueField(.eventSourceUserData) != GestureController.syntheticMark,
          let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == 8 else {
        return Unmanaged.passUnretained(event)
    }
    let key = Int32((ns.data1 & 0xFFFF_0000) >> 16)
    let state = (ns.data1 & 0xFF00) >> 8
    let pid = event.getIntegerValueField(.eventSourceUnixProcessID)
    let swallow = MainActor.assumeIsolated {
        controller.handleMediaKey(key, down: state == 0xA, sourcePID: pid)
    }
    return swallow ? nil : Unmanaged.passUnretained(event)
}

/// MediaRemote (private framework) for a real "pause" that doesn't toggle.
enum MediaRemote {
    enum Command: Int32 { case play = 0, pause = 1 }

    private typealias SendFn = @convention(c) (Int32, CFDictionary?) -> Bool
    private static let send: SendFn? = {
        guard let h = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY),
              let sym = dlsym(h, "MRMediaRemoteSendCommand") else { return nil }
        return unsafeBitCast(sym, to: SendFn.self)
    }()

    static func send(_ c: Command) -> Bool { send?(c.rawValue, nil) ?? false }
}
