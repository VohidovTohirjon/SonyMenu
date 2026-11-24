import AppKit
import Foundation

// Command-line modes (run inside the .app so macOS grants Bluetooth access):
//   --probe [--set nc|ambient|off]  print what the headphones report and exit
//   --dump                          GET every supported setting, write raw replies to ~/Library/Logs/SonyMenu-dump.txt
//   --selftest                      change each setting, read it back, restore it; results in the same file
//   --snapshot <folder>             render the panel and settings with sample data to PNGs
// Without arguments it runs the menu bar app.
let args = CommandLine.arguments

/// Writes to stdout and to ~/Library/Logs/SonyMenu-dump.txt.
@MainActor
func makeReportSink() -> (String) -> Void {
    let out = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/SonyMenu-dump.txt")
    try? Data().write(to: out)
    return { line in
        print(line); fflush(stdout)
        if let h = try? FileHandle(forWritingTo: out) {
            h.seekToEndOfFile(); h.write((line + "\n").data(using: .utf8)!); try? h.close()
        }
    }
}

if args.contains("--dump") {
    MainActor.assumeIsolated {
        let emit = makeReportSink()
        let hp = Headphones()
        hp.log = { emit("• " + $0) }
        hp.onPayload = { t, p in
            emit((t == 0x0E ? "T2 " : "T1 ") + p.map { String(format: "%02x", $0) }.joined(separator: " "))
        }
        hp.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { exit(0) }
    }
    RunLoop.main.run()
} else if args.contains("--selftest") {
    MainActor.assumeIsolated { SelfTest(emit: makeReportSink()).run() }
    RunLoop.main.run()
} else if args.contains("--probe") {
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
                print("→ Setting mode \(target)")
                hp.setMode(target)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (target == nil ? 8 : 10)) {
            print("Result: ready=\(hp.isReady) battery=\(hp.battery.map(String.init) ?? "—") mode=\(hp.mode.map { "\($0)" } ?? "—") problem=\(hp.problem ?? "none")")
            exit(0)
        }
    }
    RunLoop.main.run()
} else if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
    // Renders the panel and settings in light and dark to PNGs in the given folder.
    MainActor.assumeIsolated { renderSnapshots(to: URL(fileURLWithPath: args[i + 1])) }
} else {
    MainActor.assumeIsolated { SonyMenuApp.main() }
}
