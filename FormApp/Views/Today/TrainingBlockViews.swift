import SwiftUI

/// What the Home block card shows (docs/training-blocks.md#review-and-edits). Android `BlockCardState` matches.
enum BlockCardState: Equatable {
    case locked
    case none
    case upcoming(TrainingBlock)
    case active(TrainingBlock, week: Int, target: Int, ready: Bool)
    case otherProgram(TrainingBlock, programName: String)
    case complete(TrainingBlock)

    static func of(block: TrainingBlock?, activeProgram: Program?, programs: [Program], weekKey: String, unlocked: Bool) -> BlockCardState {
        guard unlocked else { return .locked }
        guard let block else { return .none }
        guard activeProgram?.id == block.programId else {
            return .otherProgram(block, programName: programs.first { $0.id == block.programId }?.displayName ?? "")
        }
        guard let week = TrainingBlocks.weekIndex(block, weekKey: weekKey) else { return .upcoming(block) }
        if week > block.length { return .complete(block) }
        // A strength block has no weekly effort target: its lifts follow their own schedule.
        guard let target = block.isStrength ? 0 : TrainingBlockRules.target(length: block.length, week: week) else { return .none }
        let ready = week > 1 && block.weeks.indices.contains(week - 1) && !block.weeks[week - 1].reviewed
        return .active(block, week: week, target: target, ready: ready)
    }
}

enum BlockFormat {
    /// Weekly sets with halves from secondary credit, in the app language: 12, 12.5 or 12,5.
    static func sets(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: LanguageManager.shared.currentLanguage)
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func reasons(_ codes: [String]) -> String {
        let text = codes.map { LanguageManager.t("block.reason.\($0)") }.joined(separator: ", ")
        return text.prefix(1).uppercased(with: Locale(identifier: LanguageManager.shared.currentLanguage)) + text.dropFirst()
    }

    static func muscle(_ code: String) -> String { LanguageManager.t("anatomy.muscle.\(code)") }

    /// Keeps "3 × 5" and "90 %" whole when a sentence wraps.
    static func unbroken(_ text: String) -> String {
        text.replacingOccurrences(of: " × ", with: "\u{00A0}×\u{00A0}").replacingOccurrences(of: " %", with: "\u{00A0}%")
    }

    static func percent(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: LanguageManager.shared.currentLanguage)
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// An effort tag that never splits across lines: "RIR 2".
    static func tag(_ rir: Int, scale: SetEffort.Scale) -> String {
        SetEffort.tag(rir, scale: scale).replacingOccurrences(of: " ", with: "\u{00A0}")
    }

    /// "RIR 3 · RIR 2 · RIR 1 · Deload" for a length.
    static func targets(length: Int, scale: SetEffort.Scale) -> String {
        (TrainingBlockRules.targets(length: length).dropLast().map { tag($0, scale: scale) } + [LanguageManager.t("block.setup.deload")])
            .joined(separator: " · ")
    }
}

/// The block's Home card: start, the current week, a ready week to review, or the end-of-block summary.
struct TrainingBlockCard: View {
    @ObservedObject var themeManager = ThemeManager.shared
    let state: BlockCardState
    let scale: SetEffort.Scale
    let onStart: () -> Void
    let onReview: (Int) -> Void
    let onSummary: () -> Void
    let onEnd: () -> Void
    let onLocked: () -> Void
    /// Opens the Method page; offered locked too, so the feature can be read about before buying.
    var onOpenMethod: () -> Void = {}
    @State private var confirmEnd = false
    @ScaledMetric(relativeTo: .headline) private var titleSize = 15.0
    @ScaledMetric(relativeTo: .headline) private var headlineSize = 16.0
    @ScaledMetric(relativeTo: .subheadline) private var bodySize = 13.0

    var body: some View {
        let _ = themeManager.currentTheme
        let card = VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.clock").font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.purple).accessibilityHidden(true)
                Text(LanguageManager.t("block.card.title")).font(.app(size: titleSize, weight: .bold)).foregroundStyle(AppColors.text)
                    .frame(maxWidth: .infinity, alignment: .leading).accessibilityAddTraits(.isHeader)
                if state == .locked {
                    Image(systemName: "lock.fill").font(.system(size: 14)).foregroundStyle(AppColors.purple)
                        .accessibilityLabel(LanguageManager.t("pro.premium_required"))
                }
                // Room for the info button, which sits above the card so a locked card's own tap stays separate.
                Color.clear.frame(width: 20, height: 1)
            }
            content
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AppColors.purple.opacity(0.5), lineWidth: 1))
        Group {
            if state == .locked {
                Button(action: onLocked) { card }.buttonStyle(.plain)
            } else {
                card.accessibilityElement(children: .contain)
            }
        }
        .accessibilityIdentifier("training-block-card")
        .overlay(alignment: .topTrailing) {
            Button(action: onOpenMethod) {
                Image(systemName: "info.circle").font(.system(size: 16)).foregroundStyle(AppColors.muted)
                    .frame(width: 48, height: 48).contentShape(Rectangle())
            }
            .buttonStyle(.plain).padding(.trailing, 6)
            .accessibilityLabel(LanguageManager.t("method.open"))
            .accessibilityIdentifier("training-block-method")
        }
        .alert(LanguageManager.t("block.card.endTitle"), isPresented: $confirmEnd) {
            Button(LanguageManager.t("block.card.end"), role: .destructive, action: onEnd)
            Button(LanguageManager.t("modal.cancel"), role: .cancel) {}
        } message: {
            Text(LanguageManager.t("block.card.endText"))
        }
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .locked:
            bodyText(LanguageManager.t("block.card.locked"))
        case .none:
            bodyText(LanguageManager.t("block.card.pitch"))
            primary(LanguageManager.t("block.card.start"), "training-block-start", onStart)
        case .upcoming(let block):
            headline(LanguageManager.t("block.card.startsNext"))
            bodyText(block.isStrength ? LanguageManager.t("block.card.testIn", ["count": block.length])
                     : BlockFormat.targets(length: block.length, scale: scale))
            endButton
        case .active(let block, let week, let target, let ready):
            let toTest = block.length - week
            let detail = block.isStrength
                ? (toTest == 0 ? LanguageManager.t("block.card.test") : toTest == 1 ? LanguageManager.t("block.card.taper")
                   : LanguageManager.t("block.card.testIn", ["count": toTest]))
                : TrainingBlockRules.isDeload(length: block.length, week: week) ? LanguageManager.t("block.card.deload")
                : LanguageManager.t("block.card.target", ["effort": BlockFormat.tag(target, scale: scale)])
            headline(LanguageManager.t("block.card.week", ["week": week, "length": block.length]) + " · " + detail)
            if ready {
                bodyText(LanguageManager.t("block.card.ready", ["week": week]))
                primary(LanguageManager.t("block.card.review", ["week": week]), "training-block-review") { onReview(week) }
            } else {
                Button { onReview(week) } label: {
                    Text(LanguageManager.t("block.card.review", ["week": week])).blockFont(14, .semibold)
                        .foregroundStyle(AppColors.purple).frame(minHeight: 48)
                }.buttonStyle(.plain).accessibilityIdentifier("training-block-open-week")
            }
            endButton
        case .otherProgram(_, let programName):
            bodyText(LanguageManager.t("block.card.otherProgram", ["program": programName]))
            endButton
        case .complete:
            headline(LanguageManager.t("block.card.complete"))
            primary(LanguageManager.t("block.card.summary"), "training-block-summary", onSummary)
        }
    }

    private func headline(_ text: String) -> some View {
        Text(text).font(.app(size: headlineSize, weight: .semibold)).foregroundStyle(AppColors.text)
            .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("training-block-headline")
    }

    private func bodyText(_ text: String) -> some View {
        Text(text).font(.app(size: bodySize)).foregroundStyle(AppColors.secondaryText).fixedSize(horizontal: false, vertical: true)
    }

    private func primary(_ label: String, _ identifier: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).blockFont(14, .semibold).foregroundStyle(AppColors.background)
                .padding(.horizontal, 18).frame(minHeight: 48)
                .background(AppColors.accent).clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain).padding(.top, 4).accessibilityIdentifier(identifier)
    }

    private var endButton: some View {
        Button { confirmEnd = true } label: {
            Text(LanguageManager.t("block.card.end")).blockFont(13).foregroundStyle(AppColors.muted).frame(minHeight: 48)
        }.buttonStyle(.plain).accessibilityIdentifier("training-block-end")
    }
}

private struct BlockSectionLabel: View {
    let text: String
    var body: some View {
        Text(text).blockFont(14, .semibold).foregroundStyle(AppColors.text).accessibilityAddTraits(.isHeader)
    }
}

private struct BlockBody: View {
    let text: String
    var body: some View {
        Text(text).blockFont(13).foregroundStyle(AppColors.secondaryText).fixedSize(horizontal: false, vertical: true)
    }
}

/// A choice chip with a 48pt target, selected in the purple training role.
private struct BlockChoice: View {
    let label: String
    let selected: Bool
    let identifier: String
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label).blockFont(14, .semibold)
                .foregroundStyle(selected ? AppColors.purple : enabled ? AppColors.secondaryText : AppColors.muted)
                .padding(.horizontal, 14).frame(minHeight: 48)
                .background(selected ? AppColors.purpleBg : AppColors.surfaceRaised)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(selected ? AppColors.purple.opacity(0.7) : AppColors.border, lineWidth: 1))
        }
        .buttonStyle(.plain).disabled(!enabled)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}

/// Lays chips out in rows, wrapping when a row is full.
private struct BlockFlow: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(widest, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

private func blockPrimaryButton(_ label: String, _ identifier: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Text(label).blockFont(15, .semibold).foregroundStyle(AppColors.background)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(AppColors.accent).clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }.buttonStyle(.plain).accessibilityIdentifier(identifier)
}

private func blockSecondaryButton(_ label: String, _ identifier: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Text(label).blockFont(14).foregroundStyle(AppColors.secondaryText)
            .frame(maxWidth: .infinity, minHeight: 50)
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(AppColors.border, lineWidth: 1))
    }.buttonStyle(.plain).accessibilityIdentifier(identifier)
}

/// A block sheet's scrolling page on the app's surface.
private struct BlockSheetPage<Content: View>: View {
    let identifier: String
    @ViewBuilder let content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) { content }
                .padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 36)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AppColors.surface.ignoresSafeArea())
        .accessibilityIdentifier(identifier)
        .presentationDragIndicator(.visible)
    }
}

/// Length, focus muscles and start week; starting replaces any earlier block.
struct TrainingBlockSetupContent: View {
    let program: Program
    let scale: SetEffort.Scale
    let replacesBlock: Bool
    let onStart: (Int, [String], Bool) -> Void
    /// The same Premium switch as Settings: a readiness check before each workout.
    var readinessCheck: Binding<Bool>? = nil
    var onStartStrength: (Int, [String], Bool) -> Void = { _, _, _ in }
    var onOpenMethod: () -> Void = {}
    /// Next week once none of the program's workouts is left in this one (docs/training-blocks.md#weeks).
    var suggestNextWeek = false
    @State private var length = 5
    @State private var focus: [String] = []
    @State private var chosenNextWeek: Bool?
    @State private var strength = false
    @State private var testIn = 6
    @State private var lifts: [String] = []

    private var nextWeek: Bool { chosenNextWeek ?? suggestNextWeek }

    var body: some View {
        let choices = TrainingBlocks.focusChoices(program)
        let liftChoices = TrainingBlocks.liftChoices(program)
        Text(LanguageManager.t("block.setup.title")).blockFont(20, .bold).foregroundStyle(AppColors.text)
            .accessibilityAddTraits(.isHeader)
        BlockBody(text: LanguageManager.t(strength ? "block.setup.strengthPlan" : "block.setup.intro"))
        Button(action: onOpenMethod) {
            Text(LanguageManager.t("method.open")).blockFont(14, .semibold).foregroundStyle(AppColors.purple).frame(minHeight: 48)
        }
        .buttonStyle(.plain).accessibilityIdentifier("block-setup-method")
        BlockSectionLabel(text: LanguageManager.t("block.setup.goal"))
        BlockFlow {
            BlockChoice(label: LanguageManager.t("block.setup.muscle"), selected: !strength, identifier: "block-goal-muscle") { strength = false }
            BlockChoice(label: LanguageManager.t("block.setup.strength"), selected: strength, identifier: "block-goal-strength") { strength = true }
        }
        if strength {
            BlockSectionLabel(text: LanguageManager.t("block.setup.lifts"))
            BlockBody(text: LanguageManager.t(liftChoices.isEmpty ? "block.setup.noLifts" : "block.setup.liftsHint"))
            BlockFlow {
                ForEach(liftChoices, id: \.key) { choice in
                    let selected = lifts.contains(choice.key)
                    // The same lift on two days names its day.
                    let repeated = liftChoices.filter { $0.exercise.displayName == choice.exercise.displayName }.count > 1
                    let day = program.workouts.first { choice.key.hasPrefix("\($0.id)/") }?.title
                    BlockChoice(label: choice.exercise.displayName + (repeated && day != nil ? " · \(day!)" : ""), selected: selected,
                                identifier: "block-lift-\(choice.key)", enabled: selected || lifts.count < TrainingBlockRules.maxLifts) {
                        if selected { lifts.removeAll { $0 == choice.key } } else { lifts.append(choice.key) }
                    }
                }
            }
            BlockSectionLabel(text: LanguageManager.t("block.setup.testIn"))
            BlockFlow {
                ForEach(Array(TrainingBlockRules.strengthLengths), id: \.self) { weeks in
                    BlockChoice(label: LanguageManager.t("block.setup.weeks", ["count": weeks]), selected: testIn == weeks,
                                identifier: "block-test-\(weeks)") { testIn = weeks }
                }
            }
        } else {
        BlockSectionLabel(text: LanguageManager.t("block.setup.length"))
        BlockFlow {
            ForEach(Array(TrainingBlockRules.lengths), id: \.self) { weeks in
                BlockChoice(label: LanguageManager.t("block.setup.weeks", ["count": weeks]), selected: length == weeks,
                            identifier: "block-length-\(weeks)") { length = weeks }
            }
        }
        Text(LanguageManager.t("block.setup.targets", ["targets": BlockFormat.targets(length: length, scale: scale)]))
            .blockFont(13).foregroundStyle(AppColors.purple).fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("block-setup-targets")
        }
        if !strength && !choices.isEmpty {
            BlockSectionLabel(text: LanguageManager.t("block.setup.focus"))
            BlockBody(text: LanguageManager.t("block.setup.focusHint"))
            BlockFlow {
                ForEach(choices, id: \.self) { muscle in
                    let selected = focus.contains(muscle)
                    BlockChoice(label: BlockFormat.muscle(muscle), selected: selected, identifier: "block-focus-\(muscle)",
                                enabled: selected || focus.count < TrainingBlockRules.maxFocus) {
                        if selected { focus.removeAll { $0 == muscle } } else { focus.append(muscle) }
                    }
                }
            }
        }
        BlockSectionLabel(text: LanguageManager.t("block.setup.when"))
        BlockFlow {
            BlockChoice(label: LanguageManager.t("block.setup.thisWeek"), selected: !nextWeek, identifier: "block-start-this-week") { chosenNextWeek = false }
            BlockChoice(label: LanguageManager.t("block.setup.nextWeek"), selected: nextWeek, identifier: "block-start-next-week") { chosenNextWeek = true }
        }
        if let readinessCheck {
            BlockChoice(label: LanguageManager.t("block.setup.readiness"), selected: readinessCheck.wrappedValue,
                        identifier: "block-setup-readiness") { readinessCheck.wrappedValue.toggle() }
        }
        if replacesBlock { BlockBody(text: LanguageManager.t("block.setup.replaces")) }
        blockPrimaryButton(LanguageManager.t("block.setup.confirm"), "block-setup-confirm") {
            if strength { onStartStrength(testIn, lifts, nextWeek) } else { onStart(length, focus, nextWeek) }
        }
        .disabled(strength && lifts.isEmpty).opacity(strength && lifts.isEmpty ? 0.4 : 1)
    }
}

struct TrainingBlockSetupSheet: View {
    let program: Program
    let scale: SetEffort.Scale
    let replacesBlock: Bool
    var readinessCheck: Binding<Bool>? = nil
    var onStartStrength: (Int, [String], Bool) -> Void = { _, _, _ in }
    var onOpenMethod: () -> Void = {}
    var suggestNextWeek = false
    let onStart: (Int, [String], Bool) -> Void
    var body: some View {
        BlockSheetPage(identifier: "training-block-setup") {
            TrainingBlockSetupContent(program: program, scale: scale, replacesBlock: replacesBlock, onStart: onStart,
                                      readinessCheck: readinessCheck, onStartStrength: onStartStrength, onOpenMethod: onOpenMethod,
                                      suggestNextWeek: suggestNextWeek)
        }
    }
}

/// One block week: each muscle's change with its reasons, each exercise's sets, and optional edits.
struct TrainingBlockWeekContent: View {
    let block: TrainingBlock
    let week: Int
    let program: Program
    let scale: SetEffort.Scale
    let onStartWeek: ([String: Int]) -> Void
    @State private var editing = false
    @State private var edits: [String: Int] = [:]

    var body: some View {
        if block.isStrength {
            StrengthWeekContent(block: block, week: week, program: program, scale: scale) { onStartWeek([:]) }
        } else if block.weeks.indices.contains(week - 1) {
            let current = block.weeks[week - 1]
            let previous = block.weeks.indices.contains(week - 2) ? block.weeks[week - 2] : nil
            let deload = TrainingBlockRules.isDeload(length: block.length, week: week)
            Text(LanguageManager.t("block.review.title", ["week": week, "length": block.length]))
                .blockFont(20, .bold).foregroundStyle(AppColors.text).accessibilityAddTraits(.isHeader)
            Text(deload ? LanguageManager.t("block.review.deload")
                 : LanguageManager.t("block.review.target", ["effort": BlockFormat.tag(TrainingBlockRules.target(length: block.length, week: week) ?? 0, scale: scale)]))
                .blockFont(14, .semibold).foregroundStyle(AppColors.purple).fixedSize(horizontal: false, vertical: true)
            if !current.changes.isEmpty {
                BlockSectionLabel(text: LanguageManager.t("block.review.muscles"))
                ForEach(current.changes, id: \.muscle) { change in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(BlockFormat.muscle(change.muscle)).blockFont(15, .semibold).foregroundStyle(AppColors.text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(LanguageManager.t("block.review.sets", ["from": BlockFormat.sets(change.from), "to": BlockFormat.sets(change.to)]))
                                .blockFont(14, .semibold)
                                .foregroundStyle(change.to > change.from ? AppColors.accent : change.to < change.from ? AppColors.warmupAmber : AppColors.secondaryText)
                                .fixedSize()
                        }
                        Text(BlockFormat.reasons(change.reasons)).blockFont(13).foregroundStyle(AppColors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("block-change-\(change.muscle)")
                }
            } else if !deload {
                BlockBody(text: LanguageManager.t("block.review.none"))
            }
            BlockSectionLabel(text: LanguageManager.t("block.review.exercises"))
            ForEach(program.workouts, id: \.id) { workout in
                let rows = workout.exercises.compactMap { exercise -> (Exercise, String, Int, Int)? in
                    let key = TrainingBlocks.key(workout, exercise)
                    guard let now = edits[key] ?? current.sets[key] else { return nil }
                    let before = previous?.sets[key] ?? WorkoutSessionUtils.initialSetCount(exercise: exercise)
                    return editing || before != now || current.edited.contains(key) ? (exercise, key, before, now) : nil
                }
                if !rows.isEmpty {
                    Text(workout.title).blockFont(12, .semibold).foregroundStyle(AppColors.muted)
                    ForEach(rows, id: \.1) { exercise, key, before, now in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(exercise.displayName).blockFont(14).foregroundStyle(AppColors.text).fixedSize(horizontal: false, vertical: true)
                                if current.edited.contains(key) || edits[key] != nil {
                                    Text(LanguageManager.t("block.review.edited")).blockFont(11, .semibold).foregroundStyle(AppColors.purple)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            if editing {
                                Button { edits[key] = max(1, now - 1) } label: {
                                    Image(systemName: "minus").frame(width: 48, height: 48).contentShape(Rectangle())
                                }
                                .buttonStyle(.plain).foregroundStyle(AppColors.secondaryText).disabled(now <= 1)
                                .accessibilityLabel(LanguageManager.t("block.review.fewer", ["exercise": exercise.displayName]))
                                .accessibilityIdentifier("block-fewer-\(key)")
                                Text("\(now)").blockFont(16, .semibold).foregroundStyle(AppColors.text).frame(minWidth: 24)
                                Button { edits[key] = min(TrainingBlocks.maxExerciseSets, now + 1) } label: {
                                    Image(systemName: "plus").frame(width: 48, height: 48).contentShape(Rectangle())
                                }
                                .buttonStyle(.plain).foregroundStyle(AppColors.secondaryText).disabled(now >= TrainingBlocks.maxExerciseSets)
                                .accessibilityLabel(LanguageManager.t("block.review.more", ["exercise": exercise.displayName]))
                                .accessibilityIdentifier("block-more-\(key)")
                            } else {
                                Text(LanguageManager.t("block.review.sets", ["from": before, "to": now]))
                                    .blockFont(14).foregroundStyle(AppColors.secondaryText).fixedSize()
                            }
                        }
                        .frame(minHeight: 48)
                        .accessibilityIdentifier("block-exercise-\(key)")
                    }
                }
            }
            // Stacked: either label can be long in German or French at 320 pt.
            blockPrimaryButton(LanguageManager.t("block.review.start", ["week": week]), "block-week-start") { onStartWeek(edits) }
            if !editing {
                blockSecondaryButton(LanguageManager.t("block.review.edit"), "block-week-edit") { editing = true }
            }
        }
    }
}

struct TrainingBlockWeekSheet: View {
    let block: TrainingBlock
    let week: Int
    let program: Program
    let scale: SetEffort.Scale
    let onStartWeek: ([String: Int]) -> Void
    var body: some View {
        BlockSheetPage(identifier: "training-block-week") {
            TrainingBlockWeekContent(block: block, week: week, program: program, scale: scale, onStartWeek: onStartWeek)
        }
    }
}

/// After the deload: weekly sets per muscle by week and the estimated 1RM change on each workout's first lift.
struct TrainingBlockSummaryContent: View {
    let block: TrainingBlock
    let program: Program
    let history: [WorkoutSessionRecord]
    let weightUnit: WeightUnit
    let onStartAnother: () -> Void
    let onDone: () -> Void

    var body: some View {
        if block.isStrength {
            StrengthSummaryContent(block: block, program: program, history: history, weightUnit: weightUnit,
                                   onStartAnother: onStartAnother, onDone: onDone)
        } else {
            muscleSummary
        }
    }

    @ViewBuilder private var muscleSummary: some View {
        let sets = TrainingBlocks.setsByWeek(block, program: program)
        let strength = TrainingBlocks.strengthChanges(block, program: program, history: history)
        Text(LanguageManager.t("block.summary.title")).blockFont(20, .bold).foregroundStyle(AppColors.text)
            .accessibilityAddTraits(.isHeader)
        BlockSectionLabel(text: LanguageManager.t("block.summary.sets"))
        ForEach(sets, id: \.muscle) { row in
            VStack(alignment: .leading, spacing: 2) {
                Text(BlockFormat.muscle(row.muscle)).blockFont(14, .semibold).foregroundStyle(AppColors.text)
                Text(row.weeks.enumerated().map { "\(LanguageManager.t("block.summary.week", ["week": $0.offset + 1]))\u{00A0}\(BlockFormat.sets($0.element))" }
                    .joined(separator: " · "))
                    .blockFont(13).foregroundStyle(AppColors.secondaryText).fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
        BlockSectionLabel(text: LanguageManager.t("block.summary.strength"))
        if strength.isEmpty { BlockBody(text: LanguageManager.t("block.summary.noStrength")) }
        ForEach(strength, id: \.exerciseName) { change in
            HStack(spacing: 10) {
                Text(change.exerciseName).blockFont(14).foregroundStyle(AppColors.text).frame(maxWidth: .infinity, alignment: .leading)
                Text("\(weightUnit.formatWeight(change.fromKg)) → \(weightUnit.formatWeight(change.toKg))\u{00A0}\(weightUnit.label)")
                    .blockFont(14, .semibold)
                    .foregroundStyle(change.toKg >= change.fromKg ? AppColors.accent : AppColors.secondaryText).fixedSize()
            }
            .accessibilityElement(children: .combine)
        }
        blockPrimaryButton(LanguageManager.t("block.summary.again"), "block-summary-again", action: onStartAnother)
        blockSecondaryButton(LanguageManager.t("common.done"), "block-summary-done", action: onDone)
    }
}

struct TrainingBlockSummarySheet: View {
    let block: TrainingBlock
    let program: Program
    let history: [WorkoutSessionRecord]
    let weightUnit: WeightUnit
    let onStartAnother: () -> Void
    let onDone: () -> Void
    var body: some View {
        BlockSheetPage(identifier: "training-block-summary") {
            TrainingBlockSummaryContent(block: block, program: program, history: history, weightUnit: weightUnit,
                                        onStartAnother: onStartAnother, onDone: onDone)
        }
    }
}

/// Which block sheet Home shows.
enum BlockSheet: Identifiable, Equatable {
    case setup
    case week(Int)
    case summary
    /// The Method page; from the setup, closing it returns there.
    case method(fromSetup: Bool)
    var id: String {
        switch self {
        case .setup: return "setup"
        case .week(let week): return "week-\(week)"
        case .summary: return "summary"
        case .method(let fromSetup): return fromSetup ? "method-setup" : "method"
        }
    }
}

/// A fixed design size that still follows Dynamic Type, like the app's text styles.
private struct BlockFont: ViewModifier {
    let weight: Font.Weight?
    @ScaledMetric private var size: CGFloat

    init(_ size: CGFloat, _ weight: Font.Weight?) {
        self.weight = weight
        _size = ScaledMetric(wrappedValue: size, relativeTo: .body)
    }

    func body(content: Content) -> some View { content.font(.app(size: size, weight: weight)) }
}

private extension View {
    func blockFont(_ size: CGFloat, _ weight: Font.Weight? = nil) -> some View { modifier(BlockFont(size, weight)) }
}

/// A strength week: each lift's top set and back-offs (or the test) and what the other exercises do.
private struct StrengthWeekContent: View {
    let block: TrainingBlock
    let week: Int
    let program: Program
    let scale: SetEffort.Scale
    let onDone: () -> Void

    var body: some View {
        if let plan = TrainingBlockRules.strengthWeek(length: block.length, week: week) {
            let names = Dictionary(TrainingBlocks.liftChoices(program).map { ($0.key, $0.exercise) }, uniquingKeysWith: { first, _ in first })
            Text(LanguageManager.t("block.review.title", ["week": week, "length": block.length]))
                .blockFont(20, .bold).foregroundStyle(AppColors.text).accessibilityAddTraits(.isHeader)
            Text(plan.test ? LanguageManager.t("block.card.test") : plan.taper ? LanguageManager.t("block.card.taper")
                 : LanguageManager.t("block.card.testIn", ["count": plan.weeksToTest]))
                .blockFont(14, .semibold).foregroundStyle(AppColors.purple)
            BlockSectionLabel(text: LanguageManager.t("block.setup.lifts"))
            ForEach(block.lifts ?? [], id: \.self) { key in
                if let exercise = names[key] {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(exercise.displayName).blockFont(15, .semibold).foregroundStyle(AppColors.text)
                        Text(plan.test ? LanguageManager.t("block.review.strengthTest") : BlockFormat.unbroken(LanguageManager.t("block.review.strengthLift", [
                            "reps": plan.topReps, "effort": BlockFormat.tag(plan.topRir, scale: scale), "sets": plan.backoffSets,
                            "backoffReps": plan.backoffReps, "percent": BlockFormat.percent(plan.backoffPercent)])))
                            .blockFont(13).foregroundStyle(AppColors.secondaryText).fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("block-lift-week-\(key)")
                }
            }
            BlockBody(text: LanguageManager.t(plan.weeksToTest <= 1 ? "block.review.accessoriesHalf" : "block.review.accessories"))
            blockPrimaryButton(LanguageManager.t("common.done"), "block-week-start", action: onDone)
        }
    }
}

/// After a strength block's test: each lift's best estimate by week and the heaviest single in the test.
private struct StrengthSummaryContent: View {
    let block: TrainingBlock
    let program: Program
    let history: [WorkoutSessionRecord]
    let weightUnit: WeightUnit
    let onStartAnother: () -> Void
    let onDone: () -> Void

    var body: some View {
        let progress = TrainingBlocks.liftProgress(block, program: program, history: history)
        Text(LanguageManager.t("block.summary.title")).blockFont(20, .bold).foregroundStyle(AppColors.text).accessibilityAddTraits(.isHeader)
        BlockSectionLabel(text: LanguageManager.t("block.summary.e1rm"))
        if !progress.contains(where: { lift in lift.byWeek.contains { $0 != nil } || lift.testKg != nil }) {
            BlockBody(text: LanguageManager.t("block.summary.noStrength"))
        }
        ForEach(progress, id: \.exerciseName) { lift in
            VStack(alignment: .leading, spacing: 2) {
                Text(lift.exerciseName).blockFont(14, .semibold).foregroundStyle(AppColors.text)
                Text(lift.byWeek.enumerated().map { index, kg in
                    "\(LanguageManager.t("block.summary.week", ["week": index + 1]))\u{00A0}\(kg.map(weightUnit.formatWeight) ?? "–")"
                }.joined(separator: " · "))
                    .blockFont(13).foregroundStyle(AppColors.secondaryText).fixedSize(horizontal: false, vertical: true)
                if let test = lift.testKg {
                    Text(LanguageManager.t("block.summary.test", ["load": "\(weightUnit.formatWeight(test))\u{00A0}\(weightUnit.label)"]))
                        .blockFont(14, .semibold).foregroundStyle(AppColors.accent)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("block-summary-lift")
        }
        blockPrimaryButton(LanguageManager.t("block.summary.again"), "block-summary-again", action: onStartAnother)
        blockSecondaryButton(LanguageManager.t("common.done"), "block-summary-done", action: onDone)
    }
}

/// The Method page (docs/adaptive-training.md#phase-f-method-and-why): each adaptive feature's rule in plain words,
/// what rests on evidence and what is a product rule, and the sources. Android `TrainingBlockMethodContent` matches.
struct TrainingBlockMethodContent: View {
    private let topics: [(id: String, symbol: String, tint: Color)] = [
        ("principle", "lightbulb", AppColors.accent), ("rir", "gauge.with.dots.needle.67percent", AppColors.purple),
        ("adjust", "arrow.up.right", AppColors.purple), ("blocks", "calendar.badge.clock", AppColors.purple),
        ("strength", "dumbbell", AppColors.purple), ("readiness", "bed.double", AppColors.purple), ("sources", "book", AppColors.muted)]

    var body: some View {
        Text(LanguageManager.t("method.title")).blockFont(20, .bold).foregroundStyle(AppColors.text).accessibilityAddTraits(.isHeader)
        ForEach(topics, id: \.id) { topic in
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: topic.symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(topic.tint)
                        .frame(width: 18).accessibilityHidden(true)
                    Text(LanguageManager.t("method.\(topic.id)Title")).blockFont(15, .semibold)
                        .foregroundStyle(topic.id == "principle" ? AppColors.accent : AppColors.text)
                        .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)
                }
                Text(LanguageManager.t(topic.id == "sources" ? "method.sources" : "method.\(topic.id)Text"))
                    .blockFont(topic.id == "sources" ? 12 : 13).foregroundStyle(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.surfaceRaised).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(topic.id == "principle" ? AppColors.accent.opacity(0.35) : AppColors.border, lineWidth: 1))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("method-\(topic.id)")
        }
    }
}

struct TrainingBlockMethodSheet: View {
    var body: some View {
        BlockSheetPage(identifier: "training-block-method") { TrainingBlockMethodContent() }
    }
}
