import SwiftUI

public enum AppColors {
    public static let background = Color(hex: 0x090C0F)
    public static let surface = Color(hex: 0x13171B)
    public static let surfaceRaised = Color(hex: 0x1D2227)
    public static let text = Color(hex: 0xF3F5F5)
    public static let secondaryText = Color(hex: 0xB6BEC4)
    public static let muted = Color(hex: 0x8F999F)
    public static let border = Color(hex: 0x2A3238)
    public static let accent = Color(hex: 0x49C7AF)
    public static let positive = Color(hex: 0x49C7AF)
    public static let positiveBg = Color(hex: 0x142D29)
    public static let purple = Color(hex: 0xB18AFF)
    public static let purpleBg = Color(hex: 0x28203D)
    public static let coral = Color(hex: 0xFF8C78)
    public static let danger = Color(hex: 0xFF897B)
    
    // Calendar History status colors matching Android Theme
    public static let completedGreen = Color(hex: 0x65D69B)
    public static let unfinishedOrange = Color(hex: 0xF2AF61)
    public static let missedRed = Color(hex: 0xF17E7B)
    public static let restTimerAccent = Color(hex: 0x12D8D2)
    public static let restTimerBorder = Color(hex: 0x117D79)
    public static let restTimerSurfaceStart = Color(hex: 0x071A1E)
    public static let restTimerSurfaceEnd = Color(hex: 0x071116)
    public static let restTimerTrack = Color(hex: 0x192831)
    public static let restTimerControlSurface = Color(hex: 0x091216)
    public static let restTimerControlBorder = Color(hex: 0x344047)
    
    public static let unfinishedBorder = Color(hex: 0x664923)
    public static let unfinishedText = Color(hex: 0xFDE8CC)
    public static let unfinishedSurface = Color(hex: 0x332717)
    
    public static let todayIvory = Color(hex: 0xEEE8DC)
    public static let todaySelectionText = Color(hex: 0x1A2026)
    
    // Split presentation colors
    public static let upperBorder = Color(hex: 0x494260)
    public static let lowerBorder = Color(hex: 0x37485F)
    public static let fullBodyBorder = Color(hex: 0x414C57)
}

extension Color {
    public init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}
