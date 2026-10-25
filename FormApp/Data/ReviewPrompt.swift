import Foundation
import UIKit

/// Counts deliberate, unique workout saves observed on this device. Imports and restores never call it.
struct ReviewPromptState: Codable, Equatable {
    static let storageKey = "review_prompt_v1"
    static let cooldownMillis: Int64 = 90 * 24 * 60 * 60 * 1000
    var countedSessionIds: Set<String> = []
    var pending = false
    var lastAttemptEpochMillis: Int64?

    private func cooldownElapsed(_ now: Int64) -> Bool {
        lastAttemptEpochMillis.map { now >= $0 && now - $0 >= Self.cooldownMillis } ?? true
    }
    func canAttempt(now: Int64) -> Bool { pending && countedSessionIds.count >= 5 && cooldownElapsed(now) }

    func recording(_ record: WorkoutSessionRecord, now: Int64) -> Self {
        guard !record.id.isEmpty, record.id.utf16.count <= 100, !record.id.hasPrefix("import-"), record.programId != "imported", !countedSessionIds.contains(record.id),
              record.exerciseLogs.contains(where: { log in log.sets.contains {
                  !$0.isWarmup && ($0.reps ?? 0) > 0 && $0.weightKg.map { $0.isFinite && $0 >= 0 } == true
              } }) else { return self }
        var copy = self
        copy.countedSessionIds.insert(record.id)
        if copy.countedSessionIds.count >= 5 && cooldownElapsed(now) { copy.pending = true }
        return copy
    }
    func attempting(now: Int64) -> Self {
        guard canAttempt(now: now) else { return self }
        var copy = self; copy.pending = false; copy.lastAttemptEpochMillis = now
        return copy
    }
    @discardableResult func persist(to defaults: UserDefaults = .standard) -> Bool {
        guard let data = try? JSONEncoder().encode(self) else { return false }
        defaults.set(data, forKey: Self.storageKey)
        return true
    }
    static func load(from defaults: UserDefaults = .standard) -> Self {
        guard let data = defaults.data(forKey: storageKey), var value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        value.countedSessionIds = Set(value.countedSessionIds.filter { !$0.isEmpty && $0.utf16.count <= 100 }.prefix(10_000))
        value.pending = value.pending && value.countedSessionIds.count >= 5
        if let last = value.lastAttemptEpochMillis, last < 0 { value.lastAttemptEpochMillis = nil }
        return value
    }
}

@MainActor enum ReviewPromptPresentation {
    /// A test spy exercises the actual RootView gate without displaying a store sheet during XCTest.
    static var testRequestHandler: (() -> Void)?
    static var nativeRequestsEnabled: Bool { testRequestHandler != nil || NSClassFromString("XCTestCase") == nil }

    static func hostIsIdle() -> Bool {
        guard UIApplication.shared.applicationState == .active,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }),
              let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController else { return false }
        return root.presentedViewController == nil && root.transitionCoordinator == nil && !root.isBeingPresented && !root.isBeingDismissed
    }
    static func request(_ native: () -> Void) {
        if let testRequestHandler { testRequestHandler() } else { native() }
    }
}
