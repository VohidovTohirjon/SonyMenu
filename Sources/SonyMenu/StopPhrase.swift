import AppKit
import AVFoundation
import CoreAudio
import Speech

/// While Dictator's hands-free dictation runs (started by a headphone gesture), listens on the
/// Mac's built-in microphone for "stop dictation". Then it presses Option once, which makes
/// Dictator finish and paste, and removes the phrase from the pasted text.
///
/// The built-in mic is used on purpose: opening the headphones' Bluetooth mic would switch them
/// to call quality. Recognition runs on this Mac; nothing is recorded or sent anywhere.
@MainActor
final class StopPhraseListener {
    static let shared = StopPhraseListener()
    var log: (String) -> Void = { _ in }

    private(set) var isListening = false
    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var timeout: DispatchWorkItem?
    private var restarts = 0
    private var startedAt = Date.distantPast
    /// The longest a dictation can run before we stop listening for the phrase.
    private let maxListen: TimeInterval = 10 * 60

    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "dictation.stopPhrase") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "dictation.stopPhrase") }
    }

    /// Ends with "stop dictation" (any case, trailing punctuation allowed). A plain "stop"
    /// in the middle of what you say doesn't count.
    nonisolated static func endsWithStopPhrase(_ text: String) -> Bool {
        text.range(of: #"(?<![\w-])stop\s+dictation[\s.!?,]*$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// How many characters at the end of `text` are the phrase (with the space or punctuation
    /// before it), so they can be deleted. 0 when the text doesn't end with it.
    nonisolated static func phraseSuffixLength(_ text: String) -> Int {
        guard let r = text.range(of: #"[\s,]*(?<![\w-])stop\s+dictation[\s.!?,]*$"#,
                                 options: [.regularExpression, .caseInsensitive]) else { return 0 }
        return text[r].count
    }

    func start() {
        guard enabled, !isListening else { return }
        restarts = 0
        startedAt = Date()
        timeout?.cancel()
        let t = DispatchWorkItem { [weak self] in self?.stop() }
        timeout = t
        DispatchQueue.main.asyncAfter(deadline: .now() + maxListen, execute: t)
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor in
                guard status == .authorized else {
                    self.log("Stop phrase off: Speech Recognition isn't allowed for SonyMenu")
                    return
                }
                AVCaptureDevice.requestAccess(for: .audio) { ok in
                    Task { @MainActor in
                        if ok { self.begin() } else { self.log("Stop phrase off: microphone isn't allowed for SonyMenu") }
                    }
                }
            }
        }
    }

    func stop() {
        guard isListening else { return }
        timeout?.cancel()
        pauseForRestart()
        log("Stopped listening for \"stop dictation\"")
    }

    /// Tears down the current recognition without ending the listening session's deadline.
    private func pauseForRestart() {
        isListening = false
        task?.cancel()
        request?.endAudio()
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil; request = nil; task = nil
    }

    private func begin() {
        let locale = Locale(identifier: "en-US")
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            log("Stop phrase off: speech recognition isn't available"); return
        }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        guard recognizer.supportsOnDeviceRecognition else {
            log("Stop phrase off: on-device speech recognition isn't available (won't send audio to a server)"); return
        }
        guard let mic = Self.builtInMicrophone(), let unit = input.audioUnit else {
            log("Stop phrase off: no built-in microphone (won't use the headphones' mic)"); return
        }
        var id = mic
        var current = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                   &id, size) == noErr,
              AudioUnitGetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                   &current, &size) == noErr,
              current == mic else {
            log("Stop phrase off: couldn't select the built-in microphone"); return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { log("Stop phrase off: microphone gave no audio"); return }
        input.installTap(onBus: 0, bufferSize: 2048, format: format, block: Self.feeder(request))
        do { try engine.start() } catch {
            input.removeTap(onBus: 0)
            log("Stop phrase off: \(error.localizedDescription)"); return
        }
        self.engine = engine
        self.request = request
        isListening = true
        log("Listening for \"stop dictation\" (built-in mic, on this Mac)")
        task = recognizer.recognitionTask(with: request, resultHandler: Self.handler { [weak self] text, failed in
            guard let self, self.isListening else { return }
            if Self.endsWithStopPhrase(text) {
                self.heard()
            } else if failed {
                // Recognition ends after a long pause; keep listening while dictation runs.
                self.restarts += 1
                self.pauseForRestart()
                if self.restarts <= 20, Date().timeIntervalSince(self.startedAt) < self.maxListen { self.begin() } else { self.log("Stop phrase gave up after repeated recognition errors") }
            }
        })
    }

    private func heard() {
        log("Heard \"stop dictation\": finishing dictation")
        stop()
        Self.tapOption() // Dictator: one more press of the shortcut pastes
        removePhraseWhenPasted()
    }

    /// Dictator pastes after its clean-up, about a second later. Wait for the text to end with
    /// the phrase in the focused field, then delete just the phrase.
    private func removePhraseWhenPasted(attempt: Int = 0) {
        guard attempt < 32 else { log("Pasted text didn't end with the phrase; left it as is"); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            guard let (value, caretAtEnd) = Self.focusedText() else {
                self.removePhraseWhenPasted(attempt: attempt + 1); return
            }
            let n = Self.phraseSuffixLength(value)
            guard n > 0, caretAtEnd else { self.removePhraseWhenPasted(attempt: attempt + 1); return }
            Self.backspace(n)
            self.log("Removed \"stop dictation\" from the pasted text")
        }
    }

    // MARK: System helpers

    /// Audio and recognition callbacks run off the main thread, so they're built outside the
    /// main actor and only hop back to it.
    nonisolated static func feeder(_ request: SFSpeechAudioBufferRecognitionRequest) -> AVAudioNodeTapBlock {
        { buffer, _ in request.append(buffer) }
    }

    nonisolated static func handler(_ onMain: @escaping @MainActor (String, Bool) -> Void)
        -> (SFSpeechRecognitionResult?, Error?) -> Void {
        { result, error in
            let text = result?.bestTranscription.formattedString ?? ""
            let failed = error != nil
            Task { @MainActor in onMain(text, failed) }
        }
    }

    static func tapOption() {
        let src = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: src, virtualKey: 58, keyDown: down) else { continue }
            e.type = .flagsChanged
            e.flags = down ? .maskAlternate : []
            e.post(tap: .cghidEventTap)
        }
    }

    static func backspace(_ count: Int) {
        let src = CGEventSource(stateID: .hidSystemState)
        for _ in 0..<min(count, 40) {
            for down in [true, false] {
                CGEvent(keyboardEventSource: src, virtualKey: 51, keyDown: down)?.post(tap: .cghidEventTap)
            }
        }
    }

    /// The focused text field's text, and whether the caret sits at its end.
    static func focusedText() -> (String, Bool)? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let el = focused, CFGetTypeID(el) == AXUIElementGetTypeID() else { return nil }
        let element = el as! AXUIElement
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
              let text = value as? String else { return nil }
        var rangeRef: CFTypeRef?
        var range = CFRange(location: 0, length: 0)
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
           let r = rangeRef, CFGetTypeID(r) == AXValueGetTypeID() {
            AXValueGetValue(r as! AXValue, .cfRange, &range)
        } else {
            return (text, false)
        }
        let utf16Count = (text as NSString).length
        return (text, range.length == 0 && range.location == utf16Count)
    }

    /// The Mac's own microphone (never a Bluetooth one).
    static func builtInMicrophone() -> AudioDeviceID? {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr
        else { return nil }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr
        else { return nil }
        for id in ids {
            var t = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType,
                                               mScope: kAudioObjectPropertyScopeGlobal,
                                               mElement: kAudioObjectPropertyElementMain)
            var transport: UInt32 = 0
            var tsize = UInt32(MemoryLayout<UInt32>.size)
            guard AudioObjectGetPropertyData(id, &t, 0, nil, &tsize, &transport) == noErr,
                  transport == kAudioDeviceTransportTypeBuiltIn else { continue }
            var s = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                               mScope: kAudioDevicePropertyScopeInput,
                                               mElement: kAudioObjectPropertyElementMain)
            var ssize: UInt32 = 0
            if AudioObjectGetPropertyDataSize(id, &s, 0, nil, &ssize) == noErr, ssize > 0 { return id }
        }
        return nil
    }
}
