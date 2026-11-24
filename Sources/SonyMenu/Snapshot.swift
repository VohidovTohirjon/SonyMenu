import AppKit
import SwiftUI

@MainActor
func renderSnapshots(to folder: URL) {
    _ = NSApplication.shared
    RenderMode.plain = true
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

    func render<V: View>(_ view: V, _ fileName: String, _ appearanceName: NSAppearance.Name) {
        let appearance = NSAppearance(named: appearanceName)!
        let bg = Color(nsColor: appearanceName == .darkAqua ? NSColor(white: 0.16, alpha: 1) : NSColor(white: 0.96, alpha: 1))
        let host = NSHostingView(rootView: view.background(bg).environment(\.colorScheme, appearanceName == .darkAqua ? .dark : .light))
        host.appearance = appearance
        let size = host.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        appearance.performAsCurrentDrawingAppearance {
            host.cacheDisplay(in: host.bounds, to: rep)
        }
        let url = folder.appendingPathComponent("\(fileName).png")
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        print(url.path)
    }

    for (fileName, mode, appearanceName) in [("panel-light-nc", SoundMode.noiseCancelling, NSAppearance.Name.aqua),
                                              ("panel-dark-ambient", .ambient, .darkAqua)] {
        let hp = Headphones()
        hp.loadSampleState(mode: mode)
        render(PanelView().environmentObject(hp), fileName, appearanceName)
    }
    for (fileName, tab) in [("settings-general", SettingsTab.general), ("settings-sound", .sound),
                            ("settings-controls", .controls)] {
        let hp = Headphones()
        hp.loadSampleState(mode: .ambient)
        render(SettingsView(initialTab: tab).environmentObject(hp), fileName, .aqua)
    }
}
