import SwiftUI

public struct SettingsView: View {
    @ObservedObject var store: AppStore
    @ObservedObject var langManager = LanguageManager.shared
    var onDismiss: () -> Void

    @State private var showExportSheet: Bool = false
    @State private var exportText: String = ""

    public init(store: AppStore, onDismiss: @escaping () -> Void) {
        self.store = store
        self.onDismiss = onDismiss
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Training section
                    settingsSection(title: LanguageManager.t("settings.training")) {
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

                    // Data Management
                    settingsSection(title: LanguageManager.t("settings.dataManagement")) {
                        VStack(spacing: 0) {
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
                    VStack(alignment: .leading, spacing: 4) {
                        Text(LanguageManager.t("settings.about"))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(AppColors.muted)
                        Text(LanguageManager.t("settings.version"))
                            .font(.system(size: 13))
                            .foregroundColor(AppColors.secondaryText)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                }
                .padding(.vertical, 16)
            }
            .background(AppColors.background)
            .navigationTitle(LanguageManager.t("settings.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(AppColors.muted)
                    }
                }
            }
            .sheet(isPresented: $showExportSheet) {
                ShareSheet(text: exportText)
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
}
