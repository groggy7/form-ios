import SwiftUI
import Observation

/// What a session field holds: a load, a rep count, or a partial-rep count.
public enum KeypadKind: Equatable { case weight, reps, partials }

/// The keypad's action key: on to the set's reps, log the set, or close.
public enum KeypadAction: Equatable { case next, log, done }

/// A heading shortcut such as Previous, Plates or the warm-up switch.
struct KeypadShortcut {
    let tag: String
    let description: String
    var text: String? = nil
    var systemImage: String? = nil
    var tint: Color = AppColors.text
    let action: () -> Void
}

/// One editable session value. Fields rebuild it on every render, so its callbacks see current values.
struct KeypadField {
    let id: String
    let kind: KeypadKind
    let unit: WeightUnit
    /// The field's spoken name, e.g. "SET 1, WEIGHT (KG)".
    let label: String
    /// The keypad's heading, e.g. "SET 1 · WEIGHT (KG)".
    let title: String
    let value: String
    /// The ± step in the field's own unit: the equipment's load step, or one rep.
    let step: Double
    let action: KeypadAction
    let onValue: (String) -> Void
    let onAction: () -> Void
    let onDismiss: () -> Void
    var previous: KeypadShortcut? = nil
    var tools: [KeypadShortcut] = []

    /// Everything the keypad shows, plus the row the callbacks were built from; a change rebinds the field.
    func signature(row: ExerciseSetLog) -> KeypadSignature {
        KeypadSignature(id: id, value: value, title: title, label: label, action: action, step: step,
                        previous: previous?.text, tools: tools.map { $0.tag + $0.description }, row: row)
    }
}

struct KeypadSignature: Equatable {
    let id: String
    let value: String
    let title: String
    let label: String
    let action: KeypadAction
    let step: Double
    let previous: String?
    let tools: [String]
    let row: ExerciseSetLog
}

/// Pure editing rules, shared by the keypad and hardware keys.
enum KeypadInput {
    /// The value after typing `key` (a digit or a separator), or nil when the field would refuse it.
    static func type(_ current: String, _ key: Character, kind: KeypadKind, unit: WeightUnit, replacing: Bool) -> String? {
        let base = replacing ? "" : current
        let candidate: String
        if key == "." || key == "," {
            guard kind == .weight, !base.contains(".") else { return nil }
            candidate = (base.isEmpty ? "0" : base) + "."
        } else if key.isASCII, key.isNumber {
            candidate = base == "0" ? String(key) : base + String(key)
        } else {
            return nil
        }
        return accept(candidate, kind: kind, unit: unit)
    }

    /// The normalized value, or nil when `text` is not a valid entry for the field.
    static func accept(_ text: String, kind: KeypadKind, unit: WeightUnit) -> String? {
        switch kind {
        case .weight: return WorkoutSessionUtils.sanitizedWeightInput(text, unit: unit)
        case .reps: return WorkoutSessionUtils.sanitizedRepsInput(text)
        case .partials: return IntensitySets.sanitizedPartialInput(text)
        }
    }

    static func delete(_ current: String, replacing: Bool) -> String { replacing ? "" : String(current.dropLast()) }

    /// One ± press: loads move by the equipment step within the unit's limit; counts move by one and empty at zero.
    static func step(_ current: String, by direction: Int, kind: KeypadKind, unit: WeightUnit, step: Double) -> String {
        switch kind {
        case .weight:
            let value = WorkoutSessionUtils.sanitizedWeightInput(current, unit: unit).flatMap { Decimal(string: $0) } ?? 0
            let limit = Decimal(WorkoutSessionUtils.maxAllowedWeight(unit: unit))
            var next = min(limit, max(0, value + Decimal(step) * Decimal(direction)))
            var rounded = Decimal()
            NSDecimalRound(&rounded, &next, 2, .plain)
            return NSDecimalNumber(decimal: rounded).stringValue
        case .reps:
            return WorkoutSessionUtils.adjustReps(current, by: direction)
        case .partials:
            let next = min(99, max(0, (Int(current) ?? 0) + direction))
            return next == 0 ? "" : "\(next)"
        }
    }

    /// "2.5" shown with the app language's decimal separator.
    static func display(_ value: String) -> String { value.replacingOccurrences(of: ".", with: decimalSeparator) }

    static var decimalSeparator: String { LanguageManager.numberLocale.decimalSeparator ?? "." }

    static func stepLabel(_ step: Double) -> String {
        display(NSDecimalNumber(decimal: Decimal(step)).stringValue)
    }
}

/// The session's own number pad. The selected field becomes its target; typed values go straight to the draft
/// through the field's callback. The keypad keeps its own copy of the text, so two quick presses before the table
/// renders again never read a stale value.
@MainActor @Observable
public final class SessionKeypad {
    private(set) var target: KeypadField?
    /// The first key replaces the value the field opened with, like a selected value.
    private(set) var replacing = false
    /// Changes only when the keypad opens or closes, so screen chrome is not rebuilt by every binding.
    private(set) var isOpen = false
    /// A field id ("<set id>:w" or ":r") the table should select, as a tap would.
    private(set) var requestedField: String?

    @ObservationIgnored private var text = ""
    @ObservationIgnored private var bound: String?
    @ObservationIgnored private var pending: [String] = []

    public init() {}

    /// Called by the selected field whenever what it shows changes.
    func bind(_ next: KeypadField) {
        if target?.id != next.id {
            text = next.value
            setReplacing(!next.value.isEmpty)
            pending.removeAll()
        } else if next.value != bound {
            if let sent = pending.firstIndex(of: next.value) { pending.removeFirst(sent + 1) }
            else { text = next.value; pending.removeAll() }
        }
        bound = next.value
        target = next
        if !isOpen { isOpen = true }
    }

    func release(_ id: String) {
        guard target?.id == id else { return }
        target = nil
        bound = nil
        pending.removeAll()
        setReplacing(false)
        if isOpen { isOpen = false }
    }

    /// Tapping the field again keeps its value and types after it.
    func append() { setReplacing(false) }

    /// Selects a field by id without a tap, for assistive and test drivers.
    func select(_ id: String) { requestedField = id }

    func consumeRequest() { if requestedField != nil { requestedField = nil } }

    /// Return to the saved value after an edit was declined, such as an unconfirmed unusual load.
    func resync() { text = bound ?? ""; pending.removeAll() }

    @discardableResult func type(_ key: Character) -> Bool {
        guard let field = target, let next = KeypadInput.type(text, key, kind: field.kind, unit: field.unit, replacing: replacing) else { return false }
        return commit(next)
    }

    @discardableResult func delete() -> Bool { target != nil && commit(KeypadInput.delete(text, replacing: replacing)) }

    @discardableResult func clear() -> Bool { target != nil && commit("") }

    @discardableResult func step(_ direction: Int) -> Bool {
        guard let field = target else { return false }
        return commit(KeypadInput.step(text, by: direction, kind: field.kind, unit: field.unit, step: field.step))
    }

    func act() { target?.onAction() }

    func dismiss() { target?.onDismiss() }

    private func setReplacing(_ value: Bool) { if replacing != value { replacing = value } }

    private func commit(_ value: String) -> Bool {
        guard let field = target else { return false }
        setReplacing(false)
        text = value
        pending.append(value)
        if pending.count > 16 { pending.removeFirst() }
        field.onValue(value)
        return true
    }
}

/// Sits where the exercise navigation was: a heading with shortcuts, then four rows of keys.
struct LoggingKeypadView: View {
    let keypad: SessionKeypad
    @FocusState private var focused: Bool

    var body: some View {
        if let field = keypad.target {
            let step = KeypadInput.stepLabel(field.step)
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Text(field.title)
                        .font(.app(size: 11, weight: .medium)).foregroundStyle(AppColors.secondaryText)
                        .lineLimit(1).truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("keypad-title")
                    ForEach(Array(([field.previous].compactMap { $0 } + field.tools).enumerated()), id: \.offset) { _, shortcut in
                        chip(shortcut)
                    }
                    chip(KeypadShortcut(tag: "keypad-done", description: LanguageManager.t("table.done"),
                                        text: LanguageManager.t("table.done"), tint: AppColors.accent, action: keypad.dismiss), plain: true)
                }
                .frame(height: 44).padding(.leading, 5)
                let (actionTitle, actionImage): (String, String?) = switch field.action {
                case .next: (LanguageManager.t("keypad.next"), "arrow.right")
                case .log: (LanguageManager.t("keypad.logSet"), "checkmark")
                case .done: (LanguageManager.t("table.done"), nil)
                }
                Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                    GridRow {
                        digit("1"); digit("2"); digit("3")
                        key("−\(step)", tag: "keypad-decrease", secondary: true,
                            label: LanguageManager.t("keypad.decrease", ["step": step])) { keypad.step(-1) }
                    }
                    GridRow {
                        digit("4"); digit("5"); digit("6")
                        key("+\(step)", tag: "keypad-increase", secondary: true,
                            label: LanguageManager.t("keypad.increase", ["step": step])) { keypad.step(1) }
                    }
                    GridRow {
                        digit("7"); digit("8"); digit("9")
                        key(nil, tag: "keypad-delete", systemImage: "delete.left", secondary: true,
                            label: LanguageManager.t("keypad.delete"), onLongPress: { keypad.clear() }) { keypad.delete() }
                    }
                    GridRow {
                        key(KeypadInput.decimalSeparator, tag: "keypad-decimal", enabled: field.kind == .weight,
                            label: LanguageManager.t("keypad.decimal")) { keypad.type(".") }
                        digit("0")
                        key(actionTitle, tag: "keypad-action", systemImage: actionImage, primary: true) { keypad.act() }
                            .gridCellColumns(2)
                    }
                }
            }
            .padding(.horizontal, 9).padding(.top, 2).padding(.bottom, 6)
            .background(alignment: .top) {
                // The surface continues under the home indicator, like the system keyboard.
                UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16, style: .continuous)
                    .fill(AppColors.surface)
                    .overlay(UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16, style: .continuous)
                        .stroke(AppColors.border, lineWidth: 1))
                    .ignoresSafeArea(edges: .bottom)
            }
            // A hardware keyboard types into the selected field; Return is the action key.
            .focusable()
            .focusEffectDisabled()
            .focused($focused)
            .onAppear { focused = true }
            .onKeyPress(phases: .down) { press in handle(press) ? .handled : .ignored }
            .accessibilityIdentifier("logging-keypad")
        }
    }

    private func handle(_ press: KeyPress) -> Bool {
        switch press.key {
        case .delete: return keypad.delete()
        case .return: keypad.act(); return true
        case .escape: keypad.dismiss(); return true
        default:
            guard let char = press.characters.first, char.isASCII, char.isNumber || char == "." || char == "," else { return false }
            keypad.type(char)
            return true
        }
    }

    private func digit(_ char: Character) -> some View {
        key(String(char), tag: "keypad-key-\(char)") { keypad.type(char) }
    }

    private func key(_ text: String?, tag: String, systemImage: String? = nil, primary: Bool = false, secondary: Bool = false,
                     enabled: Bool = true, label: String? = nil,
                     onLongPress: (() -> Void)? = nil, action: @escaping () -> Void) -> some View {
        let color: Color = primary ? .black : (secondary ? AppColors.secondaryText : AppColors.text)
        return Button(action: action) {
            HStack(spacing: 6) {
                if let text {
                    Text(text).font(.app(size: primary || secondary ? 15 : 21, weight: primary ? .semibold : .medium))
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: text == nil ? 20 : 15, weight: .semibold))
                }
            }
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(KeypadKeyStyle(primary: primary, secondary: secondary))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        // Delete's long press clears the field.
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in onLongPress?() }, isEnabled: onLongPress != nil)
        .accessibilityLabel(label ?? text ?? "")
        .accessibilityIdentifier(tag)
    }

    private func chip(_ shortcut: KeypadShortcut, plain: Bool = false) -> some View {
        Button(action: shortcut.action) {
            HStack(spacing: 5) {
                if let image = shortcut.systemImage { Image(systemName: image).font(.system(size: 14, weight: .semibold)) }
                if let text = shortcut.text {
                    Text(text).font(.app(size: 13, weight: plain ? .semibold : .medium)).lineLimit(1)
                }
            }
            .foregroundStyle(shortcut.tint)
            .padding(.horizontal, 10)
            .frame(minWidth: 40, minHeight: 34)
            .background(plain ? nil : RoundedRectangle(cornerRadius: 9, style: .continuous).fill(AppColors.surfaceRaised))
            .overlay(plain ? nil : RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(AppColors.border, lineWidth: 1))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel(shortcut.description)
        .accessibilityIdentifier(shortcut.tag)
    }
}

/// Key faces sit 3pt inside full 48pt touch cells; feedback starts on touch-down.
private struct KeypadKeyStyle: ButtonStyle {
    let primary: Bool
    let secondary: Bool

    func makeBody(configuration: Configuration) -> some View {
        let fill: Color = primary ? AppColors.accent : (secondary ? AppColors.surfaceRaised.opacity(0.6) : AppColors.surfaceRaised)
        configuration.label
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(configuration.isPressed ? fill.opacity(0.7) : fill)
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(primary ? .clear : AppColors.border, lineWidth: 1)))
            .padding(3)
            .contentShape(Rectangle())
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.6) }
            }
    }
}

/// A set value the keypad edits. Tapping selects it; the selected field binds itself to the keypad.
struct KeypadValueField: View {
    let field: KeypadField
    let keypad: SessionKeypad
    let row: ExerciseSetLog
    let selected: Bool
    let enabled: Bool
    var placeholder: String = "0"
    var fontSize: CGFloat = 15
    let onSelect: () -> Void

    var body: some View {
        let active = selected && enabled
        let display = KeypadInput.display(field.value)
        let highlighted = active && keypad.replacing && !field.value.isEmpty
        HStack(spacing: 1) {
            if active && field.value.isEmpty { caret }
            Text(display.isEmpty ? placeholder : display)
                .font(.app(size: field.value.isEmpty ? 15 : fontSize, weight: .semibold))
                .foregroundStyle(field.value.isEmpty ? AppColors.muted.opacity(enabled ? 0.6 : 0.25)
                                 : (enabled ? AppColors.text : AppColors.muted.opacity(0.5)))
                .lineLimit(1)
                // A freshly selected value is replaced by the first key, like selected text.
                .padding(.horizontal, highlighted ? 3 : 0)
                .background(highlighted ? AppColors.accent.opacity(0.28) : .clear, in: RoundedRectangle(cornerRadius: 4))
            if active && !field.value.isEmpty && !highlighted { caret }
        }
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(AppColors.surfaceRaised.opacity(enabled ? 1.0 : 0.5)).padding(.vertical, 4))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(active ? AppColors.accent : .clear).padding(.vertical, 4))
        .contentShape(Rectangle())
        .onTapGesture(perform: tap)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(field.label)
        .accessibilityValue(display.isEmpty ? placeholder : display)
        .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(.default, tap)
        .accessibilityIdentifier("field-\(field.id)")
        .disabled(!enabled)
        .onChange(of: active ? field.signature(row: row) : nil, initial: true) { _, signature in
            if signature != nil { keypad.bind(field) } else { keypad.release(field.id) }
        }
        .onDisappear { keypad.release(field.id) }
    }

    private var caret: some View {
        RoundedRectangle(cornerRadius: 1).fill(AppColors.accent).frame(width: 2, height: 18)
            .padding(.horizontal, 1).accessibilityHidden(true)
    }

    private func tap() {
        guard enabled else { return }
        // A second tap types after the value instead of replacing it.
        if selected { keypad.append() } else { onSelect() }
    }
}
