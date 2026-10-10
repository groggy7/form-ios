import SwiftUI

public struct AppThemePalette: Identifiable, Equatable {
    public let id: String
    public let nameKey: String
    public let descriptionKey: String
    public let isPremium: Bool
    public let background: Color
    public let surface: Color
    public let surfaceRaised: Color
    public let border: Color
    public let text: Color
    public let secondaryText: Color
    public let muted: Color
    public let accent: Color
    public let positiveBg: Color
    public let purple: Color
    public let purpleBg: Color
    public let coral: Color
    public let danger: Color
    public let calendarSurfaceStart: Color
    public let calendarSurfaceEnd: Color

    public static func == (lhs: AppThemePalette, rhs: AppThemePalette) -> Bool {
        lhs.id == rhs.id
    }
}

public enum AppThemes {
    public static let `default` = AppThemePalette(
        id: "default",
        nameKey: "theme.default.name",
        descriptionKey: "theme.default.description",
        isPremium: false,
        background: Color(hex: 0x090C0F),
        surface: Color(hex: 0x13171B),
        surfaceRaised: Color(hex: 0x1D2227),
        border: Color(hex: 0x2A3238),
        text: Color(hex: 0xF3F5F5),
        secondaryText: Color(hex: 0xB6BEC4),
        muted: Color(hex: 0x8F999F),
        accent: Color(hex: 0x49C7AF),
        positiveBg: Color(hex: 0x142D29),
        purple: Color(hex: 0xB18AFF),
        purpleBg: Color(hex: 0x28203D),
        coral: Color(hex: 0xFF8C78),
        danger: Color(hex: 0xFF897B),
        calendarSurfaceStart: Color(hex: 0x151A1E),
        calendarSurfaceEnd: Color(hex: 0x101418)
    )

    public static let espresso = AppThemePalette(
        id: "espresso",
        nameKey: "theme.espresso.name",
        descriptionKey: "theme.espresso.description",
        isPremium: true,
        background: Color(hex: 0x120E0C),
        surface: Color(hex: 0x1C1613),
        surfaceRaised: Color(hex: 0x271F1A),
        border: Color(hex: 0x382C25),
        text: Color(hex: 0xF7F2EC),
        secondaryText: Color(hex: 0xC7BCB1),
        muted: Color(hex: 0x9E9185),
        accent: Color(hex: 0xD8B382),
        positiveBg: Color(hex: 0x2D2117),
        purple: Color(hex: 0xD4A373),
        purpleBg: Color(hex: 0x2E2218),
        coral: Color(hex: 0xE28468),
        danger: Color(hex: 0xE06D53),
        calendarSurfaceStart: Color(hex: 0x1E1714),
        calendarSurfaceEnd: Color(hex: 0x140F0D)
    )

    public static let stealth = AppThemePalette(
        id: "stealth",
        nameKey: "theme.stealth.name",
        descriptionKey: "theme.stealth.description",
        isPremium: true,
        background: Color(hex: 0x000000),
        surface: Color(hex: 0x0E0E12),
        surfaceRaised: Color(hex: 0x18181E),
        border: Color(hex: 0x26262D),
        text: Color(hex: 0xFFFFFF),
        secondaryText: Color(hex: 0xC0C4CC),
        muted: Color(hex: 0x7A7E85),
        accent: Color(hex: 0xE2E8F0),
        positiveBg: Color(hex: 0x1F2024),
        purple: Color(hex: 0xB8B8C8),
        purpleBg: Color(hex: 0x232328),
        coral: Color(hex: 0xFF8C78),
        danger: Color(hex: 0xFF6B6B),
        calendarSurfaceStart: Color(hex: 0x121217),
        calendarSurfaceEnd: Color(hex: 0x0A0A0D)
    )

    public static let cobalt = AppThemePalette(
        id: "cobalt",
        nameKey: "theme.cobalt.name",
        descriptionKey: "theme.cobalt.description",
        isPremium: true,
        background: Color(hex: 0x080C14),
        surface: Color(hex: 0x101622),
        surfaceRaised: Color(hex: 0x172030),
        border: Color(hex: 0x202D42),
        text: Color(hex: 0xF0F6FC),
        secondaryText: Color(hex: 0xA5B4C7),
        muted: Color(hex: 0x6E8096),
        accent: Color(hex: 0x38BDF8),
        positiveBg: Color(hex: 0x0C2B3E),
        purple: Color(hex: 0x9382F8),
        purpleBg: Color(hex: 0x1F223D),
        coral: Color(hex: 0xFF7F66),
        danger: Color(hex: 0xFF6B6B),
        calendarSurfaceStart: Color(hex: 0x131B2A),
        calendarSurfaceEnd: Color(hex: 0x0C121D)
    )

    public static let alpine = AppThemePalette(
        id: "alpine",
        nameKey: "theme.alpine.name",
        descriptionKey: "theme.alpine.description",
        isPremium: true,
        background: Color(hex: 0x080E0B),
        surface: Color(hex: 0x0F1A15),
        surfaceRaised: Color(hex: 0x172620),
        border: Color(hex: 0x21362D),
        text: Color(hex: 0xEDF7F2),
        secondaryText: Color(hex: 0xA3BEB1),
        muted: Color(hex: 0x6C8578),
        accent: Color(hex: 0x34D399),
        positiveBg: Color(hex: 0x113324),
        purple: Color(hex: 0xA78BFA),
        purpleBg: Color(hex: 0x202B27),
        coral: Color(hex: 0xF87171),
        danger: Color(hex: 0xEF4444),
        calendarSurfaceStart: Color(hex: 0x12201A),
        calendarSurfaceEnd: Color(hex: 0x0B1410)
    )

    public static let crimson = AppThemePalette(
        id: "crimson",
        nameKey: "theme.crimson.name",
        descriptionKey: "theme.crimson.description",
        isPremium: true,
        background: Color(hex: 0x12080A),
        surface: Color(hex: 0x1C1013),
        surfaceRaised: Color(hex: 0x29181C),
        border: Color(hex: 0x3D2228),
        text: Color(hex: 0xFAF0F1),
        secondaryText: Color(hex: 0xC9B0B4),
        muted: Color(hex: 0x8F7377),
        accent: Color(hex: 0xF4978E),
        positiveBg: Color(hex: 0x31161B),
        purple: Color(hex: 0xC084FC),
        purpleBg: Color(hex: 0x2B1520),
        coral: Color(hex: 0xFB7185),
        danger: Color(hex: 0xF43F5E),
        calendarSurfaceStart: Color(hex: 0x201216),
        calendarSurfaceEnd: Color(hex: 0x150A0D)
    )

    public static let amethyst = AppThemePalette(
        id: "amethyst",
        nameKey: "theme.amethyst.name",
        descriptionKey: "theme.amethyst.description",
        isPremium: true,
        background: Color(hex: 0x0D0914),
        surface: Color(hex: 0x161120),
        surfaceRaised: Color(hex: 0x211A30),
        border: Color(hex: 0x312747),
        text: Color(hex: 0xF5F0FF),
        secondaryText: Color(hex: 0xBDB3CE),
        muted: Color(hex: 0x7C708F),
        accent: Color(hex: 0xA855F7),
        positiveBg: Color(hex: 0x26143D),
        purple: Color(hex: 0xC084FC),
        purpleBg: Color(hex: 0x2F1A45),
        coral: Color(hex: 0xFF758F),
        danger: Color(hex: 0xF72585),
        calendarSurfaceStart: Color(hex: 0x1A1326),
        calendarSurfaceEnd: Color(hex: 0x100B1A)
    )

    public static let all: [AppThemePalette] = [
        `default`, espresso, stealth, cobalt, alpine, crimson, amethyst
    ]

    public static func fromId(_ id: String) -> AppThemePalette {
        all.first(where: { $0.id == id }) ?? `default`
    }
}

public final class ThemeManager: ObservableObject {
    public static let shared = ThemeManager()

    private let themeKey = "app_theme_id"

    @Published public private(set) var currentTheme: AppThemePalette

    public init() {
        let savedId = UserDefaults.standard.string(forKey: themeKey) ?? AppThemes.default.id
        self.currentTheme = AppThemes.fromId(savedId)
    }

    public func setThemeId(_ id: String) {
        let palette = AppThemes.fromId(id)
        currentTheme = palette
        UserDefaults.standard.set(id, forKey: themeKey)
        objectWillChange.send()
    }
}
