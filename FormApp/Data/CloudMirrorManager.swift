import Foundation
#if canImport(UIKit)
import UIKit
#endif

public class CloudMirrorManager {
    public static let shared = CloudMirrorManager()

    private let keyEnabled = "cloud_mirror_enabled"
    private let keyLastSync = "cloud_mirror_last_sync"

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
        guard ProAccessManager.shared.isFeatureUnlocked(.formLab), isEnabled, hasPendingSync else { return }
        guard let payload = try? String(contentsOf: pendingBackupFile, encoding: .utf8), !payload.isEmpty else {
            clearPendingSync()
            return
        }
        autoSync(backupJson: payload)
    }

    private init() {}

    public var isICloudAvailable: Bool {
        return FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.com.perseverancesoftware.forcedrep") != nil
    }

    public var mirrorDirectory: URL {
        if let ubiquityURL = FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.com.perseverancesoftware.forcedrep") {
            let docs = ubiquityURL.appendingPathComponent("Documents").appendingPathComponent(mirrorDirName)
            if !FileManager.default.fileExists(atPath: docs.path) {
                try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
            }
            return docs
        } else {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let dir = docs.appendingPathComponent(mirrorDirName)
            if !FileManager.default.fileExists(atPath: dir.path) {
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            return dir
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
        let lastSync = UserDefaults.standard.object(forKey: keyLastSync) as? TimeInterval
        let file = mirrorDirectory.appendingPathComponent(backupFileName)
        let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int64)
        let provider = isICloudAvailable ? "iCloud Drive" : "Local Mirror (No iCloud Drive)"

        return CloudMirrorStatus(
            isEnabled: isEnabled,
            isEncrypted: false,
            lastSyncTimestamp: lastSync,
            snapshotSizeBytes: size,
            providerName: provider
        )
    }

    public func autoSync(backupJson: String) {
        guard ProAccessManager.shared.isFeatureUnlocked(.formLab) else { return }
        guard isEnabled else { return }

        // 1. Stage pending backup to disk so it survives process suspension/termination
        savePendingSync(backupJson: backupJson)

        // 2. Request background execution time from iOS to prevent immediate suspension
        #if canImport(UIKit)
        var bgTaskId: UIBackgroundTaskIdentifier = .invalid
        if Thread.isMainThread {
            bgTaskId = UIApplication.shared.beginBackgroundTask(withName: "CloudMirrorAutoSync") {
                UIApplication.shared.endBackgroundTask(bgTaskId)
                bgTaskId = .invalid
            }
        }
        #endif

        Task.detached(priority: .background) { [weak self] in
            #if canImport(UIKit)
            defer {
                if bgTaskId != .invalid {
                    DispatchQueue.main.async {
                        UIApplication.shared.endBackgroundTask(bgTaskId)
                    }
                }
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
        guard ProAccessManager.shared.isFeatureUnlocked(.formLab) else {
            throw NSError(domain: "CloudMirror", code: 403, userInfo: [NSLocalizedDescriptionKey: "Cloud Mirror sync requires Forced Rep Pro"])
        }
        guard isEnabled else {
            throw NSError(domain: "CloudMirror", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cloud Mirror is disabled"])
        }

        let file = mirrorDirectory.appendingPathComponent(backupFileName)

        var coordinatorError: NSError?
        var writeError: Error?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(writingItemAt: file, options: .forReplacing, error: &coordinatorError) { writeURL in
            do {
                guard let data = backupJson.data(using: .utf8) else {
                    throw NSError(domain: "CloudMirror", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid UTF-8 payload"])
                }
                try data.write(to: writeURL, options: .atomic)
            } catch {
                writeError = error
            }
        }
        if let err = writeError { throw err }
        if let err = coordinatorError { throw err }

        let now = Date().timeIntervalSince1970
        UserDefaults.standard.set(now, forKey: keyLastSync)

        let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
        return (attrs[.size] as? Int64) ?? 0
    }

    public func readLatestSnapshot() throws -> String {
        let file = mirrorDirectory.appendingPathComponent(backupFileName)
        guard FileManager.default.fileExists(atPath: file.path) else {
            throw NSError(domain: "CloudMirror", code: 5, userInfo: [NSLocalizedDescriptionKey: "No cloud mirror backup snapshot found."])
        }

        var coordinatorError: NSError?
        var readError: Error?
        var resultString: String?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(readingItemAt: file, options: .withoutChanges, error: &coordinatorError) { readURL in
            do {
                resultString = try String(contentsOf: readURL, encoding: .utf8)
            } catch {
                readError = error
            }
        }
        if let err = readError { throw err }
        if let err = coordinatorError { throw err }
        guard let result = resultString else {
            throw NSError(domain: "CloudMirror", code: 6, userInfo: [NSLocalizedDescriptionKey: "Failed to read cloud mirror."])
        }
        return result
    }
}
