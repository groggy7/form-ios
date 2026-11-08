import SwiftUI

struct TrainingSetupView: View {
    @ObservedObject var store: AppStore
    @ObservedObject private var language = LanguageManager.shared
    @ObservedObject private var theme = ThemeManager.shared
    let completeSetup: Bool
    var onClose: () -> Void
    var onSkip: (() -> Void)?
    @State private var profile: TrainingProfile
    @State private var step: Int
    @State private var programID: String
    @State private var editedProgram: Program?
    @State private var search = ""
    @State private var error: String?
    @State private var editing = false
    @State private var gymEquipmentOpen: Bool
    @State private var expandedDays: Set<String> = []
    @State private var advancedSearch = false
    @State private var moreDurations: Bool
    @ScaledMetric(relativeTo: .caption) private var tileLabelHeight: CGFloat = 48
    @ScaledMetric(relativeTo: .caption) private var minimumTileWidth: CGFloat = 110
    @ScaledMetric(relativeTo: .caption) private var minimumPriorityWidth: CGFloat = 136
    @ScaledMetric(relativeTo: .caption) private var priorityFontSize: CGFloat = 13
    @ScaledMetric(relativeTo: .subheadline) private var minimumWeekdayWidth: CGFloat = 64
    @ScaledMetric(relativeTo: .caption2) private var reviewBadgeSize: CGFloat = 50
    @ScaledMetric(relativeTo: .caption2) private var reviewWeekdayFontSize: CGFloat = 11
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var equipmentWidth: CGFloat = 0
    @State private var priorityWidth: CGFloat = 0
    @State private var weekdayWidth: CGFloat = 0

    init(store: AppStore, completeSetup: Bool = true, onClose: @escaping () -> Void, onSkip: (() -> Void)? = nil) {
        self.store = store; self.completeSetup = completeSetup; self.onClose = onClose; self.onSkip = onSkip
        let draft = completeSetup ? nil : TrainingSetupStore.draft()
        var initial = TrainingProfile()
        initial.equipment = TrainingCatalog.bundled?.presets["commercial_gym"] ?? []
        var starting = draft?.profile ?? (completeSetup ? nil : TrainingSetupStore.profile()) ?? initial
        starting.excludedExerciseIds = []
        // The former confidence flag now follows experience during setup, including restored drafts.
        starting.advancedLifts = ["intermediate", "advanced"].contains(starting.experience)
        // Gym equipment is ready by default; Home still needs an explicit inventory answer.
        if starting.location != "home" { starting.equipmentConfirmed = true }
        _profile = State(initialValue: starting)
        _moreDurations = State(initialValue: [20, 75, 90].contains(starting.minutes))
        // A gym inventory with removals opens the review's equipment check so the removals stay visible.
        _gymEquipmentOpen = State(initialValue: starting.location != "home" && Set(starting.equipment) != Set(TrainingCatalog.bundled?.presets["commercial_gym"] ?? []))
        // Gym users confirm equipment on the review, so a draft left on the old gym question resumes at Training days.
        let restoredStep = min(max(draft?.step ?? 1, 1), 8)
        _step = State(initialValue: restoredStep == 4 && starting.location != "home" ? 5 : restoredStep)
        _programID = State(initialValue: draft?.programId ?? UUID().uuidString)
        _editedProgram = State(initialValue: draft?.program)
    }
    private var generated: GeneratedTrainingPlan? { try? TrainingSetupStore.generate(profile, id: programID) }
    /// Only Home asks for equipment as a question; gym users review it on the generated plan instead.
    private var asksEquipment: Bool { profile.location == "home" }
    private var program: Program? { editedProgram ?? generated?.program }
    private var canContinue: Bool { TrainingCatalog.bundled != nil && (step == 4 ? profile.equipmentConfirmed : (step != 8 || program != nil)) }
    private var title: String {
        switch step {
        case 1: return "onboarding.goal.title"
        case 2: return "onboarding.experience.title"
        case 3: return "setup.space.title"
        case 4: return "setup.inventory.title"
        case 5: return "onboarding.days.title"
        case 6: return "setup.duration.title"
        case 7: return "setup.customize.title"
        default: return "setup.preview.title"
        }
    }
    var body: some View {
        let _ = theme.currentTheme
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: back) { Image(systemName: "arrow.left").frame(width: 48, height: 48) }
                    .accessibilityLabel(LanguageManager.t("onboarding.back")).accessibilityIdentifier("onboarding-back")
                // Fill each step's share gradually, matching Android's 600ms setup progress. Gym setup has one screen fewer.
                ProgressView(value: Double(asksEquipment || step < 4 ? step : step - 1), total: asksEquipment ? 8 : 7)
                    .progressViewStyle(SetupProgressStyle())
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: step)
                // After answering every question, skipping is no longer offered; the invisible button keeps the progress line's width.
                if let onSkip {
                    Button(LanguageManager.t("onboarding.skip"), action: onSkip).foregroundStyle(AppColors.secondaryText).frame(minHeight: 48)
                        .accessibilityIdentifier("onboarding-skip").opacity(step < 8 ? 1 : 0).disabled(step >= 8).accessibilityHidden(step >= 8)
                }
            }.padding(.horizontal, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(LanguageManager.t(title)).font(.app(size: 24, weight: .bold)).foregroundStyle(AppColors.text)
                    if let catalog = TrainingCatalog.bundled {
                        switch step {
                        case 1:
                            ForEach(OnboardingGoal.allCases, id: \.rawValue) { goal in
                                choice(LanguageManager.t("onboarding.goal.\(goal.rawValue).title"), selected: profile.goal == goal.rawValue) { profile.goal = goal.rawValue }
                            }
                        case 2:
                            ForEach(OnboardingExperience.allCases, id: \.rawValue) { experience in
                                choice(LanguageManager.t("onboarding.experience.\(experience.rawValue).title"), selected: profile.experience == experience.rawValue,
                                    hint: LanguageManager.t("onboarding.experience.\(experience.rawValue).desc"), tag: "setup-experience-\(experience.rawValue)") {
                                    if profile.experience != experience.rawValue {
                                        profile.experience = experience.rawValue
                                        profile.advancedLifts = experience != .beginner
                                    }
                                }
                            }
                        case 3: space(catalog)
                        case 4: equipment(catalog)
                        case 5: days
                        case 6: duration
                        case 7: preferences
                        default:
                            if let program { preview(program, catalog: catalog) }
                            else { Text(LanguageManager.t("setup.generationFailed")).foregroundStyle(AppColors.danger) }
                        }
                    } else { Text(LanguageManager.t("setup.generationFailed")).foregroundStyle(AppColors.danger) }
                    if let error { Text(error).foregroundStyle(AppColors.danger) }
                }.padding(20).frame(maxWidth: 600, alignment: .leading).frame(maxWidth: .infinity)
            }.id(step)
            Button(action: next) {
                Text(LanguageManager.t(step < 8 ? "onboarding.next" : "setup.start"))
                    .font(.app(size: 16, weight: .bold)).foregroundStyle(AppColors.background)
                    .frame(maxWidth: .infinity).frame(minHeight: 52).padding(.vertical, 4)
                    .background(AppColors.accent, in: RoundedRectangle(cornerRadius: 12))
            }.buttonStyle(.plain)
                .disabled(!canContinue).opacity(canContinue ? 1 : 0.45)
                .padding(20).accessibilityIdentifier("setup-next")
        }
        .background(AppColors.background).foregroundStyle(AppColors.text)
        .onAppear(perform: persist)
        .onChange(of: profile) { _, _ in editedProgram = nil; error = nil; persist() }
        .onChange(of: step) { _, _ in persist() }
        .onChange(of: editedProgram) { _, _ in persist() }
        .sheet(isPresented: $editing) {
            if let program, let catalog = TrainingCatalog.bundled {
                let eligible = TrainingPlanGenerator.eligible(profile, catalog: catalog)
                ProgramBuilderView(store: store, program: program,
                    draftCatalogue: store.exerciseCatalogue.filter { entry in eligible.contains { $0.id == entry.exercise.exerciseId } },
                    onDraftSave: { updated in
                        guard !updated.workouts.isEmpty, updated.workouts.allSatisfy({ !$0.exercises.isEmpty }),
                              updated.workouts.flatMap(\.exercises).allSatisfy({ ex in eligible.contains { $0.id == ex.exerciseId } }) else { return false }
                        editedProgram = updated; return true
                    }, onDismiss: { editing = false })
            }
        }
    }
    @ViewBuilder private func space(_ catalog: TrainingCatalog) -> some View {
        ForEach(["commercial_gym", "home"], id: \.self) { location in
            choice(LanguageManager.t("setup.location.\(location)"), selected: (profile.location == "home") == (location == "home"), tag: "setup-location-\(location)") {
                guard (profile.location == "home") != (location == "home") else { return }
                profile.location = location; profile.equipment = catalog.presets[location] ?? []; profile.equipmentConfirmed = location != "home"
                gymEquipmentOpen = false; advancedSearch = false; search = ""
            }
        }
    }
    @ViewBuilder private func equipment(_ catalog: TrainingCatalog) -> some View {
        Text(LanguageManager.t("setup.home.pick")).foregroundStyle(AppColors.secondaryText)
        choice(LanguageManager.t("setup.equipment.none"), selected: profile.equipment.isEmpty && profile.equipmentConfirmed, tag: "setup-no-equipment") {
            profile.equipment = []; profile.equipmentConfirmed = true
        }
        let common = catalog.equipment.filter { $0.home == true }
        if !advancedSearch {
            equipmentGrid(common)
            ForEach(catalog.equipment.filter { item in profile.equipment.contains(item.id) && !common.contains { $0.id == item.id } }, id: \.id) { item in
                choice(LanguageManager.t("setup.gear.\(item.id)"), selected: true, multiple: true, tag: "setup-gear-\(item.id)") { toggleEquipment(item.id) }
            }
        }
        equipmentSearch(catalog)
    }
    /// All 38 items stay reachable through the collapsed search, from Home's question and from the gym review.
    @ViewBuilder private func equipmentSearch(_ catalog: TrainingCatalog) -> some View {
        expander(advancedSearch ? "setup.equipment.common" : "setup.equipment.more", expanded: advancedSearch, tag: "setup-advanced-search") {
            advancedSearch.toggle(); search = ""
        }
        if advancedSearch {
            TextField("", text: $search, prompt: Text(LanguageManager.t("setup.equipment.search")).foregroundStyle(AppColors.muted))
                .textFieldStyle(.plain).padding(14).background(AppColors.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.border))
                .accessibilityLabel(LanguageManager.t("setup.equipment.search")).accessibilityIdentifier("setup-equipment-search")
            let matches = catalog.equipment.filter { LanguageManager.t("setup.gear.\($0.id)").localizedCaseInsensitiveContains(search) || $0.id.replacingOccurrences(of: "-", with: " ").localizedCaseInsensitiveContains(search) || search.isEmpty }
            if matches.isEmpty { Text(LanguageManager.t("setup.equipment.noResults")).foregroundStyle(AppColors.secondaryText) }
            ForEach(matches, id: \.id) { item in
                choice(LanguageManager.t("setup.gear.\(item.id)"), selected: profile.equipment.contains(item.id), multiple: true, tag: "setup-gear-\(item.id)") { toggleEquipment(item.id) }
            }
        }
    }
    /// The gym review's collapsed equipment check. Rows name the plan exercises each item serves; unchecking one
    /// regenerates the plan without it and keeps the row so the removal can be undone.
    @ViewBuilder private func gymEquipment(_ program: Program, catalog: TrainingCatalog) -> some View {
        Button { gymEquipmentOpen.toggle(); advancedSearch = false; search = "" } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(LanguageManager.t("setup.gym.title")).appFont(.headline, weight: .semibold).foregroundStyle(AppColors.text)
                    Text(LanguageManager.t("setup.gym.adjust")).appFont(.footnote).foregroundStyle(AppColors.secondaryText)
                }.multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: gymEquipmentOpen ? "chevron.up" : "chevron.down").foregroundStyle(AppColors.secondaryText).accessibilityHidden(true)
            }.padding(14).frame(maxWidth: .infinity, minHeight: 48, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain).setupCard()
            .accessibilityValue(LanguageManager.t(gymEquipmentOpen ? "progression.coach.expanded" : "progression.coach.collapsed"))
            .accessibilityIdentifier("setup-gym-equipment")
        if gymEquipmentOpen {
            Text(LanguageManager.t("setup.gym.remove")).foregroundStyle(AppColors.secondaryText)
            if !advancedSearch {
                let names = Dictionary(program.workouts.flatMap(\.exercises).compactMap { exercise in exercise.exerciseId.map { ($0, exercise.displayName) } },
                    uniquingKeysWith: { first, _ in first })
                ForEach(TrainingPlanGenerator.gymReviewEquipment(program, profile: profile, catalog: catalog)) { item in
                    let used = item.exerciseIds.compactMap { names[$0] }
                    choice(LanguageManager.t("setup.gear.\(item.id)"), selected: profile.equipment.contains(item.id),
                        hint: used.isEmpty ? "" : LanguageManager.t("setup.gym.usedBy", ["exercises": used.joined(separator: ", ")]),
                        multiple: true, tag: "setup-gear-\(item.id)") { toggleEquipment(item.id) }
                }
            }
            equipmentSearch(catalog)
        }
    }
    private func toggleEquipment(_ id: String) { toggle(id, in: &profile.equipment); profile.equipmentConfirmed = true }
    private func expander(_ key: String, expanded: Bool, tag: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack { Text(LanguageManager.t(key)).multilineTextAlignment(.leading); Spacer(); Image(systemName: expanded ? "chevron.up" : "chevron.down") }
                .frame(maxWidth: .infinity, minHeight: 48).contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(AppColors.accent).accessibilityIdentifier(tag)
            .accessibilityValue(LanguageManager.t(expanded ? "progression.coach.expanded" : "progression.coach.collapsed"))
    }
    private func equipmentGrid(_ items: [TrainingCatalog.Equipment]) -> some View {
        // Tile widths follow the width text scale, so phones of every width keep the same column count.
        let tileWidth = minimumTileWidth * TextWidthScale.factor
        let columns = dynamicTypeSize.isAccessibilitySize && equipmentWidth < tileWidth * 2 + 8
            ? 1 : (equipmentWidth >= tileWidth * 3 + 16 ? 3 : 2)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 8, alignment: .top), count: columns), spacing: 8) {
            ForEach(items, id: \.id) { item in
                let selected = profile.equipment.contains(item.id)
                Button { toggleEquipment(item.id) } label: {
                    VStack(spacing: 0) {
                        ZStack(alignment: .topTrailing) {
                            Color.black
                            Group {
                                if let artwork = item.artwork, artwork.hasPrefix("equipment:") {
                                    Image("setup_equipment_" + String(artwork.dropFirst("equipment:".count)).replacingOccurrences(of: "-", with: "_")).resizable().scaledToFit()
                                } else if let artwork = item.artwork, artwork.hasPrefix("product:") {
                                    Image("library_equipment_" + String(artwork.dropFirst("product:".count))).resizable().scaledToFit()
                                }
                            }.padding(6).frame(maxWidth: .infinity, maxHeight: .infinity)
                            if selected {
                                AppColors.accent.opacity(0.10)
                                Image(systemName: "checkmark.circle.fill").font(.system(size: 18)).foregroundStyle(AppColors.accent).padding(5)
                            }
                        }.frame(height: 80).accessibilityHidden(true)
                        Text(LanguageManager.t("setup.tile.\(item.id)")).appFont(.caption, weight: .medium).foregroundStyle(AppColors.text)
                            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                            .padding(7).frame(maxWidth: .infinity, minHeight: tileLabelHeight * TextWidthScale.factor)
                    }
                }.buttonStyle(.plain).background(selected ? AppColors.positiveBg : AppColors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? AppColors.accent : AppColors.border))
                    .accessibilityAddTraits(selected ? .isSelected : []).accessibilityIdentifier("setup-gear-\(item.id)")
            }
        }.onGeometryChange(for: CGFloat.self) { $0.size.width } action: { equipmentWidth = $0 }
            .accessibilityIdentifier("setup-equipment-grid")
    }
    private var days: some View {
        Group {
            Text(LanguageManager.t("setup.days.hint")).foregroundStyle(AppColors.secondaryText)
            ForEach(OnboardingFrequency.allCases, id: \.rawValue) { count in
                choice(LanguageManager.t("setup.days.count", ["count": count.rawValue]), selected: profile.selectedDays.count == count.rawValue) { profile.selectedDays = count.defaultWeekdays }
            }
            weekdayCards
        }
    }
    private var weekdayCards: some View {
        let columns = max(1, min(4, Int((weekdayWidth + 8) / (minimumWeekdayWidth * TextWidthScale.factor + 8))))
        return VStack(alignment: .leading, spacing: 8) {
            Text(LanguageManager.t("onboarding.days.weekdays")).fontWeight(.semibold)
            VStack(spacing: 8) {
                ForEach(Array(stride(from: 1, through: 7, by: columns)), id: \.self) { first in
                    HStack(spacing: 8) {
                        ForEach(first..<(first + columns), id: \.self) { day in
                            if day <= 7 { weekdayCard(day) }
                            else { Color.clear.frame(maxWidth: .infinity).frame(height: 0).accessibilityHidden(true) }
                        }
                    }
                }
            }.accessibilityIdentifier("setup-weekday-grid")
        }.padding(.top, 12)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { weekdayWidth = $0 }
    }
    private func weekdayCard(_ day: Int) -> some View {
        let selected = profile.selectedDays.contains(day)
        return Button {
            if selected && profile.selectedDays.count > 2 { profile.selectedDays.removeAll { $0 == day } }
            else if !selected && profile.selectedDays.count < 6 { profile.selectedDays.append(day); profile.selectedDays.sort() }
        } label: {
            Text(LanguageManager.dayLabels[day - 1]).appFont(.subheadline, weight: .semibold)
                .foregroundStyle(selected ? AppColors.accent : AppColors.text)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8).padding(.vertical, 12).frame(maxWidth: .infinity, minHeight: 56)
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
            .background(selected ? AppColors.positiveBg : AppColors.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? AppColors.accent : AppColors.border))
            .accessibilityLabel(LanguageManager.workoutDays[day - 1])
            .accessibilityAddTraits(selected ? .isSelected : []).accessibilityIdentifier("setup-day-\(day)")
    }
    private var duration: some View {
        Group {
            Text(LanguageManager.t("setup.duration.hint")).foregroundStyle(AppColors.secondaryText)
            ForEach([30, 45, 60], id: \.self) { minutes in
                choice(LanguageManager.t("setup.minutes", ["count": minutes]), selected: profile.minutes == minutes,
                    tag: "setup-duration-\(minutes)", badge: minutes == 45 ? LanguageManager.t("setup.duration.recommended") : "") { profile.minutes = minutes }
            }
            Button { moreDurations.toggle() } label: {
                HStack {
                    Text(LanguageManager.t(moreDurations ? "setup.duration.less" : "setup.duration.more"))
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Image(systemName: moreDurations ? "chevron.up" : "chevron.down").accessibilityHidden(true)
                }.frame(maxWidth: .infinity, minHeight: 48).contentShape(Rectangle())
            }.buttonStyle(.plain).foregroundStyle(AppColors.accent)
                .accessibilityValue(LanguageManager.t(moreDurations ? "progression.coach.expanded" : "progression.coach.collapsed"))
                .accessibilityIdentifier("setup-duration-more")
            ForEach([20, 75, 90].filter { moreDurations || profile.minutes == $0 }, id: \.self) { minutes in
                choice(LanguageManager.t("setup.minutes", ["count": minutes]), selected: profile.minutes == minutes,
                    tag: "setup-duration-\(minutes)") { profile.minutes = minutes }
            }
        }
    }
    private var preferences: some View {
        let tileWidth = minimumPriorityWidth * TextWidthScale.factor
        let columns = dynamicTypeSize.isAccessibilitySize && priorityWidth < tileWidth * 2 + 8
            ? 1 : (priorityWidth >= tileWidth * 3 + 16 ? 3 : 2)
        return VStack(alignment: .leading, spacing: 12) {
            Text(LanguageManager.t("setup.customize.hint")).foregroundStyle(AppColors.secondaryText)
            Text(LanguageManager.t("setup.priority.title")).appFont(.headline)
            choice(LanguageManager.t("setup.priority.balanced"), selected: profile.priority.isEmpty,
                hint: LanguageManager.t("setup.priority.balanced.hint"), tag: "setup-priority-balanced") { profile.priority = "" }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(LanguageManager.t("setup.priority.balanced") + ", " + LanguageManager.t("setup.priority.balanced.hint"))
            VStack(spacing: 12) {
                ForEach(0..<((SetupMusclePriority.options.count + columns - 1) / columns), id: \.self) { row in
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(0..<columns, id: \.self) { column in
                            let index = row * columns + column
                            if index < SetupMusclePriority.options.count {
                                priorityCard(SetupMusclePriority.options[index]).frame(maxWidth: .infinity)
                            } else {
                                Color.clear.frame(maxWidth: .infinity).frame(height: 0).accessibilityHidden(true)
                            }
                        }
                    }
                }
            }.accessibilityIdentifier("setup-priority-grid")
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { priorityWidth = $0 }
        }
    }
    private func priorityCard(_ priority: SetupMusclePriority) -> some View {
        let selected = profile.priority == priority.id
        let label = LanguageManager.t("setup.priority.\(priority.id)")
        return Button { profile.priority = priority.id } label: {
            VStack(spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    Color.black
                    MuscleArtwork(view: priority.muscle.bodyView, muscles: priority.muscle.muscleGroups,
                        centered: true, transparentBackground: true).accessibilityHidden(true)
                    if selected {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(AppColors.accent)
                            .font(.system(size: 18)).padding(5).accessibilityHidden(true)
                    }
                }.frame(height: 90).clipped()
                Text(label).font(.app(size: priorityFontSize, weight: .medium)).foregroundStyle(AppColors.text)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    .padding(7).frame(maxWidth: .infinity, minHeight: tileLabelHeight * TextWidthScale.factor)
            }.background(selected ? AppColors.positiveBg : AppColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(selected ? AppColors.accent : AppColors.border, lineWidth: selected ? 1.5 : 1))
        }.buttonStyle(.plain).accessibilityElement(children: .ignore).accessibilityLabel(label)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("setup-priority-\(priority.id)")
    }
    @ViewBuilder private func preview(_ program: Program, catalog: TrainingCatalog) -> some View {
        let goal = LanguageManager.t("onboarding.goal.\(profile.goal).title")
        let experience = LanguageManager.t("onboarding.experience.\(profile.experience).title")
        let eligible = TrainingPlanGenerator.eligible(profile, catalog: catalog)
        VStack(alignment: .leading, spacing: 4) {
            Text(program.name).appFont(.title3, weight: .semibold).foregroundStyle(AppColors.text)
            Text("\(goal) · \(experience)").appFont(.subheadline).foregroundStyle(AppColors.secondaryText)
            Text(program.description).appFont(.footnote).foregroundStyle(AppColors.muted).padding(.top, 6)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).setupCard()
        ForEach(generated?.warningKeys ?? [], id: \.self) { key in
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "info.circle.fill").foregroundStyle(AppColors.muted).accessibilityHidden(true)
                Text(LanguageManager.t(key)).appFont(.footnote).foregroundStyle(AppColors.secondaryText)
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading).setupCard()
        }
        if !asksEquipment { gymEquipment(program, catalog: catalog) }
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Text(LanguageManager.t("builder.trainingDays")).appFont(.headline).foregroundStyle(AppColors.text)
                Spacer(minLength: 0)
                Text(LanguageManager.t("builder.dayCount", ["count": program.workouts.count])).appFont(.caption).foregroundStyle(AppColors.muted)
            }
            Text(LanguageManager.t("builder.summaryCounts", ["exercises": program.workouts.reduce(0) { $0 + $1.exercises.count },
                "sets": program.workouts.flatMap(\.exercises).reduce(0) { $0 + WorkoutSessionUtils.initialSetCount(exercise: $1) }]))
                .appFont(.caption).foregroundStyle(AppColors.muted).accessibilityIdentifier("setup-plan-totals")
        }.accessibilityIdentifier("setup-training-days")
        ForEach(program.workouts) { workout in
            let minutes = (300 + workout.exercises.reduce(0) { $0 + TrainingPlanGenerator.estimateSeconds($1) } + 59) / 60
            let open = expandedDays.contains(workout.id)
            VStack(alignment: .leading, spacing: 0) {
                // Days start collapsed so the whole week reads at a glance; the header carries the summary.
                Button { if open { expandedDays.remove(workout.id) } else { expandedDays.insert(workout.id) } } label: {
                    reviewDayHeader(workout, minutes: minutes, open: open)
                }.buttonStyle(.plain).accessibilityIdentifier("setup-day-\(workout.day)")
                    .accessibilityLabel([LanguageManager.workoutDays[workout.day - 1], workout.title, workout.focus,
                        LanguageManager.t("weekly.exerciseCount", ["count": workout.exercises.count]),
                        LanguageManager.t("setup.minutes", ["count": minutes])].filter { !$0.isEmpty }.joined(separator: ", "))
                    .accessibilityValue(LanguageManager.t(open ? "progression.coach.expanded" : "progression.coach.collapsed"))
                if open { ForEach(workout.exercises) { exercise in
                    let role = catalog.candidates.first { $0.id == exercise.exerciseId }?.role
                    let replacement = eligible.first { row in row.role == role && !workout.exercises.contains { $0.exerciseId == row.id } }
                    Rectangle().fill(AppColors.border).frame(height: 1).padding(.horizontal, 16)
                    HStack(spacing: 10) {
                        MovementIcon(exerciseId: exercise.exerciseId, size: 44).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(exercise.displayName).font(.app(size: 15, weight: .medium)).foregroundStyle(AppColors.text)
                            // Exercises serving the chosen muscle priority carry an accent tag.
                            let priority = role.map { catalog.priorities[profile.priority]?.contains($0) ?? false } ?? false
                            (Text("\(prescription(exercise)) · \(LanguageManager.t("setup.rest", ["seconds": exercise.restSeconds ?? 90]))")
                                + Text(priority ? " · \(LanguageManager.t("setup.priority.tag"))" : "").foregroundColor(AppColors.accent))
                                .appFont(.footnote).foregroundStyle(AppColors.secondaryText)
                        }.padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
                        if let replacement {
                            Button { replace(exercise, in: workout, with: replacement, program: program) } label: {
                                Image(systemName: "arrow.left.arrow.right").frame(width: 48, height: 48).contentShape(Rectangle())
                            }.buttonStyle(.plain).foregroundStyle(AppColors.secondaryText)
                                .accessibilityLabel(LanguageManager.t("setup.replace")).accessibilityIdentifier("setup-replace")
                        }
                    }.padding(.leading, 16).padding(.trailing, replacement == nil ? 16 : 4)
                } }
            }.frame(maxWidth: .infinity, alignment: .leading).setupCard()
        }
        ForEach([("setup.editAnswers", { step = 1 }), ("modal.program.titleEdit", { editing = true })], id: \.0) { key, action in
            Button(action: action) {
                Text(LanguageManager.t(key)).frame(maxWidth: .infinity, minHeight: 48)
            }.buttonStyle(.plain).foregroundStyle(AppColors.secondaryText)
                .background(AppColors.surface.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.border))
        }
    }
    @ViewBuilder private func reviewDayHeader(_ workout: Workout, minutes: Int, open: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if dynamicTypeSize.isAccessibilitySize {
                HStack {
                    reviewWeekday(workout.day)
                    Spacer(minLength: 0)
                    Image(systemName: open ? "chevron.up" : "chevron.down").foregroundStyle(AppColors.secondaryText).accessibilityHidden(true)
                }
                reviewDayDetails(workout, minutes: minutes)
            } else {
                HStack(spacing: 12) {
                    reviewWeekday(workout.day)
                    reviewDayDetails(workout, minutes: minutes).frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: open ? "chevron.up" : "chevron.down").foregroundStyle(AppColors.secondaryText).accessibilityHidden(true)
                }
            }
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
    }
    private func reviewWeekday(_ day: Int) -> some View {
        Text(LanguageManager.dayLabels[day - 1]).font(.app(size: reviewWeekdayFontSize, weight: .bold))
            .frame(width: reviewBadgeSize, height: reviewBadgeSize).foregroundStyle(AppColors.accent)
            .background(AppColors.positiveBg, in: RoundedRectangle(cornerRadius: 12))
            .accessibilityLabel(LanguageManager.workoutDays[day - 1]).accessibilityIdentifier("setup-weekday-badge-\(day)")
    }
    private func reviewDayDetails(_ workout: Workout, minutes: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(workout.title).appFont(.headline, weight: .semibold).foregroundStyle(AppColors.text)
            if !workout.focus.isEmpty { Text(workout.focus).appFont(.footnote).foregroundStyle(AppColors.secondaryText) }
            Text("\(LanguageManager.t("weekly.exerciseCount", ["count": workout.exercises.count])) · \(LanguageManager.t("setup.minutes", ["count": minutes]))")
                .appFont(.footnote).foregroundStyle(AppColors.muted)
        }.multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
    }
    private func choice(_ label: String, selected: Bool, hint: String = "", multiple: Bool = false, tag: String = "", badge: String = "", action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    if badge.isEmpty { Text(label).fontWeight(.medium).foregroundStyle(AppColors.text) }
                    else {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 8) {
                                Text(label).fontWeight(.medium).foregroundStyle(AppColors.text).fixedSize()
                                choiceBadge(badge).fixedSize()
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                Text(label).fontWeight(.medium).foregroundStyle(AppColors.text)
                                choiceBadge(badge)
                            }
                        }
                    }
                    if !hint.isEmpty { Text(hint).appFont(.caption).foregroundStyle(AppColors.secondaryText) }
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? (multiple ? "checkmark.square.fill" : "largecircle.fill.circle") : (multiple ? "square" : "circle"))
                    .foregroundStyle(selected ? AppColors.accent : AppColors.muted).accessibilityHidden(true)
            }.padding(14).frame(minHeight: 48).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain).background(selected ? AppColors.positiveBg : AppColors.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? AppColors.accent : AppColors.border))
            .accessibilityAddTraits(selected ? .isSelected : []).accessibilityIdentifier(tag)
    }
    private func choiceBadge(_ label: String) -> some View {
        Text(label).appFont(.caption2, weight: .semibold).foregroundStyle(AppColors.secondaryText)
            .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 8).padding(.vertical, 4)
            .background(AppColors.surfaceRaised, in: RoundedRectangle(cornerRadius: 6))
    }
    private func toggle(_ value: String, in values: inout [String]) {
        if values.contains(value) { values.removeAll { $0 == value } } else { values.append(value); values.sort() }
    }
    private func prescription(_ exercise: Exercise) -> String {
        guard let sets = exercise.sets, let reps = exercise.reps else { return LanguageManager.content(exercise.displayPrescription) }
        let range: String
        if reps.toFailure { range = LanguageManager.t("targets.failure") }
        else if let min = reps.min, let max = reps.max { range = min == max ? String(min) : "\(min)–\(max)" }
        else { return LanguageManager.content(exercise.displayPrescription) }
        return "\(sets) × \(range)" + (reps.perSide ? " · \(LanguageManager.t("targets.perSide"))" : "")
    }
    private func replace(_ exercise: Exercise, in workout: Workout, with row: TrainingCatalog.Candidate, program: Program) {
        guard var replacement = ExerciseCatalog.canonicalExercises[row.id]?.toExercise(),
              let w = program.workouts.firstIndex(where: { $0.id == workout.id }),
              let e = program.workouts[w].exercises.firstIndex(where: { $0.id == exercise.id }) else { return }
        replacement.id = UUID().uuidString; replacement.sets = exercise.sets; replacement.reps = exercise.reps
        replacement.reps?.perSide = row.perSide; replacement.restSeconds = exercise.restSeconds
        var updated = program; updated.workouts[w].exercises[e] = replacement; editedProgram = updated
    }
    private func back() { if step > 1 { step -= step == 5 && !asksEquipment ? 2 : 1 } else { onClose() } }
    private func next() {
        if step < 8 { step += step == 3 && !asksEquipment ? 2 : 1; search = ""; advancedSearch = false }
        else if let program {
            if store.saveGeneratedPlan(profile: profile.normalized(), program: program, completeSetup: completeSetup) { onClose() }
            else { error = LanguageManager.t("setup.saveFailed") }
        }
    }
    private func persist() {
        guard !completeSetup else { return }
        TrainingSetupStore.saveDraft(.init(profile: profile, step: step, programId: programID, program: editedProgram))
    }
}

/// The native bar runs its own brief slide and ignores the caller's animation; this fill follows it.
private struct SetupProgressStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        Capsule().fill(AppColors.border)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Rectangle().fill(AppColors.accent).frame(width: proxy.size.width * (configuration.fractionCompleted ?? 0))
                }
            }
            .clipShape(Capsule()).frame(height: 4)
    }
}

private extension View {
    /// The standard contained surface: palette fill, 1pt border and 14pt corners.
    func setupCard() -> some View {
        background(AppColors.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.border))
    }
}

/// Only targeted priorities use the Library's registered anatomy and highlights.
private struct SetupMusclePriority: Identifiable {
    let id: String
    let muscle: MuscleGroupFilter
    static let options: [Self] = [
        .init(id: "push", muscle: .chest), .init(id: "row", muscle: .back),
        .init(id: "squat", muscle: .quads), .init(id: "shoulders", muscle: .shoulders),
        .init(id: "biceps", muscle: .biceps), .init(id: "core", muscle: .core)
    ]
}
