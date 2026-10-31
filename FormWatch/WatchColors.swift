import SwiftUI

/// Obsidian tokens from docs/design/form-design-system.md; the watch has no theme picker.
enum WatchColors {
    static let background = Color(hex: 0x090C0F)
    static let surface = Color(hex: 0x13171B)
    static let surfaceRaised = Color(hex: 0x1D2227)
    static let text = Color(hex: 0xF3F5F5)
    static let secondaryText = Color(hex: 0xB6BEC4)
    static let muted = Color(hex: 0x8F999F)
    static let border = Color(hex: 0x2A3238)
    static let accent = Color(hex: 0x49C7AF)
    static let positiveBg = Color(hex: 0x142D29)
    static let purple = Color(hex: 0xB18AFF)
    static let restAccent = Color(hex: 0x12D8D2)
    static let restBorder = Color(hex: 0x117D79)
    static let restSurface = Color(hex: 0x071A1E)
    static let restTrack = Color(hex: 0x192831)
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}
