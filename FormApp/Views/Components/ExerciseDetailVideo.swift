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
        guard let id = exerciseId, let entry = entries[id] else { return nil }
        return Bundle.main.url(forResource: entry.file, withExtension: nil,
                               subdirectory: "ExerciseVideos")
    }
}

struct ExerciseDetailVideo: View {
    let exerciseId: String?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false

    var body: some View {
        let framing = ExerciseVideoCatalog.framing(for: exerciseId)
        Group {
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
    private var looper: AVPlayerLooper?
    private var wantsPlayback = false
    var playbackTime: CMTime { queue.currentTime() }
    var playbackRate: Float { queue.rate }
    var renderedVideoFrame: CGRect { playerLayer.frame }

    init(url: URL, framing: ExerciseVideoCatalog.Framing = .init()) {
        self.framing = framing
        super.init(frame: .zero)
        clipsToBounds = true
        backgroundColor = UIColor(red: 22/255, green: 32/255, blue: 42/255, alpha: 1)
        layer.addSublayer(playerLayer)
        playerLayer.videoGravity = .resizeAspect
        queue.isMuted = true
        queue.volume = 0
        queue.defaultRate = Self.playbackSpeed
        // No audio-session activation: exercise demos must not interrupt music.
        looper = AVPlayerLooper(player: queue, templateItem: AVPlayerItem(url: url))
        playerLayer.player = queue
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Match Android's constant source viewport. No per-frame zoom or panning.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = framing.videoFrame(in: bounds.size)
        CATransaction.commit()
    }

    func setPlaying(_ playing: Bool) {
        wantsPlayback = playing
        syncPlayback()
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        syncPlayback()
    }
    private func syncPlayback() {
        if wantsPlayback && window != nil {
            queue.rate = Self.playbackSpeed
        } else {
            queue.pause()
        }
    }
    func release() {
        queue.pause()
        looper?.disableLooping()
        looper = nil
        queue.removeAllItems()
        playerLayer.player = nil
    }
}
