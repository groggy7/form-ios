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
    private let cacheKey = "video_metadata_cache"
    private let lock = NSLock()

    private init() {
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

        guard let encoded = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let endpoint = URL(string: "https://www.youtube.com/oembed?url=\(encoded)&format=json") else {
            return VideoMetadata(url: url)
        }

        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 3.0
        request.setValue("FormGym/1.0 (iOS)", forHTTPHeaderField: "User-Agent")

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
        persistCurrentCache()
        lock.unlock()
    }

    private func save(_ metadata: VideoMetadata) {
        lock.lock()
        memoryCache[metadata.url] = metadata
        persistCurrentCache()
        lock.unlock()
    }

    private func loadPersistedCache() {
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let decoded = try? JSONDecoder().decode([String: VideoMetadata].self, from: data) {
            memoryCache = decoded
        }
    }

    private func persistCurrentCache() {
        if let encoded = try? JSONEncoder().encode(memoryCache) {
            UserDefaults.standard.set(encoded, forKey: cacheKey)
        }
    }
}
