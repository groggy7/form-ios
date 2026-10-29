import SwiftUI

/// The Strong/Hevy import preview (gym/docs/history-import.md#preview). Nothing is saved until Import.
struct HistoryImportPreviewSheet: View {
    @ObservedObject var themeManager = ThemeManager.shared
    let plan: HistoryImportPlan
    let fileName: String
    let importing: Bool
    var onChooseUnit: (WeightUnit) -> Void
    var onIncludeOverlaps: (Bool) -> Void
    var onImport: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        let _ = themeManager.currentTheme
        let file = plan.file
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(AppColors.purpleBg).frame(width: 36, height: 36)
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppColors.purple)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(LanguageManager.t("import.history.title"))
                        .font(.app(size: 17, weight: .bold))
                        .foregroundStyle(AppColors.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(LanguageManager.t("import.preview.subtitle", ["source": file.source.displayName, "file": fileName]))
                        .font(.app(size: 12))
                        .foregroundStyle(AppColors.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                FormCloseButton(action: onDismiss)
                    .disabled(importing)
                    .accessibilityIdentifier("history-import-close")
            }
            .padding(.horizontal, 20)
            .padding(.top, 30)
            .padding(.bottom, 20)

            ScrollView {
                VStack(spacing: 16) {
                    card {
                        Text(LanguageManager.shared.plural("import.preview.newWorkouts", plan.records.count))
                            .font(.app(size: 22, weight: .bold))
                            .foregroundStyle(AppColors.text)
                            .accessibilityIdentifier("history-import-new-count")
                        if let first = plan.firstDate, let last = plan.lastDate {
                            Text(first == last ? date(first) : LanguageManager.t("import.preview.dateRange", ["first": date(first), "last": date(last)]))
                                .font(.app(size: 13))
                                .foregroundStyle(AppColors.secondaryText)
                        }
                        if !plan.records.isEmpty {
                            countRow("import.preview.workingSets", plan.workingSets)
                            countRow("import.preview.warmupSets", plan.warmupSets)
                            countRow("import.preview.libraryExercises", plan.libraryExercises)
                            countRow("import.preview.customExercises", plan.customExercises)
                            let noteCount = plan.records.reduce(0) { count, record in
                                count + ((record.note ?? "").isEmpty ? 0 : 1) + record.exerciseLogs.filter { !($0.setupNote ?? "").isEmpty }.count
                            }
                            if noteCount > 0 { countRow("notes.preserved", noteCount) }
                        } else if !plan.needsUnit && plan.overlapping == 0 && plan.problems.isEmpty {
                            Text(LanguageManager.t("import.preview.noneNew"))
                                .font(.app(size: 13))
                                .foregroundStyle(AppColors.secondaryText)
                        }
                    }

                    card {
                        if let unit = file.fileUnit {
                            note(LanguageManager.t("import.preview.unitFromFile", ["unit": unit.label]))
                        } else {
                            Text(LanguageManager.t("import.preview.unitQuestion", ["source": file.source.displayName]))
                                .font(.app(size: 13))
                                .foregroundStyle(AppColors.text)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: 8) {
                                ForEach(WeightUnit.allCases, id: \.self) { unit in
                                    unitChoice(unit)
                                }
                            }
                        }
                        note(LanguageManager.t("import.preview.timeZone", ["zone": file.zone.identifier]))
                    }

                    if plan.alreadyImported + file.repeatedInFile + plan.overlapping > 0 {
                        card {
                            sectionTitle("import.preview.skipped")
                            if plan.alreadyImported > 0 { countRow("import.preview.alreadyImported", plan.alreadyImported) }
                            if file.repeatedInFile > 0 { countRow("import.preview.repeatedInFile", file.repeatedInFile) }
                            if plan.overlapping > 0 {
                                countRow("import.preview.overlapping", plan.overlapping)
                                Text(LanguageManager.t("import.preview.overlappingHint"))
                                    .font(.app(size: 12))
                                    .foregroundStyle(AppColors.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                                Toggle(isOn: Binding(get: { plan.includeOverlaps }, set: onIncludeOverlaps)) {
                                    Text(LanguageManager.t("import.preview.includeOverlaps"))
                                        .font(.app(size: 14))
                                        .foregroundStyle(AppColors.text)
                                }
                                .tint(AppColors.accent)
                                .frame(minHeight: 48)
                                .disabled(importing)
                                .accessibilityIdentifier("history-import-include-overlaps")
                            }
                        }
                    }

                    if plan.dropsAttached + plan.dropsSeparate > 0 {
                        card {
                            sectionTitle("import.preview.drops")
                            if plan.dropsAttached > 0 { countRow("import.preview.dropsAttached", plan.dropsAttached) }
                            if plan.dropsSeparate > 0 { countRow("import.preview.dropsSeparate", plan.dropsSeparate) }
                        }
                    }

                    let omitted = [
                        ("import.preview.timedSets", file.timedSets),
                        ("import.preview.distanceSets", file.distanceSets),
                        ("import.preview.setsWithoutReps", file.setsWithoutReps),
                        ("import.preview.rpeValues", file.rpeValues),
                        ("import.preview.supersetLinks", file.supersetLinks),
                        ("import.preview.nothingToImport", file.nothingToImport)
                    ].filter { $0.1 > 0 }
                    if !omitted.isEmpty {
                        card {
                            sectionTitle("import.preview.notImported")
                            ForEach(omitted, id: \.0) { key, count in countRow(key, count) }
                        }
                        .accessibilityIdentifier("history-import-not-imported")
                    }

                    if let room = plan.roomLeft {
                        Text(LanguageManager.t("import.preview.historyFull", ["count": room]))
                            .font(.app(size: 13))
                            .foregroundStyle(AppColors.danger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    ForEach(Array(plan.problems.enumerated()), id: \.offset) { _, problem in
                        Text(historyImportProblemText(problem))
                            .font(.app(size: 13))
                            .foregroundStyle(AppColors.danger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button(action: onImport) {
                        HStack(spacing: 8) {
                            if importing {
                                ProgressView().tint(AppColors.background)
                                Text(LanguageManager.t("import.preview.importing"))
                            } else {
                                Text(LanguageManager.shared.plural("import.preview.importButton", plan.records.count))
                            }
                        }
                        .font(.app(size: 15, weight: .bold))
                        .foregroundStyle(AppColors.background)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(AppColors.accent.opacity(plan.canImport ? 1 : 0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .disabled(!plan.canImport || importing)
                    .accessibilityIdentifier("history-import-confirm")

                    Button(action: onDismiss) {
                        Text(LanguageManager.t("modal.cancel"))
                            .font(.app(size: 15, weight: .semibold))
                            .foregroundStyle(AppColors.text)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(importing)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 36)
            }
        }
        .background(AppColors.background.ignoresSafeArea())
        .interactiveDismissDisabled(importing)
        .accessibilityIdentifier("history-import-sheet")
    }

    private func date(_ value: String) -> String {
        guard let day = WorkoutCalendar.parseDate(value) else { return value }
        let formatter = DateFormatter()
        formatter.locale = LanguageManager.locale
        formatter.dateStyle = .medium
        return formatter.string(from: day)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8, content: content)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.surfaceRaised)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func sectionTitle(_ key: String) -> some View {
        Text(LanguageManager.t(key))
            .font(.app(size: 15, weight: .bold))
            .foregroundStyle(AppColors.text)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.app(size: 13))
            .foregroundStyle(AppColors.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func countRow(_ key: String, _ count: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(LanguageManager.t(key))
                .font(.app(size: 13))
                .foregroundStyle(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            Text(count.formatted(.number.locale(LanguageManager.numberLocale)))
                .font(.app(size: 13, weight: .semibold))
                .foregroundStyle(AppColors.text)
        }
    }

    private func unitChoice(_ unit: WeightUnit) -> some View {
        let selected = plan.unit == unit
        return Button { onChooseUnit(unit) } label: {
            Text(unit.label)
                .font(.app(size: 14, weight: .semibold))
                .foregroundStyle(selected ? AppColors.accent : AppColors.text)
                .frame(minWidth: 72, minHeight: 48)
                .padding(.horizontal, 8)
                .background(selected ? AppColors.accent.opacity(0.14) : AppColors.surface)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? AppColors.accent : AppColors.border, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(importing)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("history-import-unit-\(unit.rawValue)")
    }
}

/// The message for one problem, with its line when it has one.
func historyImportProblemText(_ problem: HistoryImportProblem) -> String {
    let message = LanguageManager.t("import.error.\(problem.code)", ["value": problem.detail])
    return problem.line > 0 ? LanguageManager.t("import.error.line", ["line": problem.line, "message": message]) : message
}
