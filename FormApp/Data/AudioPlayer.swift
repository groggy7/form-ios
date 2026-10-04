import Foundation
import AVFoundation
import UIKit

public final class FormAudioPlayer {
    public static let shared = FormAudioPlayer()
    // Preparing or playing an AVAudioPlayer can implicitly activate the audio session.
    // Keep session setup and all player access ordered off the main thread.
    private let audioQueue = DispatchQueue(label: "com.perseverancesoftware.forcedrep.audio", qos: .userInitiated)
    private var players: [String: AVAudioPlayer] = [:]

    private init() {
        guard NSClassFromString("XCTestCase") == nil else { return }
        audioQueue.async {
            self.configureAudioSession()
            self.preloadSounds()
        }
    }

    private func configureAudioSession() {
        dispatchPrecondition(condition: .onQueue(audioQueue))
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("Audio session configuration error: \(error)")
        }
    }

    private func preloadSounds() {
        dispatchPrecondition(condition: .onQueue(audioQueue))
        for name in ["form_workout_start", "form_set_complete", "form_set_undo", "form_workout_complete", "form_rest_complete"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "wav"),
                  let player = try? AVAudioPlayer(contentsOf: url) else { continue }
            player.prepareToPlay()
            players[name] = player
        }
    }

    private func playSound(named name: String) {
        guard NSClassFromString("XCTestCase") == nil else { return }
        guard UserDefaults.standard.object(forKey: "sound_enabled") as? Bool ?? true else { return }

        audioQueue.async {
            self.playSoundOnAudioQueue(named: name)
        }
    }

    private func playSoundOnAudioQueue(named name: String) {
        dispatchPrecondition(condition: .onQueue(audioQueue))
        if let existing = players[name] {
            existing.currentTime = 0
            existing.play()
            return
        }

        guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else {
            print("Audio file not found: \(name).wav")
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            player.play()
            players[name] = player
        } catch {
            print("Failed to play sound \(name): \(error)")
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
