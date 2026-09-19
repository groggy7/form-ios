import SwiftUI
import WebKit

public final class YouTubePlayerController: ObservableObject {
    @Published public var state: VideoPlaybackState
    public let video: YouTubeVideo
    public let autoplay: Bool

    weak var webView: WKWebView?
    private var timer: Timer?
    private var waitingTicks: Int = 0

    public init(video: YouTubeVideo, initialSeconds: Double = 0.0, autoplay: Bool = true) {
        self.video = video
        self.autoplay = autoplay
        self.state = VideoPlaybackState(currentSeconds: initialSeconds)
    }

    deinit {
        stopPolling()
    }

    public func play() {
        evaluate("window.formPlayer && window.formPlayer.play();")
    }

    public func pause() {
        evaluate("window.formPlayer && window.formPlayer.pause();")
    }

    public func seek(_ offset: Int) {
        evaluate("window.formPlayer && window.formPlayer.seek(\(offset));")
    }

    public func reload() {
        waitingTicks = 0
        state = VideoPlaybackState(currentSeconds: state.currentSeconds)
        webView?.reload()
    }

    func startPolling() {
        stopPolling()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.pollState()
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    private func pollState() {
        guard let webView = webView else { return }
        webView.evaluateJavaScript("window.formPlayer ? window.formPlayer.snapshot() : null") { [weak self] result, error in
            guard let self = self else { return }
            if let dict = result as? [String: Any] {
                let ready = dict["ready"] as? Bool ?? false
                let playerState = dict["playerState"] as? Int ?? -1
                let current = dict["currentSeconds"] as? Double ?? 0.0
                let duration = dict["durationSeconds"] as? Double ?? 0.0
                let err = dict["error"] as? String

                DispatchQueue.main.async {
                    self.state = VideoPlaybackState(
                        ready: ready,
                        playerState: playerState,
                        currentSeconds: current.isFinite ? max(0.0, current) : 0.0,
                        durationSeconds: duration.isFinite ? max(0.0, duration) : 0.0,
                        error: (err?.isEmpty == false && err != "null") ? err : nil
                    )
                }
            } else if error != nil {
                self.waitingTicks += 1
                if self.waitingTicks >= 40 && !self.state.ready {
                    DispatchQueue.main.async {
                        self.state.error = "network"
                    }
                }
            }
        }
    }

    private func evaluate(_ script: String) {
        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript(script, completionHandler: nil)
        }
    }
}

public struct YouTubeWebPlayerView: UIViewRepresentable {
    @ObservedObject var controller: YouTubePlayerController
    var onExternalLink: (String) -> Void

    public init(controller: YouTubePlayerController, onExternalLink: @escaping (String) -> Void) {
        self.controller = controller
        self.onExternalLink = onExternalLink
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.backgroundColor = .black
        webView.isOpaque = false
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false

        controller.webView = webView
        controller.startPolling()

        let origin = YouTubeEmbed.origin(bundleId: Bundle.main.bundleIdentifier ?? "com.perseverancesoftware.forcedrep")
        let html = YouTubeEmbed.page(
            video: controller.video,
            origin: origin,
            startSeconds: controller.state.currentSeconds,
            autoplay: controller.autoplay
        )

        webView.loadHTMLString(html, baseURL: URL(string: origin))

        return webView
    }

    public func updateUIView(_ uiView: WKWebView, context: Context) {
        controller.webView = uiView
    }

    public static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.evaluateJavaScript("window.formPlayer && window.formPlayer.pause();", completionHandler: nil)
        uiView.stopLoading()
        uiView.navigationDelegate = nil
    }

    public final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: YouTubeWebPlayerView

        init(_ parent: YouTubeWebPlayerView) {
            self.parent = parent
        }

        public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                parent.onExternalLink(url.absoluteString)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.controller.state.error = "network"
        }

        public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.controller.state.error = "network"
        }
    }
}
