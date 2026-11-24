import AppKit
import SwiftUI

// Liquid Glass panel (macOS 26+). The popover itself is system glass; controls float on it
// as glass elements, the selected mode is glass tinted with the accent blue.

struct PanelView: View {
    @EnvironmentObject private var hp: Headphones
    @ObservedObject private var loginItem = LoginItem.shared
    @Namespace private var glassNS
    var openSettings: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if let problem = hp.problem, !hp.isReady {
                status(problem, spinning: false)
            } else if !hp.isReady {
                status("Connecting…", spinning: true)
            } else {
                modes
                if hp.mode == .ambient {
                    ambientControls
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                soundSection
                if hp.supports(Fn.playback) { playbackSection }
            }

            footer
        }
        .padding(14)
        .frame(width: 290)
        .animation(.bouncy(duration: 0.35), value: hp.mode)
        .animation(.easeInOut(duration: 0.2), value: hp.isReady)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "headphones")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 30, height: 30)
                .glassOrPlain(in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(hp.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: 6) {
                    if let level = hp.battery {
                        HStack(spacing: 4) {
                            Image(systemName: batterySymbol(level))
                                .foregroundStyle(batteryColor(level))
                            if hp.charging {
                                Image(systemName: "bolt.fill").foregroundStyle(Color.dsGreen)
                            }
                            Text("\(level)%").monospacedDigit()
                        }
                    }
                    if let codec = hp.codec {
                        Text(codec)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                            .help("Bluetooth codec in use")
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            launchAtLoginSwitch
        }
    }

    /// Small "launch at login" switch opposite the name, with a tiny caption.
    private var launchAtLoginSwitch: some View {
        VStack(spacing: 2) {
            Toggle("Launch at login", isOn: Binding(
                get: { loginItem.enabled },
                set: { loginItem.set($0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .tint(.dsAccent)
            Text("Autostart")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .help("Open SonyMenu when you log in")
    }

    private func status(_ text: String, spinning: Bool) -> some View {
        HStack(spacing: 8) {
            if spinning { ProgressView().controlSize(.mini) }
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Modes

    private var modes: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(alignment: .top, spacing: 0) {
                ModeButton(title: "Noise Cancelling", symbol: "waveform.slash",
                           selected: hp.mode == .noiseCancelling, namespace: glassNS) {
                    hp.setMode(.noiseCancelling)
                }
                ModeButton(title: "Ambient Sound", symbol: "ear.fill",
                           selected: hp.mode == .ambient, namespace: glassNS) {
                    hp.setMode(.ambient)
                }
                ModeButton(title: "Off", symbol: "circle.slash",
                           selected: hp.mode == .off, namespace: glassNS) {
                    hp.setMode(.off)
                }
            }
        }
    }

    // MARK: Ambient

    private var ambientControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Ambient level")
                Spacer()
                Text("\(Int(hp.ambientLevel.rounded()))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 12))

            Slider(value: $hp.ambientLevel, in: 1...20) { editing in
                if !editing { hp.commitAmbientLevel() }
            }
            .tint(.dsAccent)
            .controlSize(.small)

            SwitchRow(title: "Focus on voice", isOn: Binding(
                get: { hp.focusOnVoice },
                set: { hp.setFocusOnVoice($0) }
            ))
        }
        .card()
    }

    // MARK: Sound

    private var soundSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            if hp.supports(Fn.presetEq), !hp.eqPresets.isEmpty {
                HStack {
                    Text("Equalizer").font(.system(size: 12))
                    Spacer()
                    Picker("Equalizer", selection: Binding(
                        get: { hp.eqPreset ?? 0 },
                        set: { hp.setEqPreset($0) }
                    )) {
                        ForEach(hp.eqPresets) { Text($0.name).tag($0.id) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .fixedSize()
                }
            }
            if hp.supports(Fn.dsee), let dsee = hp.dsee {
                SwitchRow(title: "DSEE Extreme", isOn: Binding(get: { dsee }, set: { hp.setDsee($0) }))
                    .help("Upscales compressed music. Needs \"Priority on sound quality\".")
            }
            if hp.supports(Fn.speakToChat), let stc = hp.speakToChat {
                SwitchRow(title: "Speak-to-Chat", isOn: Binding(get: { stc }, set: { hp.setSpeakToChat($0) }))
                    .help("Pauses music and lets ambient sound in when you start talking.")
            }
        }
        .card()
    }

    // MARK: Playback

    private var playbackSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 18) {
                Spacer()
                glassIcon("backward.fill", help: "Previous track") { hp.playControl(.previous) }
                glassIcon(hp.playback == .playing ? "pause.fill" : "play.fill",
                          help: "Play / Pause") { hp.togglePlayback() }
                glassIcon("forward.fill", help: "Next track") { hp.playControl(.next) }
                Spacer()
            }
            if hp.volumeKnown {
                HStack(spacing: 8) {
                    Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                    Slider(value: $hp.volume, in: 0...30) { editing in
                        if !editing { hp.commitVolume() }
                    }
                    .tint(.dsAccent)
                    .controlSize(.small)
                    Text("\(Int(hp.volume.rounded()))")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 18, alignment: .trailing)
                }
                .font(.system(size: 11))
                .help("Headphone volume")
            }
        }
        .card()
    }

    private func glassIcon(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 30, height: 30)
                .glassOrPlain(in: Circle(), interactive: true)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Button {
                openSettings()
            } label: {
                Label("Settings…", systemImage: "gearshape")
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.glass)
                .controlSize(.small)
        }
    }

    // MARK: Helpers

    private func batterySymbol(_ level: Int) -> String {
        switch level {
        case 88...: return "battery.100percent"
        case 63..<88: return "battery.75percent"
        case 38..<63: return "battery.50percent"
        case 13..<38: return "battery.25percent"
        default: return "battery.0percent"
        }
    }

    private func batteryColor(_ level: Int) -> Color {
        level <= 10 ? .dsRed : (level <= 20 ? .dsOrange : .dsGreen)
    }
}

/// `--snapshot` renders offscreen, where Liquid Glass doesn't draw; use plain fills there.
@MainActor enum RenderMode { static var plain = false }

extension View {
    @ViewBuilder func glassOrPlain<S: Shape>(in shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        if RenderMode.plain {
            background(tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.quaternary), in: shape)
        } else {
            let g: Glass = tint.map { Glass.regular.tint($0) } ?? .regular
            glassEffect(interactive ? g.interactive() : g, in: shape)
        }
    }

    /// Soft grouped background used for each block of the panel.
    func card() -> some View {
        padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct SwitchRow: View {
    let title: String
    let isOn: Binding<Bool>

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
            Spacer()
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(.dsAccent)
        }
    }
}

private struct ModeButton: View {
    let title: String
    let symbol: String
    let selected: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(selected ? Color.white : Color.primary)
                    .frame(width: 38, height: 38)
                    .glassOrPlain(in: Circle(), tint: selected ? .dsAccent : nil, interactive: true)
                    .glassEffectID(title, in: namespace)

                Text(title)
                    .font(.system(size: 10, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
