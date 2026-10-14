import Foundation
import CoreFoundation

/// The public program contract is separate from Codable app-state persistence.
enum ProgramFileCodec {
    static let version = 5
    private static func invalid() -> Error { ProgramEditing.ValidationError(message: LanguageManager.t("programs.invalidFile")) }
    private static func only(_ object: [String: Any], _ keys: [String]) throws {
        guard Set(object.keys).isSubset(of: Set(keys)) else { throw invalid() }
    }
    private static func object(_ value: Any?) throws -> [String: Any] {
        guard let result = value as? [String: Any] else { throw invalid() }; return result
    }
    private static func text(_ object: [String: Any], _ key: String, max: Int, required: Bool = false) throws -> String {
        guard let value = object[key] else { if required { throw invalid() }; return "" }
        guard let string = value as? String, string.utf16.count <= max,
              !required || !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw invalid() }
        return string
    }
    private static func integer(_ object: [String: Any], _ key: String, range: ClosedRange<Int>, required: Bool = false) throws -> Int? {
        guard let value = object[key] else { if required { throw invalid() }; return nil }
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, number.doubleValue.rounded() == number.doubleValue,
              number.doubleValue >= Double(range.lowerBound), number.doubleValue <= Double(range.upperBound) else { throw invalid() }
        return number.intValue
    }
    private static func boolean(_ object: [String: Any], _ key: String) throws -> Bool {
        guard let value = object[key] else { return false }
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { throw invalid() }
        return number.boolValue
    }
    private static func array(_ object: [String: Any], _ key: String, max: Int, required: Bool = false) throws -> [Any] {
        guard let value = object[key] else { if required { throw invalid() }; return [] }
        guard let array = value as? [Any], array.count <= max else { throw invalid() }; return array
    }
    private static func strings(_ object: [String: Any], _ key: String, max: Int, length: Int) throws -> [String] {
        try array(object, key, max: max).map { value in
            guard let text = value as? String, text.utf16.count <= length else { throw invalid() }; return text
        }
    }
    private static func id(_ object: [String: Any]) throws -> String {
        let value = try text(object, "id", max: 100, required: true)
        guard ProgramEditing.validID(value) else { throw invalid() }; return value
    }

    static func decode(_ input: Data, defaultRest: Int = 120) throws -> Program {
        guard input.count <= 5_000_000 else { throw AppStore.ProgramImportError.fileTooLarge }
        let data = input.starts(with: [0xEF, 0xBB, 0xBF]) ? Data(input.dropFirst(3)) : input
        var scanner = UniqueJSONKeys(bytes: Array(data))
        try scanner.check()
        guard let raw = try? JSONSerialization.jsonObject(with: data), let root = raw as? [String: Any] else { throw AppStore.ProgramImportError.notAnObject }
        if root["programs"] != nil || root["history"] != nil || root["backup"] != nil { throw AppStore.ProgramImportError.fullBackup }
        let revision: Int
        var p: [String: Any]
        if root["format"] != nil {
            try only(root, ["format", "schemaVersion", "program", "$schema"])
            let format = try text(root, "format", max: 40, required: true)
            guard format == "form.program" else { throw AppStore.ProgramImportError.invalidFormat(format) }
            revision = try integer(root, "schemaVersion", range: 1...Int(Int32.max), required: true) ?? 0
            guard revision <= version else { throw AppStore.ProgramImportError.unsupportedVersion(revision) }
            _ = try text(root, "$schema", max: 2000)
            p = try object(root["program"])
        } else {
            // Preserve the pre-existing iOS raw-program entry point, with v4 compatibility.
            revision = 4; p = root
        }
        try only(p, ["id", "name", "description", "guidelines", "workouts"] + (revision >= 5 ? ["coverId"] : []))
        _ = try id(p)
        let name = try text(p, "name", max: 100)
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AppStore.ProgramImportError.invalidProgramName }
        _ = try text(p, "description", max: 500)
        _ = try strings(p, "guidelines", max: 50, length: 500)
        if p["coverId"] != nil {
            let cover = try text(p, "coverId", max: 100, required: true)
            guard ProgramEditing.validID(cover) else { throw invalid() }
        }
        var days = Set<Int>(); var workoutIDs = Set<String>()
        let workouts = try array(p, "workouts", max: 7, required: true)
        p["workouts"] = try workouts.map { value -> [String: Any] in
            var workout = try object(value)
            try only(workout, ["id", "day", "title", "focus", "tone", "exercises"] + (revision >= 2 ? ["targetMuscles"] : []))
            guard workoutIDs.insert(try id(workout)).inserted else { throw AppStore.ProgramImportError.duplicateWorkoutIds }
            let day = try integer(workout, "day", range: 1...7, required: true)!
            guard days.insert(day).inserted else { throw AppStore.ProgramImportError.duplicateWorkoutDays }
            _ = try text(workout, "title", max: 100, required: true)
            _ = try text(workout, "focus", max: 180)
            _ = try text(workout, "tone", max: 20)
            _ = try strings(workout, "targetMuscles", max: 14, length: 40)
            var exerciseIDs = Set<String>()
            workout["exercises"] = try array(workout, "exercises", max: 100, required: true).map { value -> [String: Any] in
                var e = try object(value)
                try only(e, ["id", "name", "prescription", "sets", "reps", "restSeconds", "movementType", "cues", "avoid", "videos"] + (revision >= 3 ? ["movementAssetId"] : []) + (revision >= 4 ? ["exerciseId"] : []))
                guard exerciseIDs.insert(try id(e)).inserted else { throw invalid() }
                let reference = try text(e, "exerciseId", max: 100)
                let rawName = try text(e, "name", max: 100)
                let definition = ExerciseCatalog.canonicalExercises[reference] ?? ExerciseCatalog.canonicalExercises.values.first { ExerciseCatalog.key($0.name) == ExerciseCatalog.key(rawName) }
                let resolvedName = rawName.isEmpty ? definition?.name ?? "" : rawName
                guard !resolvedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw invalid() }
                e["name"] = resolvedName
                _ = try text(e, "prescription", max: 100)
                let sets = try integer(e, "sets", range: 1...10)
                if let reps = e["reps"] {
                    let r = try object(reps); try only(r, ["min", "max", "toFailure", "perSide"])
                    let failure = try boolean(r, "toFailure"); _ = try boolean(r, "perSide")
                    _ = try integer(r, "min", range: 1...999, required: !failure)
                    _ = try integer(r, "max", range: 1...999, required: !failure)
                    guard sets != nil else { throw invalid() }
                }
                _ = try integer(e, "restSeconds", range: 0...900)
                _ = try text(e, "movementType", max: 40)
                _ = try text(e, "movementAssetId", max: 80)
                _ = try strings(e, "videos", max: 3, length: 2000)
                for field in ["cues", "avoid"] {
                    if revision == 4, let legacy = e[field] as? String { e[field] = legacy.isEmpty ? [] : legacy.components(separatedBy: "\n") }
                    let lines = try strings(e, field, max: 100, length: 1000)
                    guard lines.joined(separator: "\n").utf16.count <= 1000 else { throw invalid() }
                    if e[field] == nil, let definition { e[field] = field == "cues" ? definition.cues : definition.avoid }
                }
                if e["movementType"] == nil { e["movementType"] = definition?.movementType ?? "other" }
                if e["movementAssetId"] == nil, let asset = definition?.movementAssetId { e["movementAssetId"] = asset }
                if sets == nil { e["sets"] = WorkoutSessionUtils.initialSetCount(prescription: (e["prescription"] as? String) ?? "") }
                if e["restSeconds"] == nil { e["restSeconds"] = min(900, max(0, defaultRest)) }
                return e
            }
            return workout
        }
        let normalized = try JSONSerialization.data(withJSONObject: p)
        let program = try JSONDecoder().decode(Program.self, from: normalized)
        try ProgramEditing.validate(program)
        return program
    }

    static func encode(_ program: Program, defaultRest: Int = 120) throws -> Data {
        try ProgramEditing.validate(program)
        func notes(_ text: String) -> [String] { text.isEmpty ? [] : text.components(separatedBy: "\n") }
        var p: [String: Any] = ["id": program.id, "name": program.name, "description": program.description, "guidelines": program.guidelines]
        if let cover = program.coverId { p["coverId"] = cover }
        p["workouts"] = program.workouts.map { workout -> [String: Any] in
            ["id": workout.id, "day": workout.day, "title": workout.title, "focus": workout.focus, "tone": workout.tone, "targetMuscles": workout.targetMuscles,
             "exercises": workout.exercises.map { exercise -> [String: Any] in
                var e: [String: Any] = ["id": exercise.id, "name": exercise.name, "sets": WorkoutSessionUtils.initialSetCount(exercise: exercise),
                    "restSeconds": exercise.restSeconds ?? RestTimerUtils.restSeconds(for: exercise), "movementType": exercise.resolvedMovement.rawValue,
                    "cues": notes(exercise.cues), "avoid": notes(exercise.avoid), "videos": exercise.videos]
                if let reference = exercise.exerciseId { e["exerciseId"] = reference }
                if let asset = exercise.movementAssetId { e["movementAssetId"] = asset }
                if let reps = exercise.reps {
                    var r: [String: Any] = ["toFailure": reps.toFailure, "perSide": reps.perSide]
                    if let min = reps.min { r["min"] = min }; if let max = reps.max { r["max"] = max }
                    e["reps"] = r
                } else { e["prescription"] = exercise.prescription }
                return e
             }]
        }
        let data = try JSONSerialization.data(withJSONObject: ["format": "form.program", "schemaVersion": version, "program": p], options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        _ = try decode(data, defaultRest: defaultRest)
        return data
    }

    static func shareURL(_ program: Program, defaultRest: Int = 120) throws -> URL {
        let filename = program.name.replacingOccurrences(of: "[^\\p{L}\\p{N} ._-]", with: "_", options: .regularExpression)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("program-share-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(filename.prefix(80)).form-program.json")
        try encode(program, defaultRest: defaultRest).write(to: url, options: .atomic)
        return url
    }

    /// Validate key uniqueness before Foundation's dictionary conversion can hide duplicates.
    private struct UniqueJSONKeys {
        let bytes: [UInt8]; var index = 0
        mutating func check() throws { try value(depth: 0); whitespace(); guard index == bytes.count else { throw ProgramFileCodec.invalid() } }
        mutating func whitespace() { while index < bytes.count && [9, 10, 13, 32].contains(bytes[index]) { index += 1 } }
        mutating func consume(_ byte: UInt8) throws { whitespace(); guard index < bytes.count && bytes[index] == byte else { throw ProgramFileCodec.invalid() }; index += 1 }
        mutating func string() throws -> String {
            whitespace(); let start = index; try consume(34)
            while index < bytes.count {
                let byte = bytes[index]; index += 1
                if byte == 92 { guard index < bytes.count else { throw ProgramFileCodec.invalid() }; index += 1 }
                else if byte == 34 {
                    let data = Data(bytes[start..<index])
                    guard let string = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? String else { throw ProgramFileCodec.invalid() }
                    return string
                }
            }
            throw ProgramFileCodec.invalid()
        }
        mutating func value(depth: Int) throws {
            whitespace(); guard depth < 40 && index < bytes.count else { throw ProgramFileCodec.invalid() }
            switch bytes[index] {
            case 123:
                index += 1; whitespace(); var keys = Set<String>()
                if index < bytes.count && bytes[index] == 125 { index += 1; return }
                while true {
                    guard keys.insert(try string()).inserted else { throw ProgramFileCodec.invalid() }
                    try consume(58); try value(depth: depth + 1); whitespace()
                    guard index < bytes.count else { throw ProgramFileCodec.invalid() }
                    if bytes[index] == 125 { index += 1; return }; try consume(44)
                }
            case 91:
                index += 1; whitespace()
                if index < bytes.count && bytes[index] == 93 { index += 1; return }
                while true {
                    try value(depth: depth + 1); whitespace(); guard index < bytes.count else { throw ProgramFileCodec.invalid() }
                    if bytes[index] == 93 { index += 1; return }; try consume(44)
                }
            case 34: _ = try string()
            default:
                let start = index
                while index < bytes.count && ![9, 10, 13, 32, 44, 93, 125].contains(bytes[index]) { index += 1 }
                guard index > start else { throw ProgramFileCodec.invalid() }
            }
        }
    }
}

public struct ProgramImportPreview: Identifiable {
    var incoming: Program
    var existing: Program?
    public var id: String { incoming.id }
    var changes: [(kind: String, label: String)] {
        guard let existing else { return incoming.workouts.map { ("added", $0.title) } }
        var changes: [(kind: String, label: String)] = []
        if existing.name != incoming.name || existing.description != incoming.description || existing.guidelines != incoming.guidelines || existing.coverId != incoming.coverId { changes.append(("updated", incoming.name)) }
        for workout in incoming.workouts {
            guard let before = existing.workouts.first(where: { $0.id == workout.id }) else { changes.append(("added", workout.title)); continue }
            if before.title != workout.title || before.day != workout.day || before.focus != workout.focus || before.targetMuscles != workout.targetMuscles || before.exercises.map(\.id) != workout.exercises.map(\.id) { changes.append(("updated", workout.title)) }
            for exercise in workout.exercises where before.exercises.first(where: { $0.id == exercise.id }) != exercise {
                changes.append((before.exercises.contains { $0.id == exercise.id } ? "updated" : "added", workout.title + " · " + exercise.name))
            }
            changes += before.exercises.filter { old in !workout.exercises.contains { $0.id == old.id } }.map { ("removed", workout.title + " · " + $0.name) }
        }
        changes += existing.workouts.filter { old in !incoming.workouts.contains { $0.id == old.id } }.map { ("removed", $0.title) }
        return changes
    }
}

/// Allows the legacy public envelope API to use the same explicit file encoder.
indirect enum ProgramFileJSONValue: Codable {
    case object([String: ProgramFileJSONValue]), array([ProgramFileJSONValue]), string(String), integer(Int), boolean(Bool), null
    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let decoded = try? value.decode(Bool.self) { self = .boolean(decoded) }
        else if let decoded = try? value.decode(Int.self) { self = .integer(decoded) }
        else if let decoded = try? value.decode(String.self) { self = .string(decoded) }
        else if let decoded = try? value.decode([String: ProgramFileJSONValue].self) { self = .object(decoded) }
        else { self = .array(try value.decode([ProgramFileJSONValue].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .object(let decoded): try value.encode(decoded)
        case .array(let decoded): try value.encode(decoded)
        case .string(let decoded): try value.encode(decoded)
        case .integer(let decoded): try value.encode(decoded)
        case .boolean(let decoded): try value.encode(decoded)
        case .null: try value.encodeNil()
        }
    }
}
