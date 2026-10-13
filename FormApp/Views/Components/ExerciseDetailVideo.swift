import SwiftUI
import AVFoundation
import UIKit

enum ExerciseVideoCatalog {
    static let playbackSpeed: Float = 1.2

    struct Framing: Decodable {
        var left: CGFloat = 0
        var top: CGFloat = 0
        var width: CGFloat = 1
        var height: CGFloat = 1
        var aspectRatio: CGFloat { width * 16 / (height * 9) }

        func videoFrame(in size: CGSize) -> CGRect {
            CGRect(x: -left * size.width / width, y: -top * size.height / height,
                   width: size.width / width, height: size.height / height)
        }
    }
    static let framings: [String: Framing] = {
        guard let url = Bundle.main.url(forResource: "framing", withExtension: "json",
                                        subdirectory: "ExerciseVideos"),
              let data = try? Data(contentsOf: url),
              let values = try? JSONDecoder().decode([String: Framing].self, from: data)
        else { return [:] }
        return values
    }()

    static func framing(for exerciseId: String?) -> Framing {
        exerciseId.flatMap { framings[$0] } ?? Framing()
    }

    struct Entry: Decodable {
        let videoId: String
        let name: String
        let file: String
        let equipment: String
        let targetMuscles: [String]
        let secondaryMuscles: [String]
    }
    static let entries: [String: Entry] = {
        guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json",
                                        subdirectory: "ExerciseVideos"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([String: Entry].self, from: data)
        else { return [:] }
        return entries
    }()

    static func url(for exerciseId: String?) -> URL? {
        guard let id = exerciseId else { return nil }
        if let entry = entries[id] {
            return Bundle.main.url(forResource: entry.file, withExtension: nil,
                                   subdirectory: "ExerciseVideos")
                ?? Bundle.main.url(forResource: entry.file, withExtension: nil)
        }
        let normalized = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let entry = entries[normalized] {
            return Bundle.main.url(forResource: entry.file, withExtension: nil,
                                   subdirectory: "ExerciseVideos")
                ?? Bundle.main.url(forResource: entry.file, withExtension: nil)
        }
        let slug = normalized.replacingOccurrences(of: " ", with: "-").replacingOccurrences(of: "_", with: "-")
        if let entry = entries[slug] {
            return Bundle.main.url(forResource: entry.file, withExtension: nil,
                                   subdirectory: "ExerciseVideos")
                ?? Bundle.main.url(forResource: entry.file, withExtension: nil)
        }
        return nil
    }
}

struct ExerciseDetailVideo: View {
    let exerciseId: String?
    var drawBackground: Bool = true
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = true

    var body: some View {
        let framing = ExerciseVideoCatalog.framing(for: exerciseId)
        ZStack {
            if drawBackground { ExerciseMediaBackdrop() }
            if let url = ExerciseVideoCatalog.url(for: exerciseId) {
                LocalExerciseVideo(url: url, framing: framing,
                                   playing: visible && scenePhase == .active && !reduceMotion)
                    .id(url)
            } else {
                Color.clear
            }
        }
        .aspectRatio(framing.aspectRatio, contentMode: .fit)
        .accessibilityHidden(true)
        .onAppear { visible = true }
        .onDisappear { visible = false }
    }
}

private struct LocalExerciseVideo: UIViewRepresentable {
    let url: URL
    let framing: ExerciseVideoCatalog.Framing
    let playing: Bool

    func makeUIView(context: Context) -> ExercisePlayerView {
        ExercisePlayerView(url: url, framing: framing)
    }
    func updateUIView(_ view: ExercisePlayerView, context: Context) {
        view.setPlaying(playing)
    }
    static func dismantleUIView(_ view: ExercisePlayerView, coordinator: ()) {
        view.release()
    }
}

final class ExercisePlayerView: UIView {
    static let playbackSpeed: Float = ExerciseVideoCatalog.playbackSpeed

    private let playerLayer = AVPlayerLayer()
    private let framing: ExerciseVideoCatalog.Framing
    private let queue = AVQueuePlayer()
    private let posterView = UIImageView()
    private let startTime: CMTime
    private let capturesFrames: Bool
    private var looper: AVPlayerLooper?
    private var wantsPlayback = false
    private var itemStatusObserver: NSKeyValueObservation?
    private var queueObserver: NSKeyValueObservation?
    private var displayObserver: NSKeyValueObservation?
    private var videoOutput: AVPlayerItemVideoOutput?
    private weak var outputItem: AVPlayerItem?
    private var restorePending: Bool
    private var restoreStarted = false
    private var released = false

    var playbackTime: CMTime { queue.currentTime() }
    var playbackRate: Float { queue.rate }
    var renderedVideoFrame: CGRect { playerLayer.frame }
    var readyForDisplay: Bool { playerLayer.isReadyForDisplay }

    convenience init(url: URL, framing: ExerciseVideoCatalog.Framing = .init()) {
        self.init(asset: AVURLAsset(url: url), framing: framing)
    }

    init(asset: AVAsset, framing: ExerciseVideoCatalog.Framing = .init(),
         startTime: CMTime = .zero, poster: UIImage? = nil, capturesFrames: Bool = false) {
        self.framing = framing
        self.startTime = startTime.isNumeric && CMTimeCompare(startTime, .zero) >= 0 ? startTime : .zero
        self.restorePending = CMTimeCompare(self.startTime, .zero) > 0
        self.capturesFrames = capturesFrames
        super.init(frame: .zero)
        clipsToBounds = true
        backgroundColor = .clear
        isOpaque = false
        posterView.image = poster
        posterView.contentMode = .scaleToFill
        posterView.isOpaque = false
        posterView.backgroundColor = .clear
        addSubview(posterView)
        layer.addSublayer(playerLayer)
        playerLayer.videoGravity = .resizeAspect
        playerLayer.isOpaque = false
        playerLayer.opacity = poster == nil && !restorePending ? 1 : 0
        queue.isMuted = true
        queue.volume = 0
        queue.defaultRate = Self.playbackSpeed
        // No audio-session activation: exercise demos must not interrupt music.
        let templateItem = AVPlayerItem(asset: asset)
        looper = AVPlayerLooper(player: queue, templateItem: templateItem)
        playerLayer.player = queue

        queueObserver = queue.observe(\.currentItem, options: [.initial, .new]) { [weak self] _, _ in
            DispatchQueue.main.async {
                guard let self, !self.released else { return }
                self.itemStatusObserver = nil
                if let item = self.queue.currentItem {
                    self.attachVideoOutput(to: item)
                    self.observeItemStatus(item: item)
                }
            }
        }
        displayObserver = playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.updatePosterVisibility() }
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func observeItemStatus(item: AVPlayerItem) {
        itemStatusObserver?.invalidate()
        itemStatusObserver = item.observe(\.status, options: [.new, .initial]) { [weak self] observedItem, _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                guard !self.released, self.queue.currentItem === observedItem else { return }
                switch observedItem.status {
                case .readyToPlay:
                    self.restorePositionIfNeeded()
                    self.syncPlayback()
                case .failed:
                    #if DEBUG
                    print("[ExercisePlayerView] Video item failed to load: \(String(describing: observedItem.error))")
                    #endif
                default:
                    break
                }
            }
        }
    }

    private func attachVideoOutput(to item: AVPlayerItem) {
        if let output = videoOutput { outputItem?.remove(output) }
        videoOutput = nil
        outputItem = nil
        guard capturesFrames else { return }
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        item.add(output)
        videoOutput = output
        outputItem = item
    }

    private func restorePositionIfNeeded() {
        guard restorePending, !restoreStarted else { return }
        restoreStarted = true
        queue.pause()
        queue.seek(to: startTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            DispatchQueue.main.async {
                guard let self, !self.released, finished else { return }
                self.restorePending = false
                self.syncPlayback()
                self.updatePosterVisibility()
            }
        }
    }

    private func updatePosterVisibility() {
        guard !released, !restorePending, playerLayer.isReadyForDisplay else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.opacity = 1
        posterView.isHidden = true
        posterView.image = nil
        CATransaction.commit()
    }

    func captureVideoFrame() -> (image: UIImage, time: CMTime)? {
        guard !released, let output = videoOutput else { return nil }
        var time = CMTime.invalid
        guard let buffer = output.copyPixelBuffer(forItemTime: queue.currentTime(), itemTimeForDisplay: &time),
              let image = SessionVideoFrames.image(from: buffer, framing: framing) else { return nil }
        return (image, time)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }
        // Match Android's constant source viewport. No per-frame zoom or panning.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        posterView.frame = bounds
        playerLayer.frame = framing.videoFrame(in: bounds.size)
        CATransaction.commit()
    }

    func setPlaying(_ playing: Bool) {
        guard !released else { return }
        wantsPlayback = playing
        syncPlayback()
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        syncPlayback()
    }
    private func syncPlayback() {
        guard !released, !restorePending else { queue.pause(); return }
        if wantsPlayback && window != nil {
            queue.defaultRate = Self.playbackSpeed
            if queue.currentItem?.status == .readyToPlay {
                queue.rate = Self.playbackSpeed
            } else {
                queue.play()
            }
        } else {
            queue.pause()
        }
    }
    func release() {
        guard !released else { return }
        released = true
        itemStatusObserver?.invalidate()
        itemStatusObserver = nil
        queueObserver?.invalidate()
        queueObserver = nil
        displayObserver?.invalidate()
        displayObserver = nil
        if let output = videoOutput { outputItem?.remove(output) }
        videoOutput = nil
        outputItem = nil
        posterView.image = nil
        queue.pause()
        looper?.disableLooping()
        looper = nil
        queue.removeAllItems()
        playerLayer.player = nil
    }

    deinit {
        release()
    }
}
