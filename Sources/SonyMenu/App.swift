import AppKit
import ServiceManagement
import SwiftUI

// MARK: - Design tokens

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255,
                           green: CGFloat(hex >> 8 & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }

    static let dsText = Color(light: 0x37352F, dark: 0xD4D4D4)
    static let dsTextSecondary = Color(light: 0x73726E, dark: 0x9B9B9B)
    static let dsAccent = Color(light: 0x007AFF, dark: 0x0A84FF)
    static let dsFill = Color(light: 0xE5E5EA, dark: 0x2C2C2E)
    static let dsGreen = Color(light: 0x34C759, dark: 0x30D158)
    static let dsOrange = Color(light: 0xFF9500, dark: 0xFF9F0A)
    static let dsRed = Color(light: 0xFF3B30, dark: 0xFF453A)
}

// MARK: - Panel

@MainActor
final class LoginItem: ObservableObject {
    static let shared = LoginItem()
    @Published var enabled = SMAppService.mainApp.status == .enabled

    func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {}
        enabled = SMAppService.mainApp.status == .enabled
    }
}

