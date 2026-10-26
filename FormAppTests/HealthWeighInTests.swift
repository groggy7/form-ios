import XCTest
import SwiftUI
@testable import FormApp

/// Health weigh-in fixtures from docs/design/body-and-joint-journal.md#fixtures, plus storage and reading rules.
/// Android HealthWeighInTest covers the same cases.
final class HealthWeighInTests: XCTestCase {
    private let today = "2026-10-20"
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func sample(_ date: String, _ hour: Int, _ kg: Double) -> HealthWeighIn {
        let day = utc.date(from: DateComponents(year: Int(date.prefix(4)), month: Int(date.dropFirst(5).prefix(2)), day: Int(date.suffix(2))))!
        return HealthWeighIn(date: date, time: day.addingTimeInterval(Double(hour) * 3600), kg: kg)
    }

    private func shown(_ stored: [BodyEntry], _ health: [String: Double], hidden: [String] = []) -> ShownBodyLog {
        BodyLog.merge(stored, health: health, hidden: Set(hidden))
    }

    // MARK: Reading

    func testEarliestValidWeighInOfEachDayInsideTheWindow() {
        XCTAssertEqual(HealthWeighIns.daily([sample(today, 21, 79.8), sample(today, 7, 80.4)], today: today), [today: 80.4])
        XCTAssertEqual(HealthWeighIns.daily([sample(today, 6, 12), sample(today, 7, 80.2)], today: today), [today: 80.2])
        let tomorrow = BodyDay.string(BodyDay.number(today)! + 1)
        let yearAgo = BodyDay.string(BodyDay.number(today)! - 365)
        let lastInWindow = BodyDay.string(BodyDay.number(today)! - 364)
        XCTAssertEqual(HealthWeighIns.daily([sample(tomorrow, 7, 80), sample(yearAgo, 7, 81), sample(lastInWindow, 7, 82)], today: today),
                       [lastInWindow: 82])
        XCTAssertTrue(HealthWeighIns.daily([sample(today, 7, .nan), sample(today, 8, 401)], today: today).isEmpty)
    }

    // MARK: Merge rules

    func testMergeFixtures() {
        // Fills an empty date.
        var log = shown([], [today: 80])
        XCTAssertEqual(log.entries, [BodyEntry(date: today, bodyweightKg: 80)])
        XCTAssertEqual(log.healthDates, [today])
        // A typed weight wins.
        log = shown([BodyEntry(date: today, bodyweightKg: 80)], [today: 81])
        XCTAssertEqual(log.entries, [BodyEntry(date: today, bodyweightKg: 80)])
        XCTAssertTrue(log.healthDates.isEmpty)
        XCTAssertEqual(log.health[today], 81)
        // Joins typed measurements.
        log = shown([BodyEntry(date: today, waistCm: 85)], [today: 80])
        XCTAssertEqual(log.entries, [BodyEntry(date: today, bodyweightKg: 80, waistCm: 85)])
        XCTAssertEqual(log.healthDates, [today])
        // Hidden.
        log = shown([], [today: 80], hidden: [today])
        XCTAssertTrue(log.entries.isEmpty)
        XCTAssertNil(log.health[today])
        // Hidden with typed measurements keeps only them, sorted with other dates.
        log = shown([BodyEntry(date: today, waistCm: 85)], [today: 80, "2026-10-01": 82], hidden: [today])
        XCTAssertEqual(log.entries, [BodyEntry(date: "2026-10-01", bodyweightKg: 82), BodyEntry(date: today, waistCm: 85)])
        // The trend reads the shown log: typed 80.0 on day 0 and Health 81.0 on day 1 give the daily fixture's 80.1.
        let yesterday = BodyDay.string(BodyDay.number(today)! - 1)
        let trend = BodyTrends.trend(shown([BodyEntry(date: yesterday, bodyweightKg: 80)], [today: 81]).entries)
        XCTAssertEqual(trend.last?.trendKg ?? 0, 80.1, accuracy: 1e-9)
    }

    // MARK: Editing

    private func form(_ weight: String, waist: String = "") -> [BodyMetric: String] { [.bodyweight: weight, .waist: waist] }

    func testSavedUnchangedKeepsTheHealthWeightUnstored() {
        let outcome = BodyLog.resolveForm(date: today, inputs: form("80", waist: "85"), stored: nil, healthKg: 80, unit: .kg)
        XCTAssertEqual(outcome, .save(stored: BodyEntry(date: today, waistCm: 85), hideHealth: false))
        XCTAssertEqual(shown([BodyEntry(date: today, waistCm: 85)], [today: 80]).entries, [BodyEntry(date: today, bodyweightKg: 80, waistCm: 85)])
        // Nothing typed stores nothing, and is not an empty-form error.
        XCTAssertEqual(BodyLog.resolveForm(date: today, inputs: form("80"), stored: nil, healthKg: 80, unit: .kg),
                       .save(stored: nil, hideHealth: false))
        // In pounds the untouched display value still resolves to Health's exact kilograms.
        let kg = 80.3765
        XCTAssertEqual(BodyLog.resolveForm(date: today, inputs: form(BodyUnits.formatCanonical(.bodyweight, kg, unit: .lbs)), stored: nil,
                                           healthKg: kg, unit: .lbs), .save(stored: nil, hideHealth: false))
    }

    func testChangedHealthWeightIsStoredAsTyped() {
        let outcome = BodyLog.resolveForm(date: today, inputs: form("79"), stored: nil, healthKg: 80, unit: .kg)
        XCTAssertEqual(outcome, .save(stored: BodyEntry(date: today, bodyweightKg: 79), hideHealth: false))
        let log = shown([BodyEntry(date: today, bodyweightKg: 79)], [today: 80])
        XCTAssertEqual(log.entries.first?.bodyweightKg, 79)
        XCTAssertTrue(log.healthDates.isEmpty)
    }

    func testClearedHealthWeightHidesItAndKeepsMeasurements() {
        let stored = BodyEntry(date: today, waistCm: 85)
        let outcome = BodyLog.resolveForm(date: today, inputs: form("", waist: "85"), stored: stored, healthKg: 80, unit: .kg)
        XCTAssertEqual(outcome, .save(stored: stored, hideHealth: true))
        let edit = BodyLog.applyEdit([stored], hidden: [], date: today, stored: stored, hideHealth: true)
        XCTAssertEqual(edit.entries, [stored])
        XCTAssertEqual(edit.hidden, [today])
        XCTAssertEqual(shown(edit.entries, [today: 80], hidden: edit.hidden).entries, [stored])
        // A blank form with no Health weigh-in is still an empty entry.
        XCTAssertEqual(BodyLog.resolveForm(date: today, inputs: form(""), stored: nil, healthKg: nil, unit: .kg), .empty)
        XCTAssertEqual(BodyLog.resolveForm(date: today, inputs: form("500"), stored: nil, healthKg: 80, unit: .kg), .invalid(.bodyweight))
    }

    func testQuickLogChangesOnlyTheWeightAndKeepsMeasurements() {
        let stored = BodyEntry(date: today, bodyweightKg: 80, waistCm: 85)
        let inputs = BodyLog.quickLogInputs(shown: stored, weight: "79,5", unit: .kg)
        XCTAssertEqual(BodyLog.resolveForm(date: today, inputs: inputs, stored: stored, healthKg: nil, unit: .kg),
                       .save(stored: BodyEntry(date: today, bodyweightKg: 79.5, waistCm: 85), hideHealth: false))
        // An untouched Health weight stays Health's, and the date's typed measurements stay stored.
        let health = BodyEntry(date: today, bodyweightKg: 80, chestCm: 101)
        let unchanged = BodyLog.quickLogInputs(shown: health, weight: "80", unit: .kg)
        XCTAssertEqual(BodyLog.resolveForm(date: today, inputs: unchanged, stored: BodyEntry(date: today, chestCm: 101), healthKg: 80, unit: .kg),
                       .save(stored: BodyEntry(date: today, chestCm: 101), hideHealth: false))
        // In pounds, measurements are shown in inches and still resolve to their exact stored centimetres.
        let lbs = BodyLog.quickLogInputs(shown: stored, weight: "176", unit: .lbs)
        XCTAssertEqual(BodyLog.resolveForm(date: today, inputs: lbs, stored: stored, healthKg: nil, unit: .lbs),
                       .save(stored: BodyEntry(date: today, bodyweightKg: BodyUnits.toCanonical(.bodyweight, 176, unit: .lbs), waistCm: 85), hideHealth: false))
    }

    func testDeleteHidesTheHealthWeighInOnlyWhenThereIsOne() {
        let typed = BodyEntry(date: today, bodyweightKg: 80)
        var edit = BodyLog.applyEdit([typed], hidden: [], date: today, stored: nil, hideHealth: true)
        XCTAssertTrue(edit.entries.isEmpty)
        XCTAssertEqual(edit.hidden, [today])
        XCTAssertTrue(shown(edit.entries, [today: 81], hidden: edit.hidden).entries.isEmpty)
        // Reading off: nothing to hide.
        edit = BodyLog.applyEdit([typed], hidden: [], date: today, stored: nil, hideHealth: false)
        XCTAssertTrue(edit.entries.isEmpty)
        XCTAssertTrue(edit.hidden.isEmpty)
        // Hiding twice keeps one date.
        XCTAssertEqual(BodyLog.applyEdit([], hidden: [today], date: today, stored: nil, hideHealth: true).hidden, [today])
    }

    func testStoreAppliesEditsAndBackupsCarryHiddenDatesButNoHealthValues() throws {
        let store = AppStore(persistence: AppStatePersistence(inMemory: true))
        let now = ISO8601DateFormatter().date(from: "2026-10-20T12:00:00Z")!
        let date = BodyDay.today(now)
        XCTAssertTrue(store.applyBodyEdit(date: date, stored: BodyEntry(date: date, waistCm: 85), hideHealth: true, now: now))
        XCTAssertEqual(store.state.bodyEntries, [BodyEntry(date: date, waistCm: 85)])
        XCTAssertEqual(store.state.hiddenHealthWeighIns, [date])
        XCTAssertFalse(store.applyBodyEdit(date: date, stored: BodyEntry(date: date, bodyweightKg: 500), hideHealth: false, now: now))
        XCTAssertTrue(store.deleteBodyEntry(date: date, hideHealth: true))
        XCTAssertNil(store.state.bodyEntries)
        XCTAssertEqual(store.state.hiddenHealthWeighIns, [date])

        let state = StoredAppState(currentWeekKey: "2026-W43", bodyEntries: [BodyEntry(date: "2026-10-01", waistCm: 85)],
                                   hiddenHealthWeighIns: ["2026-10-02", "bad", "2026-10-02", "2099-01-01", "2026-09-30"])
        let data = try JSONEncoder().encode(FullBackupDocument(state: state, weightUnit: .kg))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["schemaVersion"] as? Int, 6)
        let restored = try JSONDecoder().decode(FullBackupDocument.self, from: data).state
        XCTAssertEqual(restored.hiddenHealthWeighIns, ["2026-09-30", "2026-10-02"])
        XCTAssertEqual(restored.bodyEntries, [BodyEntry(date: "2026-10-01", waistCm: 85)])
        let empty = try JSONEncoder().encode(FullBackupDocument(state: StoredAppState(currentWeekKey: "2026-W43"), weightUnit: .kg))
        XCTAssertNil((try JSONSerialization.jsonObject(with: empty) as? [String: Any])?["hiddenHealthWeighIns"])
    }

    // MARK: Reader

    private final class FakeSource: HealthWeightSource {
        var isAvailable = true
        var requests = 0
        var samples: [(time: Date, kg: Double)] = []
        var failure: Error?
        var lastRange: (Date, Date)?

        func requestAccess() async throws { requests += 1 }
        func weighIns(from start: Date, to end: Date) async throws -> [(time: Date, kg: Double)] {
            lastRange = (start, end)
            if let failure { throw failure }
            return samples
        }
    }

    @MainActor func testReaderConnectsReadsAndTurnsOffWithoutStoringAnything() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "HealthWeighInTests"))
        defaults.removePersistentDomain(forName: "HealthWeighInTests")
        let source = FakeSource()
        let now = Date()
        let todayString = BodyDay.today(now)
        let morning = Calendar.current.startOfDay(for: now).addingTimeInterval(1)
        source.samples = [(morning.addingTimeInterval(60), 79.6), (morning, 80.2)]
        let reader = HealthWeights(source: source, defaults: defaults)
        XCTAssertFalse(reader.isEnabled)
        await reader.refresh(now: now)
        XCTAssertTrue(reader.weighIns.isEmpty, "Nothing is read before Connect")

        await reader.connect()
        XCTAssertEqual(source.requests, 1)
        XCTAssertTrue(reader.isEnabled)
        XCTAssertTrue(defaults.bool(forKey: HealthWeights.enabledKey))
        XCTAssertEqual(reader.weighIns, [todayString: 80.2])
        XCTAssertEqual(reader.status, .loaded)
        XCTAssertEqual(reader.latestDate, todayString)
        let (start, _) = try XCTUnwrap(source.lastRange)
        XCTAssertEqual(Calendar.current.dateComponents([.day], from: start, to: Calendar.current.startOfDay(for: now)).day, 364)

        // A failed read keeps the last weigh-ins.
        source.failure = URLError(.cannotLoadFromNetwork)
        await reader.refresh(now: now)
        XCTAssertEqual(reader.status, .failed)
        XCTAssertEqual(reader.weighIns, [todayString: 80.2])

        // A new run restores the setting without asking again.
        source.failure = nil
        let relaunched = HealthWeights(source: source, defaults: defaults)
        XCTAssertTrue(relaunched.isEnabled)
        await relaunched.refresh(now: now)
        XCTAssertEqual(source.requests, 1)
        XCTAssertEqual(relaunched.weighIns.count, 1)

        relaunched.turnOff()
        XCTAssertFalse(relaunched.isEnabled)
        XCTAssertTrue(relaunched.weighIns.isEmpty)
        XCTAssertEqual(relaunched.status, .idle)
        XCTAssertFalse(defaults.bool(forKey: HealthWeights.enabledKey))

        // No Health data store: never enabled.
        source.isAvailable = false
        defaults.set(true, forKey: HealthWeights.enabledKey)
        XCTAssertFalse(HealthWeights(source: source, defaults: defaults).isEnabled)
        defaults.removePersistentDomain(forName: "HealthWeighInTests")
    }

    /// Captures for review under forcedrep-ios/build/health-weight-review/: the Health card off, on and empty,
    /// and a Health entry's row source line, at 393pt and at 320pt with the largest standard text, in every language.
    @MainActor func testHealthCardRendersInEveryLanguage() throws {
        let previous = LanguageManager.shared.languagePreference
        defer { LanguageManager.setLanguage(previous) }
        let outputDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../build/health-weight-review").standardized
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        for language in ["en", "tr", "de", "fr", "es"] {
            LanguageManager.setLanguage(language)
            for (width, size) in [(CGFloat(393), ContentSizeCategory.large), (320, .extraExtraExtraLarge)] {
                let content = VStack(spacing: 16) {
                    BodyHealthCard(isEnabled: false, status: nil, isBusy: false, onConnect: {}, onTurnOff: {})
                    BodyHealthCard(isEnabled: true, status: LanguageManager.t("body.health.latest", ["date": "20 Oct 2026"]),
                                   isBusy: false, onConnect: {}, onTurnOff: {})
                    BodyHealthCard(isEnabled: true, status: LanguageManager.t("body.health.none"), isBusy: false, onConnect: {}, onTurnOff: {})
                    Text(LanguageManager.t("body.health.editNotice")).font(.system(size: 12)).foregroundStyle(AppColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(LanguageManager.t("body.health.from")).font(.system(size: 12)).foregroundStyle(AppColors.muted)
                }
                .padding(16).frame(width: width).frame(maxHeight: .infinity, alignment: .top).background(AppColors.background)
                .environment(\.sizeCategory, size)
                let controller = UIHostingController(rootView: content)
                let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: size == .large ? 1000 : 1700))
                window.rootViewController = controller
                window.makeKeyAndVisible()
                defer { window.isHidden = true }
                controller.view.frame = window.bounds
                controller.view.layoutIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.3))
                let image = UIGraphicsImageRenderer(bounds: controller.view.bounds).image { _ in
                    controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
                }
                XCTAssertEqual(image.size.width, width)
                try XCTUnwrap(image.pngData()).write(to: outputDir.appendingPathComponent("health-card-\(language)-\(Int(width)).png"))
            }
        }
    }
}
