import SwiftUI

public struct OnboardingView: View {
    @ObservedObject var store: AppStore
    @ObservedObject var langManager = LanguageManager.shared

    @State private var step: Int = 0
    @State private var preferences = OnboardingPreferences()

    private let totalQuestions = 5

    public init(store: AppStore) {
        self.store = store
    }

    public var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header: Back, Progress bar, Skip
                HStack(spacing: 12) {
                    if step > 0 && step < totalQuestions {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                step -= 1
                            }
                        }) {
                            Image(systemName: "arrow.left")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(AppColors.text)
                                .frame(width: 36, height: 36)
                        }
                    } else {
                        Spacer().frame(width: 36, height: 36)
                    }

                    if step < totalQuestions {
                        HStack(spacing: 4) {
                            ForEach(0..<totalQuestions, id: \.self) { index in
                                Capsule()
                                    .fill(index <= step ? AppColors.accent : AppColors.border)
                                    .frame(height: 4)
                            }
                        }
                    } else {
                        Spacer()
                    }

                    if step < totalQuestions {
                        Button(action: {
                            store.setOnboardingCompleted(true)
                        }) {
                            Text(LanguageManager.t("onboarding.skip"))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(AppColors.muted)
                                .padding(.horizontal, 8)
                                .frame(height: 36)
                        }
                    } else {
                        Spacer().frame(width: 36, height: 36)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                // Step Content
                Group {
                    switch step {
                    case 0:
                        goalStep
                    case 1:
                        experienceStep
                    case 2:
                        equipmentStep
                    case 3:
                        frequencyStep
                    case 4:
                        scheduleStep
                    default:
                        recommendationStep
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Bottom Continue Action for question steps
                if step < totalQuestions {
                    VStack(spacing: 0) {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                step += 1
                            }
                        }) {
                            Text(LanguageManager.t("onboarding.next"))
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(AppColors.background)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(AppColors.accent)
                                .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
        }
    }

    // MARK: - Step 0: Goal
    private var goalStep: some View {
        StepContainer(
            title: LanguageManager.t("onboarding.goal.title"),
            subtitle: LanguageManager.t("onboarding.goal.subtitle")
        ) {
            OptionCard(
                title: LanguageManager.t("onboarding.goal.hypertrophy.title"),
                description: LanguageManager.t("onboarding.goal.hypertrophy.desc"),
                isSelected: preferences.goal == .hypertrophy,
                onClick: { preferences.goal = .hypertrophy }
            )
            OptionCard(
                title: LanguageManager.t("onboarding.goal.strength.title"),
                description: LanguageManager.t("onboarding.goal.strength.desc"),
                isSelected: preferences.goal == .strength,
                onClick: { preferences.goal = .strength }
            )
            OptionCard(
                title: LanguageManager.t("onboarding.goal.athletic.title"),
                description: LanguageManager.t("onboarding.goal.athletic.desc"),
                isSelected: preferences.goal == .athletic,
                onClick: { preferences.goal = .athletic }
            )
            OptionCard(
                title: LanguageManager.t("onboarding.goal.foundation.title"),
                description: LanguageManager.t("onboarding.goal.foundation.desc"),
                isSelected: preferences.goal == .foundation,
                onClick: { preferences.goal = .foundation }
            )
        }
    }

    // MARK: - Step 1: Experience
    private var experienceStep: some View {
        StepContainer(
            title: LanguageManager.t("onboarding.experience.title"),
            subtitle: LanguageManager.t("onboarding.experience.subtitle")
        ) {
            OptionCard(
                title: LanguageManager.t("onboarding.experience.beginner.title"),
                description: LanguageManager.t("onboarding.experience.beginner.desc"),
                isSelected: preferences.experience == .beginner,
                onClick: { preferences.experience = .beginner }
            )
            OptionCard(
                title: LanguageManager.t("onboarding.experience.intermediate.title"),
                description: LanguageManager.t("onboarding.experience.intermediate.desc"),
                isSelected: preferences.experience == .intermediate,
                onClick: { preferences.experience = .intermediate }
            )
            OptionCard(
                title: LanguageManager.t("onboarding.experience.advanced.title"),
                description: LanguageManager.t("onboarding.experience.advanced.desc"),
                isSelected: preferences.experience == .advanced,
                onClick: { preferences.experience = .advanced }
            )
        }
    }

    // MARK: - Step 2: Equipment
    private var equipmentStep: some View {
        StepContainer(
            title: LanguageManager.t("onboarding.equipment.title"),
            subtitle: LanguageManager.t("onboarding.equipment.subtitle")
        ) {
            OptionCard(
                title: LanguageManager.t("onboarding.equipment.commercialGym.title"),
                description: LanguageManager.t("onboarding.equipment.commercialGym.desc"),
                isSelected: preferences.equipment == .commercialGym,
                onClick: { preferences.equipment = .commercialGym }
            )
            OptionCard(
                title: LanguageManager.t("onboarding.equipment.machinesOnly.title"),
                description: LanguageManager.t("onboarding.equipment.machinesOnly.desc"),
                isSelected: preferences.equipment == .machinesOnly,
                onClick: { preferences.equipment = .machinesOnly }
            )
            OptionCard(
                title: LanguageManager.t("onboarding.equipment.dumbbellsHome.title"),
                description: LanguageManager.t("onboarding.equipment.dumbbellsHome.desc"),
                isSelected: preferences.equipment == .dumbbellsHome,
                onClick: { preferences.equipment = .dumbbellsHome }
            )
        }
    }

    // MARK: - Step 3: Frequency
    private var frequencyStep: some View {
        StepContainer(
            title: LanguageManager.t("onboarding.frequency.title"),
            subtitle: LanguageManager.t("onboarding.frequency.subtitle")
        ) {
            OptionCard(
                title: LanguageManager.t("onboarding.frequency.days3.title"),
                description: LanguageManager.t("onboarding.frequency.days3.desc"),
                isSelected: preferences.frequency == .days3,
                onClick: {
                    preferences.frequency = .days3
                    preferences.selectedDays = []
                }
            )
            OptionCard(
                title: LanguageManager.t("onboarding.frequency.days4.title"),
                description: LanguageManager.t("onboarding.frequency.days4.desc"),
                isSelected: preferences.frequency == .days4,
                onClick: {
                    preferences.frequency = .days4
                    preferences.selectedDays = []
                }
            )
            OptionCard(
                title: LanguageManager.t("onboarding.frequency.days5.title"),
                description: LanguageManager.t("onboarding.frequency.days5.desc"),
                isSelected: preferences.frequency == .days5,
                onClick: {
                    preferences.frequency = .days5
                    preferences.selectedDays = []
                }
            )
            OptionCard(
                title: LanguageManager.t("onboarding.frequency.days6.title"),
                description: LanguageManager.t("onboarding.frequency.days6.desc"),
                isSelected: preferences.frequency == .days6,
                onClick: {
                    preferences.frequency = .days6
                    preferences.selectedDays = []
                }
            )
        }
    }

    // MARK: - Step 4: Schedule Days
    private var scheduleStep: some View {
        let currentDays = preferences.selectedDays.isEmpty ? preferences.frequency.defaultWeekdays : preferences.selectedDays
        let isTr = langManager.currentLanguage == "tr"
        let dayLabels = isTr ? ["PZT", "SAL", "ÇAR", "PER", "CUM", "CTS", "PAZ"] : ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]
        let dayFullNames = LanguageManager.workoutDays

        return StepContainer(
            title: LanguageManager.t("onboarding.schedule.title"),
            subtitle: LanguageManager.t("onboarding.schedule.subtitle", ["count": "\(preferences.frequency.rawValue)"])
        ) {
            HStack {
                Text(LanguageManager.t(
                    "onboarding.schedule.daysSelected",
                    ["selected": "\(currentDays.count)", "total": "\(preferences.frequency.rawValue)"]
                ))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(currentDays.count == preferences.frequency.rawValue ? AppColors.accent : AppColors.secondaryText)

                Spacer()
            }
            .padding(.bottom, 6)

            VStack(spacing: 8) {
                ForEach(1...7, id: \.self) { dayIndex in
                    let isSelected = currentDays.contains(dayIndex)
                    let label = dayLabels[dayIndex - 1]
                    let fullName = dayFullNames[dayIndex - 1]

                    Button(action: {
                        var current = currentDays
                        if current.contains(dayIndex) {
                            if current.count > 1 {
                                current.removeAll { $0 == dayIndex }
                            }
                        } else {
                            current.append(dayIndex)
                        }
                        preferences.selectedDays = current.sorted()
                    }) {
                        HStack {
                            HStack(spacing: 12) {
                                Text(label)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(isSelected ? AppColors.accent : AppColors.muted)
                                    .frame(width: 32, height: 32)
                                    .background(isSelected ? AppColors.accent.opacity(0.2) : AppColors.surfaceRaised)
                                    .cornerRadius(6)

                                Text(fullName)
                                    .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                                    .foregroundColor(isSelected ? AppColors.text : AppColors.secondaryText)
                            }

                            Spacer()

                            // Checkmark circle
                            ZStack {
                                Circle()
                                    .stroke(isSelected ? AppColors.accent : AppColors.border, lineWidth: 1.5)
                                    .background(Circle().fill(isSelected ? AppColors.accent : Color.clear))
                                    .frame(width: 22, height: 22)

                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(AppColors.background)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(isSelected ? AppColors.positiveBg : AppColors.surface)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isSelected ? AppColors.accent : AppColors.border, lineWidth: isSelected ? 1.5 : 1)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }

    // MARK: - Step 5: Recommendation
    private var recommendationStep: some View {
        let recommendation = OnboardingRecommender.recommendProgram(
            preferences: preferences,
            availablePrograms: store.state.programs
        )

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Badge
                Text(LanguageManager.t("onboarding.rec.badge"))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(AppColors.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppColors.positiveBg)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(AppColors.accent.opacity(0.3), lineWidth: 1)
                    )

                // Title
                Text(recommendation.program.displayName)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(AppColors.text)

                // Reason Card
                Text(LanguageManager.t(recommendation.explanationKey))
                    .font(.system(size: 14))
                    .foregroundColor(AppColors.secondaryText)
                    .lineSpacing(4)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppColors.surface)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(AppColors.border, lineWidth: 1)
                    )

                // Workouts in this split
                Text(LanguageManager.t("onboarding.rec.workoutsTitle"))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(AppColors.text)
                    .padding(.top, 8)

                VStack(spacing: 8) {
                    ForEach(recommendation.program.workouts) { workout in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(workout.displayTitle(programId: recommendation.program.id))
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(AppColors.text)

                                let focus = workout.displayFocus(programId: recommendation.program.id)
                                if !focus.isEmpty {
                                    Text(focus)
                                        .font(.system(size: 12))
                                        .foregroundColor(AppColors.secondaryText)
                                }
                            }

                            Spacer()

                            Text("\(workout.exercises.count) ex")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(AppColors.muted)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(AppColors.surfaceRaised)
                                .cornerRadius(6)
                        }
                        .padding(14)
                        .background(AppColors.surface)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(AppColors.border, lineWidth: 1)
                        )
                    }
                }

                // CTA Buttons
                VStack(spacing: 10) {
                    Button(action: {
                        store.completeOnboarding(preferences: preferences, targetProgramId: recommendation.targetProgramId)
                    }) {
                        Text(LanguageManager.t("onboarding.rec.startCta"))
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(AppColors.background)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(AppColors.accent)
                            .cornerRadius(12)
                    }

                    Button(action: {
                        store.completeOnboarding(preferences: preferences, targetProgramId: recommendation.targetProgramId)
                        store.navigate(to: .today)
                    }) {
                        Text(LanguageManager.t("onboarding.rec.browseAll"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(AppColors.secondaryText)
                            .padding(.vertical, 8)
                    }
                }
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }
}

// MARK: - Supporting Views

private struct StepContainer<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(AppColors.text)
                    .lineSpacing(4)

                Spacer().frame(height: 6)

                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundColor(AppColors.secondaryText)
                    .lineSpacing(4)

                Spacer().frame(height: 20)

                VStack(spacing: 10) {
                    content()
                }

                Spacer().frame(height: 20)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }
}

private struct OptionCard: View {
    let title: String
    let description: String
    let isSelected: Bool
    let onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(isSelected ? AppColors.text : AppColors.text.opacity(0.9))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if !description.isEmpty {
                        Text(description)
                            .font(.system(size: 13))
                            .foregroundColor(AppColors.secondaryText)
                            .lineSpacing(3)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                // Radio Indicator
                ZStack {
                    Circle()
                        .stroke(isSelected ? AppColors.accent : AppColors.border, lineWidth: 1.5)
                        .frame(width: 22, height: 22)

                    if isSelected {
                        Circle()
                            .fill(AppColors.accent)
                            .frame(width: 10, height: 10)
                    }
                }
            }
            .padding(16)
            .background(isSelected ? AppColors.positiveBg : AppColors.surface)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? AppColors.accent : AppColors.border, lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}
