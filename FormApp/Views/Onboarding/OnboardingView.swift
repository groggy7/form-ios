import SwiftUI
import UniformTypeIdentifiers

/// Welcome and restore, followed by equipment-based program generation. See gym/docs/design/app-tour.md.
public struct OnboardingView: View {
    @ObservedObject var themeManager = ThemeManager.shared
    @ObservedObject var store: AppStore
    @ObservedObject var langManager = LanguageManager.shared
    @Environment(\.scenePhase) private var scenePhase

    @State private var step: Int = Self.welcomeStep
    @State private var showLanguageSheet = false
    @State private var showRestoreSheet = false
    @State private var showCloudRestore = false
    @State private var isShowingBackupImporter = false
    @State private var backupToRestore: String?
    @State private var showRestoreAlert = false
    @State private var isRestoring = false
    @State private var restoreErrorMessage: String?

    private static let welcomeStep = 0
    public init(store: AppStore) {
        self.store = store
    }

    public var body: some View {
        let _ = themeManager.currentTheme
        Group {
            if step > Self.welcomeStep {
                TrainingSetupView(store: store, onClose: { step = Self.welcomeStep }, onSkip: { store.skipSetup() })
            } else {
                VStack(spacing: 0) {
                    HStack { Spacer(); languagePill }.padding(8)
                    welcomeStep
                }.background(AppColors.background)
            }
        }
        .onAppear { TrainingSetupStore.clearDraft() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .background else { return }
            // An unfinished visit restarts at Welcome; no question or answer is restored.
            step = Self.welcomeStep
            showLanguageSheet = false
            showRestoreSheet = false
            showCloudRestore = false
            isShowingBackupImporter = false
            showRestoreAlert = false
            backupToRestore = nil
            restoreErrorMessage = nil
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
                    .font(.app(size: 14, weight: .medium))
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
                            .font(.app(size: 26, weight: .bold))
                            .foregroundStyle(AppColors.text)
                            .multilineTextAlignment(.center)
                        Text(LanguageManager.t("onboarding.welcome.subtitle"))
                            .font(.app(size: 15))
                            .foregroundStyle(AppColors.secondaryText)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                    }
                    Spacer(minLength: 24)
                    VStack(spacing: 10) {
                        Button(action: { withAnimation(.easeInOut(duration: 0.25)) { step = 1 } }) {
                            Text(LanguageManager.t("onboarding.welcome.start"))
                                .font(.app(size: 16, weight: .bold))
                                .foregroundStyle(AppColors.background)
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .background(AppColors.accent, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("onboarding-start")
                        Button(action: { showRestoreSheet = true }) {
                            Text(LanguageManager.t("onboarding.welcome.restore"))
                                .font(.app(size: 15, weight: .semibold))
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
                .font(.app(size: 20, weight: .semibold))
                .foregroundStyle(AppColors.text)
            Text(LanguageManager.t("onboarding.restore.subtitle"))
                .font(.app(size: 14))
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
                        .font(.app(size: 15, weight: .medium))
                        .foregroundStyle(AppColors.text)
                    Text(LanguageManager.t(hint))
                        .font(.app(size: 13))
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


}
