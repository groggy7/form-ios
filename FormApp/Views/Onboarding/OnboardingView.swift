import SwiftUI
import UniformTypeIdentifiers

/// Welcome, four questions, then the recommendation. See gym/docs/design/app-tour.md.
public struct OnboardingView: View {
    @ObservedObject var themeManager = ThemeManager.shared
    @ObservedObject var store: AppStore
    @ObservedObject var langManager = LanguageManager.shared

    @State private var step: Int = Self.welcomeStep
    @State private var preferences = OnboardingPreferences()
    @State private var showLanguageSheet = false
    @State private var showRestoreSheet = false
    @State private var showCloudRestore = false
    @State private var isShowingBackupImporter = false
    @State private var backupToRestore: String?
    @State private var showRestoreAlert = false
    @State private var isRestoring = false
    @State private var restoreErrorMessage: String?

    private static let welcomeStep = 0
    private static let firstQuestionStep = 1
    private static let questionCount = 4
    private static let recommendationStep = firstQuestionStep + questionCount

    private var isQuestion: Bool { (Self.firstQuestionStep..<Self.recommendationStep).contains(step) }

    public init(store: AppStore) {
        self.store = store
    }

    public var body: some View {
        let _ = themeManager.currentTheme
        ZStack {
            AppColors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header: Back, progress and Skip on the questions; the language on Welcome.
                HStack(spacing: 8) {
                    if step > Self.welcomeStep {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                step -= 1
                            }
                        }) {
                            Image(systemName: "arrow.left")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(AppColors.text)
                                .frame(width: 48, height: 48)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel(LanguageManager.t("onboarding.back"))
                        .accessibilityIdentifier("onboarding-back")
                    } else {
                        Spacer().frame(width: 48, height: 48)
                    }

                    if isQuestion {
                        HStack(spacing: 4) {
                            ForEach(0..<Self.questionCount, id: \.self) { index in
                                Capsule()
                                    .fill(index <= step - Self.firstQuestionStep ? AppColors.accent : AppColors.border)
                                    .frame(height: 4)
                            }
                        }
                    } else {
                        Spacer()
                    }

                    if isQuestion {
                        Button(action: {
                            store.setOnboardingCompleted(true)
                        }) {
                            Text(LanguageManager.t("onboarding.skip"))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(AppColors.muted)
                                .padding(.horizontal, 12)
                                .frame(minHeight: 48)
                                .contentShape(Rectangle())
                        }
                    } else if step == Self.welcomeStep {
                        languagePill
                    } else {
                        Spacer().frame(width: 48, height: 48)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)

                // Step Content
                Group {
                    switch step {
                    case Self.welcomeStep:
                        welcomeStep
                    case 1:
                        goalStep
                    case 2:
                        experienceStep
                    case 3:
                        equipmentStep
                    case 4:
                        trainingDaysStep
                    default:
                        recommendationStep
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Bottom Continue Action for question steps
                if isQuestion {
                    VStack(spacing: 0) {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                step += 1
                            }
                        }) {
                            Text(LanguageManager.t("onboarding.next"))
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(AppColors.background)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(AppColors.accent)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
        }
        .sheet(isPresented: $showLanguageSheet) {
            LanguageSelectionSheet(
                preference: langManager.languagePreference,
                deviceLanguageName: deviceLanguageName,
                onSelect: { code in
                    showLanguageSheet = false
                    if code != langManager.languagePreference { LanguageManager.setLanguage(code) }
                },
                onDismiss: { showLanguageSheet = false }
            )
            .presentationDetents([.height(520), .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showRestoreSheet) {
            restoreChoiceSheet
                .presentationDetents([.height(360), .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showCloudRestore) {
            // A backup restored from the welcome step finishes setup as a returning user.
            CloudBackupSheet(store: store, onRestored: {
                showCloudRestore = false
                store.completeSetupAfterRestore()
                store.noticeMessage = LanguageManager.t("notice.backupRestored")
            })
        }
        .fileImporter(isPresented: $isShowingBackupImporter, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
            readBackup(result)
        }
        .alert(
            LanguageManager.t("programs.restoreTitle"),
            isPresented: $showRestoreAlert,
            actions: {
                Button(LanguageManager.t("settings.restoreBackup"), role: .destructive) { restoreFile() }
                Button(LanguageManager.t("modal.cancel"), role: .cancel) { backupToRestore = nil }
            },
            message: { Text(LanguageManager.t("programs.restoreHint")) }
        )
        .alert(
            LanguageManager.t("programs.fileError"),
            isPresented: Binding(get: { restoreErrorMessage != nil }, set: { if !$0 { restoreErrorMessage = nil } }),
            actions: { Button(LanguageManager.t("programs.close")) { restoreErrorMessage = nil } },
            message: { Text(restoreErrorMessage ?? "") }
        )
    }

    // MARK: - Welcome

    private var deviceLanguageName: String {
        let code = LanguageManager.resolveLanguage(Locale.preferredLanguages)
        return LanguageManager.supportedLanguages.first { $0.code == code }?.name ?? "English"
    }

    private var languagePill: some View {
        let preference = langManager.languagePreference
        let label = preference == LanguageManager.system
            ? deviceLanguageName
            : LanguageManager.supportedLanguages.first { $0.code == preference }?.name ?? deviceLanguageName
        let code = preference == LanguageManager.system ? LanguageManager.resolveLanguage(Locale.preferredLanguages) : preference
        return Button(action: { showLanguageSheet = true }) {
            HStack(spacing: 8) {
                Image(LanguageManager.flagImageName(for: code))
                    .resizable()
                    .scaledToFill()
                    .frame(width: 22, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Text(label)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppColors.text)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 48)
            .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(LanguageManager.t("settings.language")): \(label)")
        .accessibilityIdentifier("onboarding-language")
    }

    private var welcomeStep: some View {
        // The mark and text sit centred while they fit; larger text scrolls with the actions below.
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    VStack(spacing: 12) {
                        Image("LaunchMark")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 112, height: 112)
                            .foregroundStyle(AppColors.text)
                            .accessibilityHidden(true)
                        Text(LanguageManager.t("onboarding.welcome.title"))
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(AppColors.text)
                            .multilineTextAlignment(.center)
                        Text(LanguageManager.t("onboarding.welcome.subtitle"))
                            .font(.system(size: 15))
                            .foregroundStyle(AppColors.secondaryText)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                    }
                    Spacer(minLength: 24)
                    VStack(spacing: 10) {
                        Button(action: { withAnimation(.easeInOut(duration: 0.25)) { step = Self.firstQuestionStep } }) {
                            Text(LanguageManager.t("onboarding.welcome.start"))
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(AppColors.background)
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .background(AppColors.accent, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("onboarding-start")
                        Button(action: { showRestoreSheet = true }) {
                            Text(LanguageManager.t("onboarding.welcome.restore"))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(AppColors.text)
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.border, lineWidth: 1))
                                .contentShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("onboarding-restore")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(minHeight: proxy.size.height)
            }
        }
    }

    private var restoreChoiceSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LanguageManager.t("onboarding.restore.title"))
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(AppColors.text)
            Text(LanguageManager.t("onboarding.restore.subtitle"))
                .font(.system(size: 14))
                .foregroundStyle(AppColors.secondaryText)
            restoreOption(icon: "doc.text", title: "onboarding.restore.file", hint: "onboarding.restore.fileHint", id: "onboarding-restore-file") {
                showRestoreSheet = false
                isShowingBackupImporter = true
            }
            restoreOption(icon: "icloud.and.arrow.down", title: "onboarding.restore.cloud", hint: "onboarding.restore.cloudHint", id: "onboarding-restore-cloud") {
                showRestoreSheet = false
                showCloudRestore = true
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.background.ignoresSafeArea())
    }

    private func restoreOption(icon: String, title: String, hint: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(AppColors.secondaryText)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(LanguageManager.t(title))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AppColors.text)
                    Text(LanguageManager.t(hint))
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.secondaryText)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.muted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minHeight: 64)
            .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private func readBackup(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else {
            if case .failure = result { restoreErrorMessage = LanguageManager.t("errors.fileRead") }
            return
        }
        // Files inside this app's own container are not security-scoped; access still works.
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= ImportExportDataSheet.maxBackupBytes,
              let data = try? Data(contentsOf: url), let json = String(data: data, encoding: .utf8) else {
            restoreErrorMessage = LanguageManager.t("errors.fileRead")
            return
        }
        backupToRestore = json
        showRestoreAlert = true
    }

    private func restoreFile() {
        guard let json = backupToRestore, !isRestoring else { return }
        isRestoring = true
        Task { @MainActor in
            let success = await store.restoreBackupJsonAsync(json)
            isRestoring = false
            backupToRestore = nil
            if success {
                store.completeSetupAfterRestore()
                store.noticeMessage = LanguageManager.t("notice.backupRestored")
            } else {
                restoreErrorMessage = LanguageManager.t("notice.restoreFailed")
            }
        }
    }

    // MARK: - Step 1: Goal
    private var goalStep: some View {
        StepContainer(
            title: LanguageManager.t("onboarding.goal.title"),
            subtitle: LanguageManager.t("onboarding.goal.subtitle")
        ) {
            OptionCard(
                title: LanguageManager.t("onboarding.goal.bulk.title"),
                description: LanguageManager.t("onboarding.goal.bulk.desc"),
                isSelected: preferences.goal == .bulk,
                onClick: { preferences.goal = .bulk }
            )
            OptionCard(
                title: LanguageManager.t("onboarding.goal.cut.title"),
                description: LanguageManager.t("onboarding.goal.cut.desc"),
                isSelected: preferences.goal == .cut,
                onClick: { preferences.goal = .cut }
            )
            OptionCard(
                title: LanguageManager.t("onboarding.goal.strength.title"),
                description: LanguageManager.t("onboarding.goal.strength.desc"),
                isSelected: preferences.goal == .strength,
                onClick: { preferences.goal = .strength }
            )
            OptionCard(
                title: LanguageManager.t("onboarding.goal.maintain.title"),
                description: LanguageManager.t("onboarding.goal.maintain.desc"),
                isSelected: preferences.goal == .maintain,
                onClick: { preferences.goal = .maintain }
            )
        }
    }

    // MARK: - Step 2: Experience
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

    // MARK: - Step 3: Equipment
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
            OptionCard(
                title: LanguageManager.t("onboarding.equipment.bodyweightHome.title"),
                description: LanguageManager.t("onboarding.equipment.bodyweightHome.desc"),
                isSelected: preferences.equipment == .bodyweightHome,
                onClick: { preferences.equipment = .bodyweightHome }
            )
            OptionCard(
                title: LanguageManager.t("onboarding.equipment.pullUpBarHome.title"),
                description: LanguageManager.t("onboarding.equipment.pullUpBarHome.desc"),
                isSelected: preferences.equipment == .pullUpBarHome,
                onClick: { preferences.equipment = .pullUpBarHome }
            )
        }
    }

    // MARK: - Step 4: Training days
    /// One step for how many days and which: a count chip sets that count's default weekdays, and
    /// the toggles below adjust them. The ticked days decide, as the recommender expects.
    private var trainingDaysStep: some View {
        let currentDays = OnboardingRecommender.chosenWeekdays(preferences)
        let dayLabels = LanguageManager.dayLabels
        let dayFullNames = LanguageManager.workoutDays
        let describedCount = min(max(currentDays.count, 2), 6)

        return StepContainer(
            title: LanguageManager.t("onboarding.days.title"),
            subtitle: LanguageManager.t("onboarding.days.subtitle")
        ) {
            Text(LanguageManager.t("onboarding.days.perWeek"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppColors.text)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                ForEach(OnboardingFrequency.allCases, id: \.self) { frequency in
                    let isSelected = currentDays.count == frequency.rawValue
                    Button(action: {
                        preferences.frequency = frequency
                        preferences.selectedDays = frequency.defaultWeekdays
                    }) {
                        Text("\(frequency.rawValue)")
                            .font(.system(size: 17, weight: isSelected ? .bold : .medium))
                            .foregroundStyle(isSelected ? AppColors.text : AppColors.secondaryText)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(isSelected ? AppColors.positiveBg : AppColors.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(isSelected ? AppColors.accent : AppColors.border, lineWidth: isSelected ? 1.5 : 1)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityLabel(LanguageManager.t("onboarding.days.chip", ["count": frequency.rawValue]))
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .accessibilityIdentifier("onboarding-days-\(frequency.rawValue)")
                }
            }

            Text(LanguageManager.t("onboarding.frequency.days\(describedCount).desc"))
                .font(.system(size: 13))
                .foregroundStyle(AppColors.secondaryText)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(LanguageManager.t("onboarding.days.weekdays"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppColors.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)

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
                                    .foregroundStyle(isSelected ? AppColors.accent : AppColors.muted)
                                    .frame(width: 32, height: 32)
                                    .background(isSelected ? AppColors.accent.opacity(0.2) : AppColors.surfaceRaised)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))

                                Text(fullName)
                                    .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                                    .foregroundStyle(isSelected ? AppColors.text : AppColors.secondaryText)
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
                                        .foregroundStyle(AppColors.background)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(isSelected ? AppColors.positiveBg : AppColors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isSelected ? AppColors.accent : AppColors.border, lineWidth: isSelected ? 1.5 : 1)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
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
                    .foregroundStyle(AppColors.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppColors.positiveBg)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(AppColors.accent.opacity(0.3), lineWidth: 1)
                    )

                // Title
                Text(recommendation.program.displayName)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(AppColors.text)

                // Reason Card
                Text(LanguageManager.t(recommendation.explanationKey))
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.secondaryText)
                    .lineSpacing(4)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppColors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(AppColors.border, lineWidth: 1)
                    )

                // Workouts in this split
                Text(LanguageManager.t("onboarding.rec.workoutsTitle"))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AppColors.text)
                    .padding(.top, 8)

                VStack(spacing: 8) {
                    ForEach(recommendation.program.workouts) { workout in
                        HStack(spacing: 12) {
                            // The weekday this workout is scheduled on, after fitting the plan to the chosen days.
                            let dayIndex = workout.day - 1
                            Text(LanguageManager.dayLabels.indices.contains(dayIndex) ? LanguageManager.dayLabels[dayIndex] : "")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(AppColors.secondaryText)
                                .lineLimit(1)
                                .fixedSize()
                                .frame(minWidth: 32, minHeight: 32)
                                .background(AppColors.surfaceRaised)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .accessibilityLabel(LanguageManager.workoutDays.indices.contains(dayIndex) ? LanguageManager.workoutDays[dayIndex] : "")

                            VStack(alignment: .leading, spacing: 2) {
                                Text(workout.displayTitle(programId: recommendation.program.id))
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(AppColors.text)

                                let focus = workout.displayFocus(programId: recommendation.program.id)
                                if !focus.isEmpty {
                                    Text(focus)
                                        .font(.system(size: 12))
                                        .foregroundStyle(AppColors.secondaryText)
                                }

                                // Below the text rather than in a trailing chip, so longer localized counts never narrow the title.
                                Text(LanguageManager.t("programs.exerciseQuantity", ["count": workout.exercises.count]))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(AppColors.muted)
                            }

                            Spacer()
                        }
                        .padding(14)
                        .background(AppColors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(AppColors.border, lineWidth: 1)
                        )
                    }
                }

                // Loads are entered from the first set, so the unit is confirmed before training starts.
                weightUnitRow
                    .padding(.top, 8)

                // CTA Buttons
                VStack(spacing: 10) {
                    Button(action: {
                        store.completeOnboarding(preferences: preferences, targetProgramId: recommendation.targetProgramId)
                    }) {
                        Text(LanguageManager.t("onboarding.rec.startCta"))
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(AppColors.background)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(AppColors.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Button(action: {
                        store.completeOnboarding(preferences: preferences, targetProgramId: recommendation.targetProgramId)
                        store.navigate(to: .today)
                    }) {
                        Text(LanguageManager.t("onboarding.rec.browseAll"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(AppColors.secondaryText)
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

private extension OnboardingView {
    var weightUnitRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(LanguageManager.t("settings.weightUnit"))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AppColors.text)
                Text(LanguageManager.t("settings.weightUnitSubtitle"))
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.secondaryText)
            }
            Spacer(minLength: 0)
            HStack(spacing: 2) {
                ForEach([WeightUnit.kg, WeightUnit.lbs], id: \.self) { option in
                    let selected = store.weightUnit == option
                    Button(action: { store.weightUnit = option }) {
                        Text(option.label)
                            .font(.system(size: 14, weight: selected ? .semibold : .medium))
                            .foregroundStyle(selected ? AppColors.background : AppColors.secondaryText)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 44)
                            .background(selected ? AppColors.accent : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier("onboarding-unit-\(option.rawValue)")
                }
            }
            .padding(3)
            .background(AppColors.surfaceRaised, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppColors.border, lineWidth: 1))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.border, lineWidth: 1))
    }
}

private struct StepContainer<Content: View>: View {
    @ObservedObject var themeManager = ThemeManager.shared
    let title: String
    let subtitle: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        let _ = themeManager.currentTheme
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(AppColors.text)
                    .lineSpacing(4)

                Spacer().frame(height: 6)

                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.secondaryText)
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
    @ObservedObject var themeManager = ThemeManager.shared
    let title: String
    let description: String
    let isSelected: Bool
    let onClick: () -> Void

    var body: some View {
        let _ = themeManager.currentTheme
        Button(action: onClick) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(isSelected ? AppColors.text : AppColors.text.opacity(0.9))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if !description.isEmpty {
                        Text(description)
                            .font(.system(size: 13))
                            .foregroundStyle(AppColors.secondaryText)
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
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? AppColors.accent : AppColors.border, lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}
