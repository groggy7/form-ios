import Foundation

public struct ExerciseIssueReport: Codable, Identifiable, Equatable {
    public let id: String
    public let clientUuid: String
    public let exerciseId: String?
    public let exerciseName: String
    public let category: String
    public let comment: String
    public let timestamp: String
    public var status: String
    public var receiptId: String?
    public var receivedAt: String?

    public init(
        id: String = UUID().uuidString,
        clientUuid: String = UUID().uuidString,
        exerciseId: String? = nil,
        exerciseName: String,
        category: String,
        comment: String = "",
        timestamp: String = ISO8601DateFormatter().string(from: Date()),
        status: String = "pending",
        receiptId: String? = nil,
        receivedAt: String? = nil
    ) {
        self.id = id
        self.clientUuid = clientUuid
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.category = category
        self.comment = comment
        self.timestamp = timestamp
        self.status = status
        self.receiptId = receiptId
        self.receivedAt = receivedAt
    }
}

public enum PreflightStatus: Equatable {
    case allowed
    case cooldown(isDaily: Bool, nextAllowedAt: Date, remaining24h: Int)
    case pending(ExerciseIssueReport)
}

public enum SubmissionResult {
    case success(receiptId: String, receivedAt: String, nextAllowedAt: String)
    case rateLimited(isDaily: Bool, nextAllowedAt: Date, retryAfterSec: Int)
    case offlineSaved
    case error(String)
}

public final class ExerciseReportStore {
    public static let shared = ExerciseReportStore()

    public static let defaultEndpoint = "https://forcedrep-exercise-reports.sabotage1135.workers.dev/v1/reports"

    public static let categories: [String] = [
        "animation_form",
        "technique_cue",
        "what_to_avoid",
        "muscles_worked",
        "equipment_category",
        "other"
    ]

    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.form.gym.ExerciseReportStore", attributes: .concurrent)
    private var retrying = false

    private static func parseServerDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    public init(fileURL: URL? = nil) {
        if let fileURL = fileURL {
            self.fileURL = fileURL
        } else {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            self.fileURL = docs.appendingPathComponent("exercise_issue_reports.json")
        }
    }

    public static func getInstallationId() -> String {
        let key = "exercise_report_installation_id"
        if let id = UserDefaults.standard.string(forKey: key), !id.isEmpty {
            return id
        }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: key)
        return newId
    }

    public func loadReports() -> [ExerciseIssueReport] {
        return queue.sync {
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
            do {
                let data = try Data(contentsOf: fileURL)
                let decoder = JSONDecoder()
                return try decoder.decode([ExerciseIssueReport].self, from: data)
            } catch {
                return []
            }
        }
    }

    @discardableResult
    public func saveReport(_ report: ExerciseIssueReport) throws -> [ExerciseIssueReport] {
        return try queue.sync(flags: .barrier) {
            var existing = [ExerciseIssueReport]()
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let data = try Data(contentsOf: fileURL)
                existing = try JSONDecoder().decode([ExerciseIssueReport].self, from: data)
            }

            if let index = existing.firstIndex(where: { $0.id == report.id || $0.clientUuid == report.clientUuid }) {
                existing[index] = report
            } else {
                existing.append(report)
            }

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(existing)
            let dir = fileURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: dir.path) {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            try data.write(to: fileURL, options: .atomic)
            return existing
        }
    }

    @discardableResult
    public func deleteReport(id: String) throws -> [ExerciseIssueReport] {
        return try queue.sync(flags: .barrier) {
            var existing = [ExerciseIssueReport]()
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let data = try Data(contentsOf: fileURL)
                existing = try JSONDecoder().decode([ExerciseIssueReport].self, from: data)
            }

            existing.removeAll(where: { $0.id == id || $0.clientUuid == id })

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(existing)
            try data.write(to: fileURL, options: .atomic)
            return existing
        }
    }

    public func checkPreflight(
        reports: [ExerciseIssueReport]? = nil,
        now: Date = Date(),
        calendar: Calendar = Calendar.current
    ) -> PreflightStatus {
        let allReports = reports ?? loadReports()

        // 1. Any report still pending outbox delivery?
        if let pendingReport = allReports.first(where: { $0.status == "pending" }) {
            return .pending(pendingReport)
        }

        // 2. Local calendar day limit check (resets at 00:00 local time)
        let startOfDay = calendar.startOfDay(for: now)
        let startOfNextDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay.addingTimeInterval(86400)

        let allAcceptedDates = allReports
            .filter { $0.status == "accepted" }
            .compactMap { report -> Date? in
                let dateStr = report.receivedAt ?? report.timestamp
                return Self.parseServerDate(dateStr)
            }
            .sorted()

        let acceptedToday = allAcceptedDates.filter { $0 >= startOfDay }

        if acceptedToday.count >= 3 {
            let lastReport1h = acceptedToday.last!.addingTimeInterval(3600)
            let nextAllowed = max(startOfNextDay, lastReport1h)
            return .cooldown(isDaily: true, nextAllowedAt: nextAllowed, remaining24h: 0)
        }

        let oneHourAgo = now.addingTimeInterval(-3600)
        let accepted1h = allAcceptedDates.filter { $0 > oneHourAgo }
        if let latest = accepted1h.last {
            let nextAllowed = latest.addingTimeInterval(3600)
            let remaining = max(0, 3 - acceptedToday.count)
            return .cooldown(isDaily: false, nextAllowedAt: nextAllowed, remaining24h: remaining)
        }

        return .allowed
    }

    public func submitReport(_ report: ExerciseIssueReport, endpoint: String = defaultEndpoint) async -> SubmissionResult {
        guard let url = URL(string: endpoint) else {
            return .error("Invalid URL")
        }

        let installationId = Self.getInstallationId()
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let language = LanguageManager.shared.currentLanguage
        let timeZone = TimeZone.current
        let tzOffsetMinutes = timeZone.secondsFromGMT() / 60

        var payload: [String: Any] = [
            "client_uuid": report.clientUuid,
            "installation_id": installationId,
            "platform": "ios",
            "app_version": appVersion,
            "language": language,
            "exercise_name": report.exerciseName,
            "category": report.category,
            "comment": report.comment,
            "timezone": timeZone.identifier,
            "tz_offset_minutes": tzOffsetMinutes
        ]
        if let exId = report.exerciseId {
            payload["exercise_id"] = exId
        }

        guard let httpBody = try? JSONSerialization.data(withJSONObject: payload) else {
            return .error("Failed to serialize request")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10
        request.httpBody = httpBody

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .error("Invalid server response")
            }

            if (200...299).contains(httpResponse.statusCode) {
                let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
                guard let receiptId = json["receipt_id"] as? String, !receiptId.isEmpty,
                      let receivedAt = json["received_at"] as? String,
                      Self.parseServerDate(receivedAt) != nil else {
                    return .offlineSaved
                }
                let nextAllowed = json["next_allowed_at"] as? String ?? ""

                var acceptedReport = report
                acceptedReport.status = "accepted"
                acceptedReport.receiptId = receiptId
                acceptedReport.receivedAt = receivedAt
                _ = try? saveReport(acceptedReport)
                return .success(receiptId: receiptId, receivedAt: receivedAt, nextAllowedAt: nextAllowed)
            } else if httpResponse.statusCode == 429 {
                let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
                let code = json["code"] as? String ?? ""
                guard code == "DAILY_LIMIT" || code == "HOURLY_COOLDOWN" else {
                    return .offlineSaved
                }
                let nextAllowedStr = json["next_allowed_at"] as? String ?? ""
                let nextAllowedDate = Self.parseServerDate(nextAllowedStr) ?? Date().addingTimeInterval(3600)
                let retryAfterSec = json["retry_after"] as? Int ?? 3600
                do { _ = try deleteReport(id: report.id) }
                catch { return .error(error.localizedDescription) }

                return .rateLimited(isDaily: code == "DAILY_LIMIT", nextAllowedAt: nextAllowedDate, retryAfterSec: retryAfterSec)
            } else if httpResponse.statusCode == 408 || httpResponse.statusCode == 425 || httpResponse.statusCode >= 500 {
                return .offlineSaved
            } else {
                do { _ = try deleteReport(id: report.id) }
                catch { return .error(error.localizedDescription) }
                return .error(LanguageManager.t("report.rejected"))
            }
        } catch is URLError {
            return .offlineSaved
        } catch {
            return .error(error.localizedDescription)
        }
    }

    @MainActor
    public func retryPendingReports() async {
        guard !retrying else { return }
        retrying = true
        defer { retrying = false }
        for report in loadReports().filter({ $0.status == "pending" }) {
            let result = await submitReport(report)
            if case .offlineSaved = result { break }
        }
    }

    public static func formatLocalTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    public static func formatLocalDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM, HH:mm"
        if LanguageManager.shared.currentLanguage == "tr" {
            formatter.locale = Locale(identifier: "tr_TR")
        } else {
            formatter.locale = Locale(identifier: "en_US")
        }
        return formatter.string(from: date)
    }
}
