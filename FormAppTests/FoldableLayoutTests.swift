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

    func testLaunchingOnTheOpenDisplayAllowsLandscapeBeforeTheHingeReports() {
        let fold = FoldState()
        // The open Duo's inner display, either way round, before the hinge reports.
        XCTAssertEqual(fold.supportedOrientations(onScreen: CGSize(width: 951, height: 669), isPhone: true), .allButUpsideDown)
        XCTAssertEqual(fold.supportedOrientations(onScreen: CGSize(width: 669, height: 951), isPhone: true), .allButUpsideDown)
        // The folded cover, the widest iPhones held either way, an unknown screen and iPads stay portrait.
        for size in [CGSize(width: 466, height: 678), CGSize(width: 440, height: 956), CGSize(width: 956, height: 440)] {
            XCTAssertEqual(fold.supportedOrientations(onScreen: size, isPhone: true), .portrait, "\(size)")
        }
        XCTAssertEqual(fold.supportedOrientations(onScreen: nil, isPhone: true), .portrait)
        XCTAssertEqual(fold.supportedOrientations(onScreen: CGSize(width: 1032, height: 1376), isPhone: false), .portrait)

        // Once the hinge reports, it decides on every screen.
        fold.update(isOpen: false)
        XCTAssertEqual(fold.supportedOrientations(onScreen: CGSize(width: 951, height: 669), isPhone: true), .portrait)
        fold.update(isOpen: true)
        XCTAssertEqual(fold.supportedOrientations(onScreen: CGSize(width: 466, height: 678), isPhone: true), .allButUpsideDown)
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
