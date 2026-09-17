import Foundation
import AVFoundation
import UIKit

public final class FormAudioPlayer {
    public static let shared = FormAudioPlayer()
    private var players: [String: AVAudioPlayer] = [:]

    private init() {
        configureAudioSession()
        preloadSounds()
    }

    private func configureAudioSession() {
        guard NSClassFromString("XCTestCase") == nil else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Audio session configuration error: \(error)")
        }
    }

    private func preloadSounds() {
        guard NSClassFromString("XCTestCase") == nil else { return }
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

        try? AVAudioSession.sharedInstance().setActive(true)

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
