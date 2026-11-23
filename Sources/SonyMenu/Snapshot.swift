import AppKit
import SwiftUI

@MainActor
func renderSnapshots(to folder: URL) {
    _ = NSApplication.shared
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let cases: [(String, SoundMode, NSAppearance.Name)] = [
        ("light-nc", .noiseCancelling, .aqua),
        ("dark-ambient", .ambient, .darkAqua),
    ]
    for (fileName, mode, appearanceName) in cases {
        let hp = Headphones()
        hp.loadSampleState(mode: mode)
        let appearance = NSAppearance(named: appearanceName)!
        let root = PanelView()
            .environmentObject(hp)
            .background(Color(nsColor: .windowBackgroundColor))
        let host = NSHostingView(rootView: root)
        host.appearance = appearance
        let size = host.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
        appearance.performAsCurrentDrawingAppearance {
            host.cacheDisplay(in: host.bounds, to: rep)
        }
        let url = folder.appendingPathComponent("\(fileName).png")
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        print(url.path)
    }
}
