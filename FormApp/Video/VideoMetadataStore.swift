import Foundation

public struct VideoMetadata: Codable, Equatable {
    public let url: String
    public let title: String?
    public let authorName: String?
    public let isUnavailable: Bool

    public init(url: String, title: String? = nil, authorName: String? = nil, isUnavailable: Bool = false) {
        self.url = url
        self.title = title
        self.authorName = authorName
        self.isUnavailable = isUnavailable
    }
}

public final class VideoMetadataStore {
    public static let shared = VideoMetadataStore()

    private var memoryCache: [String: VideoMetadata] = [:]
    /// Saved URLs, oldest first. Linked videos change over time, so only the newest `maxEntries` are kept.
    private var savedOrder: [String] = []
    private let cacheKey = "video_metadata_cache"
    private static let queryValueAllowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
    private let lock = NSLock()
    private let defaults: UserDefaults
    private let maxEntries: Int

    init(defaults: UserDefaults = .standard, maxEntries: Int = 200) {
        self.defaults = defaults
        self.maxEntries = maxEntries
        loadPersistedCache()
    }

    public func getCached(for url: String) -> VideoMetadata? {
        lock.lock()
        defer { lock.unlock() }
        return memoryCache[url]
    }

    public func fetch(for url: String) async -> VideoMetadata {
        if let cached = getCached(for: url) {
            return cached
        }

        guard YouTubeVideo.isYouTubeUrl(url) else {
            return VideoMetadata(url: url)
        }

        // The link is one query value, so its own `&`, `=` and `+` are encoded too (as Android's URLEncoder does);
        // otherwise `watch?list=…&v=…` reaches oEmbed without its video and the link is marked unavailable.
        guard let encoded = url.addingPercentEncoding(withAllowedCharacters: Self.queryValueAllowed),
              let endpoint = URL(string: "https://www.youtube.com/oembed?url=\(encoded)&format=json") else {
            return VideoMetadata(url: url)
        }

        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 3.0
        request.setValue("ForcedRep/1.0 (iOS)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse {
                if [400, 401, 403, 404, 410].contains(http.statusCode) {
                    let unavailable = VideoMetadata(url: url, isUnavailable: true)
                    save(unavailable)
                    return unavailable
                }

                if (200...299).contains(http.statusCode) {
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        let title = (json["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                        let author = (json["author_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                        let metadata = VideoMetadata(url: url, title: title, authorName: author, isUnavailable: false)
                        save(metadata)
                        return metadata
                    }
                }
            }
        } catch {
            // Return fallback on network error
        }

        return VideoMetadata(url: url)
    }

    public func evict(for url: String) {
        lock.lock()
        memoryCache.removeValue(forKey: url)
        savedOrder.removeAll { $0 == url }
        persistCurrentCache()
        lock.unlock()
    }

    func save(_ metadata: VideoMetadata) {
        lock.lock()
        memoryCache[metadata.url] = metadata
        savedOrder.removeAll { $0 == metadata.url }
        savedOrder.append(metadata.url)
        trimToLimit()
        persistCurrentCache()
        lock.unlock()
    }

    private func trimToLimit() {
        while savedOrder.count > maxEntries {
            memoryCache.removeValue(forKey: savedOrder.removeFirst())
        }
    }

    private func loadPersistedCache() {
        guard let data = defaults.data(forKey: cacheKey) else { return }
        let decoder = JSONDecoder()
        if let entries = try? decoder.decode([VideoMetadata].self, from: data) {
            for entry in entries {
                memoryCache[entry.url] = entry
                savedOrder.removeAll { $0 == entry.url }
                savedOrder.append(entry.url)
            }
        } else if let legacy = try? decoder.decode([String: VideoMetadata].self, from: data) {
            // Earlier builds saved an unordered dictionary; its entries count as the oldest.
            memoryCache = legacy
            savedOrder = legacy.keys.sorted()
        }
        trimToLimit()
    }

    /// Saves the entries oldest first, so a relaunch keeps pruning in the same order.
    private func persistCurrentCache() {
        if let encoded = try? JSONEncoder().encode(savedOrder.compactMap { memoryCache[$0] }) {
            defaults.set(encoded, forKey: cacheKey)
        }
    }
}
