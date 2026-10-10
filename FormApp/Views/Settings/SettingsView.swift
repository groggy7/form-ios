import SwiftUI
import UniformTypeIdentifiers

public struct SettingsView: View {
    @ObservedObject var store: AppStore
    @ObservedObject var langManager = LanguageManager.shared
    @ObservedObject private var proManager = ProAccessManager.shared
    @ObservedObject private var cloudMirror = CloudMirrorManager.shared
    var onDismiss: () -> Void

    @State private var showPaywall: Bool = false
    @State private var paywallFeature: ProFeature? = nil
    @State private var showCloudBackupSheet: Bool = false
    @State private var showLanguageSheet: Bool = false
    @Environment(\.openURL) private var openURL
    @State private var showImportExportSheet: Bool = false

    public init(store: AppStore, onDismiss: @escaping () -> Void) {
        self.store = store
        self.onDismiss = onDismiss
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Forced Rep Premium Membership Card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(proManager.isProSubscribed ? AppColors.purple : AppColors.accent)
                            Text(LanguageManager.t("settings.pro_membership"))
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(AppColors.text)
                        }

                        Text(LanguageManager.t(proManager.isProSubscribed ? "settings.pro_active" : "pro.volume_matrix.description"))
                            .font(.system(size: 12.5))
                            .foregroundColor(AppColors.secondaryText)
                            .lineSpacing(2)

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
                    }
                    .padding(16)
                    .background(proManager.isProSubscribed ? AppColors.purpleBg : AppColors.surfaceRaised)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(proManager.isProSubscribed ? AppColors.purple.opacity(0.5) : AppColors.border, lineWidth: 1)
                    )
                    .cornerRadius(16)
                    .padding(.horizontal, 20)

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

                            Divider().background(AppColors.border)

                            SettingsPremiumToggle(
                                titleKey: "settings.showProgressionTargets",
                                subtitleKey: "settings.showProgressionTargetsSubtitle",
                                preference: $store.showProgressionTargets,
                                isUnlocked: proManager.isProSubscribed,
                                identifier: "toggle-progression-targets"
                            )

                            Divider().background(AppColors.border)

                            SettingsPremiumToggle(
                                titleKey: "settings.showWarmupCalculator",
                                subtitleKey: "settings.showWarmupCalculatorSubtitle",
                                preference: $store.showWarmupCalculator,
                                isUnlocked: proManager.isProSubscribed,
                                identifier: "toggle-warmup-calculator"
                            )
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

                    SettingsLanguageRow(value: languagePreferenceLabel, flagImageName: activeLanguageFlagImage) {
                        showLanguageSheet = true
                    }
                    .padding(.horizontal, 20)

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
                                showCloudBackupSheet = true
                            }) {
                                HStack(spacing: 12) {
                                    Image(systemName: "icloud.fill")
                                        .font(.system(size: 18))
                                        .foregroundColor(AppColors.secondaryText)
                                        .frame(width: 24, height: 24)
                                    Text(LanguageManager.t("settings.cloudBackup"))
                                        .font(.system(size: 15))
                                        .foregroundColor(AppColors.text)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(AppColors.muted)
                                }
                                .padding(14)
                            }
                            .accessibilityIdentifier("settings-cloud-backup-row")

                            Divider().background(AppColors.border)

                            Button(action: {
                                showImportExportSheet = true
                            }) {
                                HStack(spacing: 12) {
                                    Image(systemName: "arrow.left.arrow.right")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(AppColors.secondaryText)
                                        .frame(width: 24, height: 24)
                                    Text(LanguageManager.t("settings.importExportData"))
                                        .font(.system(size: 15))
                                        .foregroundColor(AppColors.text)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(AppColors.muted)
                                }
                                .padding(14)
                            }
                            .accessibilityIdentifier("settings-import-export-row")
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

                        if proManager.isProSubscribed {
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
                                            .multilineTextAlignment(.leading)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(AppColors.muted)
                                }
                                .padding(14)
                            }
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
                .presentationCornerRadius(28)
                .presentationBackground(AppColors.background)
            }
            .sheet(isPresented: $showImportExportSheet) {
                ImportExportDataSheet(store: store, onDismiss: {
                    showImportExportSheet = false
                })
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
                .presentationBackground(AppColors.background)
            }
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

    private var deviceLanguageName: String {
        let code = LanguageManager.resolveLanguage(Locale.preferredLanguages)
        return LanguageManager.supportedLanguages.first { $0.code == code }?.name ?? "English"
    }

    private var languagePreferenceLabel: String {
        if langManager.languagePreference == LanguageManager.system {
            return deviceLanguageName
        }
        return LanguageManager.supportedLanguages.first { $0.code == langManager.languagePreference }?.name ?? "English"
    }

    private var activeLanguageCode: String {
        if langManager.languagePreference == LanguageManager.system {
            return LanguageManager.resolveLanguage(Locale.preferredLanguages)
        }
        return langManager.languagePreference
    }

    private var activeLanguageFlagImage: String {
        LanguageManager.flagImageName(for: activeLanguageCode)
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
}

struct SettingsPremiumToggle: View {
    let titleKey: String
    let subtitleKey: String
    @Binding var preference: Bool
    let isUnlocked: Bool
    let identifier: String

    // Locked switches show the default on state without changing the saved preference.
    var selection: Binding<Bool> {
        Binding(get: { !isUnlocked || preference }, set: { value in
            if isUnlocked { preference = value }
        })
    }

    private var title: Text {
        if isUnlocked { return Text(LanguageManager.t(titleKey)) }
        return Text(LanguageManager.t(titleKey)) + Text(" ")
            + Text(Image(systemName: "lock.fill")).font(.system(size: 11))
    }

    var body: some View {
        Toggle(isOn: selection) {
            VStack(alignment: .leading, spacing: 2) {
                title
                    .font(.system(size: 15))
                    .foregroundColor(isUnlocked ? AppColors.text : AppColors.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(LanguageManager.t(titleKey))
                Text(LanguageManager.t(subtitleKey))
                    .font(.system(size: 12))
                    .foregroundColor(isUnlocked ? AppColors.secondaryText : AppColors.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .tint(isUnlocked ? AppColors.accent : AppColors.accent.opacity(0.35))
        .disabled(!isUnlocked)
        .padding(14)
        .accessibilityHint(isUnlocked ? "" : LanguageManager.t("pro.premium_required"))
        .accessibilityIdentifier(identifier)
    }
}

// A single preference row keeps every supported language out of the main settings layout.
struct SettingsLanguageRow: View {
    let value: String
    var flagImageName: String? = nil
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                let resolvedFlag = flagImageName ?? LanguageManager.flagImageName(for: LanguageManager.shared.currentLanguage)
                Image(resolvedFlag)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(AppColors.border.opacity(0.6), lineWidth: 1)
                    )
                Text(LanguageManager.t("settings.language"))
                    .font(.body.weight(.medium))
                    .foregroundColor(AppColors.text)
                Spacer()
                Text(value)
                    .font(.subheadline)
                    .foregroundColor(AppColors.secondaryText)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppColors.muted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(minHeight: 64)
            .background(AppColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.border, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(LanguageManager.t("settings.language") + ", " + value)
        .accessibilityValue(value)
        .accessibilityIdentifier("settings-language-row")
    }
}

struct LanguageSelectionSheet: View {
    let preference: String
    let deviceLanguageName: String
    var onSelect: (String) -> Void
    var onDismiss: () -> Void

    private var deviceLanguageFlagImage: String {
        let code = LanguageManager.resolveLanguage(Locale.preferredLanguages)
        return LanguageManager.flagImageName(for: code)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(LanguageManager.t("settings.language"))
                    .font(.title2.weight(.semibold))
                    .foregroundColor(AppColors.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppColors.secondaryText)
                        .frame(width: 48, height: 48)
                        .background(AppColors.surfaceRaised, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(LanguageManager.t("common.close"))
                .accessibilityIdentifier("language-picker-close")
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 16)

            ScrollView {
                VStack(spacing: 12) {
                    languageOption(code: LanguageManager.system,
                        title: LanguageManager.t("settings.deviceLanguage"), subtitle: deviceLanguageName,
                        flagImageName: deviceLanguageFlagImage)
                        .background(AppColors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.border, lineWidth: 1))

                    VStack(spacing: 0) {
                        ForEach(Array(LanguageManager.supportedLanguages.enumerated()), id: \.element.code) { index, language in
                            if index > 0 {
                                Rectangle().fill(AppColors.border).frame(height: 1).padding(.horizontal, 16)
                            }
                            languageOption(code: language.code, title: language.name,
                                flagImageName: LanguageManager.flagImageName(for: language.code))
                        }
                    }
                    .background(AppColors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.border, lineWidth: 1))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .background(AppColors.background)
        .accessibilityIdentifier("language-picker-sheet")
    }

    private func languageOption(code: String, title: String, subtitle: String? = nil, flagImageName: String) -> some View {
        let selected = preference == code
        return Button { onSelect(code) } label: {
            HStack(spacing: 14) {
                Image(flagImageName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(AppColors.border.opacity(0.6), lineWidth: 1)
                    )
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.body.weight(selected ? .semibold : .medium))
                        .foregroundColor(AppColors.text)
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle {
                        Text(subtitle).font(.subheadline).foregroundColor(AppColors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundColor(selected ? AppColors.accent : AppColors.border)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(minHeight: 54)
            .background(selected ? AppColors.positiveBg.opacity(0.5) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("language-option-\(code)")
    }
}

struct ImportExportDataSheet: View {
    @ObservedObject var store: AppStore
    var onDismiss: () -> Void

    @State private var showExportSheet: Bool = false
    @State private var exportText: String = ""
    @State private var isShowingBackupImporter: Bool = false
    @State private var backupToRestore: String? = nil
    @State private var showRestoreBackupAlert: Bool = false
    @State private var importErrorMessage: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Header Row
            HStack(spacing: 12) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(AppColors.purpleBg)
                            .frame(width: 36, height: 36)
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(AppColors.purple)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(LanguageManager.t("settings.importExportData"))
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(AppColors.text)
                        Text(LanguageManager.t("settings.importExportSubtitle"))
                            .font(.system(size: 12))
                            .foregroundColor(AppColors.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppColors.secondaryText)
                        .frame(width: 36, height: 36)
                        .background(AppColors.surfaceRaised, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(LanguageManager.t("common.close"))
                .accessibilityIdentifier("import-export-close")
            }
            .padding(.horizontal, 20)
            .padding(.top, 30)
            .padding(.bottom, 20)

            ScrollView {
                VStack(spacing: 16) {
                    // Export Data Card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(AppColors.accent)
                            Text(LanguageManager.t("settings.exportData"))
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(AppColors.text)
                        }

                        Text(LanguageManager.t("settings.exportDataDesc"))
                            .font(.system(size: 12))
                            .foregroundColor(AppColors.secondaryText)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)

                        Button(action: {
                            exportText = store.exportBackupJson()
                            showExportSheet = true
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 15, weight: .bold))
                                Text(LanguageManager.t("settings.exportData"))
                                    .font(.system(size: 13, weight: .bold))
                            }
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(AppColors.accent)
                            .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("export-data-button")
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppColors.surfaceRaised)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.border, lineWidth: 1))
                    .cornerRadius(16)

                    // Import Data Card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.down")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(AppColors.purple)
                            Text(LanguageManager.t("settings.importData"))
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(AppColors.text)
                        }

                        Text(LanguageManager.t("settings.importDataDesc"))
                            .font(.system(size: 12))
                            .foregroundColor(AppColors.secondaryText)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)

                        Button(action: {
                            isShowingBackupImporter = true
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "square.and.arrow.down")
                                    .font(.system(size: 15, weight: .semibold))
                                Text(LanguageManager.t("settings.importData"))
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundColor(AppColors.text)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(AppColors.surface)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppColors.border, lineWidth: 1))
                            .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("import-data-button")
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppColors.surfaceRaised)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.border, lineWidth: 1))
                    .cornerRadius(16)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 36)
            }
        }
        .background(AppColors.background.ignoresSafeArea())
        .accessibilityIdentifier("import-export-data-sheet")
        .sheet(isPresented: $showExportSheet) {
            ShareSheet(text: exportText)
        }
        .fileImporter(
            isPresented: $isShowingBackupImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                guard url.startAccessingSecurityScopedResource() else {
                    importErrorMessage = "Could not access selected backup file."
                    return
                }
                defer { url.stopAccessingSecurityScopedResource() }
                do {
                    let data = try Data(contentsOf: url)
                    if let jsonString = String(data: data, encoding: .utf8) {
                        backupToRestore = jsonString
                        showRestoreBackupAlert = true
                    } else {
                        importErrorMessage = "The selected backup file is not valid UTF-8 text."
                    }
                } catch {
                    importErrorMessage = LanguageManager.t("errors.fileRead")
                }
            case .failure:
                importErrorMessage = LanguageManager.t("errors.fileRead")
            }
        }
        .alert(
            LanguageManager.t("form_lab.mirror_restore_confirm"),
            isPresented: $showRestoreBackupAlert,
            actions: {
                Button(LanguageManager.t("settings.restoreBackup"), role: .destructive) {
                    if let json = backupToRestore {
                        let success = store.restoreBackupJson(json)
                        if success {
                            store.noticeMessage = LanguageManager.t("notice.backupRestored")
                            onDismiss()
                        } else {
                            importErrorMessage = LanguageManager.t("notice.restoreFailed")
                        }
                        backupToRestore = nil
                    }
                }
                Button(LanguageManager.t("modal.cancel"), role: .cancel) {
                    backupToRestore = nil
                }
            },
            message: {
                Text(LanguageManager.t("form_lab.mirror_restore_warning"))
            }
        )
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
    }
}

public struct CloudBackupSheet: View {
    @ObservedObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var mirrorManager: CloudMirrorManager
    @ObservedObject private var proManager = ProAccessManager.shared
    @ObservedObject private var langManager = LanguageManager.shared
    @State private var showPaywall = false
    @State private var isWorking = false
    @State private var isRestoring = false
    @State private var operationTask: Task<Void, Never>?
    private var isMirrorEnabled: Bool { mirrorManager.isEnabled }
    @State private var syncStatusMessage: String? = nil
    @State private var syncIsError: Bool = false
    private enum BackupAlert: Equatable {
        case restore
        case firstUpload(Data)
    }
    @State private var activeAlert: BackupAlert?

    private var mirrorStatus: CloudMirrorStatus {
        mirrorManager.status
    }

    private var isBadgeActive: Bool {
        isMirrorEnabled && mirrorStatus.isCloudConnected && !mirrorStatus.isUploadPending && mirrorStatus.errorMessage == nil && mirrorStatus.lastSyncTimestamp != nil
    }

    private var badgeLabel: String {
        let key: String
        if mirrorStatus.isCheckingCloud { key = "form_lab.mirror_checking" }
        else if mirrorStatus.errorMessage != nil { key = "form_lab.mirror_error" }
        else if !isMirrorEnabled { key = "form_lab.mirror_paused" }
        else if !mirrorStatus.isCloudConnected { key = "form_lab.mirror_local_only" }
        else if mirrorStatus.isUploadPending { key = "form_lab.mirror_pending" }
        else { key = mirrorStatus.lastSyncTimestamp == nil ? "form_lab.mirror_ready" : "form_lab.mirror_active" }
        return LanguageManager.t(key)
    }

    private var syncSubtitleText: String {
        if mirrorStatus.isCheckingCloud { return LanguageManager.t("form_lab.mirror_checking") }
        if let error = mirrorStatus.errorMessage { return error }
        if mirrorStatus.isUploadPending { return LanguageManager.t("form_lab.mirror_upload_pending") }
        if let timestamp = mirrorStatus.lastSyncTimestamp {
            return LanguageManager.t("form_lab.mirror_last_synced", ["time": formatSyncTime(Date(timeIntervalSince1970: timestamp))])
        }
        return LanguageManager.t(mirrorStatus.isCloudConnected ? "form_lab.mirror_never_synced" : "form_lab.mirror_local_help")
    }

    public init(store: AppStore) {
        self.store = store
        self.mirrorManager = .shared
    }

    init(store: AppStore, mirrorManager: CloudMirrorManager) {
        self.store = store
        self.mirrorManager = mirrorManager
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
                                Text(LanguageManager.t(proManager.isFeatureUnlocked(.cloudBackup) ? "settings.cloudBackupSubtitle" : "form_lab.mirror_free_restore"))
                                    .font(.system(size: 12))
                                    .foregroundColor(AppColors.secondaryText)
                                    .multilineTextAlignment(.leading)
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
                                Text(mirrorStatus.isCloudConnected ? "iCloud Drive" : LanguageManager.t("form_lab.mirror_local_provider"))
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(AppColors.text)
                                Text(syncSubtitleText)
                                    .font(.system(size: 11))
                                    .foregroundColor(AppColors.muted)
                            }
                            Spacer()
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(isBadgeActive ? AppColors.accent : AppColors.muted)
                                    .frame(width: 8, height: 8)
                                Text(badgeLabel)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(isBadgeActive ? AppColors.accent : AppColors.muted)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(isBadgeActive ? AppColors.positiveBg : AppColors.surface)
                            .cornerRadius(8)
                            .fixedSize(horizontal: true, vertical: false)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(isBadgeActive ? AppColors.accent.opacity(0.4) : AppColors.border, lineWidth: 1))
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
                            Toggle("", isOn: Binding(get: { isMirrorEnabled }, set: { value in
                                if proManager.isFeatureUnlocked(.cloudBackup) {
                                    mirrorManager.isEnabled = value
                                } else {
                                    showPaywall = true
                                }
                            }))
                                .labelsHidden()
                                .disabled(isWorking)
                                .accessibilityIdentifier("cloud-backup-toggle")
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
                                if isWorking && !isRestoring { ProgressView().tint(AppColors.background) }
                                else { Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 14, weight: .bold)) }
                                Text(LanguageManager.t(isWorking && !isRestoring ? "form_lab.mirror_syncing" : "form_lab.mirror_sync_now"))
                                    .font(.system(size: 14, weight: .bold))
                            }
                            .foregroundColor(AppColors.background)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(AppColors.accent)
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                        .disabled(isWorking || (proManager.isFeatureUnlocked(.cloudBackup) && !isMirrorEnabled))
                        .accessibilityIdentifier("cloud-backup-sync")

                        Button(action: { activeAlert = .restore }) {
                            HStack {
                                if isRestoring { ProgressView().tint(AppColors.accent) }
                                else { Image(systemName: "arrow.counterclockwise").font(.system(size: 13, weight: .medium)) }
                                Text(LanguageManager.t(isRestoring ? "form_lab.mirror_restoring" : "form_lab.mirror_restore_cta"))
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
                        .disabled(isWorking)
                        .accessibilityIdentifier("cloud-backup-restore")
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
                    Button(LanguageManager.t("common.done")) {
                        dismiss()
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppColors.accent)
                }
            }
            .onAppear { mirrorManager.refreshUbiquityURL(); presentFirstUploadConfirmationIfReady() }
            .onChange(of: mirrorManager.status.needsFirstUploadConfirmation) { _, needed in
                if needed { presentFirstUploadConfirmationIfReady() }
                else if case .firstUpload = activeAlert { activeAlert = nil }
            }
            .onChange(of: isWorking) { _, working in
                if !working { presentFirstUploadConfirmationIfReady() }
            }
            .onChange(of: activeAlert) { _, alert in
                if alert == nil {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        presentFirstUploadConfirmationIfReady()
                    }
                }
            }
            .onChange(of: langManager.currentLanguage) { _, _ in mirrorManager.refreshStatus() }
            .onChange(of: mirrorManager.status) { _, status in
                let isWaitingMessage = syncStatusMessage == LanguageManager.t("form_lab.mirror_upload_pending") || syncStatusMessage == LanguageManager.t("form_lab.mirror_local_saved")
                if !isWorking && !syncIsError && isWaitingMessage && status.isCloudConnected && !status.isUploadPending && status.lastSyncTimestamp != nil && status.errorMessage == nil {
                    syncStatusMessage = LanguageManager.t("form_lab.mirror_success")
                }
            }
            .task(id: syncStatusMessage) {
                guard let message = syncStatusMessage else { return }
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                if !Task.isCancelled && syncStatusMessage == message { syncStatusMessage = nil }
            }
            .onDisappear { operationTask?.cancel() }
            .sheet(isPresented: $showPaywall) { ProPaywallSheet(feature: .cloudBackup) }
            .alert(alertTitle, isPresented: Binding(get: { activeAlert != nil }, set: { if !$0 { activeAlert = nil } }), presenting: activeAlert) { alert in
                switch alert {
                case .restore:
                    Button(LanguageManager.t("form_lab.restore_btn"), role: .destructive) { restoreFromMirror() }
                    Button(LanguageManager.t("modal.cancel"), role: .cancel) {}
                case .firstUpload(let identity):
                    Button(LanguageManager.t("common.done")) { mirrorManager.acknowledgeFirstUploadConfirmation(identity: identity) }
                }
            } message: { alert in
                switch alert {
                case .restore:
                    Text(LanguageManager.t("form_lab.mirror_restore_warning"))
                case .firstUpload:
                    Text(LanguageManager.t("form_lab.mirror_first_upload_message", ["file": CloudMirrorManager.backupFileName]))
                }
            }
        }
    }

    private var alertTitle: String {
        LanguageManager.t(activeAlert == .restore ? "form_lab.mirror_restore_confirm" : "form_lab.mirror_first_upload_title")
    }

    private func presentFirstUploadConfirmationIfReady() {
        guard activeAlert == nil, !isWorking,
              let identity = mirrorManager.firstUploadConfirmationIdentity() else { return }
        activeAlert = .firstUpload(identity)
    }

    private func syncNow() {
        guard proManager.isFeatureUnlocked(.cloudBackup) else { showPaywall = true; return }
        guard !isWorking else { return }
        let json = store.exportBackupJson()
        isWorking = true
        syncStatusMessage = nil
        operationTask = Task { @MainActor in
            defer { isWorking = false }
            do {
                _ = try await mirrorManager.syncNowAsync(backupJson: json)
                let status = mirrorManager.getStatus()
                syncIsError = false
                syncStatusMessage = LanguageManager.t(!status.isCloudConnected ? "form_lab.mirror_local_saved" : status.isUploadPending || status.lastSyncTimestamp == nil ? "form_lab.mirror_upload_pending" : "form_lab.mirror_success")
            } catch {
                syncIsError = true
                syncStatusMessage = LanguageManager.t("form_lab.mirror_sync_failed", ["error": error.localizedDescription])
            }
        }
    }

    private func restoreFromMirror() {
        guard !isWorking else { return }
        isWorking = true
        isRestoring = true
        syncStatusMessage = nil
        operationTask = Task { @MainActor in
            defer { isWorking = false; isRestoring = false }
            do {
                let json = try await mirrorManager.readLatestSnapshotAsync()
                try Task.checkCancellation()
                let success = store.restoreBackupJson(json)
                if success { mirrorManager.didRestoreSnapshot() }
                syncIsError = !success
                syncStatusMessage = LanguageManager.t(success ? "notice.backupRestored" : "notice.restoreFailed")
            } catch is CancellationError {
                return
            } catch {
                syncIsError = true
                syncStatusMessage = LanguageManager.t("form_lab.mirror_restore_failed", ["error": error.localizedDescription])
            }
        }
    }

    private func formatSyncTime(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "HH:mm, dd MMM"
        return df.string(from: date)
    }
}
