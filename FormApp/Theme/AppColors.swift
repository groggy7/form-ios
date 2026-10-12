import SwiftUI

public enum AppColors {
    public static var background: Color { ThemeManager.shared.currentTheme.background }
    public static var surface: Color { ThemeManager.shared.currentTheme.surface }
    public static var surfaceRaised: Color { ThemeManager.shared.currentTheme.surfaceRaised }
    public static var calendarSurfaceStart: Color { ThemeManager.shared.currentTheme.calendarSurfaceStart }
    public static var calendarSurfaceEnd: Color { ThemeManager.shared.currentTheme.calendarSurfaceEnd }
    public static var progressionRulesSurface: Color { presentationColor(Color(hex: 0x0E181E), surface) }

    public static var progressionPaywallSurface: Color { presentationColor(Color(hex: 0x101519), surface) }
    public static var progressionPaywallBody: Color { presentationColor(Color(hex: 0xD1D8DE), text) }
    public static var progressionPaywallAccent: Color { presentationColor(Color(hex: 0x47E4CF), accent) }
    public static var progressionPaywallIconSurface: Color { presentationColor(Color(hex: 0x193234), positiveBg) }
    public static var progressionPaywallPlanSurface: Color { presentationColor(Color(hex: 0x181F24), surfaceRaised) }
    public static var progressionPaywallSelectedSurface: Color { presentationColor(Color(hex: 0x13292A), positiveBg) }

    public struct ProgressionRuleColors {
        public let accent: Color
        public let surface: Color
        public let iconSurface: Color
    }

    public static let progressionRuleLoad = ProgressionRuleColors(accent: Color(hex: 0x00F0AA), surface: Color(hex: 0x0C2325), iconSurface: Color(hex: 0x092A29))
    public static let progressionRuleReps = ProgressionRuleColors(accent: Color(hex: 0x00E5F4), surface: Color(hex: 0x0A2028), iconSurface: Color(hex: 0x092832))
    public static let progressionRuleHold = ProgressionRuleColors(accent: Color(hex: 0xFFA91F), surface: Color(hex: 0x231C16), iconSurface: Color(hex: 0x382614))
    public static let progressionRuleReview = ProgressionRuleColors(accent: Color(hex: 0xB176FF), surface: Color(hex: 0x1A1A2C), iconSurface: Color(hex: 0x23203A))

    public static let exerciseVideoSurface = Color(hex: 0x161616)
    public static let exerciseThumbnailSurface = EllipticalGradient(
        colors: [
            Color(hex: 0x383838),
            Color(hex: 0x252525),
            Color(hex: 0x161616)
        ],
        center: .center,
        startRadiusFraction: 0,
        endRadiusFraction: 0.75
    )
    public static var text: Color { ThemeManager.shared.currentTheme.text }
    public static var secondaryText: Color { ThemeManager.shared.currentTheme.secondaryText }
    public static var muted: Color { ThemeManager.shared.currentTheme.muted }
    public static var border: Color { ThemeManager.shared.currentTheme.border }
    public static var accent: Color { ThemeManager.shared.currentTheme.accent }
    public static var positive: Color { ThemeManager.shared.currentTheme.accent }
    public static var positiveBg: Color { ThemeManager.shared.currentTheme.positiveBg }
    public static var purple: Color { ThemeManager.shared.currentTheme.purple }
    public static let muscleSecondary = Color(hex: 0x8EA9F4)
    public static var purpleBg: Color { ThemeManager.shared.currentTheme.purpleBg }
    public static var coral: Color { ThemeManager.shared.currentTheme.coral }
    public static var danger: Color { ThemeManager.shared.currentTheme.danger }
    public static var cuesBg: Color { presentationColor(Color(hex: 0x061F20), positiveBg) }
    public static var cuesBorder: Color { presentationColor(Color(hex: 0x0E5B53), Color.mix(border, accent, 0.35)) }
    public static var avoidBg: Color { presentationColor(Color(hex: 0x1D1416), Color.mix(surface, danger, 0.06)) }
    public static var avoidBorder: Color { presentationColor(Color(hex: 0x54282A), Color.mix(border, danger, 0.35)) }
    
    // Calendar History status colors matching Android Theme
    public static let completedGreen = Color(hex: 0x65D69B)
    public static let unfinishedOrange = Color(hex: 0xF2AF61)
    public static let missedRed = Color(hex: 0xF17E7B)

    // Glossy Progress calendar pills; other workout status surfaces keep their own palette.
    public struct CalendarPillColors {
        public let light: Color
        public let body: Color
        public let shade: Color
    }

    public static let calendarCompletedPill = CalendarPillColors(light: Color(hex: 0x72FFC0), body: Color(hex: 0x2DE58F), shade: Color(hex: 0x13AD63))
    public static let calendarUnfinishedPill = CalendarPillColors(light: Color(hex: 0xFFD396), body: Color(hex: 0xFF9C59), shade: Color(hex: 0xE46A32))
    public static let calendarMissedPill = CalendarPillColors(light: Color(hex: 0xFF9AAF), body: Color(hex: 0xFF4D69), shade: Color(hex: 0xD92747))

    public static var restTimerAccent: Color { presentationColor(Color(hex: 0x12D8D2), purple) }
    public static var restTimerBorder: Color { presentationColor(Color(hex: 0x117D79), Color.mix(border, purple, 0.4)) }
    public static var restTimerSurfaceStart: Color { presentationColor(Color(hex: 0x071A1E), surfaceRaised) }
    public static var restTimerSurfaceEnd: Color { presentationColor(Color(hex: 0x071116), surface) }
    public static var restTimerTrack: Color { presentationColor(Color(hex: 0x192831), border) }
    public static var restTimerControlSurface: Color { presentationColor(Color(hex: 0x091216), surface) }
    public static var restTimerControlBorder: Color { presentationColor(Color(hex: 0x344047), border) }
    
    public static let unfinishedBorder = Color(hex: 0x664923)
    public static let missedDayBorder = Color(hex: 0x6B383B)
    public static let completedDayBorder = Color(hex: 0x2D5949)
    public static let unfinishedText = Color(hex: 0xFDE8CC)
    public static let unfinishedSurface = Color(hex: 0x332717)
    
    public static let todayIvory = Color(hex: 0xEEE8DC)
    public static let todaySelectionText = Color(hex: 0x1A2026)
    
    // Split presentation colors
    public static let upperBorder = Color(hex: 0x494260)
    public static let lowerBorder = Color(hex: 0x37485F)
    public static let fullBodyBorder = Color(hex: 0x414C57)
    
    // History Day Detail Sheet specific colors matching design reference
    public static var toContinueSurface: Color { presentationColor(Color(hex: 0x102523), positiveBg) }
    public static var progressTrack: Color { presentationColor(Color(hex: 0x1D262B), border) }
    
    // PR Badge & Tile colors (Orange identity)
    public static let orangePrBg = Color(hex: 0x2C1E14)
    public static let orangePrBorder = Color(hex: 0x6E461F)
    public static let orangePrText = Color(hex: 0xF2AF61)
    public static let goldPrBg = Color(hex: 0x2C1E14)
    public static let goldPrBorder = Color(hex: 0x6E461F)
    public static let goldPrText = Color(hex: 0xF2AF61)

    // Exercise Detail History Stat Card colors
    public static var historyStatCardBg: Color { presentationColor(Color(hex: 0x1A232A), surface) }
    public static var historyStatCardBorder: Color { presentationColor(Color(hex: 0x26323D), border) }
    public static var historyStatCardTitle: Color { presentationColor(Color(hex: 0x8E9BAE), muted) }
    public static let historyStatPrGreen = Color(hex: 0x20D791)
    public static let historyStat1RmAmber = Color(hex: 0xFEB447)
    public static let historyStatCyan = Color(hex: 0x38BDF8)
    public static let historyStatPurple = Color(hex: 0xB18AFF)

    public static var heroSurface: Color { presentationColor(Color(hex: 0x1E242B), surfaceRaised) }
    public static var heroBorder: Color { presentationColor(Color(hex: 0x343A41), border) }
    public static var restRingShade: Color { presentationColor(Color(hex: 0x7952D6), Color.mix(purple, background, 0.25)) }
    public static var restRingLight: Color { presentationColor(Color(hex: 0xE0BCFF), Color.mix(purple, text, 0.3)) }

    private static func presentationColor(_ original: Color, _ themed: Color) -> Color {
        ThemeManager.shared.currentTheme.id == AppThemes.default.id ? original : themed
    }
    public static var bodyViewSelectedSurface: Color { presentationColor(Color(hex: 0x25232D), purpleBg) }
    public static var bodyViewSelectedBorder: Color { presentationColor(Color(hex: 0x51455F), purple) }
    public static var bodyViewSelectedText: Color { presentationColor(Color(hex: 0xD8CFDF), purple) }

    // Warmup Set demarcation
    public static let warmupAmber = Color(hex: 0xFEB447)
    public static let warmupAmberBg = Color(hex: 0x2C1E14)
}

extension Color {
    // Resolve the explicit sRGB palette, then blend identically to Android's sRGB blend.
    static func mix(_ first: Color, _ second: Color, _ fraction: Double) -> Color {
        let a = first.resolve(in: EnvironmentValues())
        let b = second.resolve(in: EnvironmentValues())
        let f = Float(fraction)
        return Color(.sRGB, red: Double(a.red + (b.red - a.red) * f),
                     green: Double(a.green + (b.green - a.green) * f),
                     blue: Double(a.blue + (b.blue - a.blue) * f), opacity: 1)
    }

    public init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}
