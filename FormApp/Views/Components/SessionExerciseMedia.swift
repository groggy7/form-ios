import SwiftUI
import AVFoundation
import UIKit
import CoreImage

/// A reader owns only its immutable compressed clip; no network requests or asset copies on disk.
private final class SessionVideoSource: NSObject, AVAssetResourceLoaderDelegate {
    let queue = DispatchQueue(label: "com.form.session-video-source", qos: .userInitiated)
    private var data: Data?
    private let contentType: String

    init(data: Data, contentType: String) {
        self.data = data
        self.contentType = contentType
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        shouldWaitForLoadingOfRequestedResource request: AVAssetResourceLoadingRequest) -> Bool {
        guard let data else {
            request.finishLoading(with: NSError(domain: "SessionVideoSource", code: 1))
            return true
        }
        if let information = request.contentInformationRequest {
            information.contentType = contentType
            information.contentLength = Int64(data.count)
            information.isByteRangeAccessSupported = true
        }
        if let requested = request.dataRequest {
            let offset = max(requested.requestedOffset, requested.currentOffset)
            guard requested.requestedOffset >= 0, requested.requestedLength >= 0,
                  offset >= 0, offset <= Int64(data.count) else {
                request.finishLoading(with: NSError(domain: "SessionVideoSource", code: 2))
                return true
            }
            let start = Int(offset)
            let remaining = data.count - start
            let needed = max(0, Int64(requested.requestedLength) - (offset - requested.requestedOffset))
            let count = requested.requestsAllDataToEndOfResource ? remaining : min(Int(needed), remaining)
            if count > 0 { requested.respond(with: data.subdata(in: start..<(start + count))) }
        }
        request.finishLoading()
        return true
    }

    func close() { queue.async { self.data = nil } }
}

final class PreparedSessionVideo {
    let asset: AVURLAsset
    let bufferedBytes: Int
    private let source: SessionVideoSource?

    fileprivate init(url: URL, data: Data?) {
        bufferedBytes = data?.count ?? 0
        if let data {
            let reader = SessionVideoSource(data: data,
                contentType: url.pathExtension.lowercased() == "mov" ? AVFileType.mov.rawValue : AVFileType.mp4.rawValue)
            let memoryURL = URL(string: "forcedrep-session://\(UUID().uuidString)/video.\(url.pathExtension)")!
            asset = AVURLAsset(url: memoryURL)
            source = reader
            asset.resourceLoader.setDelegate(reader, queue: reader.queue)
        } else {
            asset = AVURLAsset(url: url)
            source = nil
        }
    }

    func close() {
        asset.cancelLoading()
        source?.close()
    }
}

/// Cache actual frames at the video's full-motion crop, never STEP1's tighter pose crop.
enum SessionVideoFrames {
    private static let context = CIContext(options: [.cacheIntermediates: false])

    static func cropped(_ image: CGImage, framing: ExerciseVideoCatalog.Framing) -> UIImage {
        let size = CGSize(width: 256, height: max(1, (256 / framing.aspectRatio).rounded()))
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            UIImage(cgImage: image).draw(in: framing.videoFrame(in: size))
        }
    }

    static func image(from buffer: CVPixelBuffer, framing: ExerciseVideoCatalog.Framing) -> UIImage? {
        let image = CIImage(cvPixelBuffer: buffer)
        guard let cgImage = context.createCGImage(image, from: image.extent) else { return nil }
        return cropped(cgImage, framing: framing)
    }
}

final class SessionExerciseVideo: ObservableObject {
    let exerciseId: String?
    let framing: ExerciseVideoCatalog.Framing
    @Published var clip: PreparedSessionVideo?
    @Published var frame: UIImage?
    var position: CMTime = .zero
    weak var liveView: ExercisePlayerView?
    weak var owner: SessionExerciseMedia?

    init(exerciseId: String?, owner: SessionExerciseMedia) {
        self.exerciseId = exerciseId
        self.framing = ExerciseVideoCatalog.framing(for: exerciseId)
        self.owner = owner
    }

    func capture(_ view: ExercisePlayerView) {
        guard owner?.closed == false else { return }
        let time = view.playbackTime
        if time.isValid && time.isNumeric { position = time }
        if let snapshot = view.captureVideoFrame() {
            frame = snapshot.image
            if snapshot.time.isValid && snapshot.time.isNumeric { position = snapshot.time }
        }
    }

    func freeze() {
        guard let view = liveView else { return }
        view.setPlaying(false)
        capture(view)
    }

    func detach(_ view: ExercisePlayerView) {
        if liveView === view { liveView = nil }
        guard owner?.closed == false else { return }
        let time = view.playbackTime
        let snapshot = view.captureVideoFrame()
        if time.isNumeric { position = time }
        if let snapshot, snapshot.time.isNumeric { position = snapshot.time }
        // UIKit dismantling occurs during SwiftUI updates. Publish a recovered
        // frame afterward; user handoffs already capture it before changing state.
        if let snapshot {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.owner?.closed == false, self.liveView == nil else { return }
                self.frame = snapshot.image
            }
        }
    }

    func clear() {
        liveView?.release()
        liveView = nil
        clip = nil
        frame = nil
        position = .zero
    }
}

/// Owned by the exercise screen; offscreen rows share clips but retain independent playback positions.
final class SessionExerciseMedia: ObservableObject {
    struct Row: Hashable { let id: String; let exerciseId: String? }
    struct Key: Hashable { let workoutId: String; let rows: [Row]; let summary: Bool }

    @Published private(set) var tiles: [String: SessionExerciseVideo] = [:]
    private(set) var closed = true
    private var generation = UUID()
    private var clips: [String: PreparedSessionVideo] = [:]
    private var preparingClip: PreparedSessionVideo?
    private var generator: AVAssetImageGenerator?
    private static let loadQueue = DispatchQueue(label: "com.form.session-video-preload", qos: .userInitiated)

    @MainActor
    func prepare(key: Key, initialRowId: String?) async {
        close()
        guard !key.summary else { return }
        closed = false
        let token = generation
        tiles = Dictionary(uniqueKeysWithValues: key.rows.map {
            ($0.id, SessionExerciseVideo(exerciseId: $0.exerciseId, owner: self))
        })
        let first = initialRowId.flatMap { tiles[$0]?.exerciseId }
        var ids: [String] = []
        for id in [first].compactMap({ $0 }) + key.rows.compactMap(\.exerciseId) where !ids.contains(id) {
            ids.append(id)
        }
        var remainingBudget = 32 * 1024 * 1024
        for id in ids {
            guard !Task.isCancelled, token == generation, !closed else { return }
            guard let url = ExerciseVideoCatalog.url(for: id) else { continue }
            let clip = await Self.load(url: url, budget: remainingBudget)
            guard !Task.isCancelled, token == generation, !closed else { clip.close(); return }
            preparingClip = clip
            let framing = ExerciseVideoCatalog.framing(for: id)
            let decoder = AVAssetImageGenerator(asset: clip.asset)
            decoder.appliesPreferredTrackTransform = true
            decoder.maximumSize = CGSize(width: 960, height: 540)
            decoder.requestedTimeToleranceBefore = .zero
            decoder.requestedTimeToleranceAfter = .zero
            generator = decoder
            var frame: UIImage?
            do {
                let result = try await withTaskCancellationHandler {
                    try await decoder.image(at: CMTime(value: 1, timescale: 1000))
                } onCancel: { decoder.cancelAllCGImageGeneration() }
                frame = SessionVideoFrames.cropped(result.image, framing: framing)
            } catch {
                #if DEBUG
                if !Task.isCancelled { print("[SessionExerciseMedia] Cannot prepare video frame: \(id): \(error)") }
                #endif
            }
            guard !Task.isCancelled, token == generation, !closed else { clip.close(); return }
            generator = nil
            preparingClip = nil
            remainingBudget -= clip.bufferedBytes
            clips[id] = clip
            for tile in tiles.values where tile.exerciseId == id {
                tile.frame = frame
                tile.clip = clip
            }
        }
    }

    private static func load(url: URL, budget: Int) async -> PreparedSessionVideo {
        await withCheckedContinuation { continuation in
            loadQueue.async {
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
                let data = size.map { $0 <= budget } == true ? (try? Data(contentsOf: url)) : nil
                continuation.resume(returning: PreparedSessionVideo(url: url, data: data))
            }
        }
    }

    func freezeActive() { tiles.values.forEach { $0.freeze() } }

    func close() {
        closed = true
        generation = UUID()
        generator?.cancelAllCGImageGeneration()
        generator = nil
        tiles.values.forEach { $0.clear() }
        tiles = [:]
        clips.values.forEach { $0.close() }
        clips = [:]
        preparingClip?.close()
        preparingClip = nil
    }
}

struct SessionMovementIcon: View {
    @ObservedObject var media: SessionExerciseMedia
    let rowId: String
    let active: Bool

    var body: some View {
        ZStack {
            if let video = media.tiles[rowId] { SessionVideoForeground(video: video, active: active) }
        }
        .frame(width: 72, height: 72)
        .background(ExerciseMediaBackdrop())
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(AppColors.border.opacity(0.4), lineWidth: 1))
        .accessibilityHidden(true)
    }
}

struct SessionExerciseDetailVideo: View {
    @ObservedObject var media: SessionExerciseMedia
    let rowId: String
    let exerciseId: String?

    var body: some View {
        ZStack {
            ExerciseMediaBackdrop()
            if let video = media.tiles[rowId] { SessionVideoForeground(video: video, active: true) }
        }
        .aspectRatio(ExerciseVideoCatalog.framing(for: exerciseId).aspectRatio, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

private struct SessionVideoForeground: View {
    @ObservedObject var video: SessionExerciseVideo
    let active: Bool
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if active && !reduceMotion, let clip = video.clip {
                SessionLocalExerciseVideo(video: video, clip: clip, playing: scenePhase == .active)
                    .id(ObjectIdentifier(clip))
                    .accessibilityIdentifier("movement-icon-video")
            } else if let frame = video.frame {
                Image(uiImage: frame).resizable()
            } else { Color.clear }
        }
        .aspectRatio(video.framing.aspectRatio, contentMode: .fit)
    }
}

private struct SessionLocalExerciseVideo: UIViewRepresentable {
    @ObservedObject var video: SessionExerciseVideo
    let clip: PreparedSessionVideo
    let playing: Bool

    func makeUIView(context: Context) -> ExercisePlayerView {
        let view = ExercisePlayerView(asset: clip.asset, framing: video.framing,
                                      startTime: video.position, poster: video.frame, capturesFrames: true)
        video.liveView = view
        return view
    }

    func updateUIView(_ view: ExercisePlayerView, context: Context) { view.setPlaying(playing) }

    func makeCoordinator() -> SessionExerciseVideo { video }

    static func dismantleUIView(_ view: ExercisePlayerView, coordinator: SessionExerciseVideo) {
        coordinator.detach(view)
        view.release()
    }
}
