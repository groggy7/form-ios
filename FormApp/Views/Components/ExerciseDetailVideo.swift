import SwiftUI
import AVFoundation
import UIKit

enum ExerciseVideoCatalog {
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
        Group {
            if let url = ExerciseVideoCatalog.url(for: exerciseId) {
                LocalExerciseVideo(url: url, playing: visible && scenePhase == .active && !reduceMotion)
                    .id(url)
            } else {
                Color.clear
            }
        }
        .accessibilityHidden(true)
        .onAppear { visible = true }
        .onDisappear { visible = false }
    }
}

private struct LocalExerciseVideo: UIViewRepresentable {
    let url: URL
    let playing: Bool

    func makeUIView(context: Context) -> ExercisePlayerView {
        ExercisePlayerView(url: url)
    }
    func updateUIView(_ view: ExercisePlayerView, context: Context) {
        view.setPlaying(playing)
    }
    static func dismantleUIView(_ view: ExercisePlayerView, coordinator: ()) {
        view.release()
    }
}

final class ExercisePlayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    private let queue = AVQueuePlayer()
    private var looper: AVPlayerLooper?
    private var wantsPlayback = false
    var playbackTime: CMTime { queue.currentTime() }

    init(url: URL) {
        super.init(frame: .zero)
        backgroundColor = UIColor(red: 22/255, green: 32/255, blue: 42/255, alpha: 1)
        playerLayer.videoGravity = .resizeAspect
        queue.isMuted = true
        queue.volume = 0
        // No audio-session activation: exercise demos must not interrupt music.
        looper = AVPlayerLooper(player: queue, templateItem: AVPlayerItem(url: url))
        playerLayer.player = queue
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setPlaying(_ playing: Bool) {
        wantsPlayback = playing
        syncPlayback()
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        syncPlayback()
    }
    private func syncPlayback() {
        if wantsPlayback && window != nil { queue.play() } else { queue.pause() }
    }
    func release() {
        queue.pause()
        looper?.disableLooping()
        looper = nil
        queue.removeAllItems()
        playerLayer.player = nil
    }
}
