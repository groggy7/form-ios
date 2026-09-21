import Foundation

public enum StrongCsvParser {

    private static let dateFormats = [
        "yyyy-MM-dd HH:mm:ss",
        "yyyy-MM-dd HH:mm",
        "dd.MM.yyyy HH:mm:ss",
        "dd.MM.yyyy HH:mm",
        "MM/dd/yyyy HH:mm:ss",
        "MM/dd/yyyy HH:mm",
        "yyyy-MM-dd'T'HH:mm:ss",
        "yyyy-MM-dd"
    ]

    public static func isStrongCsv(_ headers: [String]) -> Bool {
        let lower = headers.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        let hasDate = lower.contains("date")
        let hasWorkoutName = lower.contains("workout name") || lower.contains("workout title")
        let hasExercise = lower.contains("exercise name")
        return hasDate && (hasWorkoutName || hasExercise)
    }

    public static func parseDuration(_ raw: String) -> Int {
        let clean = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if clean.isEmpty { return 0 }
        if let sec = Int(clean) { return sec }

        var totalSeconds = 0
        if let hourRange = clean.range(of: #"(\d+)\s*h"#, options: .regularExpression),
           let h = Int(clean[hourRange].filter { $0.isNumber }) {
            totalSeconds += h * 3600
        }
        if let minRange = clean.range(of: #"(\d+)\s*m"#, options: .regularExpression),
           let m = Int(clean[minRange].filter { $0.isNumber }) {
            totalSeconds += m * 60
        }
        if let secRange = clean.range(of: #"(\d+)\s*s"#, options: .regularExpression),
           let s = Int(clean[secRange].filter { $0.isNumber }) {
            totalSeconds += s
        }
        return totalSeconds
    }

    public static func parseDateToIso(_ raw: String) -> (iso: String, day: String) {
        let clean = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\"", with: "")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        for fmt in dateFormats {
            formatter.dateFormat = fmt
            if let date = formatter.date(from: clean) {
                let isoFormatter = ISO8601DateFormatter()
                isoFormatter.formatOptions = [.withInternetDateTime]
                let dayFormatter = DateFormatter()
                dayFormatter.dateFormat = "yyyy-MM-dd"
                dayFormatter.timeZone = TimeZone(secondsFromGMT: 0)
                return (isoFormatter.string(from: date), dayFormatter.string(from: date))
            }
        }

        let now = Date()
        let isoFormatter = ISO8601DateFormatter()
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        return (isoFormatter.string(from: now), dayFormatter.string(from: now))
    }

    private struct RawRow {
        let dateIso: String
        let dayKey: String
        let workoutTitle: String
        let exerciseName: String
        let setOrder: Int
        let weightKg: Double?
        let reps: Int?
        let durationSeconds: Int
    }

    public static func parse(rows: [[String]], canonicalNames: [String]) -> [WorkoutSessionRecord] {
        guard rows.count > 1 else { return [] }
        let header = rows[0].map { $0.trimmingCharacters(in: .whitespaces).lowercased() }

        guard let dateIdx = header.firstIndex(of: "date"),
              let exerciseIdx = header.firstIndex(of: "exercise name") else { return [] }

        let titleIdx = header.firstIndex(where: { $0 == "workout name" || $0 == "workout title" })
        let setOrderIdx = header.firstIndex(of: "set order")
        let weightIdx = header.firstIndex(of: "weight")
        let unitIdx = header.firstIndex(of: "weight unit")
        let repsIdx = header.firstIndex(of: "reps")
        let durationIdx = header.firstIndex(of: "workout duration")

        var rawRows: [RawRow] = []

        for i in 1..<rows.count {
            let row = rows[i]
            guard row.count > max(dateIdx, exerciseIdx) else { continue }
            let dateStr = row[dateIdx].trimmingCharacters(in: .whitespaces)
            guard !dateStr.isEmpty else { continue }

            let (isoDate, dayKey) = parseDateToIso(dateStr)
            let rawTitle = titleIdx.flatMap { idx in row.indices.contains(idx) ? row[idx] : nil }?.trimmingCharacters(in: .whitespaces) ?? ""
            let title = rawTitle.isEmpty ? "Workout" : rawTitle

            let rawExercise = row[exerciseIdx].trimmingCharacters(in: .whitespaces)
            guard !rawExercise.isEmpty else { continue }
            let resolvedExercise = ExerciseAliasDictionary.resolve(rawName: rawExercise, canonicalNames: canonicalNames)

            let rawWeight = weightIdx.flatMap { idx in row.indices.contains(idx) ? row[idx] : nil }?
                .replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces) ?? ""
            let weightVal = Double(rawWeight)
            let unitStr = unitIdx.flatMap { idx in row.indices.contains(idx) ? row[idx] : nil }?.trimmingCharacters(in: .whitespaces).lowercased() ?? "kg"
            let weightKg: Double? = {
                guard let val = weightVal else { return nil }
                if unitStr == "lbs" || unitStr == "lb" {
                    return val * WeightUnit.lbsToKg
                }
                return val
            }()

            let rawReps = repsIdx.flatMap { idx in row.indices.contains(idx) ? row[idx] : nil }?.trimmingCharacters(in: .whitespaces) ?? ""
            let reps = Int(rawReps)

            let rawOrder = setOrderIdx.flatMap { idx in row.indices.contains(idx) ? row[idx] : nil }?.trimmingCharacters(in: .whitespaces) ?? ""
            let setOrder = Int(rawOrder.filter { $0.isNumber }) ?? 1

            let durationSec = durationIdx.flatMap { idx in row.indices.contains(idx) ? row[idx] : nil }.map { parseDuration($0) } ?? 0

            rawRows.append(
                RawRow(
                    dateIso: isoDate,
                    dayKey: dayKey,
                    workoutTitle: title,
                    exerciseName: resolvedExercise,
                    setOrder: setOrder,
                    weightKg: weightKg,
                    reps: reps,
                    durationSeconds: durationSec
                )
            )
        }

        var workoutsMap: [String: [RawRow]] = [:]
        var groupKeysOrder: [String] = []

        for r in rawRows {
            let groupKey = "\(r.dayKey)_\(r.workoutTitle.lowercased())"
            if workoutsMap[groupKey] == nil {
                groupKeysOrder.append(groupKey)
                workoutsMap[groupKey] = []
            }
            workoutsMap[groupKey]?.append(r)
        }

        var records: [WorkoutSessionRecord] = []

        for key in groupKeysOrder {
            guard let group = workoutsMap[key], !group.isEmpty else { continue }
            let first = group[0]
            let startedAt = group.map { $0.dateIso }.min() ?? first.dateIso
            let completedAt = group.map { $0.dateIso }.max() ?? first.dateIso
            let maxDuration = group.map { $0.durationSeconds }.max() ?? 0

            var exerciseOrder: [String] = []
            var setsByExercise: [String: [SessionSetLog]] = [:]

            for row in group {
                if !exerciseOrder.contains(row.exerciseName) {
                    exerciseOrder.append(row.exerciseName)
                }
                var setList = setsByExercise[row.exerciseName] ?? []
                let nextSetNum = setList.count + 1
                setList.append(
                    SessionSetLog(
                        setNumber: nextSetNum,
                        weightKg: row.weightKg,
                        reps: row.reps
                    )
                )
                setsByExercise[row.exerciseName] = setList
            }

            let exerciseLogs = exerciseOrder.map { name in
                let sets = setsByExercise[name] ?? []
                return SessionExerciseLog(
                    exerciseName: name,
                    sets: sets,
                    targetSets: sets.count,
                    exerciseId: ExerciseCatalog.resolveCanonicalId(stableId: nil, name: name)
                )
            }

            let completedSets = exerciseLogs.reduce(0) { acc, ex in
                acc + ex.sets.filter { ($0.reps ?? 0) > 0 }.count
            }
            let volumeKg = exerciseLogs.reduce(0.0) { acc, ex in
                acc + ex.sets.reduce(0.0) { sAcc, s in
                    sAcc + (s.weightKg ?? 0.0) * Double(s.reps ?? 0)
                }
            }

            let durationSeconds = maxDuration > 0 ? maxDuration : completedSets * 90
            let slug = first.workoutTitle.lowercased().replacingOccurrences(of: "[^a-z0-9_]", with: "_", options: .regularExpression)

            records.append(
                WorkoutSessionRecord(
                    id: UUID().uuidString,
                    programId: "imported",
                    workoutId: "imported_\(slug)",
                    workoutTitle: first.workoutTitle,
                    startedAt: startedAt,
                    completedAt: completedAt,
                    durationSeconds: durationSeconds,
                    totalVolumeKg: volumeKg,
                    totalCompletedSets: completedSets,
                    exerciseLogs: exerciseLogs,
                    isComplete: true
                )
            )
        }

        return records.sorted { $0.startedAt < $1.startedAt }
    }
}
