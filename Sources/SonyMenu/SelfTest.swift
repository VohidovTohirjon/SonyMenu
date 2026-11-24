import Foundation

/// `--selftest`: for every setting the headphones support, change it, ask the headphones
/// for the value again, check they report the new one, then put the original back and
/// check that too. Nothing is left changed. Skips anything that could disconnect the
/// headphones (multipoint, power off) or change what is playing (next/previous).
@MainActor
final class SelfTest {
    private let hp = Headphones()
    private let emit: (String) -> Void
    private var steps: [() -> Void] = []
    private var results: [(String, Bool)] = []

    init(emit: @escaping (String) -> Void) { self.emit = emit }

    func run() {
        hp.log = { [emit] in emit("• " + $0) }
        hp.start()
        after(12) { self.plan(); self.next() }
    }

    private func after(_ s: Double, _ f: @escaping @MainActor @Sendable () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + s, execute: f)
    }

    private func next() {
        guard !steps.isEmpty else { finish(); return }
        steps.removeFirst()()
    }

    /// Applies, re-reads, checks; restores, re-reads, checks.
    private func check<T: Equatable>(_ name: String, read: [UInt8], table2: Bool = false,
                                     value: @escaping () -> T?, to new: T,
                                     apply: @escaping (T) -> Void) {
        steps.append { [self] in
            guard let original = value() else {
                emit("SKIP \(name): headphones didn't report a value"); next(); return
            }
            apply(new)
            after(1.5) { [self] in
                hp.sendRaw(read, table2: table2)
                after(1.5) { [self] in
                    let changed = value() == new
                    apply(original)
                    after(1.5) { [self] in
                        hp.sendRaw(read, table2: table2)
                        after(1.5) { [self] in
                            let restored = value() == original
                            let ok = changed && restored
                            results.append((name, ok))
                            emit("\(ok ? "PASS" : "FAIL") \(name): \(original) → \(new) \(changed ? "confirmed" : "NOT confirmed"), restored \(restored ? "yes" : "NO (now \(String(describing: value())))")")
                            next()
                        }
                    }
                }
            }
        }
    }

    private func plan() {
        emit("Model \(hp.modelName ?? "?"), firmware \(hp.firmware ?? "?"), codec \(hp.codec ?? "?"), support T1 \(hp.supportT1.count), T2 \(hp.supportT2.count)")
        emit("Read: battery \(hp.battery ?? -1), mode \(String(describing: hp.mode)), EQ \(String(describing: hp.eqPreset)) bands \(hp.eqBands), DSEE \(String(describing: hp.dsee)), connection \(String(describing: hp.connectionPriority)), STC \(String(describing: hp.speakToChat)) \(String(describing: hp.stcSensitivity))/\(String(describing: hp.stcTimeout)), autoPause \(String(describing: hp.autoPause)), autoOff \(String(describing: hp.autoPowerOff)) of \(hp.autoPowerOffOptions), VA \(String(describing: hp.voiceAssistant)) of \(hp.voiceAssistantOptions), touch \(String(describing: hp.touchPanel)), multipoint \(String(describing: hp.multipoint)), guidance \(String(describing: hp.voiceGuidance)), NC button \(String(describing: hp.ncButton)), volume \(hp.volume), playback \(hp.playback)")

        check("Ambient level", read: [Cmd.ncAsmGetParam, Cmd.ncDualSeamless],
              value: { self.hp.mode == .ambient ? Int(self.hp.ambientLevel) : nil },
              to: Int(hp.ambientLevel) == 12 ? 11 : 12) { v in self.hp.ambientLevel = Double(v); self.hp.commitAmbientLevel() }
        check("Focus on voice", read: [Cmd.ncAsmGetParam, Cmd.ncDualSeamless],
              value: { self.hp.mode == nil ? nil : self.hp.focusOnVoice }, to: !hp.focusOnVoice) { self.hp.setFocusOnVoice($0) }
        check("EQ preset", read: [Cmd.eqGetParam, 0x00], value: { self.hp.eqPreset },
              to: hp.eqPreset == 0x16 ? 0x10 : 0x16) { self.hp.setEqPreset($0) }
        // Custom EQ: select the custom slot first so its stored bands are what gets restored.
        if let originalPreset = hp.eqPreset {
            steps.append { [self] in
                hp.setEqPreset(0xA0)
                after(2.5) { [self] in
                    let stored = hp.eqBands
                    var changed = stored
                    changed[0] = stored[0] == 2 ? 3 : 2      // Clear Bass
                    changed[3] = stored[3] == -2 ? -3 : -2  // 2.5 kHz
                    hp.eqBands = changed
                    hp.commitEqBands()
                    after(2.5) { [self] in
                        let ok1 = hp.eqBands == changed && hp.eqPreset == 0xA0
                        hp.eqBands = stored
                        hp.commitEqBands()
                        after(2.5) { [self] in
                            let ok2 = hp.eqBands == stored
                            hp.setEqPreset(originalPreset)
                            after(2.5) { [self] in
                                let ok3 = hp.eqPreset == originalPreset
                                let ok = ok1 && ok2 && ok3
                                results.append(("Custom EQ + Clear Bass", ok))
                                emit("\(ok ? "PASS" : "FAIL") Custom EQ + Clear Bass: stored \(stored) → \(changed) \(ok1 ? "confirmed" : "NOT confirmed"), bands restored \(ok2), preset restored \(ok3)")
                                next()
                            }
                        }
                    }
                }
            }
        }
        check("DSEE Extreme", read: [Cmd.audioGetParam, Cmd.audioUpscaling], value: { self.hp.dsee },
              to: !(hp.dsee ?? false)) { self.hp.setDsee($0) }
        check("Connection quality", read: [Cmd.audioGetParam, Cmd.audioConnection], value: { self.hp.connectionPriority },
              to: hp.connectionPriority == 0 ? UInt8(1) : 0) { self.hp.setConnectionPriority($0) }
        check("Speak-to-Chat on/off", read: [Cmd.systemGetParam, Cmd.sysSpeakToChat], value: { self.hp.speakToChat },
              to: !(hp.speakToChat ?? true)) { self.hp.setSpeakToChat($0) }
        check("Speak-to-Chat sensitivity", read: [Cmd.systemGetExtParam, Cmd.sysSpeakToChat], value: { self.hp.stcSensitivity },
              to: hp.stcSensitivity == 1 ? UInt8(2) : 1) { self.hp.setSpeakToChat(sensitivity: $0) }
        check("Speak-to-Chat timeout", read: [Cmd.systemGetExtParam, Cmd.sysSpeakToChat], value: { self.hp.stcTimeout },
              to: hp.stcTimeout == 2 ? UInt8(0) : 2) { self.hp.setSpeakToChat(timeout: $0) }
        check("Pause when taken off", read: [Cmd.systemGetParam, Cmd.sysAutoPause], value: { self.hp.autoPause },
              to: !(hp.autoPause ?? true)) { self.hp.setAutoPause($0) }
        check("Automatic power off", read: [Cmd.powerGetParam, Cmd.powerAutoOffWearing], value: { self.hp.autoPowerOff },
              to: hp.autoPowerOff == 0x11 ? UInt8(0x10) : 0x11) { self.hp.setAutoPowerOff($0) }
        check("Touch and hold (voice assistant)", read: [Cmd.systemGetParam, Cmd.sysVoiceAssistant], value: { self.hp.voiceAssistant },
              to: hp.voiceAssistant == 0x30 ? UInt8(0xFF) : 0x30) { self.hp.setVoiceAssistant($0) }
        check("Left button cycle", read: [Cmd.ncAsmGetParam, Cmd.ncAmbToggle], value: { self.hp.ncButton },
              to: hp.ncButton == .all ? NcButtonCycle.ncAmbient : .all) { self.hp.setNcButton($0) }
        check("Touch sensor panel", read: [Cmd.gsGetParam, Cmd.gsTouchPanel], value: { self.hp.touchPanel },
              to: !(hp.touchPanel ?? true)) { self.hp.setTouchPanel($0) }
        check("Voice guidance", read: [Cmd.t2VoiceGuidanceGetParam, Cmd.vgOnOff], table2: true, value: { self.hp.voiceGuidance },
              to: !(hp.voiceGuidance ?? true)) { self.hp.setVoiceGuidance($0) }
        check("Headphone volume", read: [Cmd.playGetParam, Cmd.playVolume], value: { self.hp.volumeKnown ? Int(self.hp.volume) : nil },
              to: max(0, Int(hp.volume) - 1)) { v in self.hp.volume = Double(v); self.hp.commitVolume() }
        if hp.playback == .playing {
            check("Pause / play from the app", read: [Cmd.playGetStatus, Cmd.playController], value: { self.hp.playback },
                  to: PlaybackState.paused) { s in self.hp.playControl(s == .paused ? .pause : .play) }
        } else {
            steps.append { [self] in emit("SKIP Pause / play: nothing is playing, so the test would start music"); next() }
        }
    }

    private func finish() {
        let passed = results.filter(\.1).count
        emit("DONE \(passed)/\(results.count) passed")
        after(1) { exit(0) }
    }
}
