import SwiftUI

/// The welcome step's iCloud restore. It looks the backup up from iCloud metadata, offers it with
/// its save time and restores it in one tap. It is restore-only: nothing here can save this fresh
/// install over the backup the person came to restore. See gym/docs/design/app-tour.md.
struct SetupBackupSheet: View {
    enum Phase: Equatable {
        case looking
        case found(savedAt: Date?)
        case none
        case unavailable
        case failed
    }

    @ObservedObject var store: AppStore
    @ObservedObject private var themeManager = ThemeManager.shared
    private let mirrorManager: CloudMirrorManager
    private let onRestored: () -> Void
    private let onStartFresh: () -> Void
    private let onRestoreFile: () -> Void
    @State private var phase: Phase
    @State private var isRestoring = false
    @State private var message: String?
    @State private var restoreTask: Task<Void, Never>?

    init(store: AppStore, mirrorManager: CloudMirrorManager = .shared, phase: Phase = .looking,
         onRestored: @escaping () -> Void, onStartFresh: @escaping () -> Void, onRestoreFile: @escaping () -> Void) {
        self.store = store
        self.mirrorManager = mirrorManager
        self.onRestored = onRestored
        self.onStartFresh = onStartFresh
        self.onRestoreFile = onRestoreFile
        _phase = State(initialValue: phase)
    }

    var body: some View {
        let _ = themeManager.currentTheme
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AppColors.background.ignoresSafeArea())
        .task { if phase == .looking { await lookUp() } }
        // Dismissing cancels an unfinished restore before it changes anything.
        .onDisappear { restoreTask?.cancel() }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .looking:
            header("icloud", positive: false, title: "onboarding.restore.title")
            HStack(spacing: 12) {
                ProgressView().tint(AppColors.accent)
                Text(LanguageManager.t("onboarding.restore.looking"))
                    .font(.app(size: 14))
                    .foregroundStyle(AppColors.secondaryText)
            }
            .frame(minHeight: 52)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("setup-backup-looking")
        case .found(let savedAt):
            header("icloud.and.arrow.down", positive: true, title: "onboarding.restore.found.title")
            bodyText("onboarding.restore.found.body")
            if let savedAt {
                VStack(alignment: .leading, spacing: 2) {
                    Text(LanguageManager.t("onboarding.restore.lastSaved"))
                        .font(.app(size: 12))
                        .foregroundStyle(AppColors.muted)
                    Text(Self.savedAtText(savedAt))
                        .font(.app(size: 15))
                        .foregroundStyle(AppColors.text)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.border, lineWidth: 1))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("setup-backup-found")
            }
            messageText
            primaryButton(isRestoring ? "onboarding.restore.restoring" : "form_lab.mirror_restore_cta",
                          working: isRestoring, id: "setup-backup-restore", action: restore)
            secondaryButton("onboarding.restore.startFresh", id: "setup-backup-start-fresh", action: onStartFresh)
        case .none:
            header("icloud.slash", positive: false, title: "onboarding.restore.none.title")
            bodyText("onboarding.restore.none.body").accessibilityIdentifier("setup-backup-none")
            messageText
            fileRow
        case .unavailable:
            header("icloud.slash", positive: false, title: "onboarding.restore.unavailable.title")
            bodyText("onboarding.restore.unavailable.body").accessibilityIdentifier("setup-backup-unavailable")
            primaryButton("onboarding.restore.tryAgain", working: false, id: "setup-backup-retry") { Task { await lookUp() } }
            fileRow
        case .failed:
            header("icloud.slash", positive: false, title: "onboarding.restore.title")
            bodyText("onboarding.restore.checkFailed").accessibilityIdentifier("setup-backup-failed")
            primaryButton("onboarding.restore.tryAgain", working: false, id: "setup-backup-retry") { Task { await lookUp() } }
            fileRow
        }
    }

    static func savedAtText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = LanguageManager.locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func lookUp() async {
        phase = .looking
        message = nil
        do {
            switch try await mirrorManager.findSetupBackup() {
            case .found(let savedAt): phase = .found(savedAt: savedAt)
            case .none: phase = .none
            case .unavailable: phase = .unavailable
            }
        } catch is CancellationError {
            return
        } catch {
            phase = .failed
        }
    }

    private func restore() {
        guard !isRestoring else { return }
        isRestoring = true
        message = nil
        restoreTask = Task { @MainActor in
            defer { isRestoring = false }
            do {
                let json = try await mirrorManager.readLatestSnapshotAsync()
                try Task.checkCancellation()
                let success = await store.restoreBackupJsonAsync(json)
                try Task.checkCancellation()
                guard success else { message = LanguageManager.t("notice.restoreFailed"); return }
                mirrorManager.didRestoreSnapshot()
                onRestored()
            } catch is CancellationError {
                return
            } catch CloudMirrorError.noBackup {
                phase = .none
            } catch {
                message = LanguageManager.t("form_lab.mirror_restore_failed", ["error": error.localizedDescription])
            }
        }
    }

    // MARK: - Pieces

    private func header(_ symbol: String, positive: Bool, title: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(positive ? AppColors.accent : AppColors.secondaryText)
                .frame(width: 40, height: 40)
                .background(positive ? AppColors.positiveBg : AppColors.surfaceRaised, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
            Text(LanguageManager.t(title))
                .font(.app(size: 20, weight: .semibold))
                .foregroundStyle(AppColors.text)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private func bodyText(_ key: String) -> some View {
        Text(LanguageManager.t(key))
            .font(.app(size: 14))
            .foregroundStyle(AppColors.secondaryText)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var messageText: some View {
        if let message {
            Text(message)
                .font(.app(size: 13))
                .foregroundStyle(AppColors.danger)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("setup-backup-message")
        }
    }

    private func primaryButton(_ key: String, working: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if working { ProgressView().tint(AppColors.background) }
                Text(LanguageManager.t(key))
                    .font(.app(size: 16, weight: .bold))
            }
            .foregroundStyle(AppColors.background)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(AppColors.accent, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(isRestoring)
        .accessibilityIdentifier(id)
    }

    private func secondaryButton(_ key: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(LanguageManager.t(key))
                .font(.app(size: 15, weight: .semibold))
                .foregroundStyle(isRestoring ? AppColors.muted : AppColors.text)
                .frame(maxWidth: .infinity, minHeight: 52)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.border, lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(isRestoring)
        .accessibilityIdentifier(id)
    }

    private var fileRow: some View {
        Button(action: onRestoreFile) {
            HStack(spacing: 14) {
                Image(systemName: "doc.text")
                    .font(.system(size: 20))
                    .foregroundStyle(AppColors.secondaryText)
                    .frame(width: 24)
                Text(LanguageManager.t("onboarding.restore.fromFile"))
                    .font(.app(size: 15, weight: .medium))
                    .foregroundStyle(AppColors.text)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.muted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minHeight: 56)
            .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("setup-backup-file")
    }
}
