//
//  CBUITests.swift
//  CBUITests
//
//  Created by Adrian Feeger on 23/6/2026.
//

import XCTest

final class CBUITests: XCTestCase {

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
    func testHistorySelectionAndSearch() throws {
        let app = makeApplication()
        app.launch()

        XCTAssertTrue(app.otherElements["clipboard.main"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["UI Test Note"].exists)
        XCTAssertTrue(app.staticTexts["UI Test URL"].exists)

        app.staticTexts["UI Test Note"].click()
        XCTAssertTrue(app.buttons["clipboard.detail.copy"].waitForExistence(timeout: 2))

        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.exists)
        searchField.click()
        searchField.typeText("type:url")

        XCTAssertTrue(app.staticTexts["UI Test URL"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["UI Test Note"].exists)
    }

    @MainActor
    func testQuickPickerOpensWithKeyboardShortcut() throws {
        let app = makeApplication()
        app.launch()

        app.typeKey("v", modifierFlags: [.command, .shift])

        XCTAssertTrue(
            app.otherElements["quickClipboard.main"].waitForExistence(timeout: 3)
        )
        XCTAssertTrue(app.textFields["quickClipboard.search"].exists)
        XCTAssertTrue(app.staticTexts["UI Test Note"].exists)
    }

    @MainActor
    func testBuiltInSavedFilterNarrowsHistory() throws {
        let app = makeApplication()
        app.launch()

        XCTAssertTrue(app.otherElements["clipboard.main"].waitForExistence(timeout: 5))

        let savedFiltersMenu = app.buttons["clipboard.savedFilters.menu"]
        XCTAssertTrue(savedFiltersMenu.waitForExistence(timeout: 2))
        savedFiltersMenu.click()

        let favoritesItem = app.menuItems["Favorites"]
        XCTAssertTrue(favoritesItem.waitForExistence(timeout: 2))
        favoritesItem.click()

        XCTAssertTrue(app.staticTexts["UI Test URL"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["UI Test Note"].exists)
    }

    @MainActor
    func testCaptureMenuExposesCaptureAndRecordingControls() throws {
        let app = makeApplication()
        app.launch()

        XCTAssertTrue(app.otherElements["clipboard.main"].waitForExistence(timeout: 5))

        let captureMenu = app.buttons["clipboard.capture.menu"]
        XCTAssertTrue(captureMenu.waitForExistence(timeout: 2))
        captureMenu.click()

        XCTAssertTrue(app.menuItems["Capture Region"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.menuItems["Capture Display"].exists)
        XCTAssertTrue(app.menuItems["Record Display"].exists)
    }

    @MainActor
    func testSettingsExposeSetupDiagnosticsAndCleanupSurfaces() throws {
        let app = makeApplication()
        app.launch()

        XCTAssertTrue(app.otherElements["clipboard.main"].waitForExistence(timeout: 5))
        app.typeKey(",", modifierFlags: .command)

        XCTAssertTrue(app.buttons["settings.setup.open"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["settings.diagnostics.copy"].exists)

        app.buttons["settings.setup.open"].click()
        XCTAssertTrue(app.otherElements["setup.main"].waitForExistence(timeout: 2))

        app.buttons["Done"].click()
        XCTAssertTrue(app.buttons["settings.setup.open"].waitForExistence(timeout: 2))

        app.buttons["Storage"].click()
        XCTAssertTrue(app.buttons["settings.health.cleanup.menu"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            makeApplication().launch()
        }
    }

    @MainActor
    func testQuickPickerPerformanceWithLargeHistory() throws {
        measure(metrics: [XCTClockMetric()]) {
            let app = makeApplication(arguments: ["--ui-testing-large-history"])
            app.launch()
            XCTAssertTrue(app.otherElements["clipboard.main"].waitForExistence(timeout: 5))

            app.typeKey("v", modifierFlags: [.command, .shift])
            XCTAssertTrue(app.otherElements["quickClipboard.main"].waitForExistence(timeout: 3))

            app.typeKey(.escape, modifierFlags: [])
            app.terminate()
        }
    }

    private func makeApplication(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"] + arguments
        return app
    }
}
