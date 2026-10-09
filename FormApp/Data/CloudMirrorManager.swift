import Foundation
import Combine
import Network
#if canImport(UIKit)
import UIKit
#endif

struct CloudSnapshot {
    let url: URL
    let modifiedAt: Date
}

/// Runs on the main run loop, as required by NSMetadataQuery. Remote placeholders
/// are results too: do not use fileExists to decide whether an iCloud backup exists.
@MainActor
private final class CloudSnapshotDiscovery {
    private let query = NSMetadataQuery()
    private var observers: [NSObjectProtocol] = []
    private var timeout: Task<Void, Never>?
    private var continuation: CheckedContinuation<CloudSnapshot?, Error>?

    func find(in container: URL) async throws -> CloudSnapshot? {
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
                query.predicate = NSPredicate(format: "%K == %@", NSMetadataItemFSNameKey, CloudMirrorManager.backupFileName)
                observers.append(NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.finish(.success(Self.latestSnapshot(in: self.query, container: container)))
                    }
                })
                timeout = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 15_000_000_000)
                    guard !Task.isCancelled else { return }
                    self?.finish(.failure(CloudMirrorError.discoveryTimedOut))
                }
                if Task.isCancelled { finish(.failure(CancellationError())) }
                else if !query.start() { finish(.failure(CloudMirrorError.discoveryFailed)) }
            }
        }, onCancel: { Task { @MainActor [weak self] in self?.finish(.failure(CancellationError())) } })
    }

    static func latestSnapshot(in query: NSMetadataQuery, container: URL) -> CloudSnapshot? {
        query.disableUpdates()
        defer { query.enableUpdates() }
        let prefix = container.standardizedFileURL.path + "/"
        return (query.results as? [NSMetadataItem] ?? []).compactMap { item -> CloudSnapshot? in
            guard let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL,
                  url.standardizedFileURL.path.hasPrefix(prefix) else { return nil }
            let date = item.value(forAttribute: NSMetadataItemFSContentChangeDateKey) as? Date ?? .distantFuture
            return CloudSnapshot(url: url, modifiedAt: date)
        }.max { $0.modifiedAt < $1.modifiedAt }
    }

    private func finish(_ result: Result<CloudSnapshot?, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        query.stop()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        timeout?.cancel()
        timeout = nil
        continuation.resume(with: result)
    }
}

enum CloudMirrorError: LocalizedError {
    case premiumRequired, disabled, noBackup, discoveryTimedOut, discoveryFailed, downloadTimedOut, accountChanged, newerCloudBackup, invalidBackup
    var errorDescription: String? {
        let key: String
        switch self {
        case .premiumRequired: key = "form_lab.mirror_premium_required"
        case .disabled: key = "form_lab.mirror_disabled"
        case .noBackup: key = "form_lab.mirror_no_backup"
        case .discoveryTimedOut, .discoveryFailed: key = "form_lab.mirror_discovery_failed"
        case .downloadTimedOut: key = "form_lab.mirror_download_failed"
        case .accountChanged: key = "form_lab.mirror_account_changed"
        case .newerCloudBackup: key = "form_lab.mirror_newer_cloud"
        case .invalidBackup: key = "form_lab.mirror_invalid_backup"
        }
        return LanguageManager.t(key)
    }
}

public final class CloudMirrorManager: ObservableObject {
    public static let shared = CloudMirrorManager()
    static let backupFileName = "form_safety_mirror.json"
    private let keyEnabled = "cloud_mirror_enabled"
    private let keyLastLocalWrite = "cloud_mirror_last_local_write"
    private let keyLastCloudUpload = "cloud_mirror_last_cloud_upload"
    private let keyLastIdentity = "cloud_mirror_last_identity"
    private let keyLocalIdentity = "cloud_mirror_local_identity"

    @Published public private(set) var status = CloudMirrorStatus(isEnabled: true, lastSyncTimestamp: nil, snapshotSizeBytes: nil, providerName: "iCloud Drive", isCheckingCloud: true)
    private let defaults: UserDefaults
    private let documents: URL
    private let containerResolver: () -> URL?
    private let identityProvider: () -> Data?
    private let premiumAvailable: () -> Bool
    private let discoverSnapshot: (URL) async throws -> CloudSnapshot?
    private let prepareDownload: (URL) async throws -> Void
    private let uploadStatus: (URL) throws -> (isUploaded: Bool, isUploading: Bool, error: Error?)
    private let observesSystem: Bool
    private let pendingLock = NSLock()
    private let stateLock = NSLock()
    private let syncQueue = DispatchQueue(label: "com.form.CloudMirror.sync", qos: .utility)
    private var cachedContainer: URL?
    private var observedSnapshot: CloudSnapshot?
    private var checkingCloud = true
    private var operationError: String?
    private var isRetrying = false
    private var cachedStatus: CloudMirrorStatus?
    private var systemObservers: [NSObjectProtocol] = []
    private var networkMonitor: NWPathMonitor?
    // Main-thread-only metadata observation. It drives status when iCloud finishes uploading.
    private var liveQuery: NSMetadataQuery?
    private var queryObservers: [NSObjectProtocol] = []

    private struct PendingBackup: Codable {
        let payload: String
        let identity: Data?
        let canBindFirstAccount: Bool
        let createdAt: Date
        let generation: UUID
    }

    init(documentsDirectory: URL? = nil, defaults: UserDefaults = .standard,
         containerResolver: @escaping () -> URL? = { FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.com.perseverancesoftware.forcedrep") },
         identityProvider: @escaping () -> Data? = {
             guard let token = FileManager.default.ubiquityIdentityToken else { return nil }
             return try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: false)
         },
         premiumAvailable: @escaping () -> Bool = { ProAccessManager.shared.isFeatureUnlocked(.cloudBackup) },
         discoverSnapshot: @escaping (URL) async throws -> CloudSnapshot? = { container in
             try await CloudSnapshotDiscovery().find(in: container)
         },
         prepareDownload: @escaping (URL) async throws -> Void = CloudMirrorManager.downloadSnapshot,
         uploadStatus: @escaping (URL) throws -> (isUploaded: Bool, isUploading: Bool, error: Error?) = { url in
             var refreshedURL = url
             refreshedURL.removeAllCachedResourceValues()
             let values = try refreshedURL.resourceValues(forKeys: [.ubiquitousItemIsUploadedKey, .ubiquitousItemIsUploadingKey, .ubiquitousItemUploadingErrorKey])
             return (values.ubiquitousItemIsUploaded ?? false, values.ubiquitousItemIsUploading ?? false, values.ubiquitousItemUploadingError)
         }, observesSystem: Bool = true) {
        self.documents = documentsDirectory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.defaults = defaults
        self.containerResolver = containerResolver
        self.identityProvider = identityProvider
        self.premiumAvailable = premiumAvailable
        self.discoverSnapshot = discoverSnapshot
        self.prepareDownload = prepareDownload
        self.uploadStatus = uploadStatus
        self.observesSystem = observesSystem
        if observesSystem {
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { [weak self] path in
                if path.status == .satisfied { self?.refreshUbiquityURL() }
            }
            monitor.start(queue: DispatchQueue(label: "com.form.CloudMirror.network", qos: .utility))
            networkMonitor = monitor
            systemObservers.append(NotificationCenter.default.addObserver(forName: .NSUbiquityIdentityDidChange, object: nil, queue: .main) { [weak self] _ in
                self?.invalidateCloudIdentity()
                self?.refreshUbiquityURL()
            })
            #if canImport(UIKit)
            systemObservers.append(NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
                self?.refreshUbiquityURL()
            })
            #endif
            refreshUbiquityURL()
        }
    }

    deinit {
        networkMonitor?.cancel()
        systemObservers.forEach { NotificationCenter.default.removeObserver($0) }
        queryObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    private var pendingBackupFile: URL { documents.appendingPathComponent("pending_form_safety_mirror.json") }
    public var localMirrorDirectory: URL {
        let dir = documents.appendingPathComponent("CloudMirror")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    private func cloudMirrorDirectory(in container: URL) throws -> URL {
        let dir = container.appendingPathComponent("Documents/CloudMirror")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    public var ubiquitousMirrorDirectory: URL? {
        stateLock.lock(); let container = cachedContainer; stateLock.unlock()
        return container?.appendingPathComponent("Documents/CloudMirror")
    }
    public var mirrorDirectory: URL { ubiquitousMirrorDirectory ?? localMirrorDirectory }
    public var isICloudAvailable: Bool { ubiquitousMirrorDirectory != nil }
    public var isEnabled: Bool {
        get { defaults.object(forKey: keyEnabled) as? Bool ?? true }
        set {
            defaults.set(newValue, forKey: keyEnabled)
            refreshStatus()
            if newValue { retryPendingSyncIfAny() }
        }
    }
    public var isEncrypted: Bool { get { false } set {} }
    public var hasPendingSync: Bool { readPendingSync() != nil }

    @discardableResult
    public func savePendingSync(backupJson: String) -> Bool {
        pendingLock.lock(); defer { pendingLock.unlock() }
        let identity = identityProvider() ?? defaults.data(forKey: keyLastIdentity)
        let record = PendingBackup(payload: backupJson, identity: identity, canBindFirstAccount: identity == nil, createdAt: Date(), generation: UUID())
        do {
            try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
            try JSONEncoder().encode(record).write(to: pendingBackupFile, options: .atomic)
            return true
        } catch { recordError(error); return false }
    }

    private func readPendingSync() -> PendingBackup? {
        pendingLock.lock(); defer { pendingLock.unlock() }
        guard let data = try? Data(contentsOf: pendingBackupFile) else { return nil }
        if let record = try? JSONDecoder().decode(PendingBackup.self, from: data) { return record }
        // Preserve old staged payloads, but never silently send an unbound legacy
        // backup to a different Apple account. Manual Sync Now binds it explicitly.
        guard let payload = String(data: data, encoding: .utf8) else { return nil }
        let date = (try? pendingBackupFile.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        return PendingBackup(payload: payload, identity: nil, canBindFirstAccount: false, createdAt: date, generation: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!)
    }

    public func clearPendingSync(onlyIfMatching payload: String? = nil) {
        pendingLock.lock(); defer { pendingLock.unlock() }
        if let payload {
            guard let data = try? Data(contentsOf: pendingBackupFile) else { return }
            let staged = (try? JSONDecoder().decode(PendingBackup.self, from: data).payload) ?? String(data: data, encoding: .utf8)
            guard staged == payload else { return }
        }
        try? FileManager.default.removeItem(at: pendingBackupFile)
    }

    private func clearPendingSync(generation: UUID) {
        pendingLock.lock(); defer { pendingLock.unlock() }
        guard let data = try? Data(contentsOf: pendingBackupFile),
              let record = try? JSONDecoder().decode(PendingBackup.self, from: data), record.generation == generation else { return }
        try? FileManager.default.removeItem(at: pendingBackupFile)
    }

    public func refreshUbiquityURL() {
        Task { [weak self] in
            guard let self else { return }
            _ = try? await self.resolveContainer()
            self.retryPendingSyncIfAny()
        }
    }

    private func invalidateCloudIdentity() {
        stateLock.lock()
        cachedContainer = nil
        observedSnapshot = nil
        checkingCloud = true
        operationError = nil
        stateLock.unlock()
        defaults.removeObject(forKey: keyLastCloudUpload)
        startObservingCloud(nil)
        refreshStatus()
    }

    private func resolveContainer() async throws -> URL? {
        try await runIO {
            let identity = self.identityProvider()
            let container = self.containerResolver()
            guard Self.sameIdentity(identity, self.identityProvider()) else { throw CloudMirrorError.accountChanged }
            if let identity {
                if let previous = self.defaults.data(forKey: self.keyLastIdentity), !Self.sameIdentity(previous, identity) {
                    self.defaults.removeObject(forKey: self.keyLastCloudUpload)
                }
                self.defaults.set(identity, forKey: self.keyLastIdentity)
            }
            self.stateLock.lock()
            if self.cachedContainer != container { self.observedSnapshot = nil }
            self.cachedContainer = container
            self.checkingCloud = false
            self.stateLock.unlock()
            self.startObservingCloud(container)
            self.updateStatus()
            return container
        }
    }

    public func retryPendingSyncIfAny() {
        guard premiumAvailable(), isEnabled, hasPendingSync else { return }
        stateLock.lock()
        guard !isRetrying else { stateLock.unlock(); return }
        isRetrying = true
        stateLock.unlock()
        Task { [weak self] in
            guard let self else { return }
            let generation = self.readPendingSync()?.generation
            let backgroundTask = await self.beginBackgroundTask()
            defer {
                self.endBackgroundTask(backgroundTask)
                self.finishRetry(previousGeneration: generation)
            }
            do { try await self.flushPendingSync() }
            catch { self.recordError(error) }
        }
    }

    private func finishRetry(previousGeneration: UUID?) {
        stateLock.lock(); isRetrying = false; stateLock.unlock()
        if let current = readPendingSync()?.generation, current != previousGeneration {
            retryPendingSyncIfAny()
        }
    }

    public func autoSync(backupJson: String) {
        guard premiumAvailable(), isEnabled, savePendingSync(backupJson: backupJson) else { return }
        retryPendingSyncIfAny()
    }

    private func flushPendingSync() async throws {
        guard let pending = readPendingSync() else { return }
        let localSize = try await runIO {
            try self.checkWriteAccess()
            guard self.readPendingSync()?.generation == pending.generation else { return Int64(0) }
            return try self.writeLocal(pending)
        }
        guard localSize > 0 else { return }
        guard let container = try await resolveContainer() else { return } // Keep the offline payload on disk.
        guard let identity = identityProvider() else { throw CloudMirrorError.accountChanged }
        guard Self.sameIdentity(pending.identity, identity) || (pending.canBindFirstAccount && pending.identity == nil) else { throw CloudMirrorError.accountChanged }
        let remote = try await discoverSnapshot(container)
        if let remote, remote.modifiedAt > pending.createdAt { throw CloudMirrorError.newerCloudBackup }
        try await runIO {
            try self.checkWriteAccess()
            guard Self.sameIdentity(identity, self.identityProvider()) else { throw CloudMirrorError.accountChanged }
            guard self.readPendingSync()?.generation == pending.generation else { return }
            try self.writeCloud(pending, container: container, identity: identity)
            self.clearPendingSync(generation: pending.generation)
            self.clearOperationError()
            self.updateStatus()
        }
    }

    /// Synchronous compatibility entry point; UI uses syncNowAsync so file coordination never blocks it.
    @discardableResult
    public func syncNow(backupJson: String) throws -> Int64 {
        try checkWriteAccess()
        guard savePendingSync(backupJson: backupJson), let pending = readPendingSync() else { throw CloudMirrorError.invalidBackup }
        let size = try writeLocal(pending)
        let identity = identityProvider()
        if let container = containerResolver() {
            guard identity != nil, Self.sameIdentity(pending.identity, identity) || (pending.canBindFirstAccount && pending.identity == nil) else { throw CloudMirrorError.accountChanged }
            guard Self.sameIdentity(identity, identityProvider()) else { throw CloudMirrorError.accountChanged }
            try writeCloud(pending, container: container, identity: identity)
            clearPendingSync(generation: pending.generation)
            stateLock.lock(); cachedContainer = container; checkingCloud = false; stateLock.unlock()
            startObservingCloud(container)
        } else {
            stateLock.lock(); cachedContainer = nil; checkingCloud = false; stateLock.unlock()
        }
        clearOperationError()
        updateStatus()
        return size
    }

    public func syncNowAsync(backupJson: String) async throws -> Int64 {
        do { return try await runIO { try self.syncNow(backupJson: backupJson) } }
        catch { recordError(error); throw error }
    }

    private static func sameIdentity(_ lhs: Data?, _ rhs: Data?) -> Bool {
        if lhs == rhs { return true }
        guard let lhs, let rhs,
              let left = decodeIdentity(lhs), let right = decodeIdentity(rhs) else { return false }
        // Archives need not be byte-identical across launches; compare Apple's
        // opaque NSCoding identity tokens by equality, as the platform intends.
        return left.isEqual(right)
    }

    private static func decodeIdentity(_ data: Data) -> NSObject? {
        guard let decoder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        // Apple's opaque identity contract guarantees NSCoding, not NSSecureCoding.
        // These archives originate from the local FileManager identity token.
        decoder.requiresSecureCoding = false
        defer { decoder.finishDecoding() }
        return decoder.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? NSObject
    }

    private func checkWriteAccess() throws {
        // Keep the legacy error domain/code consumed by the existing manager tests.
        guard premiumAvailable() else { throw NSError(domain: "CloudMirror", code: 403, userInfo: [NSLocalizedDescriptionKey: CloudMirrorError.premiumRequired.localizedDescription]) }
        guard isEnabled else { throw CloudMirrorError.disabled }
    }

    private func writeLocal(_ pending: PendingBackup) throws -> Int64 {
        let file = localMirrorDirectory.appendingPathComponent(Self.backupFileName)
        let data = Data(pending.payload.utf8)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], object["schemaVersion"] != nil else { throw CloudMirrorError.invalidBackup }
        if let unitValue = object["weightUnit"], !(unitValue is NSNull) {
            guard let code = unitValue as? String,
                  WeightUnit(rawValue: code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) != nil else { throw CloudMirrorError.invalidBackup }
        }
        try data.write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.modificationDate: pending.createdAt], ofItemAtPath: file.path)
        defaults.set(pending.createdAt.timeIntervalSince1970, forKey: keyLastLocalWrite)
        defaults.set(pending.identity, forKey: keyLocalIdentity)
        updateStatus()
        return Int64(data.count)
    }

    private func writeCloud(_ pending: PendingBackup, container: URL, identity: Data?) throws {
        let file = try cloudMirrorDirectory(in: container).appendingPathComponent(Self.backupFileName)
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: file, options: .forReplacing, error: &coordinationError) { url in
            do {
                try self.checkWriteAccess()
                guard Self.sameIdentity(identity, self.identityProvider()) else { throw CloudMirrorError.accountChanged }
                guard self.readPendingSync()?.generation == pending.generation else { return }
                try Data(pending.payload.utf8).write(to: url, options: .atomic)
                try FileManager.default.setAttributes([.modificationDate: pending.createdAt], ofItemAtPath: url.path)
            } catch { writeError = error }
        }
        if let error = writeError ?? coordinationError { throw error }
        if let identity {
            defaults.set(identity, forKey: keyLocalIdentity)
            if let previous = defaults.data(forKey: keyLastIdentity), !Self.sameIdentity(previous, identity) {
                defaults.removeObject(forKey: keyLastCloudUpload)
            }
            defaults.set(identity, forKey: keyLastIdentity)
        }
    }

    public func readLatestSnapshotAsync() async throws -> String {
        do {
            let container = try await resolveContainer()
            let identity = identityProvider()
            let remote: CloudSnapshot?
            if let container { remote = try await discoverSnapshot(container) }
            else { remote = nil }
            let local = localMirrorDirectory.appendingPathComponent(Self.backupFileName)
            let localDate = try await runIO { () -> Date? in
                let boundIdentity = self.defaults.data(forKey: self.keyLocalIdentity)
                if let identity, let boundIdentity, !Self.sameIdentity(identity, boundIdentity) { return nil }
                return try? local.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            }
            guard Self.sameIdentity(identity, identityProvider()) else { throw CloudMirrorError.accountChanged }
            let result: String
            if let remote, localDate == nil || remote.modifiedAt >= localDate! {
                try await prepareDownload(remote.url)
                result = try await runIO {
                    guard Self.sameIdentity(identity, self.identityProvider()) else { throw CloudMirrorError.accountChanged }
                    return try self.readCoordinated(remote.url)
                }
            } else {
                guard localDate != nil else { throw CloudMirrorError.noBackup }
                result = try await runIO {
                    guard Self.sameIdentity(identity, self.identityProvider()) else { throw CloudMirrorError.accountChanged }
                    return try String(contentsOf: local, encoding: .utf8)
                }
            }
            try Task.checkCancellation()
            guard Self.sameIdentity(identity, identityProvider()) else { throw CloudMirrorError.accountChanged }
            clearOperationError()
            refreshStatus()
            return result
        } catch { recordError(error); throw error }
    }

    public func didRestoreSnapshot() {
        // Restoring replaces the saved app data, so an older queued export must
        // never upload later and undo that deliberate restore.
        clearPendingSync()
        clearOperationError()
        refreshStatus()
    }

    /// Local read for old callers/tests. Remote restore must use the async discovery path.
    public func readLatestSnapshot() throws -> String {
        let local = localMirrorDirectory.appendingPathComponent(Self.backupFileName)
        guard FileManager.default.fileExists(atPath: local.path) else { throw CloudMirrorError.noBackup }
        return try String(contentsOf: local, encoding: .utf8)
    }

    private func readCoordinated(_ file: URL) throws -> String {
        var coordinationError: NSError?
        var result: Result<String, Error>?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: file, options: .withoutChanges, error: &coordinationError) { url in
            result = Result { try String(contentsOf: url, encoding: .utf8) }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CloudMirrorError.noBackup }
        return try result.get()
    }

    private static func downloadSnapshot(_ url: URL) async throws {
        let download = Task.detached(priority: .utility) {
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
            let deadline = Date().addingTimeInterval(30)
            repeat {
                try Task.checkCancellation()
                var refreshedURL = url
                refreshedURL.removeAllCachedResourceValues()
                let values = try refreshedURL.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey, .ubiquitousItemDownloadingErrorKey])
                if let error = values.ubiquitousItemDownloadingError { throw error }
                if values.ubiquitousItemDownloadingStatus == .current { return }
                try await Task.sleep(nanoseconds: 250_000_000)
            } while Date() < deadline
            throw CloudMirrorError.downloadTimedOut
        }
        try await withTaskCancellationHandler(operation: { try await download.value }, onCancel: { download.cancel() })
    }

    private func runIO<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            syncQueue.async { continuation.resume(with: Result(catching: work)) }
        }
    }

    public func getStatus() -> CloudMirrorStatus {
        stateLock.lock(); defer { stateLock.unlock() }
        return cachedStatus ?? status
    }
    public func checkICloudUploadStatus() -> (isUploaded: Bool, isUploading: Bool, error: Error?) {
        guard let file = ubiquitousMirrorDirectory?.appendingPathComponent(Self.backupFileName), FileManager.default.fileExists(atPath: file.path) else { return (false, false, nil) }
        do { return try uploadStatus(file) } catch { return (false, false, error) }
    }
    public func refreshStatus() { syncQueue.async { [weak self] in self?.updateStatus() } }
    private func recordError(_ error: Error) {
        stateLock.lock(); operationError = error.localizedDescription; stateLock.unlock()
        refreshStatus()
    }
    private func clearOperationError() { stateLock.lock(); operationError = nil; stateLock.unlock() }

    private func updateStatus() {
        stateLock.lock(); let container = cachedContainer; let observed = observedSnapshot; let checking = checkingCloud; let failure = operationError; stateLock.unlock()
        let file = observed?.url ?? container?.appendingPathComponent("Documents/CloudMirror").appendingPathComponent(Self.backupFileName)
        let exists = observed != nil || (file.map { FileManager.default.fileExists(atPath: $0.path) } ?? false)
        let upload: (isUploaded: Bool, isUploading: Bool, error: Error?)
        if exists, let file {
            do { upload = try uploadStatus(file) } catch { upload = (false, false, error) }
        } else { upload = (false, false, nil) }
        if upload.isUploaded, let file, let date = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
            defaults.set(date.timeIntervalSince1970, forKey: keyLastCloudUpload)
        }
        let local = localMirrorDirectory.appendingPathComponent(Self.backupFileName)
        let size = try? (exists ? file! : local).resourceValues(forKeys: [.fileSizeKey]).fileSize
        let newStatus = CloudMirrorStatus(isEnabled: isEnabled,
            lastSyncTimestamp: container == nil ? nil : defaults.object(forKey: keyLastCloudUpload) as? TimeInterval,
            snapshotSizeBytes: size.map(Int64.init),
            providerName: container == nil ? LanguageManager.t("form_lab.mirror_local_provider") : "iCloud Drive",
            isCloudConnected: container != nil, isUploadPending: exists && !upload.isUploaded,
            isCheckingCloud: checking, errorMessage: upload.error?.localizedDescription ?? failure)
        stateLock.lock(); cachedStatus = newStatus; stateLock.unlock()
        DispatchQueue.main.async { [weak self] in self?.status = newStatus }
    }

    private func setObservedSnapshot(_ snapshot: CloudSnapshot?, container: URL) {
        stateLock.lock(); defer { stateLock.unlock() }
        if cachedContainer == container { observedSnapshot = snapshot }
    }

    private func startObservingCloud(_ container: URL?) {
        guard observesSystem else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.liveQuery?.stop()
            self.queryObservers.forEach { NotificationCenter.default.removeObserver($0) }
            self.queryObservers.removeAll()
            guard let container else { self.liveQuery = nil; return }
            let query = NSMetadataQuery()
            query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
            query.predicate = NSPredicate(format: "%K == %@", NSMetadataItemFSNameKey, Self.backupFileName)
            for name in [Notification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
                self.queryObservers.append(NotificationCenter.default.addObserver(forName: name, object: query, queue: .main) { [weak self] _ in
                    // Query notifications are the upload completion/error signal, even
                    // when the backup sheet stays open without further user input.
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        let snapshot = CloudSnapshotDiscovery.latestSnapshot(in: query, container: container)
                        self.setObservedSnapshot(snapshot, container: container)
                        self.refreshStatus()
                    }
                })
            }
            self.liveQuery = query
            _ = query.start()
        }
    }

    private func beginBackgroundTask() async -> BackgroundAssertion {
        let assertion = BackgroundAssertion()
        #if canImport(UIKit)
        await MainActor.run { assertion.start() }
        #endif
        return assertion
    }
    private func endBackgroundTask(_ assertion: BackgroundAssertion) { assertion.end() }
}

private final class BackgroundAssertion: @unchecked Sendable {
    #if canImport(UIKit)
    private var identifier = UIBackgroundTaskIdentifier.invalid
    @MainActor func start() {
        identifier = UIApplication.shared.beginBackgroundTask(withName: "CloudMirrorAutoSync") { [weak self] in self?.end() }
    }
    #endif
    func end() {
        #if canImport(UIKit)
        DispatchQueue.main.async { [self] in
            guard identifier != .invalid else { return }
            UIApplication.shared.endBackgroundTask(identifier)
            identifier = .invalid
        }
        #endif
    }
}
