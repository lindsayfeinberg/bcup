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
        XCTAssertTrue(finishButton.waitForExistence(timeout: 5))
        if app.keyboards.element.exists {
            app.keyboards.buttons["Return"].firstMatch.tap()
        }
        finishButton.tap()

        // Profile submit runs asynchronously; wait for feed chrome before asserting Log Game.
        XCTAssertTrue(app.staticTexts["Bitch Cup"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["feed.logGame"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testGameLogCriticalPath() throws {
        let app = launchApp(scenario: "gameLog")

        let wonButton = app.buttons["gamelog.outcome.won"]
        XCTAssertTrue(wonButton.waitForExistence(timeout: 5))
        wonButton.tap()

        let opponentsDropdown = app.descendants(matching: .any)["gamelog.dropdown.Opponents_(Losers)"]
        var foundOpponents = opponentsDropdown.waitForExistence(timeout: 3)
        if !foundOpponents {
            let list = app.collectionViews.firstMatch
            for _ in 0..<8 where !foundOpponents {
                if list.exists {
                    list.swipeUp()
                } else {
                    app.swipeUp()
                }
                foundOpponents = opponentsDropdown.waitForExistence(timeout: 2)
            }
        }
        if foundOpponents {
            opponentsDropdown.tap()
            let opponentRow = app.descendants(matching: .any)["gamelog.participant.ui-opponent-1"]
            XCTAssertTrue(opponentRow.waitForExistence(timeout: 5))
            opponentRow.tap()
        }

        let submitButton = app.descendants(matching: .any)["gamelog.submit"]
        var foundSubmit = submitButton.waitForExistence(timeout: 2)
        if !foundSubmit {
            let list = app.collectionViews.firstMatch
            for _ in 0..<8 where !foundSubmit {
                if list.exists {
                    list.swipeUp()
                } else {
                    app.swipeUp()
                }
                foundSubmit = submitButton.waitForExistence(timeout: 1)
            }
        }
        XCTAssertTrue(foundSubmit)
    }

    @MainActor
    func testBracketCriticalPath() throws {
        let app = launchApp(scenario: "bracket")

        XCTAssertTrue(
            app.staticTexts["Bracket Manager"].waitForExistence(timeout: 20),
            "Expected CommunityDetailView bracket section. Check UITest harness scenario=bracket and AppShell.prepareFirstFrame."
        )

        let createBracketButton = app.buttons["community.createBracket"]
        XCTAssertTrue(createBracketButton.waitForExistence(timeout: 15))
        createBracketButton.tap()

        let popupCreateButton = app.buttons["community.popup.createBracket"]
        XCTAssertTrue(popupCreateButton.waitForExistence(timeout: 5))
        popupCreateButton.tap()

        // Harness may navigate directly to BracketsView on create, or return to list first.
        if app.navigationBars["Bracket"].waitForExistence(timeout: 5) {
            XCTAssertTrue(true)
        } else {
            let createdBracketRow = app.buttons["community.bracket.ui-bracket-1"]
            XCTAssertTrue(createdBracketRow.waitForExistence(timeout: 15))
            createdBracketRow.tap()
            XCTAssertTrue(
                app.navigationBars["Bracket"].waitForExistence(timeout: 8),
                "Expected BracketsView navigation title after opening mock bracket."
            )
        }
    }

    @discardableResult
    private func launchApp(scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        // Arguments are available when @main App init runs; env alone can be unset too early for UITestRuntime.scenario.
        app.launchArguments = [
            "UI_TESTING",
            "-UI_TEST_SCENARIO", scenario,
            "UI_TEST_SCENARIO=\(scenario)"
        ]
        app.launchEnvironment["UI_TESTING"] = "1"
        app.launchEnvironment["UI_TEST_SCENARIO"] = scenario
        app.launchEnvironment["UI_TEST_USER_ID"] = "ui-test-user"
        app.launch()
        return app
    }
}
