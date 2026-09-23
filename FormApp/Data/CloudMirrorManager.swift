import Foundation
#if canImport(UIKit)
import UIKit
#endif

public class CloudMirrorManager {
    public static let shared = CloudMirrorManager()

    private let keyEnabled = "cloud_mirror_enabled"
    private let keyLastSync = "cloud_mirror_last_sync" // Legacy key
    private let keyLastLocalWrite = "cloud_mirror_last_local_write"
    private let keyLastCloudUpload = "cloud_mirror_last_cloud_upload"

    private let mirrorDirName = "CloudMirror"
    private let backupFileName = "form_safety_mirror.json"
    private let pendingBackupFileName = "pending_form_safety_mirror.json"

    private var pendingBackupFile: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent(pendingBackupFileName)
    }

    public func savePendingSync(backupJson: String) {
        try? backupJson.write(to: pendingBackupFile, atomically: true, encoding: .utf8)
    }

    public func clearPendingSync() {
        try? FileManager.default.removeItem(at: pendingBackupFile)
    }

    public var hasPendingSync: Bool {
        FileManager.default.fileExists(atPath: pendingBackupFile.path)
    }

    public func retryPendingSyncIfAny() {
        guard ProAccessManager.shared.isFeatureUnlocked(.cloudBackup), isEnabled, hasPendingSync else { return }
        guard let payload = try? String(contentsOf: pendingBackupFile, encoding: .utf8), !payload.isEmpty else {
            clearPendingSync()
            return
        }
        autoSync(backupJson: payload)
    }

#if canImport(UIKit)
private final class BackgroundTaskTracker: @unchecked Sendable {
    private var taskId: UIBackgroundTaskIdentifier = .invalid
    private var isEnded = false
    private let lock = NSLock()

    func start(name: String) {
        lock.lock()
        defer { lock.unlock() }
        guard !isEnded else { return }
        taskId = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            self?.end()
        }
    }

    func end() {
        lock.lock()
        isEnded = true
        let id = taskId
        taskId = .invalid
        lock.unlock()
        if id != .invalid {
            UIApplication.shared.endBackgroundTask(id)
        }
    }
}
#endif

    private var _cachedUbiquityURL: URL? = nil
    private let ubiquityLock = NSLock()
    private let ubiquityQueue = DispatchQueue(label: "com.form.CloudMirror.ubiquity", qos: .utility)

    private var cachedUbiquityURL: URL? {
        get {
            ubiquityLock.lock()
            defer { ubiquityLock.unlock() }
            return _cachedUbiquityURL
        }
        set {
            ubiquityLock.lock()
            _cachedUbiquityURL = newValue
            ubiquityLock.unlock()
        }
    }

    private init() {
        refreshUbiquityURL()
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSUbiquityIdentityDidChange,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.refreshUbiquityURL()
        }
    }

    public func refreshUbiquityURL() {
        ubiquityQueue.async { [weak self] in
            guard let self = self else { return }
            let url = FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.com.perseverancesoftware.forcedrep")
            self.cachedUbiquityURL = url
            if url != nil {
                self.migrateLocalToCloudIfNewer()
            }
        }
    }

    private func migrateLocalToCloudIfNewer() {
        guard let ubiDir = ubiquitousMirrorDirectory else { return }
        let localFile = localMirrorDirectory.appendingPathComponent(backupFileName)
        guard FileManager.default.fileExists(atPath: localFile.path) else { return }

        let ubiFile = ubiDir.appendingPathComponent(backupFileName)
        let localDate = (try? FileManager.default.attributesOfItem(atPath: localFile.path)[.modificationDate] as? Date) ?? Date.distantPast
        let ubiDate = (try? FileManager.default.attributesOfItem(atPath: ubiFile.path)[.modificationDate] as? Date) ?? Date.distantPast

        if !FileManager.default.fileExists(atPath: ubiFile.path) || localDate > ubiDate {
            guard let localContent = try? Data(contentsOf: localFile) else { return }
            var coordinatorError: NSError?
            var writeError: Error?
            let coordinator = NSFileCoordinator(filePresenter: nil)
            coordinator.coordinate(writingItemAt: ubiFile, options: .forReplacing, error: &coordinatorError) { writeURL in
                do {
                    try localContent.write(to: writeURL, options: .atomic)
                } catch {
                    writeError = error
                }
            }
            if coordinatorError == nil && writeError == nil {
                print("[CloudMirror] Successfully migrated newer local backup to iCloud Drive.")
            }
        }
    }

    private func resolveUbiquityURL() -> URL? {
        if let cached = cachedUbiquityURL { return cached }
        if !Thread.isMainThread {
            let url = FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.com.perseverancesoftware.forcedrep")
            cachedUbiquityURL = url
            if url != nil {
                migrateLocalToCloudIfNewer()
            }
            return url
        }
        refreshUbiquityURL()
        return nil
    }

    public var isICloudAvailable: Bool {
        return resolveUbiquityURL() != nil
    }

    public var localMirrorDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent(mirrorDirName)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    public var ubiquitousMirrorDirectory: URL? {
        guard let ubiquityURL = resolveUbiquityURL() else { return nil }
        let docs = ubiquityURL.appendingPathComponent("Documents").appendingPathComponent(mirrorDirName)
        if !FileManager.default.fileExists(atPath: docs.path) {
            try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        }
        return docs
    }

    public var mirrorDirectory: URL {
        return ubiquitousMirrorDirectory ?? localMirrorDirectory
    }

    public func checkICloudUploadStatus() -> (isUploaded: Bool, isUploading: Bool, error: Error?) {
        guard let ubiDir = ubiquitousMirrorDirectory else {
            return (false, false, nil)
        }
        let file = ubiDir.appendingPathComponent(backupFileName)
        guard FileManager.default.fileExists(atPath: file.path) else {
            return (false, false, nil)
        }
        do {
            let resourceValues = try file.resourceValues(forKeys: [
                .ubiquitousItemIsUploadedKey,
                .ubiquitousItemIsUploadingKey,
                .ubiquitousItemUploadingErrorKey
            ])
            let isUploaded = resourceValues.ubiquitousItemIsUploaded ?? false
            let isUploading = resourceValues.ubiquitousItemIsUploading ?? false
            let error = resourceValues.ubiquitousItemUploadingError
            return (isUploaded, isUploading, error)
        } catch {
            return (false, false, error)
        }
    }

    public var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: keyEnabled) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: keyEnabled) }
    }

    public var isEncrypted: Bool {
        get { false }
        set { }
    }

    public func getStatus() -> CloudMirrorStatus {
        let isCloud = isICloudAvailable
        var confirmedSyncTimestamp: TimeInterval? = nil
        var isUploadPending = false
        var provider = "No Cloud Storage (Local Only)"

        if isCloud {
            let uploadStatus = checkICloudUploadStatus()
            let ubiFile = ubiquitousMirrorDirectory?.appendingPathComponent(backupFileName)
            let ubiExists = ubiFile != nil && FileManager.default.fileExists(atPath: ubiFile!.path)

            if uploadStatus.isUploaded {
                let modDate = (try? FileManager.default.attributesOfItem(atPath: ubiFile!.path)[.modificationDate] as? Date)?.timeIntervalSince1970
                let recorded = UserDefaults.standard.object(forKey: keyLastCloudUpload) as? TimeInterval
                let finalTs = recorded ?? modDate ?? UserDefaults.standard.object(forKey: keyLastSync) as? TimeInterval
                confirmedSyncTimestamp = finalTs
                if let finalTs = finalTs {
                    UserDefaults.standard.set(finalTs, forKey: keyLastCloudUpload)
                }
                provider = "iCloud Drive"
            } else if uploadStatus.isUploading {
                isUploadPending = true
                provider = "iCloud Drive (Uploading...)"
                confirmedSyncTimestamp = UserDefaults.standard.object(forKey: keyLastCloudUpload) as? TimeInterval
            } else if ubiExists {
                isUploadPending = true
                provider = "iCloud Drive (Pending Upload)"
                confirmedSyncTimestamp = UserDefaults.standard.object(forKey: keyLastCloudUpload) as? TimeInterval
            } else {
                provider = "iCloud Drive"
                confirmedSyncTimestamp = UserDefaults.standard.object(forKey: keyLastCloudUpload) as? TimeInterval
            }
        } else {
            // Local fallback only: no off-device copy exists
            confirmedSyncTimestamp = nil
            provider = "No Cloud Storage (Local Only)"
        }

        let file = (isCloud ? ubiquitousMirrorDirectory?.appendingPathComponent(backupFileName) : nil)
            ?? localMirrorDirectory.appendingPathComponent(backupFileName)
        let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int64)

        return CloudMirrorStatus(
            isEnabled: isEnabled,
            isEncrypted: false,
            lastSyncTimestamp: confirmedSyncTimestamp,
            snapshotSizeBytes: size,
            providerName: provider,
            isCloudConnected: isCloud,
            isUploadPending: isUploadPending
        )
    }

    public func autoSync(backupJson: String) {
        guard ProAccessManager.shared.isFeatureUnlocked(.cloudBackup) else { return }
        guard isEnabled else { return }

        // 1. Stage pending backup to disk so it survives process suspension/termination
        savePendingSync(backupJson: backupJson)

        // 2. Request background execution time from iOS to prevent immediate suspension
        #if canImport(UIKit)
        let bgTracker = BackgroundTaskTracker()
        if Thread.isMainThread {
            bgTracker.start(name: "CloudMirrorAutoSync")
        } else {
            DispatchQueue.main.async {
                bgTracker.start(name: "CloudMirrorAutoSync")
            }
        }
        #endif

        Task.detached(priority: .background) { [weak self] in
            #if canImport(UIKit)
            defer {
                bgTracker.end()
            }
            #endif
            do {
                _ = try self?.syncNow(backupJson: backupJson)
                self?.clearPendingSync()
                print("[CloudMirror] Durable autoSync succeeded.")
            } catch {
                print("[CloudMirror] AutoSync failed (retained on disk to retry on next app launch/foreground): \(error.localizedDescription)")
            }
        }
    }

    @discardableResult
    public func syncNow(backupJson: String) throws -> Int64 {
        guard ProAccessManager.shared.isFeatureUnlocked(.cloudBackup) else {
            throw NSError(domain: "CloudMirror", code: 403, userInfo: [NSLocalizedDescriptionKey: "Cloud Mirror sync requires Forced Rep Pro"])
        }
        guard isEnabled else {
            throw NSError(domain: "CloudMirror", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cloud Mirror is disabled"])
        }
        guard let data = backupJson.data(using: .utf8) else {
            throw NSError(domain: "CloudMirror", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid UTF-8 payload"])
        }

        let now = Date().timeIntervalSince1970

        // 1. Always write local mirror snapshot atomically
        let localFile = localMirrorDirectory.appendingPathComponent(backupFileName)
        try data.write(to: localFile, options: .atomic)
        UserDefaults.standard.set(now, forKey: keyLastLocalWrite)

        var writtenSize: Int64 = (try? FileManager.default.attributesOfItem(atPath: localFile.path)[.size] as? Int64) ?? Int64(data.count)

        // 2. If iCloud is available, write to ubiquitous container via NSFileCoordinator
        if let ubiDir = ubiquitousMirrorDirectory {
            let ubiFile = ubiDir.appendingPathComponent(backupFileName)
            var coordinatorError: NSError?
            var writeError: Error?
            let coordinator = NSFileCoordinator(filePresenter: nil)
            coordinator.coordinate(writingItemAt: ubiFile, options: .forReplacing, error: &coordinatorError) { writeURL in
                do {
                    try data.write(to: writeURL, options: .atomic)
                } catch {
                    writeError = error
                }
            }
            if let err = writeError { throw err }
            if let err = coordinatorError { throw err }

            let attrs = try FileManager.default.attributesOfItem(atPath: ubiFile.path)
            writtenSize = (attrs[.size] as? Int64) ?? writtenSize
            UserDefaults.standard.set(now, forKey: keyLastSync)
        }

        return writtenSize
    }

    public func readLatestSnapshot() throws -> String {
        let localFile = localMirrorDirectory.appendingPathComponent(backupFileName)
        let localExists = FileManager.default.fileExists(atPath: localFile.path)

        var ubiFile: URL? = nil
        var ubiExists = false
        if let ubiDir = ubiquitousMirrorDirectory {
            let candidate = ubiDir.appendingPathComponent(backupFileName)
            if FileManager.default.fileExists(atPath: candidate.path) {
                ubiFile = candidate
                ubiExists = true
            }
        }

        if !localExists && !ubiExists {
            throw NSError(domain: "CloudMirror", code: 5, userInfo: [NSLocalizedDescriptionKey: "No cloud mirror backup snapshot found."])
        }

        // If both exist, inspect modification dates to pick the newer one so local offline workouts are never lost
        let readTarget: URL
        let isUbiquitous: Bool
        if localExists && ubiExists, let ubi = ubiFile {
            let localDate = (try? FileManager.default.attributesOfItem(atPath: localFile.path)[.modificationDate] as? Date) ?? Date.distantPast
            let ubiDate = (try? FileManager.default.attributesOfItem(atPath: ubi.path)[.modificationDate] as? Date) ?? Date.distantPast
            if ubiDate >= localDate {
                readTarget = ubi
                isUbiquitous = true
            } else {
                readTarget = localFile
                isUbiquitous = false
            }
        } else if let ubi = ubiFile {
            readTarget = ubi
            isUbiquitous = true
        } else {
            readTarget = localFile
            isUbiquitous = false
        }

        var resultString: String?
        if isUbiquitous {
            var coordinatorError: NSError?
            var readError: Error?
            let coordinator = NSFileCoordinator(filePresenter: nil)
            coordinator.coordinate(readingItemAt: readTarget, options: .withoutChanges, error: &coordinatorError) { readURL in
                do {
                    resultString = try String(contentsOf: readURL, encoding: .utf8)
                } catch {
                    readError = error
                }
            }
            if let err = readError { throw err }
            if let err = coordinatorError { throw err }
        } else {
            resultString = try String(contentsOf: readTarget, encoding: .utf8)
        }

        guard let result = resultString else {
            throw NSError(domain: "CloudMirror", code: 6, userInfo: [NSLocalizedDescriptionKey: "Failed to read cloud mirror."])
        }
        return result
    }
}
