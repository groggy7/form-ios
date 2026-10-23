import XCTest
import SwiftUI
import UIKit
@testable import FormApp

/// iPhone Duo support (gym/docs/design/form-design-system.md#foldable-iphone); other iPhones keep the portrait lock.
final class FoldableLayoutTests: XCTestCase {

    func testRotationStaysPortraitUntilAHingeReportsOpen() {
        let fold = FoldState()
        XCTAssertFalse(fold.hasHinge)
        XCTAssertEqual(fold.supportedOrientations, .portrait)

        fold.update(isOpen: false)
        XCTAssertTrue(fold.hasHinge)
        XCTAssertEqual(fold.supportedOrientations, .portrait)

        fold.update(isOpen: true)
        XCTAssertEqual(fold.supportedOrientations, .allButUpsideDown)

        fold.update(isOpen: false)
        XCTAssertEqual(fold.supportedOrientations, .portrait)
    }

    @MainActor
    func testSideDockStacksTheFourTabsInsideTheVerticalBar() {
        let host = UIHostingController(rootView: BottomDock(currentView: .constant(.today), axis: .vertical).frame(width: 84))
        let size = host.sizeThatFits(in: CGSize(width: 84, height: 1000))
        XCTAssertEqual(size.width, 84, accuracy: 0.5)
        // Four 64pt tabs with 4pt gaps inside the 6pt inset of the 72pt-wide surface.
        XCTAssertEqual(size.height, 4 * 64 + 3 * 4 + 2 * 6, accuracy: 0.5)
    }
}
