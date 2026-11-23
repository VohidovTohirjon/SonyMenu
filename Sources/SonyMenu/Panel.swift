import AppKit
import SwiftUI

// Liquid Glass panel (macOS 26+). The popover itself is system glass; controls float on it
// as glass elements, the selected mode is glass tinted with the accent blue.

struct PanelView: View {
    @EnvironmentObject private var hp: Headphones
    @ObservedObject private var loginItem = LoginItem.shared
    @Namespace private var glassNS

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if let problem = hp.problem, !hp.isReady {
                status(problem, spinning: false)
            } else if !hp.isReady {
                status("Подключаюсь…", spinning: true)
            } else {
                modes
                if hp.mode == .ambient {
                    ambientControls
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            footer
        }
        .padding(14)
        .frame(width: 270)
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
                .glassEffect(.regular, in: .circle)

            VStack(alignment: .leading, spacing: 2) {
                Text(hp.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let level = hp.battery {
                    HStack(spacing: 4) {
                        Image(systemName: batterySymbol(level))
                            .foregroundStyle(batteryColor(level))
                        if hp.charging {
                            Image(systemName: "bolt.fill").foregroundStyle(Color.dsGreen)
                        }
                        Text("\(level) %").monospacedDigit()
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            launchAtLoginSwitch
        }
    }

    /// Small «launch at login» switch opposite the name, with a tiny caption.
    private var launchAtLoginSwitch: some View {
        VStack(spacing: 2) {
            Toggle("Запускать при входе", isOn: Binding(
                get: { loginItem.enabled },
                set: { loginItem.set($0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .tint(.dsAccent)
            Text("Автозапуск")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .help("Запускать при входе в систему")
    }

    private func status(_ text: String, spinning: Bool) -> some View {
        HStack(spacing: 8) {
            if spinning { ProgressView().controlSize(.mini) }
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Modes

    private var modes: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(alignment: .top, spacing: 0) {
                ModeButton(title: "Шумоподавление", symbol: "waveform.slash",
                           selected: hp.mode == .noiseCancelling, namespace: glassNS) {
                    hp.setMode(.noiseCancelling)
                }
                ModeButton(title: "Внешний звук", symbol: "ear.fill",
                           selected: hp.mode == .ambient, namespace: glassNS) {
                    hp.setMode(.ambient)
                }
                ModeButton(title: "Выключено", symbol: "circle.slash",
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
                Text("Уровень")
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

            SwitchRow(title: "Фокус на голосе", isOn: Binding(
                get: { hp.focusOnVoice },
                set: { hp.setFocusOnVoice($0) }
            ))
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Spacer()
            Button("Выйти") { NSApp.terminate(nil) }
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

private struct SwitchRow: View {
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
                    .glassEffect(selected ? .regular.tint(.dsAccent).interactive() : .regular.interactive(),
                                 in: .circle)
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
