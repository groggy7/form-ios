import SwiftUI

/// What the Home block card shows (docs/training-blocks.md#review-and-edits). Android `BlockCardState` matches.
enum BlockCardState: Equatable {
    case locked
    case none
    case upcoming(TrainingBlock)
    case active(TrainingBlock, week: Int, target: Int, ready: Bool)
    case otherProgram(TrainingBlock, programName: String)
    case complete(TrainingBlock)

    /// `unlocked` is Premium. A block that is already running keeps its whole card when Premium ends, to its last
    /// week and summary; only starting a block needs Premium.
    static func of(block: TrainingBlock?, activeProgram: Program?, programs: [Program], weekKey: String, unlocked: Bool) -> BlockCardState {
        guard let block else { return unlocked ? .none : .locked }
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
                // Wraps rather than truncating, and shrinks before it would break inside "d'entraînement".
                Text(LanguageManager.t("block.card.title")).font(.app(size: titleSize, weight: .bold)).foregroundStyle(AppColors.text)
                    .lineLimit(2).minimumScaleFactor(0.6).fixedSize(horizontal: false, vertical: true)
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
        // A footer's 48pt target is taller than what it shows, so the card's own bottom padding gives way to it.
        .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, state == .locked ? 14 : 8)
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
            footer(end: false) { primary(LanguageManager.t("block.card.start"), "training-block-start", onStart) }
        case .upcoming(let block):
            headline(LanguageManager.t("block.card.startsNext"))
            bodyText(block.isStrength ? LanguageManager.t("block.card.testIn", ["count": block.length])
                     : BlockFormat.targets(length: block.length, scale: scale))
            footer(end: true) { EmptyView() }
        case .active(let block, let week, let target, let ready):
            let toTest = block.length - week
            let detail = block.isStrength
                ? (toTest == 0 ? LanguageManager.t("block.card.test") : toTest == 1 ? LanguageManager.t("block.card.taper")
                   : LanguageManager.t("block.card.testIn", ["count": toTest]))
                : TrainingBlockRules.isDeload(length: block.length, week: week) ? LanguageManager.t("block.card.deload")
                : LanguageManager.t("block.card.target", ["effort": BlockFormat.tag(target, scale: scale)])
            headline(LanguageManager.t("block.card.week", ["week": week, "length": block.length]) + " · " + detail)
            if ready { bodyText(LanguageManager.t("block.card.ready", ["week": week])) }
            footer(end: true) {
                if ready {
                    primary(LanguageManager.t("block.card.review", ["week": week]), "training-block-review") { onReview(week) }
                } else {
                    Button { onReview(week) } label: {
                        Text(LanguageManager.t("block.card.review", ["week": week])).blockFont(14, .semibold)
                            .foregroundStyle(AppColors.purple).multilineTextAlignment(.trailing)
                            .fixedSize(horizontal: false, vertical: true).frame(minHeight: 48)
                    }.buttonStyle(.plain).accessibilityIdentifier("training-block-open-week")
                }
            }
        case .otherProgram(_, let programName):
            bodyText(LanguageManager.t("block.card.otherProgram", ["program": programName]))
            footer(end: true) { EmptyView() }
        case .complete:
            headline(LanguageManager.t("block.card.complete"))
            footer(end: false) { primary(LanguageManager.t("block.card.summary"), "training-block-summary", onSummary) }
        }
    }

    /// The card's last row: the quiet End block at the start and the card's one action at the end, each on one line.
    /// When they cannot share the row (large text, long languages), the action takes its own full-width row with End
    /// block under it, rather than squeezing into a narrow, many-line button. Android `Footer` matches.
    private func footer<Action: View>(end: Bool, @ViewBuilder action: () -> Action) -> some View {
        let action = action()
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                if end { endButton.fixedSize() }
                Spacer(minLength: 0)
                action.fixedSize()
            }
            VStack(alignment: .leading, spacing: 0) {
                action.environment(\.blockActionFills, true)
                if end { endButton }
            }
        }
        .padding(.top, 2)
    }

    private func headline(_ text: String) -> some View {
        Text(text).font(.app(size: headlineSize, weight: .semibold)).foregroundStyle(AppColors.text)
            .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("training-block-headline")
    }

    private func bodyText(_ text: String) -> some View {
        Text(text).font(.app(size: bodySize)).foregroundStyle(AppColors.secondaryText).fixedSize(horizontal: false, vertical: true)
    }

    private func primary(_ label: String, _ identifier: String, _ action: @escaping () -> Void) -> some View {
        BlockPrimaryAction(label: label, identifier: identifier, action: action)
    }

    private var endButton: some View {
        Button { confirmEnd = true } label: {
            Text(LanguageManager.t("block.card.end")).blockFont(13).foregroundStyle(AppColors.muted).frame(minHeight: 48)
        }.buttonStyle(.plain).accessibilityIdentifier("training-block-end")
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
    var unselected = AppColors.surfaceRaised
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label).blockFont(14, .semibold)
                .foregroundStyle(selected ? AppColors.purple : enabled ? AppColors.secondaryText : AppColors.muted)
                .padding(.horizontal, 14).frame(minHeight: 48)
                .background(selected ? AppColors.purpleBg : unselected)
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

/// Goal, length (or lifts and test week), start week, focus muscles and the readiness switch; starting replaces any
/// earlier block. The Method page explains the questions and the rules, so the sheet keeps only the choices.
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
    /// The goal and focus row the sheet opens with; renders use them to show each state.
    var opensOnStrength = false
    var opensFocus = false
    @State private var length = 5
    @State private var focus: [String] = []
    @State private var chosenFocusOpen: Bool?
    @State private var chosenNextWeek: Bool?
    @State private var chosenStrength: Bool?
    @State private var testIn = 6
    @State private var lifts: [String] = []

    private var nextWeek: Bool { chosenNextWeek ?? suggestNextWeek }
    private var strength: Bool { chosenStrength ?? opensOnStrength }
    private var focusOpen: Binding<Bool> { Binding(get: { chosenFocusOpen ?? opensFocus }, set: { chosenFocusOpen = $0 }) }

    var body: some View {
        let choices = TrainingBlocks.focusChoices(program)
        let liftChoices = TrainingBlocks.liftChoices(program)
        let weeks = { (count: Int) in LanguageManager.t("block.setup.weeks", ["count": count]) }
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                // Three lines at most, shrinking before it would break inside a word ("d'entraînement") at accessibility sizes.
                Text(LanguageManager.t("block.setup.title")).blockFont(20, .bold).foregroundStyle(AppColors.text)
                    .lineLimit(3).minimumScaleFactor(0.6)
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
                // A 48pt target whose glyph lines up with the content edge.
                Button(action: onOpenMethod) {
                    Image(systemName: "info.circle").font(.system(size: 19)).foregroundStyle(AppColors.muted)
                        .frame(width: 48, height: 48).contentShape(Rectangle())
                }
                .buttonStyle(.plain).padding(.trailing, -14)
                .accessibilityLabel(LanguageManager.t("method.open")).accessibilityIdentifier("block-setup-method")
            }
            HStack(spacing: 8) {
                BlockGoalCard(symbol: "calendar.badge.clock", title: LanguageManager.t("block.setup.muscle"),
                              hint: LanguageManager.t("block.setup.muscleHint"), selected: !strength, identifier: "block-goal-muscle") {
                    chosenStrength = false
                }
                BlockGoalCard(symbol: "dumbbell", title: LanguageManager.t("block.setup.strength"),
                              hint: LanguageManager.t("block.setup.strengthHint"), selected: strength, identifier: "block-goal-strength") {
                    chosenStrength = true
                }
            }
            .fixedSize(horizontal: false, vertical: true).padding(.top, 12).padding(.bottom, 22)
            if strength {
                BlockSetupHeader(text: LanguageManager.t("block.setup.lifts"),
                                 value: liftChoices.isEmpty ? nil : LanguageManager.t("block.setup.liftsLimit"))
                if liftChoices.isEmpty { BlockBody(text: LanguageManager.t("block.setup.noLifts")) }
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
                .padding(.bottom, 22)
                BlockSetupHeader(text: LanguageManager.t("block.setup.testIn"), value: weeks(testIn))
                BlockSegments(options: Array(TrainingBlockRules.strengthLengths), selected: testIn, label: { "\($0)" }, spoken: weeks,
                              identifier: { "block-test-\($0)" }) { testIn = $0 }
                BlockWeekStrip(cells: BlockStrip.strength(length: testIn), lead: nil,
                               description: LanguageManager.t("block.setup.strengthPlan"))
                    .padding(.top, 8)
            } else {
                BlockSetupHeader(text: LanguageManager.t("block.setup.length"), value: weeks(length))
                BlockSegments(options: Array(TrainingBlockRules.lengths), selected: length, label: { "\($0)" }, spoken: weeks,
                              identifier: { "block-length-\($0)" }) { length = $0 }
                BlockWeekStrip(cells: BlockStrip.muscle(length: length, scale: scale),
                               lead: LanguageManager.t(scale == .rir ? "effort.scale.rir" : "effort.scale.rpe"),
                               description: LanguageManager.t("block.setup.targets", ["targets": BlockFormat.targets(length: length, scale: scale)]))
                    .padding(.top, 8)
            }
            BlockSetupHeader(text: LanguageManager.t("block.setup.when")).padding(.top, 22)
            BlockSegments(options: [false, true], selected: nextWeek,
                          label: { LanguageManager.t($0 ? "block.setup.nextWeek" : "block.setup.thisWeek") },
                          identifier: { $0 ? "block-start-next-week" : "block-start-this-week" }) { chosenNextWeek = $0 }
                .padding(.bottom, 22)
            if !strength && !choices.isEmpty {
                BlockFocusPicker(choices: choices, focus: $focus, open: focusOpen).padding(.bottom, 8)
            }
            if let readinessCheck {
                Toggle(isOn: readinessCheck) {
                    Text(LanguageManager.t("block.setup.readiness")).blockFont(14, .medium).foregroundStyle(AppColors.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .tint(AppColors.accent)
                .padding(.leading, 14).padding(.trailing, 12).padding(.vertical, 6).frame(minHeight: 56)
                .background(AppColors.surfaceRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AppColors.border, lineWidth: 1))
                .accessibilityIdentifier("block-setup-readiness")
            }
            if replacesBlock {
                Text(LanguageManager.t("block.setup.replaces")).blockFont(13).foregroundStyle(AppColors.muted)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 22)
            }
            blockPrimaryButton(LanguageManager.t("block.setup.confirm"), "block-setup-confirm") {
                if strength { onStartStrength(testIn, lifts, nextWeek) } else { onStart(length, focus, nextWeek) }
            }
            .disabled(strength && lifts.isEmpty).opacity(strength && lifts.isEmpty ? 0.4 : 1)
            .padding(.top, replacesBlock ? 10 : 22)
        }
    }
}

/// A setup heading with the chosen value quietly at its end: "Length … 5 weeks".
private struct BlockSetupHeader: View {
    let text: String
    var value: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(text).blockFont(14, .semibold).foregroundStyle(AppColors.text).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading).accessibilityAddTraits(.isHeader)
            if let value { Text(value).blockFont(13).foregroundStyle(AppColors.muted) }
        }
        .padding(.bottom, 8)
    }
}

/// A goal: its glyph from the Method page, its name and one line on what it does. Cards in the row share one height.
private struct BlockGoalCard: View {
    let symbol: String
    let title: String
    let hint: String
    let selected: Bool
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: symbol).font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(selected ? AppColors.purple : AppColors.muted).frame(height: 20).accessibilityHidden(true)
                Text(title).blockFont(15, .semibold).foregroundStyle(selected ? AppColors.text : AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 8)
                Text(hint).blockFont(12).foregroundStyle(selected ? AppColors.secondaryText : AppColors.muted)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 2)
            }
            .padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(selected ? AppColors.purpleBg : AppColors.surfaceRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(selected ? AppColors.purple.opacity(0.7) : AppColors.border, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}

/// One of a few, as a full-width bar: equal segments with 48pt targets that grow together when a label wraps.
private struct BlockSegments<Value: Hashable>: View {
    let options: [Value]
    let selected: Value
    let label: (Value) -> String
    var spoken: ((Value) -> String)? = nil
    let identifier: (Value) -> String
    let onSelect: (Value) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selected
                let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
                Button { onSelect(option) } label: {
                    Text(label(option)).blockFont(14, .semibold).multilineTextAlignment(.center)
                        .foregroundStyle(isSelected ? AppColors.purple : AppColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 6).padding(.vertical, 8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(isSelected ? AppColors.purpleBg : Color.clear, in: shape)
                        .overlay(shape.stroke(isSelected ? AppColors.purple.opacity(0.7) : Color.clear, lineWidth: 1))
                        .padding(3).frame(minHeight: 48).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(spoken?(option) ?? label(option))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier(identifier(option))
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(AppColors.surfaceRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AppColors.border, lineWidth: 1))
    }
}

/// A week in the strip: `level` 1–3 deepens the purple with the work, 0 is a quiet deload or taper; the test is outlined.
struct BlockStripCell: Equatable {
    let label: String
    let level: Int
    var outlined = false
    var weight: CGFloat = 1
}

enum BlockStrip {
    /// RIR 3 · 2 · 2 · 1, then a deload cell twice as wide for its word.
    static func muscle(length: Int, scale: SetEffort.Scale) -> [BlockStripCell] {
        TrainingBlockRules.targets(length: length).dropLast().map { BlockStripCell(label: SetEffort.chipLabel($0, scale: scale), level: min(max(4 - $0, 1), 3)) }
            + [BlockStripCell(label: LanguageManager.t("block.setup.deload"), level: 0, weight: 2)]
    }

    /// Each week's top set reps: ×5 … ×3, the taper's ×2 and the test's singles.
    static func strength(length: Int) -> [BlockStripCell] {
        (1...length).compactMap { TrainingBlockRules.strengthWeek(length: length, week: $0) }.map { week in
            if week.test { return BlockStripCell(label: "×1", level: 3, outlined: true) }
            if week.taper { return BlockStripCell(label: "×\(week.topReps)", level: 0) }
            return BlockStripCell(label: "×\(week.topReps)", level: min(max(6 - week.topReps, 1), 3))
        }
    }
}

/// The block's weeks at a glance. VoiceOver hears `description`, the same line the sheet used to show.
private struct BlockWeekStrip: View {
    let cells: [BlockStripCell]
    let lead: String?
    let description: String
    /// In a week's review the strip marks that week and dims the rest; the setup outlines the test week instead.
    var current: Int? = nil
    private static let levels = [0.2, 0.34, 0.5]

    var body: some View {
        HStack(spacing: 8) {
            if let lead { Text(lead).blockFont(11, .semibold).foregroundStyle(AppColors.muted).fixedSize() }
            BlockStripLayout(weights: cells.map(\.weight), spacing: 4) {
                ForEach(Array(cells.enumerated()), id: \.offset) { index, cell in
                    let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
                    let quiet = cell.level == 0
                    let here = current == index + 1
                    let outlined = current == nil ? cell.outlined : here
                    // Sized to fit its cell: "Décharge" stays whole at accessibility sizes.
                    Text(cell.label).blockFont(13, .semibold).lineLimit(1).minimumScaleFactor(0.5)
                        .foregroundStyle(quiet ? AppColors.secondaryText : AppColors.text)
                        .padding(.horizontal, 4).padding(.vertical, 6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center).frame(minHeight: 36)
                        .background(quiet ? AppColors.surfaceRaised : Color.mix(AppColors.surface, AppColors.purple, Self.levels[cell.level - 1]),
                                    in: shape)
                        .overlay(shape.stroke(outlined ? AppColors.purple : quiet ? AppColors.border : Color.clear, lineWidth: here ? 1.5 : 1))
                        .opacity(current == nil || here ? 1 : 0.45)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(description)
        .accessibilityIdentifier("block-setup-targets")
    }
}

/// Lays the strip's cells out in one row, splitting the width by each cell's weight.
private struct BlockStripLayout: Layout {
    let weights: [CGFloat]
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        let height = zip(subviews, widths(width)).map { $0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height }.max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (subview, width) in zip(subviews, widths(bounds.width)) {
            subview.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(width: width, height: bounds.height))
            x += width + spacing
        }
    }

    private func widths(_ width: CGFloat) -> [CGFloat] {
        let total = weights.reduce(0, +)
        let free = max(0, width - spacing * CGFloat(max(weights.count - 1, 0)))
        return weights.map { total > 0 ? free * $0 / total : 0 }
    }
}

/// Optional focus muscles, folded into one row until opened; closed, it names the chosen ones.
private struct BlockFocusPicker: View {
    let choices: [String]
    @Binding var focus: [String]
    @Binding var open: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(.easeOut(duration: 0.2)) { open.toggle() } } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(LanguageManager.t("block.setup.focus")).blockFont(14, .semibold).foregroundStyle(AppColors.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(focus.isEmpty ? LanguageManager.t("block.setup.focusOptional") : focus.map(BlockFormat.muscle).joined(separator: ", "))
                            .blockFont(13).foregroundStyle(focus.isEmpty ? AppColors.muted : AppColors.purple)
                            .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("block-setup-focus-value")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.down").font(.system(size: 14, weight: .semibold)).foregroundStyle(AppColors.muted)
                        .rotationEffect(.degrees(open ? 180 : 0)).accessibilityHidden(true)
                }
                .padding(.horizontal, 14).padding(.vertical, 10).frame(minHeight: 56).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityIdentifier("block-setup-focus")
            if open {
                VStack(alignment: .leading, spacing: 10) {
                    BlockBody(text: LanguageManager.t("block.setup.focusEffect"))
                    BlockFlow {
                        ForEach(choices, id: \.self) { muscle in
                            let selected = focus.contains(muscle)
                            BlockChoice(label: BlockFormat.muscle(muscle), selected: selected, identifier: "block-focus-\(muscle)",
                                        enabled: selected || focus.count < TrainingBlockRules.maxFocus, unselected: AppColors.surface) {
                                if selected { focus.removeAll { $0 == muscle } } else { focus.append(muscle) }
                            }
                        }
                    }
                }
                .padding(.horizontal, 14).padding(.bottom, 14)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surfaceRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AppColors.border, lineWidth: 1))
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

/// One block week: this week in the block's strip, each muscle's change with its reasons, each exercise's sets, and
/// optional edits. Editing sits on its section's heading, so Start is the sheet's one button.
struct TrainingBlockWeekContent: View {
    let block: TrainingBlock
    let week: Int
    let program: Program
    let scale: SetEffort.Scale
    let onStartWeek: ([String: Int]) -> Void
    /// Whether the sheet opens editing; renders use it to show the steppers.
    var opensEditing = false
    @State private var chosenEditing: Bool?
    @State private var edits: [String: Int] = [:]

    private var editing: Bool { chosenEditing ?? opensEditing }

    private struct Row: Identifiable {
        let exercise: Exercise
        let key: String
        let before: Int
        let now: Int
        var id: String { key }
    }

    var body: some View {
        if block.isStrength {
            StrengthWeekContent(block: block, week: week, program: program, scale: scale) { onStartWeek([:]) }
        } else if block.weeks.indices.contains(week - 1) {
            let current = block.weeks[week - 1]
            let previous = block.weeks.indices.contains(week - 2) ? block.weeks[week - 2] : nil
            let deload = TrainingBlockRules.isDeload(length: block.length, week: week)
            // Each workout's rows: exercises whose sets changed or were edited, or every exercise while editing.
            let groups: [(title: String, rows: [Row])] = program.workouts.compactMap { workout in
                let rows = workout.exercises.compactMap { exercise -> Row? in
                    let key = TrainingBlocks.key(workout, exercise)
                    guard let now = edits[key] ?? current.sets[key] else { return nil }
                    let before = previous?.sets[key] ?? WorkoutSessionUtils.initialSetCount(exercise: exercise)
                    return editing || before != now || current.edited.contains(key) ? Row(exercise: exercise, key: key, before: before, now: now) : nil
                }
                return rows.isEmpty ? nil : (workout.title, rows)
            }
            VStack(alignment: .leading, spacing: 0) {
                BlockWeekHeader(title: LanguageManager.t("block.review.title", ["week": week, "length": block.length]),
                                target: deload ? LanguageManager.t("block.review.deload")
                                    : LanguageManager.t("block.review.target", ["effort": BlockFormat.tag(TrainingBlockRules.target(length: block.length, week: week) ?? 0, scale: scale)]))
                BlockWeekStrip(cells: BlockStrip.muscle(length: block.length, scale: scale),
                               lead: LanguageManager.t(scale == .rir ? "effort.scale.rir" : "effort.scale.rpe"),
                               description: LanguageManager.t("block.setup.targets", ["targets": BlockFormat.targets(length: block.length, scale: scale)]),
                               current: week)
                    // The exercise heading's 48pt action row brings its own room, so the gap above it is smaller.
                    .padding(.bottom, current.changes.isEmpty ? 12 : 22)
                if !current.changes.isEmpty {
                    BlockSetupHeader(text: LanguageManager.t("block.review.muscles"))
                    BlockGroup {
                        ForEach(Array(current.changes.enumerated()), id: \.element.muscle) { index, change in
                            if index > 0 { BlockGroupDivider() }
                            // The reasons run the full width under the name and pill, so long words never break.
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 12) {
                                    Text(BlockFormat.muscle(change.muscle)).blockFont(15, .semibold).foregroundStyle(AppColors.text)
                                        .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                                    BlockChangePill(from: BlockFormat.sets(change.from), to: BlockFormat.sets(change.to),
                                                    direction: change.to > change.from ? 1 : change.to < change.from ? -1 : 0)
                                }
                                Text(BlockFormat.reasons(change.reasons)).blockFont(13).foregroundStyle(AppColors.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14).padding(.vertical, 12)
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("block-change-\(change.muscle)")
                        }
                    }
                    .padding(.bottom, 12)
                }
                HStack(spacing: 8) {
                    Text(LanguageManager.t("block.review.exercises")).blockFont(14, .semibold).foregroundStyle(AppColors.text)
                        .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)
                    Button { chosenEditing = !editing } label: {
                        // One line: the heading beside it wraps instead.
                        Text(LanguageManager.t(editing ? "common.done" : "block.review.edit")).blockFont(14, .semibold).lineLimit(1).fixedSize()
                            .foregroundStyle(AppColors.purple).padding(.horizontal, 12).frame(minHeight: 48).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).padding(.trailing, -12).accessibilityIdentifier("block-week-edit")
                }
                BlockGroup {
                    if groups.isEmpty {
                        Text(LanguageManager.t("block.review.none")).blockFont(13).foregroundStyle(AppColors.muted)
                            .fixedSize(horizontal: false, vertical: true).padding(14)
                    }
                    ForEach(Array(groups.enumerated()), id: \.offset) { groupIndex, group in
                        Text(group.title).blockFont(12, .semibold).foregroundStyle(AppColors.muted)
                            .padding(.horizontal, 14).padding(.top, groupIndex == 0 ? 12 : 18).padding(.bottom, 2)
                        ForEach(Array(group.rows.enumerated()), id: \.element.id) { index, row in
                            if index > 0 { BlockGroupDivider() }
                            exerciseRow(row, edited: current.edited.contains(row.key) || edits[row.key] != nil)
                        }
                    }
                }
                blockPrimaryButton(LanguageManager.t("block.review.start", ["week": week]), "block-week-start") { onStartWeek(edits) }
                    .padding(.top, 22)
            }
        }
    }

    private func exerciseRow(_ row: Row, edited: Bool) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.exercise.displayName).blockFont(14).foregroundStyle(AppColors.text).fixedSize(horizontal: false, vertical: true)
                if edited {
                    Text(LanguageManager.t("block.review.edited")).blockFont(11, .semibold).foregroundStyle(AppColors.purple)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if editing {
                HStack(spacing: 0) {
                    stepperButton("minus", enabled: row.now > 1, label: LanguageManager.t("block.review.fewer", ["exercise": row.exercise.displayName]),
                                  identifier: "block-fewer-\(row.key)") { edits[row.key] = max(1, row.now - 1) }
                    Text("\(row.now)").blockFont(16, .semibold).foregroundStyle(AppColors.text).frame(minWidth: 20)
                    stepperButton("plus", enabled: row.now < TrainingBlocks.maxExerciseSets,
                                  label: LanguageManager.t("block.review.more", ["exercise": row.exercise.displayName]),
                                  identifier: "block-more-\(row.key)") { edits[row.key] = min(TrainingBlocks.maxExerciseSets, row.now + 1) }
                }
                .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(AppColors.border, lineWidth: 1))
            } else {
                // The heading already says these are sets; VoiceOver still hears "3 → 5 sets".
                Text("\(row.before)\u{00A0}→\u{00A0}\(row.now)").blockFont(13).foregroundStyle(AppColors.secondaryText).fixedSize()
                    .accessibilityLabel(LanguageManager.t("block.review.sets", ["from": row.before, "to": row.now]))
            }
        }
        .padding(.leading, 14).padding(.trailing, editing ? 8 : 14).padding(.vertical, 6).frame(minHeight: 52)
        .accessibilityIdentifier("block-exercise-\(row.key)")
    }

    private func stepperButton(_ symbol: String, enabled: Bool, label: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).frame(width: 48, height: 48).contentShape(Rectangle())
        }
        .buttonStyle(.plain).foregroundStyle(enabled ? AppColors.secondaryText : AppColors.muted.opacity(0.4)).disabled(!enabled)
        .accessibilityLabel(label).accessibilityIdentifier(identifier)
    }
}

/// The week's title and its target (or what the deload or taper asks) in purple, above the block's strip.
private struct BlockWeekHeader: View {
    let title: String
    let target: String
    var body: some View {
        Text(title).blockFont(20, .bold).foregroundStyle(AppColors.text).accessibilityAddTraits(.isHeader)
        Text(target).blockFont(14, .semibold).foregroundStyle(AppColors.purple).fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4).padding(.bottom, 14).accessibilityIdentifier("block-week-target")
    }
}

/// Rows of one kind, contained in a single raised card.
private struct BlockGroup<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.surfaceRaised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AppColors.border, lineWidth: 1))
    }
}

private struct BlockGroupDivider: View {
    var body: some View { Rectangle().fill(AppColors.border).frame(height: 1).padding(.leading, 14) }
}

/// A muscle's weekly sets as a pill: accent for more, amber for fewer, quiet for a hold.
private struct BlockChangePill: View {
    let from: String
    let to: String
    let direction: Int
    var body: some View { BlockPill(text: LanguageManager.t("block.review.sets", ["from": from, "to": to]), direction: direction) }
}

/// A result: accent when it went up, amber when it went down, quiet when it held. Inside `alignedBlockPills()` it takes
/// its group's widest pill's width.
private struct BlockPill: View {
    let text: String
    let direction: Int
    @Environment(\.blockPillWidth) private var sharedWidth
    var body: some View {
        Text(text).blockFont(13, .semibold).lineLimit(1).fixedSize()
            .foregroundStyle(direction > 0 ? AppColors.accent : direction < 0 ? AppColors.warmupAmber : AppColors.secondaryText)
            .padding(.horizontal, 8).padding(.vertical, 4)
            // Its own width, measured before the shared one applies.
            .background(GeometryReader { Color.clear.preference(key: BlockPillWidthKey.self, value: $0.size.width) })
            .frame(minWidth: sharedWidth)
            .background(direction > 0 ? AppColors.positiveBg : direction < 0 ? AppColors.warmupAmberBg : AppColors.surface,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct BlockPillWidthKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// A compact accent button: 40pt shown inside a 48pt target, so it never towers over the card's text. In a stacked
/// footer it fills the row.
private struct BlockPrimaryAction: View {
    let label: String
    let identifier: String
    let action: () -> Void
    @Environment(\.blockActionFills) private var fills

    var body: some View {
        Button(action: action) {
            Text(label).blockFont(14, .semibold).foregroundStyle(AppColors.background)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .frame(maxWidth: fills ? .infinity : nil, minHeight: 40)
                .background(AppColors.accent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .frame(minHeight: 48).contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityIdentifier(identifier)
    }
}

private struct BlockActionFillsEnvironment: EnvironmentKey {
    static let defaultValue = false
}

private extension EnvironmentValues {
    /// The block card's footer stacked, so its action fills the row.
    var blockActionFills: Bool {
        get { self[BlockActionFillsEnvironment.self] }
        set { self[BlockActionFillsEnvironment.self] = newValue }
    }
}

private struct BlockPillWidthEnvironment: EnvironmentKey {
    static var defaultValue: CGFloat? { nil }
}

private extension EnvironmentValues {
    var blockPillWidth: CGFloat? {
        get { self[BlockPillWidthEnvironment.self] }
        set { self[BlockPillWidthEnvironment.self] = newValue }
    }
}

/// Gives a summary group's pills one width, the widest of them, so every row's bars start at one x. Without it,
/// "7,5 → 7,5" and "16,5 → 16,5" left the bars ragged.
private struct AlignedBlockPills: ViewModifier {
    @State private var width: CGFloat = 0
    func body(content: Content) -> some View {
        content
            .environment(\.blockPillWidth, width > 0 ? width : nil)
            .onPreferenceChange(BlockPillWidthKey.self) { widest in width = widest }
    }
}

private extension View {
    func alignedBlockPills() -> some View { modifier(AlignedBlockPills()) }
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
        VStack(alignment: .leading, spacing: 0) {
            BlockSummaryHeader(block: block)
            BlockSetupHeader(text: LanguageManager.t("block.summary.sets"))
            BlockGroup {
                ForEach(Array(sets.enumerated()), id: \.element.muscle) { index, row in
                    if index > 0 { BlockGroupDivider() }
                    // Week 1 against the last hard week; the deload, when there, is the quiet last bar.
                    let hard = Array(row.weeks.prefix(block.length - 1))
                    let from = hard.first ?? 0
                    let to = hard.last ?? 0
                    BlockSummaryRow(name: BlockFormat.muscle(row.muscle), weeks: row.weeks.map { Optional($0) },
                                    pill: "\(BlockFormat.sets(from))\u{00A0}→\u{00A0}\(BlockFormat.sets(to))",
                                    spokenPill: LanguageManager.t("block.review.sets", ["from": BlockFormat.sets(from), "to": BlockFormat.sets(to)]),
                                    direction: to > from ? 1 : to < from ? -1 : 0, quietLast: row.weeks.count >= block.length, fromZero: true,
                                    weeksText: row.weeks.enumerated().map { "\(LanguageManager.t("block.summary.week", ["week": $0.offset + 1]))\u{00A0}\(BlockFormat.sets($0.element))" }
                                        .joined(separator: " · "), identifier: "block-summary-muscle-\(row.muscle)")
                }
            }
            .alignedBlockPills()
            BlockSetupHeader(text: LanguageManager.t("block.summary.strength")).padding(.top, 22)
            BlockGroup {
                if strength.isEmpty { BlockSummaryNote(text: LanguageManager.t("block.summary.noStrength")) }
                ForEach(Array(strength.enumerated()), id: \.element.exerciseName) { index, change in
                    if index > 0 { BlockGroupDivider() }
                    let text = "\(weightUnit.formatWeight(change.fromKg))\u{00A0}→\u{00A0}\(weightUnit.formatWeight(change.toKg))\u{00A0}\(weightUnit.label)"
                    BlockSummaryRow(name: change.exerciseName, weeks: nil, pill: text, spokenPill: text,
                                    direction: change.toKg > change.fromKg ? 1 : change.toKg < change.fromKg ? -1 : 0)
                }
            }
            .alignedBlockPills()
            BlockSummaryActions(onStartAnother: onStartAnother, onDone: onDone)
        }
    }
}

/// "Block complete", then which block it was in purple: "Build muscle · 5 weeks".
private struct BlockSummaryHeader: View {
    let block: TrainingBlock
    var body: some View {
        BlockWeekHeader(title: LanguageManager.t("block.summary.title"),
                        target: LanguageManager.t(block.isStrength ? "block.setup.strength" : "block.setup.muscle") + " · "
                            + LanguageManager.t("block.setup.weeks", ["count": block.length]))
            .padding(.bottom, 8)
    }
}

private struct BlockSummaryNote: View {
    let text: String
    var body: some View {
        Text(text).blockFont(13).foregroundStyle(AppColors.muted).fixedSize(horizontal: false, vertical: true).padding(14)
    }
}

private struct BlockSummaryActions: View {
    let onStartAnother: () -> Void
    let onDone: () -> Void
    var body: some View {
        blockPrimaryButton(LanguageManager.t("block.summary.again"), "block-summary-again", action: onStartAnother).padding(.top, 22)
        blockSecondaryButton(LanguageManager.t("common.done"), "block-summary-done", action: onDone).padding(.top, 10)
    }
}

/// A summary row: the name, its weeks as small bars when there are any, and the result as a pill. VoiceOver hears the
/// name, every week's value (`weeksText`) and the result.
private struct BlockSummaryRow: View {
    let name: String
    let weeks: [Double?]?
    let pill: String?
    let spokenPill: String?
    let direction: Int
    var quietLast = false
    var fromZero = false
    var weeksText: String? = nil
    var identifier: String? = nil
    @Environment(\.blockPillWidth) private var pillWidth

    var body: some View {
        HStack(spacing: 12) {
            Text(name).blockFont(15, .semibold).foregroundStyle(AppColors.text).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            // Bars and pills keep their slots, in a row without them too, so the group reads in columns.
            if let weeks { BlockWeekBars(values: weeks, quietLast: quietLast, fromZero: fromZero) }
            if let pill { BlockPill(text: pill, direction: direction) } else if let pillWidth { Color.clear.frame(width: pillWidth, height: 1) }
        }
        .padding(.horizontal, 14).padding(.vertical, 10).frame(minHeight: 52)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([name, weeksText, spokenPill].compactMap { $0 }.joined(separator: ", "))
        .accessibilityIdentifier(identifier ?? "")
    }
}

/// Each week's bar height as a share of the full bar, nil for a week without a value. Sets rise from zero; estimated
/// 1RMs use their own range, since a few kilograms would not show from zero, but that range spans at least a tenth of
/// the best week, so a kilogram or two still looks small (a taper week's lighter estimate is not a drop).
func weekBarFractions(_ values: [Double?], fromZero: Bool) -> [Double?] {
    let known = values.compactMap { $0 }
    let top = known.max() ?? 0
    let bottom = fromZero ? 0 : min(known.min() ?? 0, top * 0.9)
    return values.map { value in
        guard let value else { return nil }
        if top <= bottom { return 1 }
        return fromZero ? value / top : 0.35 + 0.65 * (value - bottom) / (top - bottom)
    }
}

/// Small bars, one per week (`weekBarFractions`). The deload is quiet and a week without a value keeps its slot as a stub.
private struct BlockWeekBars: View {
    let values: [Double?]
    let quietLast: Bool
    let fromZero: Bool

    var body: some View {
        let fractions = weekBarFractions(values, fromZero: fromZero)
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                let fraction = fractions[index] ?? 0
                let quiet = quietLast && index == values.count - 1
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(value == nil ? AppColors.border : quiet ? AppColors.muted.opacity(0.45) : AppColors.purple)
                    .frame(width: 6, height: value == nil ? 2 : max(3, 22 * fraction))
            }
        }
        .frame(height: 22, alignment: .bottom)
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
    /// The Method page from the block card. The setup shows it over itself instead, keeping its choices.
    case method
    var id: String {
        switch self {
        case .setup: return "setup"
        case .week(let week): return "week-\(week)"
        case .summary: return "summary"
        case .method: return "method"
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
            let lifts = (block.lifts ?? []).compactMap { key in names[key].map { (key: key, exercise: $0) } }
            VStack(alignment: .leading, spacing: 0) {
                BlockWeekHeader(title: LanguageManager.t("block.review.title", ["week": week, "length": block.length]),
                                target: plan.test ? LanguageManager.t("block.card.test") : plan.taper ? LanguageManager.t("block.card.taper")
                                    : LanguageManager.t("block.card.testIn", ["count": plan.weeksToTest]))
                BlockWeekStrip(cells: BlockStrip.strength(length: block.length), lead: nil,
                               description: LanguageManager.t("block.setup.strengthPlan"), current: week)
                    .padding(.bottom, 22)
                BlockSetupHeader(text: LanguageManager.t("block.setup.lifts"))
                BlockGroup {
                    ForEach(Array(lifts.enumerated()), id: \.element.key) { index, lift in
                        if index > 0 { BlockGroupDivider() }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(lift.exercise.displayName).blockFont(15, .semibold).foregroundStyle(AppColors.text)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(plan.test ? LanguageManager.t("block.review.strengthTest") : BlockFormat.unbroken(LanguageManager.t("block.review.strengthLift", [
                                "reps": plan.topReps, "effort": BlockFormat.tag(plan.topRir, scale: scale), "sets": plan.backoffSets,
                                "backoffReps": plan.backoffReps, "percent": BlockFormat.percent(plan.backoffPercent)])))
                                .blockFont(13).foregroundStyle(AppColors.secondaryText).fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("block-lift-week-\(lift.key)")
                    }
                }
                Text(LanguageManager.t(plan.weeksToTest <= 1 ? "block.review.accessoriesHalf" : "block.review.accessories"))
                    .blockFont(13).foregroundStyle(AppColors.muted).fixedSize(horizontal: false, vertical: true).padding(.top, 10)
                blockPrimaryButton(LanguageManager.t("common.done"), "block-week-start", action: onDone).padding(.top, 22)
            }
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
        let load = { (kg: Double) in "\(weightUnit.formatWeight(kg))\u{00A0}\(weightUnit.label)" }
        VStack(alignment: .leading, spacing: 0) {
            BlockSummaryHeader(block: block)
            BlockSetupHeader(text: LanguageManager.t("block.summary.e1rm"))
            BlockGroup {
                if !progress.contains(where: { lift in lift.byWeek.contains { $0 != nil } || lift.testKg != nil }) {
                    BlockSummaryNote(text: LanguageManager.t("block.summary.noStrength"))
                }
                ForEach(Array(progress.enumerated()), id: \.element.exerciseName) { index, lift in
                    if index > 0 { BlockGroupDivider() }
                    // The test's heaviest single is the result; without one, the first estimate against the last.
                    let estimates = lift.byWeek.compactMap { $0 }
                    let pill: String? = lift.testKg.map { LanguageManager.t("block.summary.test", ["load": load($0)]) }
                        ?? (estimates.count >= 2 ? "\(weightUnit.formatWeight(estimates[0]))\u{00A0}→\u{00A0}\(load(estimates[estimates.count - 1]))" : nil)
                    let direction = lift.testKg != nil ? 1
                        : estimates.count >= 2 ? (estimates[estimates.count - 1] > estimates[0] ? 1 : estimates[estimates.count - 1] < estimates[0] ? -1 : 0) : 0
                    BlockSummaryRow(name: lift.exerciseName, weeks: lift.byWeek, pill: pill, spokenPill: pill, direction: direction,
                                    weeksText: lift.byWeek.enumerated().map { index, kg in
                                        "\(LanguageManager.t("block.summary.week", ["week": index + 1]))\u{00A0}\(kg.map(weightUnit.formatWeight) ?? "–")"
                                    }.joined(separator: " · "), identifier: "block-summary-lift")
                }
            }
            .alignedBlockPills()
            BlockSummaryActions(onStartAnother: onStartAnother, onDone: onDone)
        }
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
