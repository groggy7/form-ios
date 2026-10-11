import Foundation
import SQLite3

/// One transaction owns both the small app metadata and its ordered history.
/// Database access and routine-save encoding stay on this queue.
final class AppStatePersistence {
    static let shared = AppStatePersistence()
    private let queue = DispatchQueue(label: "com.perseverancesoftware.forcedrep.persistence", qos: .userInitiated)
    private let queueKey = DispatchSpecificKey<Bool>()
    private let databaseURL: URL?
    private let inMemory: Bool
    private var database: OpaquePointer?
    private var records: [String: WorkoutSessionRecord] = [:]
    private var metadataData: Data?
    private var didLoad = false
    private var lastError: Error?
    private let beforeCommit: (() throws -> Void)?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private struct Metadata: Codable {
        var state: StoredAppState
        var historyKeys: [String]
    }

    init(databaseURL: URL? = nil, inMemory: Bool = false, beforeCommit: (() throws -> Void)? = nil) {
        self.inMemory = inMemory
        self.beforeCommit = beforeCommit
        self.databaseURL = databaseURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("ForcedRep", isDirectory: true).appendingPathComponent("state.sqlite")
        queue.setSpecific(key: queueKey, value: true)
    }

    deinit {
        let close = { if let database = self.database { sqlite3_close(database) } }
        if DispatchQueue.getSpecific(key: queueKey) == true { close() } else { queue.sync(execute: close) }
    }

    func load() throws -> StoredAppState? {
        try queue.sync { try read() }
    }

    private func read() throws -> StoredAppState? {
        try open()
        let statement = try prepare("SELECT payload FROM app_metadata WHERE singleton = 1")
        defer { sqlite3_finalize(statement) }
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { didLoad = true; return nil }
        guard result == SQLITE_ROW else { throw failure() }
        let data = try blob(statement, column: 0)
        let metadata = try JSONDecoder().decode(Metadata.self, from: data)
        let history = try prepare("SELECT record_key, payload FROM workout_sessions")
        defer { sqlite3_finalize(history) }
        var loaded: [String: WorkoutSessionRecord] = [:]
        while true {
            let result = sqlite3_step(history)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW, let key = sqlite3_column_text(history, 0) else { throw failure() }
            loaded[String(cString: key)] = try JSONDecoder().decode(WorkoutSessionRecord.self, from: blob(history, column: 1))
        }
        var state = metadata.state
        state.history = try metadata.historyKeys.map { key in
            guard let record = loaded[key] else { throw CocoaError(.fileReadCorruptFile) }
            return record
        }
        guard loaded.count == Set(metadata.historyKeys).count else { throw CocoaError(.fileReadCorruptFile) }
        records = loaded
        metadataData = data
        didLoad = true
        return state
    }

    func save(_ state: StoredAppState, completion: @escaping (Error?) -> Void) {
        queue.async {
            do { try self.write(state); self.lastError = nil; completion(nil) }
            catch { self.lastError = error; completion(error) }
        }
    }

    /// Used before clearing a completed draft, acknowledging restore, or migrating.
    func saveAndWait(_ state: StoredAppState) throws {
        try queue.sync {
            do { try write(state); lastError = nil }
            catch { lastError = error; throw error }
        }
    }

    func flush() throws {
        try queue.sync { if let lastError { throw lastError } }
    }

    /// Legacy fixtures/importers can explicitly supply this key on a later launch.
    /// Remove it only after the complete database snapshot can be decoded again.
    func migrate(_ state: StoredAppState, defaults: UserDefaults, legacyKey: String) throws {
        try saveAndWait(state)
        guard let reloaded = try load() else { throw CocoaError(.fileReadCorruptFile) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard try encoder.encode(reloaded) == encoder.encode(state) else { throw CocoaError(.fileReadCorruptFile) }
        defaults.removeObject(forKey: legacyKey)
    }

    private func write(_ state: StoredAppState) throws {
        try open()
        if !didLoad { _ = try read() }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        var counts: [String: Int] = [:]
        var nextRecords: [String: WorkoutSessionRecord] = [:]
        var keys: [String] = []
        var changed: [(String, Data)] = []
        for record in state.history {
            let occurrence = counts[record.id, default: 0]
            counts[record.id] = occurrence + 1
            // Preserve ordering and even duplicate legacy IDs without merging records.
            let key = "\(record.id.utf8.count):\(record.id):\(occurrence)"
            keys.append(key)
            nextRecords[key] = record
            if records[key] != record { changed.append((key, try encoder.encode(record))) }
        }
        var smallState = state
        smallState.history = []
        let metadata = try encoder.encode(Metadata(state: smallState, historyKeys: keys))
        let removed = records.keys.filter { nextRecords[$0] == nil }
        guard metadata != metadataData || !changed.isEmpty || !removed.isEmpty else { return }
        try execute("BEGIN IMMEDIATE")
        do {
            let upsert = try prepare("INSERT OR REPLACE INTO workout_sessions(record_key,payload) VALUES (?,?)")
            defer { sqlite3_finalize(upsert) }
            for (key, payload) in changed {
                sqlite3_reset(upsert); sqlite3_clear_bindings(upsert)
                try bind(key, to: upsert, at: 1); try bind(payload, to: upsert, at: 2)
                guard sqlite3_step(upsert) == SQLITE_DONE else { throw failure() }
            }
            let deletion = try prepare("DELETE FROM workout_sessions WHERE record_key = ?")
            defer { sqlite3_finalize(deletion) }
            for key in removed {
                sqlite3_reset(deletion); sqlite3_clear_bindings(deletion)
                try bind(key, to: deletion, at: 1)
                guard sqlite3_step(deletion) == SQLITE_DONE else { throw failure() }
            }
            let meta = try prepare("INSERT OR REPLACE INTO app_metadata(singleton,payload) VALUES (1,?)")
            defer { sqlite3_finalize(meta) }
            try bind(metadata, to: meta, at: 1)
            guard sqlite3_step(meta) == SQLITE_DONE else { throw failure() }
            try beforeCommit?()
            try execute("COMMIT")
            records = nextRecords
            metadataData = metadata
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func open() throws {
        dispatchPrecondition(condition: .onQueue(queue))
        if database != nil { return }
        let path: String
        if inMemory { path = ":memory:" }
        else {
            guard let databaseURL else { throw CocoaError(.fileNoSuchFile) }
            try FileManager.default.createDirectory(at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            path = databaseURL.path
        }
        var connection: OpaquePointer?
        guard sqlite3_open_v2(path, &connection, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            if let connection { sqlite3_close(connection) }
            throw CocoaError(.fileWriteUnknown)
        }
        database = connection
        do {
            sqlite3_busy_timeout(database, 5000)
            try execute("PRAGMA journal_mode = WAL")
            try execute("PRAGMA synchronous = FULL")
            try execute("CREATE TABLE IF NOT EXISTS app_metadata(singleton INTEGER PRIMARY KEY CHECK(singleton = 1), payload BLOB NOT NULL)")
            try execute("CREATE TABLE IF NOT EXISTS workout_sessions(record_key TEXT PRIMARY KEY, payload BLOB NOT NULL)")
        } catch {
            sqlite3_close(database); database = nil
            throw error
        }
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw failure() }
    }
    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw failure() }
        return statement
    }
    private func bind(_ value: String, to statement: OpaquePointer, at index: Int32) throws {
        guard sqlite3_bind_text(statement, index, value, -1, transient) == SQLITE_OK else { throw failure() }
    }
    private func bind(_ value: Data, to statement: OpaquePointer, at index: Int32) throws {
        let result = value.withUnsafeBytes { sqlite3_bind_blob(statement, index, $0.baseAddress, Int32(value.count), transient) }
        guard result == SQLITE_OK else { throw failure() }
    }
    private func blob(_ statement: OpaquePointer, column: Int32) throws -> Data {
        guard let bytes = sqlite3_column_blob(statement, column) else { throw CocoaError(.fileReadCorruptFile) }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, column)))
    }
    private func failure() -> Error {
        NSError(domain: "ForcedRep.Persistence", code: Int(sqlite3_errcode(database)), userInfo: [NSLocalizedDescriptionKey: "Workout storage could not be read or written."])
    }
}
