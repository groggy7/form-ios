import SwiftUI
import UniformTypeIdentifiers

public struct SettingsView: View {
    @ObservedObject var store: AppStore
    @ObservedObject var langManager = LanguageManager.shared
    @ObservedObject private var proManager = ProAccessManager.shared
    var onDismiss: () -> Void

    @State private var showPaywall: Bool = false
    @Environment(\.openURL) private var openURL
    @State private var showExportSheet: Bool = false
    @State private var exportText: String = ""
    @State private var isShowingFileImporter: Bool = false
    @State private var importPreview: HistoryImportPreview? = nil
    @State private var importErrorMessage: String? = nil

    public init(store: AppStore, onDismiss: @escaping () -> Void) {
        self.store = store
        self.onDismiss = onDismiss
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Forced Rep Pro Membership Card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            HStack(spacing: 8) {
                                Image(systemName: "crown.fill")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(proManager.isProSubscribed ? AppColors.purple : AppColors.accent)
                                Text(LanguageManager.t("settings.pro_membership"))
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(AppColors.text)
                            }
                            Spacer()
                            ProBadge(text: proManager.isProSubscribed ? "PRO ACTIVE" : "FREE")
                        }

                        Text(LanguageManager.t(proManager.isProSubscribed ? "settings.pro_active" : "pro.volume_matrix.description"))
                            .font(.system(size: 12.5))
                            .foregroundColor(AppColors.secondaryText)
                            .lineSpacing(2)

                        HStack(spacing: 8) {
                            if !proManager.isProSubscribed {
                                Button(action: { showPaywall = true }) {
                                    Text(LanguageManager.t("settings.upgrade_to_pro"))
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(AppColors.background)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 38)
                                        .background(AppColors.accent)
                                        .cornerRadius(10)
                                }
                                .buttonStyle(.plain)
                            }

                            #if DEBUG
                            Button(action: { _ = proManager.toggleSubscriptionStatus() }) {
                                Text(proManager.isProSubscribed ? LanguageManager.t("paywall.dev_locked") : LanguageManager.t("settings.test_pro_toggle"))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(proManager.isProSubscribed ? AppColors.purple : AppColors.text)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 38)
                                    .background(Color.clear)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(proManager.isProSubscribed ? AppColors.purple.opacity(0.6) : AppColors.border, lineWidth: 1)
                                    )
                                    .cornerRadius(10)
                            }
                            .buttonStyle(.plain)
                            #endif
                        }
                    }
                    .padding(16)
                    .background(proManager.isProSubscribed ? AppColors.purpleBg : AppColors.surfaceRaised)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(proManager.isProSubscribed ? AppColors.purple.opacity(0.5) : AppColors.border, lineWidth: 1)
                    )
                    .cornerRadius(16)

                    // Training section
                    settingsSection(title: LanguageManager.t("settings.training")) {
                        VStack(spacing: 0) {
                            HStack {
                                Text(LanguageManager.t("settings.defaultRest"))
                                    .font(.system(size: 15))
                                    .foregroundColor(AppColors.text)
                                Spacer()
                                Picker("", selection: $store.defaultRestSeconds) {
                                    Text("60s").tag(60)
                                    Text("90s").tag(90)
                                    Text("120s").tag(120)
                                    Text("180s").tag(180)
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 180)
                            }
                            .padding(14)

                            Divider().background(AppColors.border)

                            Toggle(isOn: $store.prefillNextSet) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(LanguageManager.t("settings.prefillNextSet"))
                                        .font(.system(size: 15))
                                        .foregroundColor(AppColors.text)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(LanguageManager.t("settings.prefillNextSetSubtitle"))
                                        .font(.system(size: 12))
                                        .foregroundColor(AppColors.secondaryText)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .tint(AppColors.accent)
                            .padding(14)

                            if store.isProgressionCardDismissed || store.isWarmupCardDismissed {
                                Divider().background(AppColors.border)

                                Button(action: {
                                    withAnimation {
                                        store.resetDismissedProCards()
                                    }
                                }) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(LanguageManager.t("settings.restore_pro_cards"))
                                                .font(.system(size: 15))
                                                .foregroundColor(AppColors.text)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                            Text(LanguageManager.t("settings.restore_pro_cards_desc"))
                                                .font(.system(size: 12))
                                                .foregroundColor(AppColors.secondaryText)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        Spacer()
                                        Image(systemName: "arrow.counterclockwise")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(AppColors.accent)
                                    }
                                    .padding(14)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Preferences
                    settingsSection(title: LanguageManager.t("settings.timerAndAlerts")) {
                        Toggle(isOn: $store.soundEnabled) {
                            Text(LanguageManager.t("settings.lockedScreenAlerts"))
                                .font(.system(size: 15))
                                .foregroundColor(AppColors.text)
                        }
                        .tint(AppColors.accent)
                        .padding(14)
                    }

                    // Language
                    settingsSection(title: LanguageManager.t("settings.language")) {
                        HStack {
                            Text(LanguageManager.t("settings.language"))
                                .font(.system(size: 15))
                                .foregroundColor(AppColors.text)
                            Spacer()
                            Picker("", selection: $langManager.currentLanguage) {
                                Text("English").tag("en")
                                Text("Türkçe").tag("tr")
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 160)
                        }
                        .padding(14)
                    }

                    // Weight Unit
                    settingsSection(title: LanguageManager.t("settings.weightUnit")) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(LanguageManager.t("settings.weightUnit"))
                                    .font(.system(size: 15))
                                    .foregroundColor(AppColors.text)
                                Text(LanguageManager.t("settings.weightUnitSubtitle"))
                                    .font(.system(size: 12))
                                    .foregroundColor(AppColors.secondaryText)
                            }
                            Spacer()
                            Picker("", selection: $store.weightUnit) {
                                Text(LanguageManager.t("settings.unitKg")).tag(WeightUnit.kg)
                                Text(LanguageManager.t("settings.unitLbs")).tag(WeightUnit.lbs)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 120)
                        }
                        .padding(14)
                    }

                    // Data Management
                    settingsSection(title: LanguageManager.t("settings.dataManagement")) {
                        VStack(spacing: 0) {
                            Button(action: { isShowingFileImporter = true }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(LanguageManager.t("settings.importHistory"))
                                            .font(.system(size: 15))
                                            .foregroundColor(AppColors.text)
                                        Text(LanguageManager.t("settings.importHistorySubtitle"))
                                            .font(.system(size: 12))
                                            .foregroundColor(AppColors.secondaryText)
                                    }
                                    Spacer()
                                    Image(systemName: "square.and.arrow.down")
                                        .font(.system(size: 14))
                                        .foregroundColor(AppColors.accent)
                                }
                                .padding(14)
                            }

                            Divider().background(AppColors.border)

                            Button(action: exportBackup) {
                                HStack {
                                    Text(LanguageManager.t("settings.exportBackup"))
                                        .font(.system(size: 15))
                                        .foregroundColor(AppColors.accent)
                                    Spacer()
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 14))
                                        .foregroundColor(AppColors.accent)
                                }
                                .padding(14)
                            }

                            Divider().background(AppColors.border)

                            Button(action: {}) {
                                HStack {
                                    Text(LanguageManager.t("settings.restoreBackup"))
                                        .font(.system(size: 15))
                                        .foregroundColor(AppColors.secondaryText)
                                    Spacer()
                                    Image(systemName: "arrow.counterclockwise")
                                        .font(.system(size: 14))
                                        .foregroundColor(AppColors.muted)
                                }
                                .padding(14)
                            }
                        }
                    }

                    // About
                    settingsSection(title: LanguageManager.t("settings.about")) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Text("FORCED REP")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(AppColors.text)
                                Text(LanguageManager.t("settings.version"))
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(AppColors.accent)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(AppColors.accent.opacity(0.15))
                                    .cornerRadius(6)
                            }
                            Text(LanguageManager.t("settings.aboutDescription"))
                                .font(.system(size: 14))
                                .foregroundColor(AppColors.secondaryText)
                                .lineSpacing(3)
                        }
                        .padding(14)

                        Divider().background(AppColors.border)

                        Button(action: {
                            if let url = URL(string: LegalUrls.termsOfService) {
                                openURL(url)
                            }
                        }) {
                            HStack {
                                Text(LanguageManager.t("settings.terms"))
                                    .font(.system(size: 15))
                                    .foregroundColor(AppColors.text)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(AppColors.muted)
                            }
                            .padding(14)
                        }

                        Divider().background(AppColors.border)

                        Button(action: {
                            if let url = URL(string: LegalUrls.privacyPolicy) {
                                openURL(url)
                            }
                        }) {
                            HStack {
                                Text(LanguageManager.t("settings.privacy"))
                                    .font(.system(size: 15))
                                    .foregroundColor(AppColors.text)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(AppColors.muted)
                            }
                            .padding(14)
                        }

                        Divider().background(AppColors.border)

                        Button(action: {
                            if let url = URL(string: LegalUrls.support) {
                                openURL(url)
                            }
                        }) {
                            HStack {
                                Text(LanguageManager.t("settings.support"))
                                    .font(.system(size: 15))
                                    .foregroundColor(AppColors.text)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(AppColors.muted)
                            }
                            .padding(14)
                        }
                    }
                }
                .padding(.vertical, 16)
            }
            .background(AppColors.background)
            .navigationTitle(LanguageManager.t("settings.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AppColors.text.opacity(0.85))
                    }
                }
            }
            .sheet(isPresented: $showExportSheet) {
                ShareSheet(text: exportText)
            }
            .fileImporter(
                isPresented: $isShowingFileImporter,
                allowedContentTypes: [.commaSeparatedText, .plainText, UTType(filenameExtension: "csv") ?? .plainText],
                allowsMultipleSelection: false
            ) { result in
                handleFileImportResult(result)
            }
            .sheet(item: $importPreview) { preview in
                HistoryImportPreviewSheet(
                    preview: preview,
                    onConfirm: {
                        store.executeHistoryImport(preview)
                        importPreview = nil
                    },
                    onCancel: {
                        importPreview = nil
                    }
                )
            }
            .alert(
                "Import Error",
                isPresented: Binding(
                    get: { importErrorMessage != nil },
                    set: { if !$0 { importErrorMessage = nil } }
                ),
                actions: {
                    Button("OK") { importErrorMessage = nil }
                },
                message: {
                    Text(importErrorMessage ?? "")
                }
            )
            .sheet(isPresented: $showPaywall) {
                ProPaywallSheet(feature: nil, onDismiss: { showPaywall = false })
            }
        }
    }

    private func settingsSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(AppColors.muted)
                .padding(.horizontal, 20)

            VStack(spacing: 0) {
                content()
            }
            .background(AppColors.surface)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.border, lineWidth: 1))
            .padding(.horizontal, 20)
        }
    }

    private func exportBackup() {
        if let data = try? JSONEncoder().encode(store.state), let str = String(data: data, encoding: .utf8) {
            exportText = str
            showExportSheet = true
        }
    }

    private func handleFileImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else {
                importErrorMessage = "Could not access selected file."
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            do {
                let data = try Data(contentsOf: url)
                let csvText = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
                guard !csvText.isEmpty else {
                    importErrorMessage = "The selected file is empty or could not be read."
                    return
                }
                let preview = try store.previewHistoryImport(csvText: csvText)
                self.importPreview = preview
            } catch {
                importErrorMessage = error.localizedDescription
            }
        case .failure(let error):
            importErrorMessage = error.localizedDescription
        }
    }
}
