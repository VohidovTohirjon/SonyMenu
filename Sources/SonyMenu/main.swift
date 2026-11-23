import AppKit
import Foundation

// `SonyMenu --probe [--set nc|ambient|off]` prints what the headphones report and exits.
// Without arguments it runs the menu bar app.
let args = CommandLine.arguments

if args.contains("--probe") {
    MainActor.assumeIsolated {
        let hp = Headphones()
        hp.log = { print("•", $0); fflush(stdout) }
        hp.start()

        var target: SoundMode?
        if let i = args.firstIndex(of: "--set"), i + 1 < args.count {
            switch args[i + 1] {
            case "nc": target = .noiseCancelling
            case "ambient": target = .ambient
            case "off": target = .off
            default: break
            }
        }
        if let target {
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                print("→ Ставлю режим \(target)")
                hp.setMode(target)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (target == nil ? 8 : 10)) {
            print("Итог: готово=\(hp.isReady) батарея=\(hp.battery.map(String.init) ?? "—") режим=\(hp.mode.map { "\($0)" } ?? "—") проблема=\(hp.problem ?? "нет")")
            exit(0)
        }
    }
    RunLoop.main.run()
} else if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
    // Renders the panel in light and dark to PNGs in the given folder.
    MainActor.assumeIsolated { renderSnapshots(to: URL(fileURLWithPath: args[i + 1])) }
} else {
    MainActor.assumeIsolated { SonyMenuApp.main() }
}
