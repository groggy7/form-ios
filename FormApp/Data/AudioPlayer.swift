import Foundation
import AVFoundation
import UIKit

protocol EffectAudioPlayer: AnyObject {
    var isPlaying: Bool { get }
    func restart() -> Bool
    func stop()
}

/// Called only on the audio queue in production; the injected boundaries let tests
/// exercise interruptions, overlapping effects and failures without activating audio.
final class AudioPlaybackController {
    private let activate: () throws -> Void
    private let deactivate: () throws -> Void
    private let makePlayer: (String) throws -> EffectAudioPlayer?
    private var players: [String: EffectAudioPlayer] = [:]
    private var active = false
    private var interrupted = false

    init(activate: @escaping () throws -> Void, deactivate: @escaping () throws -> Void,
         makePlayer: @escaping (String) throws -> EffectAudioPlayer?) {
        self.activate = activate
        self.deactivate = deactivate
        self.makePlayer = makePlayer
    }

    func play(_ name: String, enabled: Bool) {
        guard enabled, !interrupted else { return }
        do {
            guard let player = try players[name] ?? makePlayer(name) else { return }
            players[name] = player
            if !active { try activate(); active = true }
            if !player.restart() { player.stop(); releaseIfIdle() }
        } catch {
            releaseIfIdle()
            print("Audio effect could not be played: \(error)")
        }
    }

    func releaseIfIdle() {
        guard active, !players.values.contains(where: { $0.isPlaying }) else { return }
        do { try deactivate(); active = false }
        catch { print("Audio session could not be released: \(error)") }
    }

    func interruptionBegan() {
        interrupted = true
        players.values.forEach { $0.stop() }
        // The system has already deactivated the interrupted session.
        active = false
    }

    func interruptionEnded() { interrupted = false }

    func mediaServicesReset() {
        players.values.forEach { $0.stop() }
        players.removeAll()
        active = false
        interrupted = false
    }
}

final class EffectPlayer: NSObject, EffectAudioPlayer, AVAudioPlayerDelegate {
    private let player: AVAudioPlayer
    private let finished: () -> Void
    private let audioQueue: DispatchQueue
    var isPlaying: Bool { player.isPlaying }

    init(url: URL, audioQueue: DispatchQueue, finished: @escaping () -> Void) throws {
        self.player = try AVAudioPlayer(contentsOf: url)
        self.finished = finished
        self.audioQueue = audioQueue
        super.init()
        player.delegate = self
    }

    func restart() -> Bool { player.currentTime = 0; return player.play() }
    func stop() { player.stop() }
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        audioQueue.async { self.finished() }
    }
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        audioQueue.async { self.player.stop(); self.finished() }
    }
}

public final class FormAudioPlayer {
    public static let shared = FormAudioPlayer()
    private let audioQueue = DispatchQueue(label: "com.perseverancesoftware.forcedrep.audio", qos: .userInitiated)
    private var observers: [NSObjectProtocol] = []
    private lazy var playback: AudioPlaybackController = AudioPlaybackController(activate: {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)
    }, deactivate: {
        try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }, makePlayer: { [weak self] name in
        guard let self, let url = Bundle.main.url(forResource: name, withExtension: "wav") else { return nil }
        return try EffectPlayer(url: url, audioQueue: self.audioQueue) { [weak self] in
            self?.playback.releaseIfIdle()
        }
    })

    private init() {
        guard NSClassFromString("XCTestCase") == nil else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: nil) { [weak self] notice in
            guard let raw = notice.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            self?.audioQueue.async { [weak self] in
                if type == .began { self?.playback.interruptionBegan() }
                else { self?.playback.interruptionEnded() }
            }
        })
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil) { [weak self] _ in
            self?.audioQueue.async { [weak self] in self?.playback.releaseIfIdle() }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: nil) { [weak self] _ in
            self?.audioQueue.async { [weak self] in self?.playback.mediaServicesReset() }
        })
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    private func playSound(named name: String) {
        guard NSClassFromString("XCTestCase") == nil else { return }
        audioQueue.async {
            let enabled = UserDefaults.standard.object(forKey: "sound_enabled") as? Bool ?? true
            self.playback.play(name, enabled: enabled)
        }
    }

    public static func playWorkoutStartSound() {
        shared.playSound(named: "form_workout_start")
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }

    public static func playSetCompleteSound() {
        shared.playSound(named: "form_set_complete")
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    public static func playSetUndoSound() {
        shared.playSound(named: "form_set_undo")
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    public static func playWorkoutCompleteSound() {
        shared.playSound(named: "form_workout_complete")
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    public static func playRestCompleteSound() {
        shared.playSound(named: "form_rest_complete")
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
}
