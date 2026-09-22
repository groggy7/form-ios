import SwiftUI
import UniformTypeIdentifiers

public struct SettingsView: View {
    @ObservedObject var store: AppStore
    @ObservedObject var langManager = LanguageManager.shared
    @ObservedObject private var proManager = ProAccessManager.shared
    var onDismiss: () -> Void

    @State private var showPaywall: Bool = false
    @State private var paywallFeature: ProFeature? = nil
    @State private var showCloudBackupSheet: Bool = false
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
                            if proManager.isProSubscribed {
                                Button(action: {
                                    if let url = URL(string: LegalUrls.manageSubscriptions) {
                                        openURL(url)
                                    }
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "arrow.up.right")
                                            .font(.system(size: 11, weight: .semibold))
                                        Text(LanguageManager.t("settings.manage_subscription"))
                                            .font(.system(size: 13, weight: .semibold))
                                    }
                                    .foregroundColor(AppColors.text)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 38)
                                    .background(AppColors.purple)
                                    .cornerRadius(10)
                                }
                                .buttonStyle(.plain)
                            } else {
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

                        if !proManager.isProSubscribed {
                            Button(action: {
                                if let url = URL(string: LegalUrls.manageSubscriptions) {
                                    openURL(url)
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Text(LanguageManager.t("settings.manage_subscription_store"))
                                        .font(.system(size: 12))
                                        .foregroundColor(AppColors.secondaryText)
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(AppColors.secondaryText)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 2)
                            }
                            .buttonStyle(.plain)
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
                            Button(action: {
                                if proManager.isProSubscribed {
                                    showCloudBackupSheet = true
                                } else {
                                    paywallFeature = .cloudBackup
                                    showPaywall = true
                                }
                            }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(LanguageManager.t("settings.cloudBackup"))
                                                .font(.system(size: 15))
                                                .foregroundColor(AppColors.text)
                                            if !proManager.isProSubscribed {
                                                ProBadge(text: "PRO")
                                            }
                                        }
                                        if proManager.isProSubscribed {
                                            let status = CloudMirrorManager.shared.getStatus()
                                            let lastSyncStr = status.lastSyncTimestamp.map { timestamp -> String in
                                                let df = DateFormatter()
                                                df.dateFormat = "HH:mm, dd MMM"
                                                return df.string(from: Date(timeIntervalSince1970: timestamp))
                                            }
                                            let syncLabel = lastSyncStr != nil ? LanguageManager.t("form_lab.mirror_last_synced", ["time": lastSyncStr!]) : LanguageManager.t("form_lab.mirror_never_synced")
                                            Text("\(status.providerName) · \(syncLabel)")
                                                .font(.system(size: 12))
                                                .foregroundColor(AppColors.secondaryText)
                                        } else {
                                            Text(LanguageManager.t("settings.cloudBackupSubtitle"))
                                                .font(.system(size: 12))
                                                .foregroundColor(AppColors.secondaryText)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(AppColors.muted)
                                }
                                .padding(14)
                            }

                            Divider().background(AppColors.border)

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
                            if let url = URL(string: LegalUrls.manageSubscriptions) {
                                openURL(url)
                            }
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(LanguageManager.t("settings.manage_subscription"))
                                        .font(.system(size: 15))
                                        .foregroundColor(AppColors.text)
                                    Text(LanguageManager.t("settings.manage_subscription_desc"))
                                        .font(.system(size: 12))
                                        .foregroundColor(AppColors.secondaryText)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(AppColors.muted)
                            }
                            .padding(14)
                        }

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
                ProPaywallSheet(feature: paywallFeature, onDismiss: {
                    showPaywall = false
                    paywallFeature = nil
                })
            }
            .sheet(isPresented: $showCloudBackupSheet) {
                CloudBackupSheet(store: store)
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

public struct CloudBackupSheet: View {
    @ObservedObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var isMirrorEnabled: Bool = CloudMirrorManager.shared.isEnabled
    @State private var syncStatusMessage: String? = nil
    @State private var syncIsError: Bool = false
    @State private var showRestoreConfirm: Bool = false
    @State private var lastSyncTime: Date? = CloudMirrorManager.shared.getStatus().lastSyncTimestamp.map { Date(timeIntervalSince1970: $0) }

    public init(store: AppStore) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Header Overview Card
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 10) {
                            Image(systemName: "icloud.fill")
                                .font(.system(size: 22))
                                .foregroundColor(AppColors.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(LanguageManager.t("settings.cloudBackup"))
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(AppColors.text)
                                Text(LanguageManager.t("settings.cloudBackupSubtitle"))
                                    .font(.system(size: 12))
                                    .foregroundColor(AppColors.secondaryText)
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppColors.surfaceRaised)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.border, lineWidth: 1))
                    .cornerRadius(16)

                    // Sync Status Card
                    VStack(spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(CloudMirrorManager.shared.isICloudAvailable ? "iCloud Drive" : "Local Mirror (No iCloud Drive)")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(AppColors.text)
                                if let syncTime = lastSyncTime {
                                    Text(LanguageManager.t("form_lab.mirror_last_synced", ["time": formatSyncTime(syncTime)]))
                                        .font(.system(size: 11))
                                        .foregroundColor(AppColors.muted)
                                } else {
                                    Text(LanguageManager.t("form_lab.mirror_never_synced"))
                                        .font(.system(size: 11))
                                        .foregroundColor(AppColors.muted)
                                }
                            }
                            Spacer()
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(isMirrorEnabled ? AppColors.accent : AppColors.muted)
                                    .frame(width: 8, height: 8)
                                Text(isMirrorEnabled ? "Active" : "Paused")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(isMirrorEnabled ? AppColors.accent : AppColors.muted)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(isMirrorEnabled ? AppColors.positiveBg : AppColors.surface)
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(isMirrorEnabled ? AppColors.accent.opacity(0.4) : AppColors.border, lineWidth: 1))
                        }

                        Divider().background(AppColors.border)

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(LanguageManager.t("form_lab.mirror_toggle"))
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(AppColors.text)
                                Text(LanguageManager.t("paywall.cloud_backup.benefit3_desc"))
                                    .font(.system(size: 11))
                                    .foregroundColor(AppColors.muted)
                            }
                            Spacer()
                            Toggle("", isOn: $isMirrorEnabled)
                                .labelsHidden()
                                .onChange(of: isMirrorEnabled) { val in
                                    CloudMirrorManager.shared.isEnabled = val
                                }
                        }
                    }
                    .padding(16)
                    .background(AppColors.surfaceRaised)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.border, lineWidth: 1))
                    .cornerRadius(16)

                    // Action Buttons
                    VStack(spacing: 10) {
                        Button(action: syncNow) {
                            HStack {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 14, weight: .bold))
                                Text(LanguageManager.t("form_lab.mirror_sync_now"))
                                    .font(.system(size: 14, weight: .bold))
                            }
                            .foregroundColor(AppColors.background)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(AppColors.accent)
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)

                        Button(action: { showRestoreConfirm = true }) {
                            HStack {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 13, weight: .medium))
                                Text(LanguageManager.t("form_lab.mirror_restore_cta"))
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .foregroundColor(AppColors.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(AppColors.surfaceRaised)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.border, lineWidth: 1))
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                    }

                    if let msg = syncStatusMessage {
                        HStack(spacing: 8) {
                            Image(systemName: syncIsError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                                .foregroundColor(syncIsError ? AppColors.danger : AppColors.accent)
                            Text(msg)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(AppColors.text)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(syncIsError ? AppColors.avoidBg : AppColors.positiveBg)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(syncIsError ? AppColors.danger : AppColors.accent, lineWidth: 1))
                        .cornerRadius(10)
                    }

                    // Zero-Tracking Privacy Note
                    VStack(alignment: .leading, spacing: 4) {
                        Text(LanguageManager.t("paywall.cloud_backup.benefit2"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AppColors.text)
                        Text(LanguageManager.t("paywall.cloud_backup.benefit2_desc"))
                            .font(.system(size: 11))
                            .lineSpacing(2)
                            .foregroundColor(AppColors.secondaryText)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppColors.surfaceRaised)
                    .cornerRadius(12)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle(LanguageManager.t("settings.cloudBackup"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(LanguageManager.t("modal.done")) {
                        dismiss()
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppColors.accent)
                }
            }
            .alert(LanguageManager.t("form_lab.mirror_restore_confirm"), isPresented: $showRestoreConfirm) {
                Button(LanguageManager.t("form_lab.restore_btn"), role: .destructive) {
                    restoreFromMirror()
                }
                Button(LanguageManager.t("table.deleteSet"), role: .cancel) {}
            } message: {
                Text(LanguageManager.t("form_lab.mirror_restore_warning"))
            }
        }
    }

    private func syncNow() {
        let json = store.exportBackupJson()
        do {
            _ = try CloudMirrorManager.shared.syncNow(backupJson: json)
            lastSyncTime = Date()
            syncIsError = false
            syncStatusMessage = LanguageManager.t("form_lab.mirror_success")
        } catch {
            syncIsError = true
            syncStatusMessage = "Sync failed: \(error.localizedDescription)"
        }
    }

    private func restoreFromMirror() {
        do {
            let json = try CloudMirrorManager.shared.readLatestSnapshot()
            store.restoreBackupJson(json)
            syncIsError = false
            syncStatusMessage = LanguageManager.t("notice.backupRestored")
        } catch {
            syncIsError = true
            syncStatusMessage = "Restore failed: \(error.localizedDescription)"
        }
    }

    private func formatSyncTime(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "HH:mm, dd MMM"
        return df.string(from: date)
    }
}
