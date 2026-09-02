import Foundation
import AVFoundation
import UIKit

public final class FormAudioPlayer {
    public static let shared = FormAudioPlayer()
    private var players: [String: AVAudioPlayer] = [:]

    private init() {
        configureAudioSession()
    }

    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Audio session configuration error: \(error)")
        }
    }

    private func playSound(named name: String) {
        guard UserDefaults.standard.object(forKey: "sound_enabled") as? Bool ?? true else { return }

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

    public static func playRestCompleteSound() {
        shared.playSound(named: "form_rest_complete")
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
}
