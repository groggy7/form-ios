import Foundation

public enum HevyCsvParser {

    private static let dateFormats = [
        "dd MMM yyyy, HH:mm",
        "d MMM yyyy, HH:mm",
        "dd MMM yyyy, HH:mm:ss",
        "yyyy-MM-dd HH:mm:ss",
        "yyyy-MM-dd HH:mm",
        "dd.MM.yyyy HH:mm",
        "yyyy-MM-dd'T'HH:mm:ss",
        "yyyy-MM-dd"
    ]

    public static func isHevyCsv(_ headers: [String]) -> Bool {
        let lower = headers.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        let hasTitle = lower.contains("title")
        let hasStartTime = lower.contains("start_time")
        let hasExerciseTitle = lower.contains("exercise_title")
        let hasWeightLbs = lower.contains("weight_lbs") || lower.contains("weight_kg")
        return (hasTitle && hasStartTime) || (hasExerciseTitle && (hasWeightLbs || hasStartTime))
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
        let startIso: String
        let endIso: String?
        let dayKey: String
        let workoutTitle: String
        let exerciseName: String
        let setIndex: Int
        let weightKg: Double?
        let reps: Int?
        let durationSeconds: Int
    }

    public static func parse(rows: [[String]], canonicalNames: [String]) -> [WorkoutSessionRecord] {
        guard rows.count > 1 else { return [] }
        let header = rows[0].map { $0.trimmingCharacters(in: .whitespaces).lowercased() }

        guard let startIdx = header.firstIndex(of: "start_time"),
              let exerciseIdx = header.firstIndex(of: "exercise_title") else { return [] }

        let titleIdx = header.firstIndex(of: "title")
        let endIdx = header.firstIndex(of: "end_time")
        let setIdx = header.firstIndex(of: "set_index")
        let weightLbsIdx = header.firstIndex(of: "weight_lbs")
        let weightKgIdx = header.firstIndex(of: "weight_kg")
        let repsIdx = header.firstIndex(of: "reps")
        let durationIdx = header.firstIndex(of: "duration_seconds")

        var rawRows: [RawRow] = []

        for i in 1..<rows.count {
            let row = rows[i]
            guard row.count > max(startIdx, exerciseIdx) else { continue }
            let startStr = row[startIdx].trimmingCharacters(in: .whitespaces)
            guard !startStr.isEmpty else { continue }

            let (startIso, dayKey) = parseDateToIso(startStr)
            let endStr = endIdx.flatMap { idx in row.indices.contains(idx) ? row[idx] : nil }?.trimmingCharacters(in: .whitespaces) ?? ""
            let endIso = endStr.isEmpty ? nil : parseDateToIso(endStr).iso

            let rawTitle = titleIdx.flatMap { idx in row.indices.contains(idx) ? row[idx] : nil }?.trimmingCharacters(in: .whitespaces) ?? ""
            let title = rawTitle.isEmpty ? "Workout" : rawTitle

            let rawExercise = row[exerciseIdx].trimmingCharacters(in: .whitespaces)
            guard !rawExercise.isEmpty else { continue }
            let resolvedExercise = ExerciseAliasDictionary.resolve(rawName: rawExercise, canonicalNames: canonicalNames)

            let weightKg: Double? = {
                if let idx = weightKgIdx, row.indices.contains(idx), !row[idx].trimmingCharacters(in: .whitespaces).isEmpty {
                    return Double(row[idx].replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
                }
                if let idx = weightLbsIdx, row.indices.contains(idx), !row[idx].trimmingCharacters(in: .whitespaces).isEmpty {
                    let lbs = Double(row[idx].replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
                    return lbs.map { $0 * WeightUnit.lbsToKg }
                }
                return nil
            }()

            let rawReps = repsIdx.flatMap { idx in row.indices.contains(idx) ? row[idx] : nil }?.trimmingCharacters(in: .whitespaces) ?? ""
            let reps = Int(rawReps)

            let rawSetIndex = setIdx.flatMap { idx in row.indices.contains(idx) ? row[idx] : nil }?.trimmingCharacters(in: .whitespaces) ?? ""
            let setIndex = Int(rawSetIndex) ?? 1

            let rawDuration = durationIdx.flatMap { idx in row.indices.contains(idx) ? row[idx] : nil }?.trimmingCharacters(in: .whitespaces) ?? ""
            let durationSec = Int(rawDuration) ?? 0

            rawRows.append(
                RawRow(
                    startIso: startIso,
                    endIso: endIso,
                    dayKey: dayKey,
                    workoutTitle: title,
                    exerciseName: resolvedExercise,
                    setIndex: setIndex,
                    weightKg: weightKg,
                    reps: reps,
                    durationSeconds: durationSec
                )
            )
        }

        var workoutsMap: [String: [RawRow]] = [:]
        var groupKeysOrder: [String] = []

        for r in rawRows {
            let groupKey = "\(r.dayKey)_\(r.startIso)_\(r.workoutTitle.lowercased())"
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
            let startedAt = first.startIso
            let completedAt = group.compactMap { $0.endIso }.max() ?? startedAt
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
                    targetSets: sets.count
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
