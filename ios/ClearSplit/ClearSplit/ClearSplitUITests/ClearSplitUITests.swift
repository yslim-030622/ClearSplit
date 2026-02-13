//
//  ClearSplitUITests.swift
//  ClearSplitUITests
//
//  Created by Yeongseok Lim on 12/18/25.
//

import XCTest

final class ClearSplitUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLoginScreenShowsCoreControls() throws {
        let app = launchApp()

        XCTAssertTrue(app.textFields["login.emailField"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.secureTextFields["login.passwordField"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["login.submitButton"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["login.createAccountButton"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["login.submitButton"].isEnabled)
    }

    @MainActor
    func testCanOpenSignUpFromLogin() throws {
        let app = launchApp()

        let createAccountButton = app.buttons["login.createAccountButton"]
        XCTAssertTrue(createAccountButton.waitForExistence(timeout: 10))
        createAccountButton.tap()

        XCTAssertTrue(app.textFields["signup.firstNameField"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["signup.submitButton"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "UITEST_MODE",
            "UITEST_RESET_SESSION",
            "UITEST_DISABLE_ANIMATIONS"
        ]
        app.launch()
        return app
    }
}
