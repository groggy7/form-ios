import CryptoKit
import Foundation

/// One reason a file cannot be imported. `line` is the record's first line in the file (the header is line 1).
public struct HistoryImportProblem: Equatable {
    public let code: String
    public let line: Int
    public let detail: String

    public init(code: String, line: Int, detail: String = "") {
        self.code = code
        self.line = line
        self.detail = detail
    }
}

public struct HistoryImportError: Error {
    public let problems: [HistoryImportProblem]

    public init(_ problems: [HistoryImportProblem]) { self.problems = problems }
    public init(_ code: String, line: Int, detail: String = "") {
        problems = [HistoryImportProblem(code: code, line: line, detail: detail)]
    }
}

/// CSV reading for Strong and Hevy exports (gym/docs/history-import.md#file-rules). Android `HistoryImportCsv`
/// applies the same rules. Text is read as Unicode scalars so CRLF is two characters, never one grapheme.
enum HistoryImportCsv {
    static let maxBytes = 25 * 1024 * 1024

    struct Record { let line: Int; let fields: [String] }

    /// Strict UTF-8 without a leading byte-order mark.
    static func decode(_ data: Data) throws -> [Unicode.Scalar] {
        guard data.count <= maxBytes else { throw HistoryImportError("tooLarge", line: 0) }
        guard let text = String(data: data, encoding: .utf8) else { throw HistoryImportError("encoding", line: 0) }
        var scalars = Array(text.unicodeScalars)
        if scalars.first == "\u{FEFF}" { scalars.removeFirst() }
        return scalars
    }

    /// The 1-based line of `index`, counting CRLF, LF and CR as one break each.
    static func lineOf(_ text: [Unicode.Scalar], _ index: Int) -> Int {
        var line = 1
        for i in 0..<index where text[i] == "\n" || (text[i] == "\r" && (i + 1 >= text.count || text[i + 1] != "\n")) {
            line += 1
        }
        return line
    }

    /// The most frequent of comma, semicolon and tab outside quotes on the header line; comma on a tie.
    static func delimiter(_ text: [Unicode.Scalar]) -> Unicode.Scalar {
        var inQuotes = false
        var counts: [Unicode.Scalar: Int] = [",": 0, ";": 0, "\t": 0]
        for c in text {
            if c == "\"" { inQuotes.toggle() }
            else if !inQuotes && (c == "\n" || c == "\r") { break }
            else if !inQuotes, let count = counts[c] { counts[c] = count + 1 }
        }
        let order: [Unicode.Scalar] = [",", ";", "\t"]
        return order.max { (counts[$0]!, -order.firstIndex(of: $0)!) < (counts[$1]!, -order.firstIndex(of: $1)!) }!
    }

    /// Records with their first line numbers. `strongQuotes` reads Strong's undoubled quotes: inside a quoted field a
    /// quote closes it only before the delimiter, a line break or the end; a doubled quote before anything else is one quote.
    /// Blank records are left out.
    static func records(_ text: [Unicode.Scalar], delimiter: Unicode.Scalar, strongQuotes: Bool) throws -> [Record] {
        var records: [Record] = []
        var fields: [String] = []
        var field = String.UnicodeScalarView()
        var line = 1
        var recordLine = 1
        var quoteLine = 1
        var inQuotes = false
        var i = 0
        func endsField(_ index: Int) -> Bool {
            index >= text.count || text[index] == delimiter || text[index] == "\n" || text[index] == "\r"
        }
        func endRecord() {
            fields.append(String(field))
            field = String.UnicodeScalarView()
            if fields.contains(where: { !$0.isEmpty }) { records.append(Record(line: recordLine, fields: fields)) }
            fields = []
        }
        while i < text.count {
            let c = text[i]
            if inQuotes {
                if c == "\"" && strongQuotes {
                    if endsField(i + 1) { inQuotes = false; i += 1 }
                    else if text[i + 1] == "\"" && !endsField(i + 2) { field.append("\""); i += 2 }
                    else { field.append("\""); i += 1 }
                } else if c == "\"" {
                    if i + 1 < text.count && text[i + 1] == "\"" { field.append("\""); i += 2 } else { inQuotes = false; i += 1 }
                } else if c == "\r" {
                    field.append("\n"); line += 1
                    i += (i + 1 < text.count && text[i + 1] == "\n") ? 2 : 1
                } else {
                    if c == "\n" { line += 1 }
                    field.append(c); i += 1
                }
                continue
            }
            switch c {
            case "\"":
                if field.isEmpty { inQuotes = true; quoteLine = line } else { field.append(c) }
                i += 1
            case delimiter:
                fields.append(String(field)); field = String.UnicodeScalarView(); i += 1
            case "\r", "\n":
                endRecord()
                i += (c == "\r" && i + 1 < text.count && text[i + 1] == "\n") ? 2 : 1
                line += 1
                recordLine = line
            default:
                field.append(c); i += 1
            }
        }
        if inQuotes { throw HistoryImportError("unterminatedQuote", line: quoteLine) }
        if !field.isEmpty || !fields.isEmpty { endRecord() }
        return records
    }
}

public enum HistoryImportSource: String {
    case strong
    case hevy

    public var displayName: String { self == .strong ? "Strong" : "Hevy" }
}

/// Reviewed aliases and library names for matching exported exercise names (gym/docs/history-import.md#exercises).
public struct HistoryImportCatalog {
    private let aliases: [String: String]
    private let names: [String: String]
    private let byName: [String: String]

    public init(aliases: [String: String], names: [String: String]) {
        self.names = names
        self.aliases = aliases.filter { names[$0.value] != nil }
        var byName: [String: String] = [:]
        for (id, name) in names { byName[Self.normalize(name)] = id }
        self.byName = byName
    }

    /// The library ID and English name for an exported name, or nil for a custom exercise.
    public func match(_ name: String) -> (id: String, name: String)? {
        let key = Self.normalize(name)
        guard let id = aliases[key] ?? byName[key], let libraryName = names[id] else { return nil }
        return (id, libraryName)
    }

    public static func normalize(_ name: String) -> String {
        var text = name.precomposedStringWithCompatibilityMapping
            .replacingOccurrences(of: "\u{2018}", with: "'").replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{201C}", with: "\"").replacingOccurrences(of: "\u{201D}", with: "\"")
        text = String(String.UnicodeScalarView(text.unicodeScalars.map { ($0.value >= 0x2010 && $0.value <= 0x2015) || $0 == "-" ? " " : $0 }))
        text = text.replacingOccurrences(of: "'", with: "")
        return text.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }

    public static func fromJSON(_ data: Data, exercises: [String: ExerciseDefinition]) -> HistoryImportCatalog {
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let aliases = object?["aliases"] as? [String: String] ?? [:]
        return HistoryImportCatalog(aliases: aliases, names: exercises.mapValues(\.name))
    }

    /// The bundled table.
    public static func bundled(_ bundle: Bundle = .main) -> HistoryImportCatalog {
        let data = bundle.url(forResource: "history_import_aliases", withExtension: "json").flatMap { try? Data(contentsOf: $0) } ?? Data()
        return fromJSON(data, exercises: ExerciseCatalog.canonicalExercises)
    }
}

/// A wall-clock date and time exactly as exported, with no time zone.
struct ImportedDateTime: Equatable, Comparable {
    let year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int

    var date: String { String(format: "%04d-%02d-%02d", year, month, day) }
    var minuteKey: String { String(format: "%04d-%02d-%02dT%02d:%02d", year, month, day, hour, minute) }
    private var components: DateComponents {
        DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
    }
    /// Seconds on a time-zone-free axis, for wall-clock differences.
    var wallSeconds: Int {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        return Int(utc.date(from: components)!.timeIntervalSince1970)
    }
    func instant(in zone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: components)!
    }
    static func < (lhs: ImportedDateTime, rhs: ImportedDateTime) -> Bool { lhs.wallSeconds < rhs.wallSeconds }
}

enum ImportedSetKind { case working, warmup, drop }

/// One exported set row, with its weight still in the file's unit.
struct ImportedSetRow {
    let line: Int
    let kind: ImportedSetKind
    let weight: Double
    let reps: Int
}

struct ImportedExercise { let sourceName: String; let rows: [ImportedSetRow]; var note: String? = nil }

struct ImportedSession {
    let line: Int
    let title: String
    let start: ImportedDateTime
    let durationSeconds: Int
    let exercises: [ImportedExercise]
    var note: String? = nil
}

/// A readable export: its unique sessions and what the file holds that cannot be imported.
public struct HistoryImportFile {
    public let source: HistoryImportSource
    /// Nil when the export does not name its weight unit; the user then chooses one.
    public let fileUnit: WeightUnit?
    public let zone: TimeZone
    let sessions: [ImportedSession]
    public let repeatedInFile: Int
    public let nothingToImport: Int
    public let timedSets: Int
    public let distanceSets: Int
    public let setsWithoutReps: Int
    public let rpeValues: Int
    public let exerciseNotes: Int
    public let workoutDescriptions: Int
    public let supersetLinks: Int

    public var workoutsInFile: Int { sessions.count }
}

/// What Import will save for one weight unit and overlap choice.
public struct HistoryImportPlan {
    public let file: HistoryImportFile
    /// Nil until the user chooses a unit for an export that does not name one.
    public let unit: WeightUnit?
    public let includeOverlaps: Bool
    public let records: [WorkoutSessionRecord]
    public let alreadyImported: Int
    public let overlapping: Int
    public let workingSets: Int
    public let warmupSets: Int
    public let dropsAttached: Int
    public let dropsSeparate: Int
    public let libraryExercises: Int
    public let customExercises: Int
    public let firstDate: String?
    public let lastDate: String?
    /// How many workouts history can still take when the import would exceed the limit; otherwise nil.
    public let roomLeft: Int?

    public var needsUnit: Bool { unit == nil }
    public var canImport: Bool { !needsUnit && !records.isEmpty && roomLeft == nil }
}

/// Strong and Hevy CSV history import; the rules are gym/docs/history-import.md. Android `HistoryImport` matches it.
public enum HistoryImport {
    public static let maxHistoryRecords = 10_000
    public static let idPrefix = "import-"
    public static let programId = "imported"
    private static let maxProblems = 5
    private static let maxSessionSeconds = 7 * 24 * 60 * 60
    private static let maxEntries = 100
    private static let maxSets = 100
    private static let maxText = 100
    private static let maxRawWeight = 22_044.0
    private static let loadTolerance = 0.0001
    private static let decimal = try! NSRegularExpression(pattern: "^[0-9]+(\\.[0-9]+)?$")
    private static let whole = try! NSRegularExpression(pattern: "^[0-9]+(\\.0+)?$")
    private static let clockDuration = try! NSRegularExpression(pattern: "^(?:([0-9]+)h)?\\s*(?:([0-9]+)m)?\\s*(?:([0-9]+)s)?$")
    private static let isoDate = try! NSRegularExpression(pattern: "^([0-9]{4})-([0-9]{2})-([0-9]{2}) ([0-9]{2}):([0-9]{2})(?::([0-9]{2}))?$")
    private static let hevyDate = try! NSRegularExpression(pattern: "^([0-9]{1,2}) ([A-Za-z]{3}) ([0-9]{4}), ([0-9]{2}):([0-9]{2})$")
    private static let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]

    private enum RowKind { case working, warmup, drop, rest, note }

    private struct Row {
        let line: Int
        let key: String
        let title: String
        let start: ImportedDateTime
        let duration: Int
        let description: String
        let exercise: String
        let kind: RowKind
        let order: Int?
        let weight: Double
        let reps: Int?
        let seconds: Double?
        let distance: Double?
        let rpe: Double?
        let note: String
        let superset: String
        let raw: [String]

        var isSet: Bool { kind == .working || kind == .warmup || kind == .drop }
        var hasReps: Bool { (reps ?? 0) > 0 }
    }

    private static func matches(_ regex: NSRegularExpression, _ text: String) -> [String?]? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) }
        }
    }

    private static func dateTime(_ text: String, hevy: Bool) -> ImportedDateTime? {
        var parts: (Int, Int, Int, Int, Int, Int)?
        if let m = matches(isoDate, text) {
            parts = (Int(m[1]!)!, Int(m[2]!)!, Int(m[3]!)!, Int(m[4]!)!, Int(m[5]!)!, m[6].flatMap { Int($0) } ?? 0)
        } else if hevy, let m = matches(hevyDate, text), let month = months.firstIndex(of: m[2]!.lowercased()) {
            parts = (Int(m[3]!)!, month + 1, Int(m[1]!)!, Int(m[4]!)!, Int(m[5]!)!, 0)
        }
        guard let (y, mo, d, h, mi, s) = parts, (1...12).contains(mo), (0...23).contains(h), (0...59).contains(mi), (0...59).contains(s) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let components = DateComponents(calendar: calendar, year: y, month: mo, day: d)
        guard (1...31).contains(d), components.isValidDate else { return nil }
        return ImportedDateTime(year: y, month: mo, day: d, hour: h, minute: mi, second: s)
    }

    /// Reads and validates a whole export, or throws `HistoryImportError` with up to five problems.
    public static func read(_ data: Data, zone: TimeZone, today: String, untitled: String) throws -> HistoryImportFile {
        let text = try HistoryImportCsv.decode(data)
        // The header is the first non-blank line.
        guard let headerStart = text.firstIndex(where: { $0 != "\n" && $0 != "\r" }) else { throw HistoryImportError("empty", line: 1) }
        let headerLine = HistoryImportCsv.lineOf(text, headerStart)
        let rest = text[headerStart...]
        let headerText = Array(rest.prefix { $0 != "\n" && $0 != "\r" })
        let delimiter = HistoryImportCsv.delimiter(headerText)
        guard let headerRecord = try HistoryImportCsv.records(headerText, delimiter: delimiter, strongQuotes: false).first else {
            throw HistoryImportError("empty", line: headerLine)
        }
        let header = headerRecord.fields.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        var seen = Set<String>()
        for name in header where !name.isEmpty {
            if !seen.insert(name).inserted { throw HistoryImportError("duplicateColumn", line: headerLine, detail: name) }
        }
        var columns: [String: Int] = [:]
        for (index, name) in header.enumerated() where columns[name] == nil { columns[name] = index }
        let source: HistoryImportSource
        if columns["title"] != nil && columns["start_time"] != nil && columns["set_type"] != nil { source = .hevy }
        else if columns["workout name"] != nil && columns["set order"] != nil { source = .strong }
        else { throw HistoryImportError("unknownFormat", line: headerLine) }
        let required = source == .hevy
            ? ["title", "start_time", "end_time", "exercise_title", "set_type", "reps"]
            : ["date", "workout name", "exercise name", "set order", "reps"]
        if let missing = required.first(where: { columns[$0] == nil }) {
            throw HistoryImportError("missingColumn", line: headerLine, detail: missing)
        }
        let weightColumn: String
        let fileUnit: WeightUnit?
        switch source {
        case .hevy:
            if columns["weight_kg"] != nil { weightColumn = "weight_kg"; fileUnit = .kg }
            else if columns["weight_lbs"] != nil { weightColumn = "weight_lbs"; fileUnit = .lbs }
            else { throw HistoryImportError("missingColumn", line: headerLine, detail: "weight_kg") }
        case .strong:
            if columns["weight (kg)"] != nil { weightColumn = "weight (kg)"; fileUnit = .kg }
            else if columns["weight (lbs)"] != nil { weightColumn = "weight (lbs)"; fileUnit = .lbs }
            else if columns["weight"] != nil { weightColumn = "weight"; fileUnit = nil }
            else { throw HistoryImportError("missingColumn", line: headerLine, detail: "weight (kg)") }
        }
        let maxWeight = fileUnit == .kg ? 9_999.0 : maxRawWeight

        let records = try HistoryImportCsv.records(text, delimiter: delimiter, strongQuotes: source == .strong)
        var problems: [HistoryImportProblem] = []
        func problem(_ code: String, _ line: Int, _ detail: String = "") {
            if problems.count < maxProblems { problems.append(HistoryImportProblem(code: code, line: line, detail: detail)) }
        }
        let latest = WorkoutCalendar.parseDate(today).flatMap { Calendar(identifier: .gregorian).date(byAdding: .day, value: 1, to: $0) }
            .map { WorkoutCalendar.formatDate($0) } ?? today
        func dateOrProblem(_ value: String, _ line: Int, hevy: Bool) -> ImportedDateTime? {
            let parsed = dateTime(value.trimmingCharacters(in: .whitespacesAndNewlines), hevy: hevy)
            if parsed == nil || parsed!.year < 1970 { problem("date", line, value) }
            else if parsed!.date > latest { problem("futureDate", line, value) }
            else { return parsed }
            return nil
        }
        func number(_ value: String, _ code: String, _ line: Int, max: Double = .greatestFiniteMagnitude) -> Double? {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return nil }
            if matches(decimal, trimmed) != nil, let parsed = Double(trimmed), parsed.isFinite, parsed <= max { return parsed }
            problem(code, line, value)
            return nil
        }

        var rows: [Row] = []
        for record in records.dropFirst() {
            let line = record.line
            guard record.fields.count == header.count else { problem("fieldCount", line); continue }
            func field(_ name: String) -> String { columns[name].map { record.fields[$0] } ?? "" }
            let before = problems.count
            let exercise = field(source == .hevy ? "exercise_title" : "exercise name").trimmingCharacters(in: .whitespacesAndNewlines)
            if exercise.isEmpty { problem("exerciseName", line) }
            let weight = number(field(weightColumn), "weight", line, max: maxWeight) ?? 0
            let repsText = field("reps").trimmingCharacters(in: .whitespacesAndNewlines)
            var reps: Int?
            if !repsText.isEmpty {
                if matches(whole, repsText) != nil, let value = Int(repsText.split(separator: ".").first ?? ""), value <= 999 { reps = value }
                else { problem("reps", line, repsText) }
            }
            let rpe = number(field("rpe"), "rpe", line, max: 10)
            var row: Row?
            switch source {
            case .strong:
                let dateText = field("date")
                let start = dateOrProblem(dateText, line, hevy: false)
                var duration = 0
                if columns["duration (sec)"] != nil {
                    duration = number(field("duration (sec)"), "duration", line, max: Double(maxSessionSeconds)).map { Int($0.rounded()) } ?? 0
                } else if columns["duration"] != nil {
                    if let value = clockSeconds(field("duration")), value <= maxSessionSeconds { duration = value }
                    else { problem("duration", line, field("duration")) }
                }
                let seconds = number(field("seconds"), "duration", line)
                let distance = number(field(columns["distance (meters)"] != nil ? "distance (meters)" : "distance"), "distance", line)
                let order = field("set order").trimmingCharacters(in: .whitespacesAndNewlines)
                var kind: RowKind?
                switch order.lowercased() {
                case "rest timer": kind = .rest
                case "note": kind = .note
                case "w": kind = .warmup
                case "d": kind = .drop
                case "f": kind = .working
                default:
                    if let number = Int(order), number >= 1 { kind = .working } else { problem("setType", line, order) }
                }
                let title = field("workout name").trimmingCharacters(in: .whitespacesAndNewlines)
                let workoutNumber = field("workout #").trimmingCharacters(in: .whitespacesAndNewlines)
                if let start, let kind {
                    row = Row(
                        line: line,
                        key: workoutNumber.isEmpty ? dateText.trimmingCharacters(in: .whitespacesAndNewlines) + "\u{0}" + title : "#" + workoutNumber,
                        title: title, start: start, duration: duration,
                        description: field("workout notes").trimmingCharacters(in: .whitespacesAndNewlines),
                        exercise: exercise, kind: kind, order: nil, weight: weight, reps: reps,
                        seconds: seconds, distance: distance, rpe: rpe,
                        note: field("notes").trimmingCharacters(in: .whitespacesAndNewlines), superset: "", raw: record.fields
                    )
                }
            case .hevy:
                let start = dateOrProblem(field("start_time"), line, hevy: true)
                let end = dateOrProblem(field("end_time"), line, hevy: true)
                var duration: Int?
                if let start, let end {
                    let seconds = end.wallSeconds - start.wallSeconds
                    if seconds < 0 || seconds > maxSessionSeconds { problem("duration", line) } else { duration = seconds }
                }
                let seconds = number(field("duration_seconds"), "duration", line)
                let distance = number(field(columns["distance_km"] != nil ? "distance_km" : "distance_miles"), "distance", line)
                let type = field("set_type").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                var kind: RowKind?
                switch type {
                case "normal", "failure": kind = .working
                case "warmup": kind = .warmup
                case "dropset": kind = .drop
                default: problem("setType", line, type)
                }
                let indexText = field("set_index").trimmingCharacters(in: .whitespacesAndNewlines)
                var order: Int?
                if !indexText.isEmpty {
                    if let value = Int(indexText), value >= 0 { order = value } else { problem("setOrder", line, indexText) }
                }
                let title = field("title").trimmingCharacters(in: .whitespacesAndNewlines)
                if let start, let duration, let kind {
                    let key = [title, field("start_time").trimmingCharacters(in: .whitespacesAndNewlines),
                               field("end_time").trimmingCharacters(in: .whitespacesAndNewlines)].joined(separator: "\u{0}")
                    row = Row(
                        line: line, key: key, title: title, start: start, duration: duration,
                        description: field("description").trimmingCharacters(in: .whitespacesAndNewlines),
                        exercise: exercise, kind: kind, order: order, weight: weight, reps: reps,
                        seconds: seconds, distance: distance, rpe: rpe,
                        note: field("exercise_notes").trimmingCharacters(in: .whitespacesAndNewlines),
                        superset: field("superset_id").trimmingCharacters(in: .whitespacesAndNewlines), raw: record.fields
                    )
                }
            }
            if let row, problems.count == before { rows.append(row) }
        }
        if !problems.isEmpty { throw HistoryImportError(problems) }

        // Runs are consecutive rows of one session; a repeated identical run is the same export pasted twice.
        var runs: [[Row]] = []
        for row in rows {
            if let last = runs.last?.first, last.key == row.key { runs[runs.count - 1].append(row) } else { runs.append([row]) }
        }
        var firstRuns: [[Row]] = []
        var runIndex: [String: Int] = [:]
        var repeated = 0
        for run in runs {
            let head = run[0]
            if let odd = run.first(where: { $0.title != head.title || $0.start != head.start || $0.duration != head.duration }) {
                problem("inconsistentWorkout", odd.line)
            }
            if let index = runIndex[head.key] {
                let earlier = firstRuns[index]
                if earlier.map(\.raw) == run.map(\.raw) { repeated += 1 }
                else { problem("conflictingRepeat", head.line, String(earlier[0].line)) }
            } else {
                runIndex[head.key] = firstRuns.count
                firstRuns.append(run)
            }
        }
        if !problems.isEmpty { throw HistoryImportError(problems) }

        var nothing = 0, timed = 0, distanceSets = 0, noReps = 0, rpeCount = 0, notes = 0, descriptions = 0, supersets = 0
        var sessions: [ImportedSession] = []
        for run in firstRuns {
            let head = run[0]
            if !head.description.isEmpty { descriptions += 1 }
            var entries: [[Row]] = []
            for row in run where row.kind != .rest {
                if let last = entries.last?.first, last.exercise == row.exercise { entries[entries.count - 1].append(row) } else { entries.append([row]) }
            }
            var exercises: [ImportedExercise] = []
            for entry in entries {
                if entry.contains(where: { !$0.note.isEmpty }) { notes += 1 }
                if entry.contains(where: { !$0.superset.isEmpty }) { supersets += 1 }
                var sets = entry.filter(\.isSet)
                if sets.allSatisfy({ $0.order != nil }) {
                    // A stable sort keeps rows with the same index in file order, as Android's sortedBy does.
                    sets = sets.enumerated().sorted { ($0.element.order!, $0.offset) < ($1.element.order!, $1.offset) }.map(\.element)
                }
                for row in sets {
                    if row.rpe != nil { rpeCount += 1 }
                    if !row.hasReps {
                        if (row.distance ?? 0) > 0 { distanceSets += 1 }
                        else if (row.seconds ?? 0) > 0 { timed += 1 }
                        else { noReps += 1 }
                    }
                }
                let imported = sets.filter(\.hasReps)
                if imported.count > maxSets { problem("tooManySets", head.line) }
                guard !imported.isEmpty else { continue }
                let note = uniqueNotes(entry.map(\.note))
                if (note?.utf16.count ?? 0) > 10_000 { problem("notesTooLong", entry[0].line) }
                exercises.append(ImportedExercise(sourceName: entry[0].exercise, rows: imported.map { row in
                    let kind: ImportedSetKind = row.kind == .warmup ? .warmup : row.kind == .drop ? .drop : .working
                    return ImportedSetRow(line: row.line, kind: kind, weight: row.weight, reps: row.reps!)
                }, note: note))
            }
            if exercises.count > maxEntries { problem("tooManySets", head.line) }
            if exercises.isEmpty { nothing += 1 }
            let title = head.title.isEmpty ? untitled : head.title
            let note = uniqueNotes(run.map(\.description))
            if (note?.utf16.count ?? 0) > 10_000 { problem("notesTooLong", head.line) }
            sessions.append(ImportedSession(line: head.line, title: String(title.prefix(maxText)), start: head.start,
                                            durationSeconds: head.duration, exercises: exercises, note: note))
        }
        if !problems.isEmpty { throw HistoryImportError(problems) }
        return HistoryImportFile(
            source: source, fileUnit: fileUnit, zone: zone, sessions: sessions, repeatedInFile: repeated,
            nothingToImport: nothing, timedSets: timed, distanceSets: distanceSets, setsWithoutReps: noReps,
            rpeValues: rpeCount, exerciseNotes: notes, workoutDescriptions: descriptions, supersetLinks: supersets
        )
    }

    /// The records Import saves for `unit` (the file's own unit wins) against `existing` history.
    public static func plan(_ file: HistoryImportFile, unit: WeightUnit?, existing: [WorkoutSessionRecord],
                            includeOverlaps: Bool, catalog: HistoryImportCatalog) -> HistoryImportPlan {
        let chosen = file.fileUnit ?? unit
        let factor = chosen == .lbs ? WeightUnit.lbsToKg : 1.0
        let existingIds = Set(existing.map(\.id))
        let native: [(date: String?, start: Date, end: Date)] = existing.filter { !$0.id.hasPrefix(idPrefix) }.compactMap { record in
            guard let start = WorkoutCalendar.parseIsoTimestamp(record.startedAt) else { return nil }
            let end = WorkoutCalendar.parseIsoTimestamp(record.completedAt) ?? start
            let date = record.performedDate ?? WorkoutCalendar.localDate(from: record.startedAt, timeZone: file.zone)
            return (date, start, max(end, start.addingTimeInterval(60)))
        }
        var alreadyImported = 0, overlapping = 0, attached = 0, separate = 0
        var records: [WorkoutSessionRecord] = []
        for session in file.sessions where !session.exercises.isEmpty {
            let built = build(session, factor: factor, catalog: catalog, zone: file.zone)
            if existingIds.contains(built.record.id) { alreadyImported += 1; continue }
            let start = built.start
            let end = max(start.addingTimeInterval(TimeInterval(session.durationSeconds)), start.addingTimeInterval(60))
            if native.contains(where: { $0.date == built.record.performedDate && $0.start < end && start < $0.end }) {
                overlapping += 1
                if !includeOverlaps { continue }
            }
            attached += built.dropsAttached
            separate += built.dropsSeparate
            records.append(built.record)
        }
        let logs = records.flatMap(\.exerciseLogs)
        let dates = records.compactMap(\.performedDate).sorted()
        let room = maxHistoryRecords - existing.count
        return HistoryImportPlan(
            file: file, unit: chosen, includeOverlaps: includeOverlaps,
            records: chosen == nil ? [] : records,
            alreadyImported: alreadyImported, overlapping: overlapping,
            workingSets: logs.reduce(0) { $0 + $1.sets.filter { !$0.isWarmup }.count },
            warmupSets: logs.reduce(0) { $0 + $1.sets.filter(\.isWarmup).count },
            dropsAttached: attached, dropsSeparate: separate,
            libraryExercises: Set(logs.compactMap(\.exerciseId)).count,
            customExercises: Set(logs.filter { $0.exerciseId == nil }.map { HistoryImportCatalog.normalize($0.exerciseName) }).count,
            firstDate: dates.first, lastDate: dates.last,
            roomLeft: records.count > room ? max(room, 0) : nil
        )
    }

    /// `import-` + the first 32 hex digits of SHA-256 over the exported start minute and the title.
    static func recordId(start: ImportedDateTime, title: String) -> String {
        idPrefix + sha256("\(start.minuteKey)|\(title.trimmingCharacters(in: .whitespacesAndNewlines))").prefix(32)
    }

    private static func build(_ session: ImportedSession, factor: Double, catalog: HistoryImportCatalog, zone: TimeZone)
        -> (record: WorkoutSessionRecord, start: Date, dropsAttached: Int, dropsSeparate: Int) {
        var attached = 0, separate = 0
        var logs: [(log: SessionExerciseLog, assisted: Bool)] = []
        for exercise in session.exercises {
            let match = catalog.match(exercise.sourceName)
            let id = match?.id
            let name = match?.name ?? String(exercise.sourceName.prefix(maxText))
            let assisted = WorkoutSessionUtils.isAssisted(exerciseId: id, name: name)
            let allowsZero = WorkoutSessionUtils.allowsZeroWeight(Exercise(name: name, exerciseId: id))
            var sets: [SessionSetLog] = []
            for row in exercise.rows {
                let kg = row.weight * factor
                if row.kind == .drop {
                    if let target = sets.lastIndex(where: { !$0.isWarmup }) {
                        let main = sets[target]
                        let previous = main.setExtensions.last?.weightKg ?? main.weightKg
                        let ordered = previous.map { assisted ? kg > $0 + loadTolerance : kg < $0 - loadTolerance } ?? false
                        if ordered && main.setExtensions.count < IntensitySets.maxExtensions && (kg > 0 || allowsZero) {
                            sets[target].technique = SetTechnique.drop.rawValue
                            sets[target].extensions = main.setExtensions + [SessionSetExtension(weightKg: kg, reps: row.reps)]
                            attached += 1
                            continue
                        }
                    }
                    separate += 1
                }
                sets.append(SessionSetLog(setNumber: sets.count + 1, weightKg: kg, reps: row.reps, isWarmup: row.kind == .warmup))
            }
            logs.append((SessionExerciseLog(exerciseName: name, sets: sets, targetSets: sets.filter { !$0.isWarmup }.count, exerciseId: id, setupNote: exercise.note), assisted))
        }
        let started = session.start.instant(in: zone)
        let iso = ISO8601DateFormatter()
        let record = WorkoutSessionRecord(
            id: recordId(start: session.start, title: session.title),
            programId: programId,
            workoutId: "imported-" + sha256(session.title.trimmingCharacters(in: .whitespacesAndNewlines)).prefix(16),
            workoutTitle: session.title,
            startedAt: iso.string(from: started),
            completedAt: iso.string(from: started.addingTimeInterval(TimeInterval(session.durationSeconds))),
            durationSeconds: session.durationSeconds,
            totalVolumeKg: logs.filter { !$0.assisted }.reduce(0) { total, entry in
                entry.log.sets.filter { !$0.isWarmup }.reduce(total) { $0 + IntensitySets.loadVolume($1) }
            },
            totalCompletedSets: logs.reduce(0) { $0 + $1.log.sets.filter { !$0.isWarmup }.count },
            exerciseLogs: logs.map(\.log),
            isComplete: true,
            performedDate: session.start.date, note: session.note
        )
        return (record, started, attached, separate)
    }

    private static func uniqueNotes(_ values: [String]) -> String? {
        var seen = Set<String>()
        let result = values.filter { !$0.isEmpty && seen.insert($0).inserted }.joined(separator: "\n")
        return result.isEmpty ? nil : result
    }

    private static func clockSeconds(_ value: String) -> Int? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return 0 }
        guard let m = matches(clockDuration, trimmed), !trimmed.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return (m[1].flatMap { Int($0) } ?? 0) * 3600 + (m[2].flatMap { Int($0) } ?? 0) * 60 + (m[3].flatMap { Int($0) } ?? 0)
    }

    private static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Store

extension AppStore {
    static let historyImportCatalog = HistoryImportCatalog.bundled()

    /// Refuses while a workout is in progress; the caller reads and plans the file off the main thread.
    public func checkHistoryImportAllowed() throws {
        guard activeSession == nil else { throw HistoryImportError("activeWorkout", line: 0) }
    }

    public static func readHistoryImport(_ data: Data) throws -> HistoryImportFile {
        try HistoryImport.read(data, zone: .current, today: WorkoutCalendar.formatDate(Date()),
                               untitled: LanguageManager.t("import.history.untitled"))
    }

    public func planHistoryImport(_ file: HistoryImportFile, unit: WeightUnit?, includeOverlaps: Bool) -> HistoryImportPlan {
        HistoryImport.plan(file, unit: unit, existing: state.history, includeOverlaps: includeOverlaps, catalog: Self.historyImportCatalog)
    }

    /// Saves `plan`'s workouts, planned again against current history, after a safety backup. The new history and
    /// calendar days are written in one transaction and published only once stored; on failure nothing is imported.
    @discardableResult
    public func importHistory(_ plan: HistoryImportPlan) throws -> Int {
        try checkHistoryImportAllowed()
        let fresh = planHistoryImport(plan.file, unit: plan.unit, includeOverlaps: plan.includeOverlaps)
        guard fresh.canImport else { throw HistoryImportError(fresh.roomLeft != nil ? "historyFull" : "nothingNew", line: 0) }
        try writeImportSafetyBackup()
        var next = state
        next.history = (fresh.records + state.history).sorted { $0.completedAt > $1.completedAt }
        var calendar = next.calendarHistory ?? WorkoutCalendarHistory(
            nextScheduledDate: WorkoutCalendar.mondayOfCurrentWeek(),
            scheduledWeekdays: WorkoutCalendar.weekdays(state: state)
        )
        let ids = Set(fresh.records.map { "session:\($0.id)" })
        calendar.entries = calendar.entries.filter { !ids.contains($0.id) } + fresh.records.compactMap { record in
            record.performedDate.map { WorkoutDayEntry(id: "session:\(record.id)", date: $0, status: .completed) }
        }
        next.calendarHistory = calendar
        guard saveState(next, durable: true) else { throw HistoryImportError("saveFailed", line: 0) }
        if let month = WorkoutCalendar.earliestWorkoutMonth(history: nil, sessions: fresh.records) {
            updateCalendarStartMonthIfEarlier(month)
        }
        return fresh.records.count
    }

    /// A full backup in Application Support before an import; the newest three are kept. A failed write stops the import.
    private func writeImportSafetyBackup() throws {
        let fileManager = FileManager.default
        let directory = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("import-backups", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = "before-import-\(Int(Date().timeIntervalSince1970 * 1000)).json"
        try Data(exportBackupJson().utf8).write(to: directory.appendingPathComponent(name), options: .atomic)
        let backups = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in backups.dropFirst(3) { try? fileManager.removeItem(at: old) }
    }
}
