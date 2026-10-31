import Foundation

/// Watch strings from `data/localization/<language>/watch.json`, in the language the iPhone app resolved.
enum WatchStrings {
    private static let bundles: [String: Bundle] = Dictionary(uniqueKeysWithValues: ["en", "tr", "de", "fr", "es"].map { code in
        (code, Bundle.main.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:)) ?? Bundle.main)
    })

    static func t(_ key: String, language: String, _ params: [String: Any] = [:]) -> String {
        let text = (bundles[language] ?? bundles["en"] ?? Bundle.main).localizedString(forKey: key, value: nil, table: nil)
        return params.reduce(text) { $0.replacingOccurrences(of: "{\($1.key)}", with: "\($1.value)") }
    }

    /// Loads keep up to two decimals, as the iPhone's set fields do.
    static func load(_ value: Double, language: String) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).grouping(.never).locale(Locale(identifier: language)))
    }

    static func clock(_ seconds: Int) -> String {
        let clamped = max(0, seconds)
        return String(format: "%d:%02d", clamped / 60, clamped % 60)
    }
}
