import SwiftUI

public struct IdentifiableCooldown: Identifiable, Equatable {
    public var id: String { "\(isDaily)_\(nextAllowedAt.timeIntervalSince1970)" }
    public let isDaily: Bool
    public let nextAllowedAt: Date
    public let remaining24h: Int

    public init(isDaily: Bool, nextAllowedAt: Date, remaining24h: Int) {
        self.isDaily = isDaily
        self.nextAllowedAt = nextAllowedAt
        self.remaining24h = remaining24h
    }
}

public struct ExerciseReportSheet: View {
    let exercise: Exercise
    var initialDraft: ExerciseIssueReport?
    var onDismiss: () -> Void
    var onSubmitNotice: (String) -> Void

    @State private var selectedCategory: String
    @State private var comments: String
    @State private var isSubmitting: Bool = false
    @State private var inlineToast: String? = nil

    public init(
        exercise: Exercise,
        initialDraft: ExerciseIssueReport? = nil,
        onDismiss: @escaping () -> Void,
        onSubmitNotice: @escaping (String) -> Void
    ) {
        self.exercise = exercise
        self.initialDraft = initialDraft
        self.onDismiss = onDismiss
        self.onSubmitNotice = onSubmitNotice
        _selectedCategory = State(initialValue: initialDraft?.category ?? ExerciseReportStore.categories.first ?? "animation_form")
        _comments = State(initialValue: initialDraft?.comment ?? "")
    }

    public init(
        exercise: Exercise,
        onDismiss: @escaping () -> Void,
        onSubmit: @escaping (ExerciseIssueReport) -> Void
    ) {
        self.exercise = exercise
        self.initialDraft = nil
        self.onDismiss = onDismiss
        self.onSubmitNotice = { _ in }
        _selectedCategory = State(initialValue: ExerciseReportStore.categories.first ?? "animation_form")
        _comments = State(initialValue: "")
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(LanguageManager.t("report.title"))
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(AppColors.text)
                    }

                    Spacer()

                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(AppColors.muted)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .disabled(isSubmitting)
                    .accessibilityLabel(LanguageManager.t("common.close"))
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

                // Scrollable Content
                ScrollView {
                    VStack(spacing: 16) {
                        // Privacy & Metadata Disclosure
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 14))
                                .foregroundColor(AppColors.muted)
                                .padding(.top, 2)
                            Text(LanguageManager.t("report.disclosure"))
                                .font(.system(size: 12))
                                .foregroundColor(AppColors.secondaryText)
                                .lineSpacing(3)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(AppColors.surfaceRaised)
                                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(AppColors.border, lineWidth: 1))
                        )

                        // Exercise Info Card
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(AppColors.exerciseThumbnailSurface)

                                MovementIllustration(exerciseId: exercise.exerciseId)
                                    .padding(4)
                            }
                            .frame(width: 76, height: 76)

                            VStack(alignment: .leading, spacing: 8) {
                                Text(exercise.displayName)
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(AppColors.text)
                                    .lineLimit(2)

                                Text(LanguageManager.t("category.\(exercise.resolvedMovement.key)").uppercased())
                                    .font(.system(size: 11, weight: .semibold))
                                    .tracking(0.6)
                                    .foregroundColor(AppColors.accent)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(AppColors.border, lineWidth: 1)
                                    )
                            }

                            Spacer()
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(AppColors.surface)
                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AppColors.border, lineWidth: 1))
                        )

                        // Issue Category Section
                        VStack(alignment: .leading, spacing: 10) {
                            Text(LanguageManager.t("report.category"))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(AppColors.text)

                            VStack(spacing: 8) {
                                ForEach(ExerciseReportStore.categories, id: \.self) { cat in
                                    let isSelected = selectedCategory == cat
                                    Button(action: {
                                        selectedCategory = cat
                                    }) {
                                        HStack {
                                            Text(LanguageManager.t("report.category.\(cat)"))
                                                .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                                                .foregroundColor(isSelected ? AppColors.accent : AppColors.text)

                                            Spacer()

                                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                                .font(.system(size: 18))
                                                .foregroundColor(isSelected ? AppColors.accent : AppColors.muted)
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 12)
                                        .background(
                                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                                .fill(isSelected ? AppColors.positiveBg : AppColors.surface)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                                                        .stroke(isSelected ? AppColors.accent.opacity(0.4) : AppColors.border, lineWidth: 1)
                                                )
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(isSubmitting)
                                }
                            }
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(AppColors.surface)
                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AppColors.border, lineWidth: 1))
                        )

                        // Comments Section
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(LanguageManager.t("report.detailsLabel"))
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(AppColors.text)

                                Spacer()

                                Text("\(comments.count) / 1000")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(comments.count > 950 ? AppColors.danger : AppColors.muted)
                            }

                            ZStack(alignment: .topLeading) {
                                if comments.isEmpty {
                                    Text(LanguageManager.t("report.detailsPlaceholder"))
                                        .font(.system(size: 14))
                                        .foregroundColor(AppColors.muted)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                }

                                TextEditor(text: $comments)
                                    .scrollContentBackground(.hidden)
                                    .font(.system(size: 14))
                                    .foregroundColor(AppColors.text)
                                    .frame(minHeight: 90)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .disabled(isSubmitting)
                                    .onChange(of: comments) { _, newValue in
                                        if newValue.count > 1000 {
                                            comments = String(newValue.prefix(1000))
                                        }
                                    }
                            }
                            .background(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(AppColors.surfaceRaised)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                                            .stroke(AppColors.border, lineWidth: 1)
                                    )
                            )
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(AppColors.surface)
                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AppColors.border, lineWidth: 1))
                        )

                        // Inline toast/error message if 429 occurs while sheet is open
                        if let toast = inlineToast {
                            Text(toast)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(AppColors.danger)
                                .multilineTextAlignment(.center)
                                .padding(12)
                                .frame(maxWidth: .infinity)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(AppColors.surfaceRaised)
                                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(AppColors.danger.opacity(0.4), lineWidth: 1))
                                )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                }

                // Bottom Submit Action
                VStack(spacing: 0) {
                    Divider().background(AppColors.border)

                    Button(action: {
                        guard !isSubmitting else { return }
                        isSubmitting = true
                        inlineToast = nil

                        let report = ExerciseIssueReport(
                            id: initialDraft?.id ?? UUID().uuidString,
                            clientUuid: initialDraft?.clientUuid ?? UUID().uuidString,
                            exerciseId: exercise.exerciseId,
                            exerciseName: exercise.name,
                            category: selectedCategory,
                            comment: comments.trimmingCharacters(in: .whitespacesAndNewlines),
                            status: "pending"
                        )
                        do {
                            _ = try ExerciseReportStore.shared.saveReport(report)
                        } catch {
                            isSubmitting = false
                            inlineToast = LanguageManager.t("report.saveFailed")
                            return
                        }

                        Task {
                            let result = await ExerciseReportStore.shared.submitReport(report)
                            await MainActor.run {
                                isSubmitting = false
                                switch result {
                                case .success:
                                    onDismiss()
                                    onSubmitNotice(LanguageManager.t("report.received"))
                                case .offlineSaved:
                                    onDismiss()
                                    onSubmitNotice(LanguageManager.t("report.savedOffline"))
                                case .rateLimited(let isDaily, let nextAllowedAt, _):
                                    let msg = isDaily
                                        ? LanguageManager.t("report.toastDaily", ["dateTime": ExerciseReportStore.formatLocalDateTime(nextAllowedAt)])
                                        : LanguageManager.t("report.toastHourly", ["time": ExerciseReportStore.formatLocalTime(nextAllowedAt)])
                                    inlineToast = msg
                                case .error(let err):
                                    inlineToast = err
                                }
                            }
                        }
                    }) {
                        HStack(spacing: 8) {
                            if isSubmitting {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: AppColors.background))
                                    .scaleEffect(0.9)
                            }
                            Text(LanguageManager.t("report.submit"))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(AppColors.background)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(isSubmitting ? AppColors.accent.opacity(0.7) : AppColors.accent)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isSubmitting)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                }
                .background(AppColors.surface)
            }
            .background(AppColors.background.ignoresSafeArea())
        }
    }
}

public struct ExerciseReportCooldownSheet: View {
    let isDaily: Bool
    let nextAllowedAt: Date
    let remaining24h: Int
    var onDismiss: () -> Void

    public init(
        isDaily: Bool,
        nextAllowedAt: Date,
        remaining24h: Int,
        onDismiss: @escaping () -> Void
    ) {
        self.isDaily = isDaily
        self.nextAllowedAt = nextAllowedAt
        self.remaining24h = remaining24h
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 20) {
            Text(LanguageManager.t(isDaily ? "report.dailyLimitModalTitle" : "report.hourlyCooldownModalTitle"))
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(AppColors.text)
                .multilineTextAlignment(.center)

            let bodyText = isDaily
                ? LanguageManager.t("report.dailyLimitModalBody", ["dateTime": ExerciseReportStore.formatLocalDateTime(nextAllowedAt)])
                : LanguageManager.t("report.hourlyCooldownModalBody", ["time": ExerciseReportStore.formatLocalTime(nextAllowedAt)])

            Text(bodyText)
                .font(.system(size: 14))
                .foregroundColor(AppColors.secondaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            if !isDaily {
                Text(LanguageManager.t("report.allowanceRemaining", ["remaining": remaining24h]))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppColors.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(AppColors.positiveBg)
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(AppColors.accent.opacity(0.3), lineWidth: 1))
                    )
            } else {
                Link(LanguageManager.t("report.supportSafetyNotice"), destination: URL(string: "https://forcedrep.com/support")!)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppColors.accent)
            }

            Button(action: onDismiss) {
                Text(LanguageManager.t("report.gotIt"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppColors.background)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(AppColors.accent)
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
        }
        .padding(24)
        .background(AppColors.surface.ignoresSafeArea())
    }
}

public struct PendingReportSheet: View {
    let report: ExerciseIssueReport
    var onDismiss: () -> Void
    var onSendNow: () -> Void
    var onDiscard: () -> Void

    public init(
        report: ExerciseIssueReport,
        onDismiss: @escaping () -> Void,
        onSendNow: @escaping () -> Void,
        onDiscard: @escaping () -> Void
    ) {
        self.report = report
        self.onDismiss = onDismiss
        self.onSendNow = onSendNow
        self.onDiscard = onDiscard
    }

    public var body: some View {
        VStack(spacing: 18) {
            Text(LanguageManager.t("report.pendingModalTitle"))
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(AppColors.text)

            Text(LanguageManager.t("report.pendingModalBody"))
                .font(.system(size: 14))
                .foregroundColor(AppColors.secondaryText)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 4) {
                Text(report.exerciseName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppColors.text)
                Text(LanguageManager.t("report.category.\(report.category)"))
                    .font(.system(size: 12))
                    .foregroundColor(AppColors.accent)
                if !report.comment.isEmpty {
                    Text(report.comment)
                        .font(.system(size: 12))
                        .foregroundColor(AppColors.muted)
                        .lineLimit(2)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AppColors.surfaceRaised)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(AppColors.border, lineWidth: 1))
            )

            VStack(spacing: 10) {
                Button(action: onSendNow) {
                    Text(LanguageManager.t("report.pendingSendNow"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppColors.background)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(AppColors.accent)
                        )
                }
                .buttonStyle(.plain)

                HStack(spacing: 12) {
                    Button(action: onDiscard) {
                        Text(LanguageManager.t("report.pendingDiscard"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(AppColors.danger)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                    .buttonStyle(.plain)

                    Button(action: onDismiss) {
                        Text(LanguageManager.t("report.pendingKeep"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(AppColors.secondaryText)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(24)
        .background(AppColors.surface.ignoresSafeArea())
    }
}
