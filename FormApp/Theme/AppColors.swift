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
    public static var progressionPaywallPhotoBody: Color { lightThemeColor(progressionPaywallBody, Color(hex: 0xD1D8DE)) }
    public static var progressionPaywallPhotoTitle: Color { lightThemeColor(text, Color(hex: 0xF3F5F5)) }
    public static var progressionPaywallPhotoSurface: Color { lightThemeColor(progressionPaywallSurface, Color(hex: 0x101519)) }
    public static var progressionPaywallAccent: Color { presentationColor(Color(hex: 0x47E4CF), accent) }
    public static var progressionPaywallIconSurface: Color { presentationColor(Color(hex: 0x193234), positiveBg) }
    public static var progressionPaywallPlanSurface: Color { presentationColor(Color(hex: 0x181F24), surfaceRaised) }
    public static var progressionPaywallSelectedSurface: Color { presentationColor(Color(hex: 0x13292A), positiveBg) }

    public struct ProgressionRuleColors {
        public let accent: Color
        public let surface: Color
        public let iconSurface: Color
    }

    public static var progressionRuleLoad: ProgressionRuleColors { ProgressionRuleColors(accent: lightThemeColor(Color(hex: 0x00F0AA), Color(hex: 0x1D7050)), surface: lightThemeColor(Color(hex: 0x0C2325), Color(hex: 0xE2EDE4)), iconSurface: lightThemeColor(Color(hex: 0x092A29), Color(hex: 0xCFE1D4))) }
    public static var progressionRuleReps: ProgressionRuleColors { ProgressionRuleColors(accent: lightThemeColor(Color(hex: 0x00E5F4), Color(hex: 0x1B6681)), surface: lightThemeColor(Color(hex: 0x0A2028), Color(hex: 0xE3EBED)), iconSurface: lightThemeColor(Color(hex: 0x092832), Color(hex: 0xD0E0E5))) }
    public static var progressionRuleHold: ProgressionRuleColors { ProgressionRuleColors(accent: lightThemeColor(Color(hex: 0xFFA91F), Color(hex: 0x845014)), surface: lightThemeColor(Color(hex: 0x231C16), Color(hex: 0xF2E4D0)), iconSurface: lightThemeColor(Color(hex: 0x382614), Color(hex: 0xEAD5B6))) }
    public static var progressionRuleReview: ProgressionRuleColors { ProgressionRuleColors(accent: lightThemeColor(Color(hex: 0xB176FF), Color(hex: 0x765064)), surface: lightThemeColor(Color(hex: 0x1A1A2C), Color(hex: 0xEDDFE4)), iconSurface: lightThemeColor(Color(hex: 0x23203A), Color(hex: 0xE1CED8))) }

    public static var exerciseVideoSurface: Color { ExerciseBackdropStyle.perimeter(for: ThemeManager.shared.currentTheme.id) }
    public static var exerciseThumbnailSurface: Color { exerciseVideoSurface }
    public static var text: Color { ThemeManager.shared.currentTheme.text }
    public static var secondaryText: Color { ThemeManager.shared.currentTheme.secondaryText }
    public static var muted: Color { ThemeManager.shared.currentTheme.muted }
    public static var border: Color { ThemeManager.shared.currentTheme.border }
    public static var accent: Color { ThemeManager.shared.currentTheme.accent }
    public static var positive: Color { ThemeManager.shared.currentTheme.accent }
    public static var positiveBg: Color { ThemeManager.shared.currentTheme.positiveBg }
    public static var purple: Color { ThemeManager.shared.currentTheme.purple }
    public static var muscleSecondary: Color { lightThemeColor(Color(hex: 0x8EA9F4), Color(hex: 0x4D679A)) }
    public static var purpleBg: Color { ThemeManager.shared.currentTheme.purpleBg }
    public static var coral: Color { ThemeManager.shared.currentTheme.coral }
    public static var danger: Color { ThemeManager.shared.currentTheme.danger }
    public static var cuesBg: Color { presentationColor(Color(hex: 0x061F20), positiveBg) }
    public static var cuesBorder: Color { presentationColor(Color(hex: 0x0E5B53), Color.mix(border, accent, 0.35)) }
    public static var avoidBg: Color { presentationColor(Color(hex: 0x1D1416), Color.mix(surface, danger, 0.06)) }
    public static var avoidBorder: Color { presentationColor(Color(hex: 0x54282A), Color.mix(border, danger, 0.35)) }
    
    // Calendar History status colors matching Android Theme
    public static var completedGreen: Color { lightThemeColor(Color(hex: 0x65D69B), Color(hex: 0x1D7050)) }
    public static var unfinishedOrange: Color { lightThemeColor(Color(hex: 0xF2AF61), Color(hex: 0x845014)) }
    public static var missedRed: Color { lightThemeColor(Color(hex: 0xF17E7B), Color(hex: 0xAA3E2F)) }

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
    
    public static var unfinishedBorder: Color { lightThemeColor(Color(hex: 0x664923), Color(hex: 0xCCB18E)) }
    public static var missedDayBorder: Color { lightThemeColor(Color(hex: 0x6B383B), Color(hex: 0xC79088)) }
    public static var completedDayBorder: Color { lightThemeColor(Color(hex: 0x2D5949), Color(hex: 0xA4BCAD)) }
    public static var unfinishedText: Color { lightThemeColor(Color(hex: 0xFDE8CC), Color(hex: 0x845014)) }
    public static var unfinishedSurface: Color { lightThemeColor(Color(hex: 0x332717), Color(hex: 0xF2E4D0)) }
    
    /// Border of today's calendar pill: neutral ink on dark suites, a softened accent on light ones.
    public static var calendarTodayBorder: Color { lightThemeColor(text.opacity(0.8), accent.opacity(0.6)) }
    public static var todayIvory: Color { lightThemeColor(Color(hex: 0xEEE8DC), accent) }
    public static var todaySelectionText: Color { lightThemeColor(Color(hex: 0x1A2026), background) }

    // Home glass stays neutral; status light is independent of the theme accent. `base` is the
    // milky fill used by light themes; dark suites tint the canvas with the tile's own light.
    public struct HomeDayGlassColors {
        public let base: Color
        public let reflection: Color
        public let neutralRim: Color
        public let completedLight: Color
        public let unfinishedLight: Color
        public let missedLight: Color
    }

    public static var homeDayGlassColors: HomeDayGlassColors {
        if ThemeManager.shared.currentTheme.isDark {
            return HomeDayGlassColors(
                base: Color(hex: 0x20262B, alpha: 0.58),
                reflection: Color(hex: 0xECF2F5),
                neutralRim: Color(hex: 0xCBD4DD),
                completedLight: Color(hex: 0x6AF5AD),
                unfinishedLight: Color(hex: 0xFFB96A),
                missedLight: Color(hex: 0xFF8294))
        }
        return HomeDayGlassColors(
            base: Color(hex: 0xFFFBF4, alpha: 0.60),
            reflection: Color(hex: 0xFFFFFF),
            neutralRim: Color(hex: 0x938879),
            completedLight: Color(hex: 0x1C965C),
            unfinishedLight: Color(hex: 0xDE7612),
            missedLight: Color(hex: 0xD0362E))
    }

    // Split presentation colors
    public static var upperBorder: Color { lightThemeColor(Color(hex: 0x494260), Color(hex: 0xC7AFBA)) }
    public static var lowerBorder: Color { lightThemeColor(Color(hex: 0x37485F), Color(hex: 0xA8B8C6)) }
    public static var fullBodyBorder: Color { lightThemeColor(Color(hex: 0x414C57), Color(hex: 0xC7B6A1)) }
    
    // History Day Detail Sheet specific colors matching design reference
    public static var toContinueSurface: Color { presentationColor(Color(hex: 0x102523), positiveBg) }
    public static var progressTrack: Color { presentationColor(Color(hex: 0x1D262B), border) }
    
    // PR Badge & Tile colors (Orange identity)
    public static var orangePrBg: Color { lightThemeColor(Color(hex: 0x2C1E14), Color(hex: 0xF2E4D0)) }
    public static var orangePrBorder: Color { lightThemeColor(Color(hex: 0x6E461F), Color(hex: 0xC7A477)) }
    public static var orangePrText: Color { lightThemeColor(Color(hex: 0xF2AF61), Color(hex: 0x845014)) }
    public static var goldPrBg: Color { lightThemeColor(Color(hex: 0x2C1E14), Color(hex: 0xF2E4D0)) }
    public static var goldPrBorder: Color { lightThemeColor(Color(hex: 0x6E461F), Color(hex: 0xC7A477)) }
    public static var goldPrText: Color { lightThemeColor(Color(hex: 0xF2AF61), Color(hex: 0x845014)) }

    // Exercise Detail History Stat Card colors
    public static var historyStatCardBg: Color { presentationColor(Color(hex: 0x1A232A), surface) }
    public static var historyStatCardBorder: Color { presentationColor(Color(hex: 0x26323D), border) }
    public static var historyStatCardTitle: Color { presentationColor(Color(hex: 0x8E9BAE), muted) }
    public static var historyStatPrGreen: Color { lightThemeColor(Color(hex: 0x20D791), Color(hex: 0x1D7050)) }
    public static var historyStat1RmAmber: Color { lightThemeColor(Color(hex: 0xFEB447), Color(hex: 0x845014)) }
    public static var historyStatCyan: Color { lightThemeColor(Color(hex: 0x38BDF8), Color(hex: 0x1B6681)) }
    public static var historyStatPurple: Color { lightThemeColor(Color(hex: 0xB18AFF), Color(hex: 0x765064)) }

    public static var heroSurface: Color { presentationColor(Color(hex: 0x1E242B), surfaceRaised) }
    public static var heroBorder: Color { presentationColor(Color(hex: 0x343A41), border) }
    // The original recovery photograph's neutral studio tone, beneath the native theme gradients.
    public static let recoveryStudioBackdrop = Color(hex: 0x090909)
    public static var restRingShade: Color { presentationColor(Color(hex: 0x7952D6), Color.mix(purple, background, 0.25)) }
    public static var restRingLight: Color { presentationColor(Color(hex: 0xE0BCFF), Color.mix(purple, text, 0.3)) }

    public static var completedSurface: Color { lightThemeColor(Color(hex: 0x14241D), Color(hex: 0xE2EDE4)) }
    public static var unfinishedSummarySurface: Color { lightThemeColor(Color(hex: 0x261D13), Color(hex: 0xF2E4D0)) }
    public static var completedDaySurface: Color { lightThemeColor(Color(hex: 0x1B332B), Color(hex: 0xE2EDE4)) }
    public static var completedDayText: Color { lightThemeColor(Color(hex: 0xD8F3E5), Color(hex: 0x1D7050)) }
    public static var calendarPillText: Color { lightThemeColor(background, Color(hex: 0x090C0F)) }
    public static var goalSegmentActive: Color { lightThemeColor(Color(hex: 0x21E498), Color(hex: 0x258759)) }
    public static var goalSegmentPending: Color { lightThemeColor(Color(hex: 0x1E946A), Color(hex: 0x739681)) }

    public static func lightThemeColor(_ dark: Color, _ light: Color) -> Color {
        ThemeManager.shared.currentTheme.isDark ? dark : light
    }

    private static func presentationColor(_ original: Color, _ themed: Color) -> Color {
        ThemeManager.shared.currentTheme.id == AppThemes.default.id ? original : themed
    }
    public static var bodyViewSelectedSurface: Color { presentationColor(Color(hex: 0x25232D), purpleBg) }
    public static var bodyViewSelectedBorder: Color { presentationColor(Color(hex: 0x51455F), purple) }
    public static var bodyViewSelectedText: Color { presentationColor(Color(hex: 0xD8CFDF), purple) }

    // Warmup Set demarcation
    public static var warmupAmber: Color { lightThemeColor(Color(hex: 0xFEB447), Color(hex: 0x845014)) }
    public static var warmupAmberBg: Color { lightThemeColor(Color(hex: 0x2C1E14), Color(hex: 0xF2E4D0)) }
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
