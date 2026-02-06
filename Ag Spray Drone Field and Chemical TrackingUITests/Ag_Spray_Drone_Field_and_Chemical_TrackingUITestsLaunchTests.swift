//
//  Ag_Spray_Drone_Field_and_Chemical_TrackingUITestsLaunchTests.swift
//  Ag Spray Drone Field and Chemical TrackingUITests
//
//  Created by Reggie Hetsler on 2/6/26.
//

import XCTest

final class Ag_Spray_Drone_Field_and_Chemical_TrackingUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()

        // Insert steps here to perform after app launch but before taking a screenshot,
        // such as logging into a test account or navigating somewhere in the app

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
