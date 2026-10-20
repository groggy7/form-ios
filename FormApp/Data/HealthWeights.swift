import Foundation
import HealthKit

/// Where Apple Health weigh-ins come from; tests substitute a fake.
protocol HealthWeightSource {
    var isAvailable: Bool { get }
    /// Shows the system Health sheet for reading Weight. iOS never reveals whether reading was allowed.
    func requestAccess() async throws
    func weighIns(from start: Date, to end: Date) async throws -> [(time: Date, kg: Double)]
}

struct HealthKitWeightSource: HealthWeightSource {
    private let store = HKHealthStore()
    private let bodyMass = HKQuantityType(.bodyMass)

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAccess() async throws {
        try await store.requestAuthorization(toShare: [], read: [bodyMass])
    }

    func weighIns(from start: Date, to end: Date) async throws -> [(time: Date, kg: Double)] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: bodyMass, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        return try await descriptor.result(for: store).map { ($0.startDate, $0.quantity.doubleValue(for: .gramUnit(with: .kilo))) }
    }
}

/// Reads bodyweight from Apple Health for the body log (docs/design/body-and-joint-journal.md#health-weigh-ins).
/// Weigh-ins stay in memory: they are never written to the app state, backups or iCloud Drive.
@MainActor
public final class HealthWeights: ObservableObject {
    public static let shared = HealthWeights()

    public enum Status: Equatable {
        /// Reading is off, or on with no read finished yet in this run.
        case idle
        case loaded
        /// The last read failed; `weighIns` keeps the last successful one.
        case failed
    }

    static let enabledKey = "health_weight_reading"

    @Published public private(set) var isEnabled: Bool
    @Published public private(set) var weighIns: [String: Double] = [:]
    @Published public private(set) var status: Status = .idle
    @Published public private(set) var isConnecting = false
    public var isAvailable: Bool { source.isAvailable }

    private let source: HealthWeightSource
    private let defaults: UserDefaults
    private var reading: Task<Void, Never>?

    init(source: HealthWeightSource = HealthKitWeightSource(), defaults: UserDefaults = .standard) {
        self.source = source
        self.defaults = defaults
        isEnabled = source.isAvailable && defaults.bool(forKey: Self.enabledKey)
    }

    /// The latest date with a weigh-in, for the Health card.
    public var latestDate: String? { weighIns.keys.max() }

    /// Asks for read access from the Body screen, then reads. Never called at launch.
    public func connect() async {
        guard source.isAvailable, !isConnecting else { return }
        isConnecting = true
        defer { isConnecting = false }
        do {
            try await source.requestAccess()
        } catch {
            status = .failed
            return
        }
        isEnabled = true
        defaults.set(true, forKey: Self.enabledKey)
        await refresh()
    }

    /// Stops reading and forgets this run's weigh-ins; nothing stored changes.
    public func turnOff() {
        reading?.cancel()
        reading = nil
        isEnabled = false
        defaults.set(false, forKey: Self.enabledKey)
        weighIns = [:]
        status = .idle
    }

    /// Reads the window again when reading is on. Overlapping calls share one read.
    public func refresh(now: Date = Date()) async {
        guard isEnabled else { return }
        if let reading { return await reading.value }
        let task = Task { await read(now: now) }
        reading = task
        await task.value
        reading = nil
    }

    private func read(now: Date) async {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -(HealthWeighIns.windowDays - 1), to: calendar.startOfDay(for: now)) ?? now
        do {
            let samples = try await source.weighIns(from: start, to: now).map {
                HealthWeighIn(date: BodyDay.today($0.time), time: $0.time, kg: $0.kg)
            }
            guard !Task.isCancelled, isEnabled else { return }
            weighIns = HealthWeighIns.daily(samples, today: BodyDay.today(now))
            status = .loaded
        } catch {
            guard !Task.isCancelled, isEnabled else { return }
            status = .failed
        }
    }
}

extension HealthWeights {
    /// The body log as shown on this device: typed entries joined with this run's weigh-ins.
    func shownLog(_ state: StoredAppState) -> ShownBodyLog {
        BodyLog.merge(state.bodyEntries ?? [], health: weighIns, hidden: Set(state.hiddenHealthWeighIns ?? []))
    }
}
