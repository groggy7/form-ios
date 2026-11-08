import XCTest
@testable import FormApp

/// The session keypad's editing rules (docs/design/form-design-system.md, session set entry).
@MainActor
final class LoggingKeypadTests: XCTestCase {
    func testTypingFollowsTheSessionInputLimits() {
        XCTAssertEqual(KeypadInput.type("", "1", kind: .weight, unit: .kg, replacing: false), "1")
        XCTAssertEqual(KeypadInput.type("", ".", kind: .weight, unit: .kg, replacing: false), "0.")
        XCTAssertEqual(KeypadInput.type("102", ",", kind: .weight, unit: .kg, replacing: false), "102.")
        XCTAssertNil(KeypadInput.type("102.5", ".", kind: .weight, unit: .kg, replacing: false), "one decimal point")
        XCTAssertNil(KeypadInput.type("102.25", "5", kind: .weight, unit: .kg, replacing: false), "two decimal places")
        XCTAssertNil(KeypadInput.type("150", "1", kind: .weight, unit: .kg, replacing: false), "over the unit's limit")
        XCTAssertEqual(KeypadInput.type("150", "1", kind: .weight, unit: .lbs, replacing: false), "1501")
        XCTAssertEqual(KeypadInput.type("0", "5", kind: .weight, unit: .kg, replacing: false), "5", "a lone zero is replaced")
        XCTAssertNil(KeypadInput.type("8", ".", kind: .reps, unit: .kg, replacing: false), "reps have no decimals")
        XCTAssertNil(KeypadInput.type("", "0", kind: .reps, unit: .kg, replacing: false), "reps start at one")
        XCTAssertNil(KeypadInput.type("999", "1", kind: .reps, unit: .kg, replacing: false), "reps stop at 999")
        XCTAssertNil(KeypadInput.type("99", "1", kind: .partials, unit: .kg, replacing: false), "partials stop at 99")
    }

    func testAFreshlySelectedValueIsReplacedByTheFirstKey() {
        XCTAssertEqual(KeypadInput.type("100", "7", kind: .weight, unit: .kg, replacing: true), "7")
        XCTAssertEqual(KeypadInput.type("100", ".", kind: .weight, unit: .kg, replacing: true), "0.")
        XCTAssertEqual(KeypadInput.delete("100", replacing: true), "")
        XCTAssertEqual(KeypadInput.delete("100", replacing: false), "10")
    }

    func testStepsUseTheEquipmentIncrementAndClamp() {
        XCTAssertEqual(KeypadInput.step("100", by: 1, kind: .weight, unit: .kg, step: 2.5), "102.5")
        XCTAssertEqual(KeypadInput.step("1", by: -1, kind: .weight, unit: .kg, step: 2.5), "0")
        XCTAssertEqual(KeypadInput.step("", by: 1, kind: .weight, unit: .kg, step: 2.5), "2.5")
        XCTAssertEqual(KeypadInput.step("1499", by: 1, kind: .weight, unit: .kg, step: 2.5), "1500")
        XCTAssertEqual(KeypadInput.step("20", by: 1, kind: .weight, unit: .kg, step: 1), "21")
        XCTAssertEqual(KeypadInput.step("8", by: 1, kind: .reps, unit: .kg, step: 1), "9")
        XCTAssertEqual(KeypadInput.step("1", by: -1, kind: .reps, unit: .kg, step: 1), "", "count steps empty at zero")
        XCTAssertEqual(KeypadInput.step("1", by: -1, kind: .partials, unit: .kg, step: 1), "")
    }

    func testLoadStepsComeFromEquipmentAndShowTheLanguageSeparator() {
        let steps = ProgressionLoadSteps(dumbbellKg: 2, machineKg: 5, smallestPlateKg: 1.25)
        XCTAssertEqual(WorkoutSessionUtils.loadStep(Exercise(name: "Barbell Back Squat", exerciseId: "barbell-back-squat"), unit: .kg, steps: steps), 2.5)
        XCTAssertEqual(WorkoutSessionUtils.loadStep(Exercise(name: "Hammer Curl", exerciseId: "dumbbell-hammer-curl"), unit: .kg, steps: steps), 2)
        XCTAssertEqual(WorkoutSessionUtils.defaultLoadStep(.lbs), 5)
        let previous = LanguageManager.shared.currentLanguage
        defer { LanguageManager.setLanguage(previous) }
        LanguageManager.setLanguage("tr")
        XCTAssertEqual(KeypadInput.stepLabel(2.5), "2,5")
        XCTAssertEqual(KeypadInput.display("62.5"), "62,5")
        LanguageManager.setLanguage("en")
        XCTAssertEqual(KeypadInput.stepLabel(2.5), "2.5")
    }

    func testKeypadKeepsItsOwnTextWhenTheTableHasNotRenderedYet() {
        var saved = ""
        let keypad = SessionKeypad()
        func field(_ value: String, _ id: String = "set-1:w") -> KeypadField {
            KeypadField(id: id, kind: .weight, unit: .kg, label: "SET 1, WEIGHT (KG)", title: "SET 1 · WEIGHT (KG)", value: value,
                        step: 2.5, action: .next, onValue: { saved = $0 }, onAction: {}, onDismiss: {})
        }
        keypad.bind(field("100"))
        XCTAssertTrue(keypad.replacing)
        XCTAssertTrue(keypad.isOpen)
        // Two presses before the table renders: the second builds on the first.
        keypad.type("1"); keypad.type("2")
        XCTAssertEqual(saved, "12")
        // A late render with the first value must not roll the text back.
        keypad.bind(field("1"))
        keypad.type("5")
        XCTAssertEqual(saved, "125")
        keypad.bind(field("12")); keypad.bind(field("125"))
        // A change from elsewhere, such as an applied target, is adopted.
        keypad.bind(field("80"))
        keypad.delete()
        XCTAssertEqual(saved, "8")
        // Declined edits return to the saved value.
        keypad.bind(field("8"))
        keypad.type("0")
        keypad.resync()
        keypad.type("5")
        XCTAssertEqual(saved, "85")
        // Selecting another field starts it fresh, and releasing an old id leaves it alone.
        keypad.bind(field("6", "set-1:r"))
        keypad.release("set-1:w")
        XCTAssertTrue(keypad.isOpen)
        keypad.release("set-1:r")
        XCTAssertFalse(keypad.isOpen)
    }
}
