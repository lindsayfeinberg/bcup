//
//  bitchcupUITests.swift
//  bitchcupUITests
//
//  Created by Lindsay Feinberg on 3/21/26.
//

import XCTest

final class bitchcupUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testOnboardingCriticalPath() throws {
        let app = launchApp(scenario: "onboarding")

        let ageConfirmButton = app.buttons["onboarding.age.confirm"]
        XCTAssertTrue(ageConfirmButton.waitForExistence(timeout: 5))
        ageConfirmButton.tap()

        let displayNameField = app.textFields["onboarding.profile.displayName"]
        XCTAssertTrue(displayNameField.waitForExistence(timeout: 5))
        displayNameField.tap()
        displayNameField.typeText("UITest User")

        let finishButton = app.buttons["onboarding.profile.finish"]
        XCTAssertTrue(finishButton.exists)
        finishButton.tap()

        XCTAssertTrue(app.buttons["feed.logGame"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testGameLogCriticalPath() throws {
        let app = launchApp(scenario: "gameLog")

        let wonButton = app.buttons["gamelog.outcome.won"]
        XCTAssertTrue(wonButton.waitForExistence(timeout: 5))
        wonButton.tap()

        let opponentsDropdown = app.buttons["gamelog.dropdown.Opponents_(Losers)"]
        XCTAssertTrue(opponentsDropdown.waitForExistence(timeout: 5))
        opponentsDropdown.tap()

        let opponentRow = app.buttons["gamelog.participant.ui-opponent-1"]
        XCTAssertTrue(opponentRow.waitForExistence(timeout: 5))
        opponentRow.tap()

        XCTAssertTrue(app.buttons["gamelog.submit"].exists)
    }

    @MainActor
    func testBracketCriticalPath() throws {
        let app = launchApp(scenario: "bracket")

        let createBracketButton = app.buttons["community.createBracket"]
        XCTAssertTrue(createBracketButton.waitForExistence(timeout: 5))
        createBracketButton.tap()

        let popupCreateButton = app.buttons["community.popup.createBracket"]
        XCTAssertTrue(popupCreateButton.waitForExistence(timeout: 5))
        popupCreateButton.tap()

        let createdBracketRow = app.buttons["community.bracket.ui-bracket-1"]
        XCTAssertTrue(createdBracketRow.waitForExistence(timeout: 5))
        createdBracketRow.tap()

        XCTAssertTrue(app.staticTexts["Bracket"].waitForExistence(timeout: 5))
    }

    @discardableResult
    private func launchApp(scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["UI_TESTING"]
        app.launchEnvironment["UI_TEST_SCENARIO"] = scenario
        app.launchEnvironment["UI_TEST_USER_ID"] = "ui-test-user"
        app.launch()
        return app
    }
}
