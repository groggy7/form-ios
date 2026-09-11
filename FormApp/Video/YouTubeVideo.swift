import Foundation

public struct YouTubeVideo: Equatable {
    public let id: String
    public let isShort: Bool
    public let startSeconds: Int

    private static let idRegex = try! NSRegularExpression(pattern: "^[A-Za-z0-9_-]{11}$")
    private static let maxStartSeconds: Int = 7 * 24 * 60 * 60
    private static let hosts: Set<String> = [
        "youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com",
        "youtu.be", "www.youtu.be", "youtube-nocookie.com", "www.youtube-nocookie.com"
    ]

    public init?(id: String, isShort: Bool = false, startSeconds: Int = 0) {
        let range = NSRange(location: 0, length: id.utf16.count)
        guard Self.idRegex.firstMatch(in: id, options: [], range: range) != nil,
              startSeconds >= 0 && startSeconds <= Self.maxStartSeconds else {
            return nil
        }
        self.id = id
        self.isShort = isShort
        self.startSeconds = startSeconds
    }

    public var watchUrl: String {
        var base = "https://www.youtube.com/watch?v=\(id)"
        if startSeconds > 0 {
            base += "&t=\(startSeconds)s"
        }
        return base
    }

    public static func isYouTubeUrl(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.user == nil,
              let host = url.host?.lowercased(),
              hosts.contains(host),
              url.port == nil || url.port == 80 || url.port == 443 else {
            return false
        }
        return true
    }

    public static func normalizeInput(_ raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty || value.contains("://") ? value : "https://\(value)"
    }

    public static func isSupportedLink(_ raw: String) -> Bool {
        let url = normalizeInput(raw)
        return url.count <= 2_000 && parse(url) != nil
    }

    public static func validatedLinks(_ raw: [String]) -> [String]? {
        let urls = raw.map(normalizeInput).filter { !$0.isEmpty }
        guard urls.allSatisfy(isSupportedLink) else { return nil }
        var seenIds = Set<String>()
        return Array(urls.filter { url in
            let key = parse(url)?.id ?? url
            return seenIds.insert(key).inserted
        }.prefix(3))
    }

    public static func parse(_ urlString: String) -> YouTubeVideo? {
        guard isYouTubeUrl(urlString),
              let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let host = (url.host?.lowercased() ?? "").replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
        let parts = url.path.split(separator: "/").map(String.init)
        let queryMap = parameters(from: components.query)

        var videoId: String? = nil
        var isShort = false

        if host == "youtu.be" && parts.count == 1 {
            videoId = parts[0]
        } else if parts.count == 1 && parts[0] == "watch" {
            videoId = queryMap["v"]
        } else if parts.count == 2 && ["shorts", "embed", "live", "v"].contains(parts[0]) {
            videoId = parts[1]
            if parts[0] == "shorts" {
                isShort = true
            }
        }

        guard let id = videoId else { return nil }

        let fragmentMap = parameters(from: components.fragment)
        let rawStart = queryMap["t"] ?? queryMap["start"] ?? fragmentMap["t"]
        let start = parseStart(rawStart)

        return YouTubeVideo(id: id, isShort: isShort, startSeconds: start)
    }

    private static func parameters(from query: String?) -> [String: String] {
        guard let query = query, !query.isEmpty else { return [:] }
        var result: [String: String] = [:]
        for item in query.split(separator: "&") {
            let pair = item.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            if pair.count == 2 {
                let key = String(pair[0]).removingPercentEncoding ?? String(pair[0])
                let value = String(pair[1]).removingPercentEncoding ?? String(pair[1])
                result[key] = value
            }
        }
        return result
    }

    private static func parseStart(_ raw: String?) -> Int {
        guard let raw = raw, !raw.isEmpty else { return 0 }
        if let seconds = Int(raw) {
            return max(0, min(seconds, maxStartSeconds))
        }

        let pattern = "^(?:(\\d+)h)?(?:(\\d+)m)?(?:(\\d+)s)?$"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: raw, options: [], range: NSRange(location: 0, length: raw.utf16.count)) else {
            return 0
        }

        func extract(at index: Int) -> Int {
            guard index < match.numberOfRanges else { return 0 }
            let range = match.range(at: index)
            if range.location != NSNotFound, let r = Range(range, in: raw) {
                return min(Int(raw[r]) ?? 0, maxStartSeconds)
            }
            return 0
        }

        let h = extract(at: 1)
        let m = extract(at: 2)
        let s = extract(at: 3)
        let total = h * 3600 + m * 60 + s
        return max(0, min(total, maxStartSeconds))
    }
}

public struct VideoPlaybackState: Equatable {
    public var ready: Bool = false
    public var playerState: Int = -1
    public var currentSeconds: Double = 0.0
    public var durationSeconds: Double = 0.0
    public var error: String? = nil

    public init(
        ready: Bool = false,
        playerState: Int = -1,
        currentSeconds: Double = 0.0,
        durationSeconds: Double = 0.0,
        error: String? = nil
    ) {
        self.ready = ready
        self.playerState = playerState
        self.currentSeconds = currentSeconds
        self.durationSeconds = durationSeconds
        self.error = error
    }

    public var playing: Bool { playerState == 1 || playerState == 3 }
    public var ended: Bool { playerState == 0 && ready }
    public var canControl: Bool { ready && error == nil }
}

public func formatVideoTime(_ seconds: Double) -> String {
    let total = seconds.isFinite ? max(0, Int(seconds)) : 0
    if total >= 3600 {
        return String(format: "%d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
    } else {
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
