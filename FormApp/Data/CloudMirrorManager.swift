import Foundation
import CryptoKit

public class CloudMirrorManager {
    public static let shared = CloudMirrorManager()

    private let keyEnabled = "cloud_mirror_enabled"
    private let keyEncrypted = "cloud_mirror_encrypted"
    private let keyLastSync = "cloud_mirror_last_sync"
    private let keySalt = "cloud_mirror_salt"
    private let keyPassHash = "cloud_mirror_pass_hash"

    private let mirrorDirName = "CloudMirror"
    private let backupFileName = "form_safety_mirror.json"
    private let encryptedBackupFileName = "form_safety_mirror.enc"

    private init() {}

    public var mirrorDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent(mirrorDirName)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    public var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: keyEnabled) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: keyEnabled) }
    }

    public var isEncrypted: Bool {
        get { UserDefaults.standard.bool(forKey: keyEncrypted) }
        set { UserDefaults.standard.set(newValue, forKey: keyEncrypted) }
    }

    public func setEncrypted(_ encrypted: Bool, passphrase: String? = nil) {
        isEncrypted = encrypted
        if encrypted, let pass = passphrase, !pass.isEmpty {
            var saltBytes = [UInt8](repeating: 0, count: 16)
            _ = SecRandomCopyBytes(kSecRandomDefault, 16, &saltBytes)
            let saltStr = Data(saltBytes).base64EncodedString()
            let hash = Self.sha256("\(pass):\(saltStr)")
            UserDefaults.standard.set(saltStr, forKey: keySalt)
            UserDefaults.standard.set(hash, forKey: keyPassHash)
        }
    }

    public func getStatus() -> CloudMirrorStatus {
        let lastSync = UserDefaults.standard.object(forKey: keyLastSync) as? TimeInterval
        let file = isEncrypted ? mirrorDirectory.appendingPathComponent(encryptedBackupFileName) : mirrorDirectory.appendingPathComponent(backupFileName)
        let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int64)

        return CloudMirrorStatus(
            isEnabled: isEnabled,
            isEncrypted: isEncrypted,
            lastSyncTimestamp: lastSync,
            snapshotSizeBytes: size,
            providerName: "iCloud Drive & Cloud Mirror"
        )
    }

    public static func encryptPayload(_ payloadJson: String, passphrase: String) throws -> String {
        guard let data = payloadJson.data(using: .utf8) else {
            throw NSError(domain: "CloudMirror", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid UTF-8 payload"])
        }

        var saltBytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, 16, &saltBytes)
        let salt = Data(saltBytes)

        // Derive 256-bit key
        let keyMaterial = "\(passphrase):\(salt.base64EncodedString())".data(using: .utf8)!
        let digest = SHA256.hash(data: keyMaterial)
        let symmetricKey = SymmetricKey(data: digest)

        let sealedBox = try AES.GCM.seal(data, using: symmetricKey)

        let envelope: [String: Any] = [
            "format": "form_cloud_mirror_v1",
            "encrypted": true,
            "timestamp": Date().timeIntervalSince1970 * 1000,
            "salt": salt.base64EncodedString(),
            "iv": sealedBox.nonce.withUnsafeBytes { Data($0).base64EncodedString() },
            "ciphertext": (sealedBox.ciphertext + sealedBox.tag).base64EncodedString(),
            "sha256": SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
        ]

        let envelopeData = try JSONSerialization.data(withJSONObject: envelope, options: [.prettyPrinted])
        return String(data: envelopeData, encoding: .utf8) ?? "{}"
    }

    public static func decryptPayload(_ envelopeJson: String, passphrase: String) throws -> String {
        guard let envelopeData = envelopeJson.data(using: .utf8),
              let dict = try JSONSerialization.jsonObject(with: envelopeData) as? [String: Any],
              let saltStr = dict["salt"] as? String,
              let salt = Data(base64Encoded: saltStr),
              let combinedCiphertextStr = dict["ciphertext"] as? String,
              let combinedData = Data(base64Encoded: combinedCiphertextStr),
              let ivStr = dict["iv"] as? String,
              let ivData = Data(base64Encoded: ivStr) else {
            throw NSError(domain: "CloudMirror", code: 2, userInfo: [NSLocalizedDescriptionKey: "Malformed encrypted envelope"])
        }

        // Derive symmetric key
        let keyMaterial = "\(passphrase):\(salt.base64EncodedString())".data(using: .utf8)!
        let digest = SHA256.hash(data: keyMaterial)
        let symmetricKey = SymmetricKey(data: digest)

        let nonce = try AES.GCM.Nonce(data: ivData)

        guard combinedData.count >= 16 else {
            throw NSError(domain: "CloudMirror", code: 3, userInfo: [NSLocalizedDescriptionKey: "Ciphertext too short"])
        }
        let tag = combinedData.suffix(16)
        let ciphertext = combinedData.prefix(combinedData.count - 16)

        let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
        let decryptedData = try AES.GCM.open(sealedBox, using: symmetricKey)

        guard let decryptedString = String(data: decryptedData, encoding: .utf8) else {
            throw NSError(domain: "CloudMirror", code: 4, userInfo: [NSLocalizedDescriptionKey: "Decrypted payload is not valid UTF-8"])
        }

        return decryptedString
    }

    @discardableResult
    public func syncNow(backupJson: String, passphrase: String? = nil) throws -> Int64 {
        let file = isEncrypted ? mirrorDirectory.appendingPathComponent(encryptedBackupFileName) : mirrorDirectory.appendingPathComponent(backupFileName)

        if isEncrypted {
            let pass = passphrase ?? "form_default_secure_key"
            let envelope = try Self.encryptPayload(backupJson, passphrase: pass)
            try envelope.data(using: .utf8)?.write(to: file)
        } else {
            try backupJson.data(using: .utf8)?.write(to: file)
        }

        let now = Date().timeIntervalSince1970
        UserDefaults.standard.set(now, forKey: keyLastSync)

        let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
        return (attrs[.size] as? Int64) ?? 0
    }

    public func readLatestSnapshot(passphrase: String? = nil) throws -> String {
        let encryptedFile = mirrorDirectory.appendingPathComponent(encryptedBackupFileName)
        let plainFile = mirrorDirectory.appendingPathComponent(backupFileName)

        if FileManager.default.fileExists(atPath: encryptedFile.path) {
            let content = try String(contentsOf: encryptedFile, encoding: .utf8)
            let pass = passphrase ?? "form_default_secure_key"
            return try Self.decryptPayload(content, passphrase: pass)
        } else if FileManager.default.fileExists(atPath: plainFile.path) {
            return try String(contentsOf: plainFile, encoding: .utf8)
        } else {
            throw NSError(domain: "CloudMirror", code: 5, userInfo: [NSLocalizedDescriptionKey: "No cloud mirror backup snapshot found."])
        }
    }

    private static func sha256(_ input: String) -> String {
        guard let data = input.data(using: .utf8) else { return "" }
        return SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
    }
}
