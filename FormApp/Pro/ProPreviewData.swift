import Foundation

public enum ProPreviewData {

    public static func hasWorkingHistory(_ history: [WorkoutSessionRecord]) -> Bool {
        return history.contains { session in
            session.exerciseLogs.contains { log in
                log.sets.contains { set in
                    !set.isWarmup && ((set.weightKg ?? 0.0) > 0.0 || (set.reps ?? 0) > 0)
                }
            }
        }
    }

    public static func previewHistory(today: Date = Date()) -> [WorkoutSessionRecord] {
        var calendar = Calendar(identifier: .iso8601)
        calendar.firstWeekday = 2 // Monday
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

        let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)
        let currentMonday = calendar.date(from: comps) ?? today

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        df.timeZone = TimeZone(secondsFromGMT: 0)

        func dateAt(base: Date, days: Int, hour: Int, minute: Int = 0) -> String {
            guard let d = calendar.date(byAdding: .day, value: days, to: base) else { return "" }
            var c = calendar.dateComponents([.year, .month, .day], from: d)
            c.hour = hour
            c.minute = minute
            c.second = 0
            let finalDate = calendar.date(from: c) ?? d
            return df.string(from: finalDate)
        }

        func makeSession(
            id: String,
            title: String,
            baseDate: Date,
            daysOffset: Int,
            hour: Int,
            durationMins: Int,
            exercises: [SessionExerciseLog]
        ) -> WorkoutSessionRecord {
            let startedAt = dateAt(base: baseDate, days: daysOffset, hour: hour)
            let endHour = hour + durationMins / 60
            let endMin = durationMins % 60
            let completedAt = dateAt(base: baseDate, days: daysOffset, hour: endHour, minute: endMin)
            let totalSets = exercises.reduce(0) { sum, log in
                sum + log.sets.filter { !$0.isWarmup && (($0.weightKg ?? 0.0) > 0.0 || ($0.reps ?? 0) > 0) }.count
            }
            let totalVol = exercises.reduce(0.0) { sum, log in
                sum + log.sets.filter { !$0.isWarmup }.reduce(0.0) { s, set in
                    s + (set.weightKg ?? 0.0) * Double(set.reps ?? 0)
                }
            }
            return WorkoutSessionRecord(
                id: id,
                programId: "preview-program",
                workoutId: "preview-workout-\(id)",
                workoutTitle: title,
                startedAt: startedAt,
                completedAt: completedAt,
                durationSeconds: durationMins * 60,
                totalVolumeKg: totalVol,
                totalCompletedSets: totalSets,
                exerciseLogs: exercises,
                isComplete: true
            )
        }

        func log(_ name: String, _ sets: [(Double, Int)]) -> SessionExerciseLog {
            let setLogs = sets.enumerated().map { idx, item in
                SessionSetLog(
                    setNumber: idx + 1,
                    weightKg: item.0,
                    reps: item.1,
                    isWarmup: false
                )
            }
            return SessionExerciseLog(
                exerciseName: name,
                sets: setLogs,
                targetSets: sets.count
            )
        }

        var sessions: [WorkoutSessionRecord] = []

        // 1. Historical sessions
        // 8 weeks ago
        let wMinus8 = calendar.date(byAdding: .weekOfYear, value: -8, to: currentMonday) ?? currentMonday
        sessions.append(
            makeSession(
                id: "preview-hist-w8-1",
                title: "Upper Body Strength",
                baseDate: wMinus8,
                daysOffset: 0,
                hour: 17,
                durationMins: 45,
                exercises: [
                    log("Barbell Bench Press", [(85.0, 8), (85.0, 8), (85.0, 8)]),
                    log("Barbell Row", [(70.0, 8), (70.0, 8), (70.0, 8)]),
                    log("Lat Pulldown", [(65.0, 10), (65.0, 10), (65.0, 10)])
                ]
            )
        )
        sessions.append(
            makeSession(
                id: "preview-hist-w8-2",
                title: "Lower Body Foundation",
                baseDate: wMinus8,
                daysOffset: 2,
                hour: 17,
                durationMins: 45,
                exercises: [
                    log("Barbell Back Squat", [(120.0, 6), (120.0, 6), (120.0, 6)]),
                    log("Barbell Romanian Deadlift", [(95.0, 8), (95.0, 8), (95.0, 8)])
                ]
            )
        )

        // 5 weeks ago
        let wMinus5 = calendar.date(byAdding: .weekOfYear, value: -5, to: currentMonday) ?? currentMonday
        sessions.append(
            makeSession(
                id: "preview-hist-w5-1",
                title: "Upper Body Progression",
                baseDate: wMinus5,
                daysOffset: 0,
                hour: 17,
                durationMins: 50,
                exercises: [
                    log("Barbell Bench Press", [(90.0, 8), (90.0, 8), (90.0, 8)]),
                    log("Barbell Row", [(75.0, 8), (75.0, 8), (75.0, 8)]),
                    log("Lat Pulldown", [(70.0, 10), (70.0, 10), (70.0, 10)])
                ]
            )
        )
        sessions.append(
            makeSession(
                id: "preview-hist-w5-2",
                title: "Lower Body Progression",
                baseDate: wMinus5,
                daysOffset: 2,
                hour: 17,
                durationMins: 45,
                exercises: [
                    log("Barbell Back Squat", [(127.5, 6), (127.5, 6), (127.5, 6)]),
                    log("Barbell Romanian Deadlift", [(102.5, 8), (102.5, 8), (102.5, 8)])
                ]
            )
        )

        // 3 weeks ago
        let wMinus3 = calendar.date(byAdding: .weekOfYear, value: -3, to: currentMonday) ?? currentMonday
        sessions.append(
            makeSession(
                id: "preview-hist-w3-1",
                title: "Upper Body Overload",
                baseDate: wMinus3,
                daysOffset: 0,
                hour: 18,
                durationMins: 55,
                exercises: [
                    log("Barbell Bench Press", [(95.0, 8), (95.0, 8), (95.0, 8), (95.0, 8)]),
                    log("Barbell Row", [(77.5, 8), (77.5, 8), (77.5, 8)]),
                    log("Incline Dumbbell Press", [(32.0, 10), (32.0, 10), (32.0, 10)])
                ]
            )
        )
        sessions.append(
            makeSession(
                id: "preview-hist-w3-2",
                title: "Lower Body Overload",
                baseDate: wMinus3,
                daysOffset: 2,
                hour: 18,
                durationMins: 50,
                exercises: [
                    log("Barbell Back Squat", [(132.5, 6), (132.5, 6), (132.5, 6), (132.5, 6)]),
                    log("Barbell Romanian Deadlift", [(107.5, 8), (107.5, 8), (107.5, 8)])
                ]
            )
        )

        // 1 week ago
        let wMinus1 = calendar.date(byAdding: .weekOfYear, value: -1, to: currentMonday) ?? currentMonday
        sessions.append(
            makeSession(
                id: "preview-hist-w1-1",
                title: "Upper Body Peak",
                baseDate: wMinus1,
                daysOffset: 0,
                hour: 18,
                durationMins: 55,
                exercises: [
                    log("Barbell Bench Press", [(97.5, 8), (97.5, 8), (97.5, 8), (97.5, 8)]),
                    log("Barbell Row", [(80.0, 8), (80.0, 8), (80.0, 8)]),
                    log("Lat Pulldown", [(72.5, 10), (72.5, 10), (72.5, 10)])
                ]
            )
        )
        sessions.append(
            makeSession(
                id: "preview-hist-w1-2",
                title: "Lower Body Peak",
                baseDate: wMinus1,
                daysOffset: 2,
                hour: 18,
                durationMins: 50,
                exercises: [
                    log("Barbell Back Squat", [(137.5, 6), (137.5, 6), (137.5, 6), (137.5, 6)]),
                    log("Barbell Romanian Deadlift", [(110.0, 8), (110.0, 8), (110.0, 8)])
                ]
            )
        )

        // 2. Current Week Active Sessions
        // Monday: Upper Body Focus
        sessions.append(
            makeSession(
                id: "preview-current-mon",
                title: "Upper Body Hypertrophy",
                baseDate: currentMonday,
                daysOffset: 0,
                hour: 10,
                durationMins: 60,
                exercises: [
                    log("Barbell Bench Press", [(100.0, 8), (100.0, 8), (100.0, 8), (100.0, 8)]),
                    log("Barbell Row", [(80.0, 8), (80.0, 8), (80.0, 8), (80.0, 8)]),
                    log("Incline Dumbbell Press", [(34.0, 10), (34.0, 10), (34.0, 10)]),
                    log("Lat Pulldown", [(75.0, 10), (75.0, 10), (75.0, 10), (75.0, 10)]),
                    log("Rope Triceps Pressdown", [(35.0, 12), (35.0, 12), (35.0, 12)]),
                    log("Dumbbell Hammer Curl", [(18.0, 12), (18.0, 12), (18.0, 12), (18.0, 12)])
                ]
            )
        )

        // Wednesday: Lower Body & Core
        sessions.append(
            makeSession(
                id: "preview-current-wed",
                title: "Lower Body & Core",
                baseDate: currentMonday,
                daysOffset: 2,
                hour: 10,
                durationMins: 55,
                exercises: [
                    log("Barbell Back Squat", [(140.0, 6), (140.0, 6), (140.0, 6), (140.0, 6)]),
                    log("Barbell Romanian Deadlift", [(110.0, 8), (110.0, 8), (110.0, 8)]),
                    log("Leg Press", [(220.0, 10), (220.0, 10), (220.0, 10), (220.0, 10)]),
                    log("Barbell Standing Calf Raise", [(80.0, 12), (80.0, 12), (80.0, 12), (80.0, 12)]),
                    log("Ab Wheel Rollout", [(0.0, 15), (0.0, 15), (0.0, 15)])
                ]
            )
        )

        // Friday: Push & Pull Strength
        sessions.append(
            makeSession(
                id: "preview-current-fri",
                title: "Push & Pull Strength",
                baseDate: currentMonday,
                daysOffset: 4,
                hour: 11,
                durationMins: 50,
                exercises: [
                    log("Standing Barbell Overhead Press", [(60.0, 8), (60.0, 8), (60.0, 8)]),
                    log("Lat Pulldown", [(80.0, 8), (80.0, 8), (80.0, 8), (80.0, 8)]),
                    log("Barbell Bench Press", [(102.5, 8), (102.5, 8), (102.5, 8)]),
                    log("Dumbbell Lateral Raise", [(14.0, 15), (14.0, 15), (14.0, 15)]),
                    log("Barbell Romanian Deadlift", [(115.0, 8), (115.0, 8)])
                ]
            )
        )

        return sessions
    }
}
