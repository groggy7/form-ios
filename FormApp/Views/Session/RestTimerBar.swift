import SwiftUI

public struct RestTimerBar: View {
    let secondsRemaining: Int
    let totalSeconds: Int
    let exerciseName: String
    let isRunning: Bool
    var onTogglePause: () -> Void
    var onAddSeconds: (Int) -> Void
    var onSetDuration: (Int) -> Void
    var onSkip: () -> Void
    var isMuted: Bool
    var onToggleMute: () -> Void

    @State private var isExpanded: Bool = false

    public init(
        secondsRemaining: Int,
        totalSeconds: Int,
        exerciseName: String,
        isRunning: Bool,
        onTogglePause: @escaping () -> Void,
        onAddSeconds: @escaping (Int) -> Void,
        onSetDuration: @escaping (Int) -> Void,
        onSkip: @escaping () -> Void,
        isMuted: Bool,
        onToggleMute: @escaping () -> Void
    ) {
        self.secondsRemaining = secondsRemaining
        self.totalSeconds = totalSeconds
        self.exerciseName = exerciseName
        self.isRunning = isRunning
        self.onTogglePause = onTogglePause
        self.onAddSeconds = onAddSeconds
        self.onSetDuration = onSetDuration
        self.onSkip = onSkip
        self.isMuted = isMuted
        self.onToggleMute = onToggleMute
    }

    private var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return min(1.0, max(0.0, Double(secondsRemaining) / Double(totalSeconds)))
    }

    private var complete: Bool {
        secondsRemaining == 0
    }

    private var timeText: String {
        RestTimerUtils.formatSecondsToTime(secondsRemaining)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Top info row
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(LanguageManager.t("rest.title").uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.25)
                        .foregroundColor(AppColors.restTimerAccent)
                    Text(exerciseName)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(AppColors.text)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    Text(timeText)
                        .font(.system(size: 31, weight: .bold))
                        .monospacedDigit()
                        .foregroundColor(AppColors.restTimerAccent)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(AppColors.secondaryText)
                        .frame(width: 22, height: 22)
                }
            }
            .allowsHitTesting(false)

            RestTimerProgressBar(progress: progress)
                .allowsHitTesting(false)

            // Controls row
            HStack(spacing: 10) {
                Button(action: { onAddSeconds(-15) }) {
                    Text("-15s")
                        .font(.system(size: 13))
                        .foregroundColor(AppColors.muted)
                        .frame(width: 60, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(AppColors.restTimerControlSurface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(AppColors.restTimerControlBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Button(action: { onAddSeconds(30) }) {
                    Text("+30s")
                        .font(.system(size: 13))
                        .foregroundColor(AppColors.muted)
                        .frame(width: 60, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(AppColors.restTimerControlSurface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(AppColors.restTimerControlBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            Button(action: { isExpanded = true }) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [AppColors.restTimerSurfaceStart, AppColors.restTimerSurfaceEnd],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(AppColors.restTimerBorder, lineWidth: 1)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(LanguageManager.t("rest.title")), \(exerciseName), \(timeText)")
            .accessibilityHint(LanguageManager.t("rest.expand"))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .fullScreenCover(isPresented: $isExpanded) {
            RestTimerFullScreenModal(
                secondsRemaining: secondsRemaining,
                totalSeconds: totalSeconds,
                exerciseName: exerciseName,
                isRunning: isRunning,
                progress: progress,
                complete: complete,
                timeText: timeText,
                isMuted: isMuted,
                onDismiss: { isExpanded = false },
                onTogglePause: onTogglePause,
                onAddSeconds: onAddSeconds,
                onSetDuration: onSetDuration,
                onSkip: {
                    isExpanded = false
                    onSkip()
                },
                onToggleMute: onToggleMute
            )
        }
    }
}

private struct RestTimerProgressBar: View {
    let progress: Double

    @Environment(\.displayScale) private var displayScale

    private var clampedProgress: CGFloat {
        CGFloat(min(1.0, max(0.0, progress)))
    }

    var body: some View {
        GeometryReader { proxy in
            let barWidth = proxy.size.width * 0.68

            Canvas { context, size in
                let track = Path(
                    roundedRect: CGRect(origin: .zero, size: size),
                    cornerSize: CGSize(width: size.height / 2, height: size.height / 2)
                )
                let rawFillWidth = size.width * clampedProgress
                let fillWidth = (rawFillWidth * displayScale).rounded() / displayScale

                context.fill(track, with: .color(AppColors.restTimerTrack))

                if fillWidth > 0 {
                    context.clip(
                        to: Path(CGRect(x: 0, y: 0, width: fillWidth, height: size.height))
                    )
                    context.fill(track, with: .color(AppColors.restTimerAccent))
                }
            }
            .frame(width: barWidth, height: 4)
        }
        .frame(height: 4)
        .animation(.easeInOut(duration: 0.35), value: clampedProgress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(LanguageManager.t("rest.title"))
        .accessibilityValue("\(Int((Double(clampedProgress) * 100).rounded()))%")
    }
}

public struct RestTimerFullScreenModal: View {
    let secondsRemaining: Int
    let totalSeconds: Int
    let exerciseName: String
    let isRunning: Bool
    let progress: Double
    let complete: Bool
    let timeText: String
    let isMuted: Bool
    var onDismiss: () -> Void
    var onTogglePause: () -> Void
    var onAddSeconds: (Int) -> Void
    var onSetDuration: (Int) -> Void
    var onSkip: () -> Void
    var onToggleMute: () -> Void

    private var stateLabel: String {
        if complete {
            return LanguageManager.t("rest.finished")
        } else if isRunning {
            return LanguageManager.t("rest.resting")
        } else {
            return LanguageManager.t("rest.paused")
        }
    }

    public var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top Header Row
                HStack {
                    Button(action: onDismiss) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(AppColors.text)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)

                    Text(LanguageManager.t("rest.title"))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(AppColors.text)

                    Spacer()

                    Button(action: onToggleMute) {
                        Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 18))
                            .foregroundColor(isMuted ? AppColors.muted : AppColors.purple)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)

                ScrollView {
                    VStack(spacing: 24) {
                        // Exercise Name
                        Text(exerciseName)
                            .font(.system(size: 14))
                            .foregroundColor(AppColors.muted)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)

                        // Circular Gauge
                        ZStack {
                            // Background Track
                            Circle()
                                .stroke(AppColors.purpleBg, lineWidth: 8)

                            // Animated Progress Arc
                            Circle()
                                .trim(from: 0, to: CGFloat(progress))
                                .stroke(
                                    AngularGradient(
                                        gradient: Gradient(colors: [
                                            Color(hex: 0x7952D6),
                                            AppColors.purple,
                                            Color(hex: 0xE0BCFF),
                                            Color(hex: 0x7952D6)
                                        ]),
                                        center: .center,
                                        startAngle: .degrees(-90),
                                        endAngle: .degrees(270)
                                    ),
                                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                                )
                                .rotationEffect(.degrees(-90))
                                .animation(.easeInOut(duration: 0.35), value: progress)

                            // Inner labels
                            VStack(spacing: 8) {
                                Text(stateLabel)
                                    .font(.system(size: 12, weight: .bold))
                                    .tracking(1)
                                    .foregroundColor(complete ? AppColors.accent : AppColors.secondaryText)

                                Text(timeText)
                                    .font(.system(size: 58, weight: .medium, design: .monospaced))
                                    .foregroundColor(AppColors.text)

                                Text(LanguageManager.t("rest.target", ["time": RestTimerUtils.formatSecondsToTime(totalSeconds)]))
                                    .font(.system(size: 13))
                                    .foregroundColor(AppColors.muted)
                            }
                        }
                        .frame(maxWidth: 280, maxHeight: 280)
                        .aspectRatio(1, contentMode: .fit)
                        .padding(.vertical, 8)

                        // Presets Row
                        HStack(spacing: 6) {
                            ForEach(RestTimerUtils.restPresets, id: \.self) { duration in
                                let isSel = totalSeconds == duration
                                Button(action: { onSetDuration(duration) }) {
                                    Text("\(duration)s")
                                        .font(.system(size: 12, weight: isSel ? .bold : .medium))
                                        .foregroundColor(isSel ? AppColors.purple : AppColors.secondaryText)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 48)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .fill(isSel ? AppColors.purpleBg : AppColors.surface)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .stroke(isSel ? AppColors.purple : AppColors.border, lineWidth: 1)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 20)

                        // Controls Row (-15s, Toggle/Check, +15s)
                        HStack(spacing: 20) {
                            Button(action: { onAddSeconds(-15) }) {
                                Text("−15s")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(AppColors.text)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 50)
                                    .background(
                                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                                            .fill(AppColors.surface)
                                    )
                            }
                            .buttonStyle(.plain)

                            Button(action: {
                                if complete {
                                    onSkip()
                                } else {
                                    onTogglePause()
                                }
                            }) {
                                ZStack {
                                    Circle()
                                        .fill(AppColors.purpleBg)
                                        .frame(width: 72, height: 72)

                                    Image(systemName: complete ? "checkmark" : (isRunning ? "pause.fill" : "play.fill"))
                                        .font(.system(size: 30, weight: .semibold))
                                        .foregroundColor(AppColors.purple)
                                }
                            }
                            .buttonStyle(.plain)

                            Button(action: { onAddSeconds(15) }) {
                                Text("+15s")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(AppColors.text)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 50)
                                    .background(
                                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                                            .fill(AppColors.surface)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 20)

                        // Skip Rest Button
                        Button(action: onSkip) {
                            Text(LanguageManager.t("rest.skip"))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(AppColors.secondaryText)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(AppColors.border, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 20)
                        .padding(.top, 4)
                    }
                    .padding(.bottom, 24)
                }
            }
        }
    }
}
