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

        XCTAssertTrue(waitForMainWindow(in: app))
        let noteItem = historyItem(named: "UI Test Note", in: app)
        let urlItem = historyItem(named: "UI Test URL", in: app)
        XCTAssertTrue(noteItem.waitForExistence(timeout: 2))
        XCTAssertTrue(urlItem.waitForExistence(timeout: 2))

        noteItem.click()
        XCTAssertTrue(app.buttons["clipboard.detail.copy"].waitForExistence(timeout: 2))

        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.exists)
        searchField.click()
        searchField.typeText("type:url")

        XCTAssertTrue(urlItem.waitForExistence(timeout: 2))
        XCTAssertFalse(noteItem.exists)
    }

    @MainActor
    func testQuickPickerOpensWithKeyboardShortcut() throws {
        let app = makeApplication()
        app.launch()

        app.typeKey("v", modifierFlags: [.command, .shift])

        XCTAssertTrue(
            app.windows["quick-clipboard-picker"].waitForExistence(timeout: 3)
        )
        XCTAssertTrue(
            app.textFields["quickClipboard.search"].waitForExistence(timeout: 2)
        )
        XCTAssertTrue(
            historyItem(named: "UI Test Note", in: app).waitForExistence(timeout: 2)
        )
    }

    @MainActor
    func testBuiltInSavedFilterNarrowsHistory() throws {
        let app = makeApplication()
        app.launch()

        XCTAssertTrue(waitForMainWindow(in: app))

        let overflowMenu = app.popUpButtons["more toolbar items"]
        XCTAssertTrue(overflowMenu.waitForExistence(timeout: 2))
        overflowMenu.click()

        let savedFiltersMenu = app.menuItems["Saved Filters"]
        XCTAssertTrue(savedFiltersMenu.waitForExistence(timeout: 2))
        savedFiltersMenu.click()

        let favoritesItem = app.menuItems
            .matching(identifier: "Favorites")
            .element(boundBy: 1)
        XCTAssertTrue(favoritesItem.waitForExistence(timeout: 2))
        favoritesItem.click()

        XCTAssertTrue(historyItem(named: "UI Test URL", in: app).waitForExistence(timeout: 2))
        XCTAssertFalse(historyItem(named: "UI Test Note", in: app).exists)
    }

    @MainActor
    func testCaptureMenuExposesCaptureAndRecordingControls() throws {
        let app = makeApplication()
        app.launch()

        XCTAssertTrue(waitForMainWindow(in: app))

        let captureMenu = app.menuBars.menuBarItems["Capture"]
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

        XCTAssertTrue(waitForMainWindow(in: app))
        app.menuBars.menuBarItems["ClipSnap"].click()
        app.menuItems["Settings…"].click()

        let generalTab = app.buttons["General"]
        XCTAssertTrue(generalTab.waitForExistence(timeout: 3))
        generalTab.click()
        XCTAssertTrue(app.buttons["settings.setup.open"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["settings.diagnostics.copy"].exists)

        app.buttons["settings.setup.open"].click()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 2))

        app.buttons["Done"].click()
        XCTAssertTrue(app.buttons["settings.setup.open"].waitForExistence(timeout: 2))

        app.buttons["History"].click()
        XCTAssertTrue(
            app.menuButtons["settings.health.cleanup.menu"].waitForExistence(timeout: 2)
        )
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
            XCTAssertTrue(waitForMainWindow(in: app))

            app.typeKey("v", modifierFlags: [.command, .shift])
            XCTAssertTrue(app.windows["quick-clipboard-picker"].waitForExistence(timeout: 3))

            app.typeKey(.escape, modifierFlags: [])
            app.terminate()
        }
    }

    private func makeApplication(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"] + arguments
        return app
    }

    private func waitForMainWindow(
        in app: XCUIApplication,
        timeout: TimeInterval = 5
    ) -> Bool {
        app.windows
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "clipboard-AppWindow"))
            .firstMatch
            .waitForExistence(timeout: timeout)
    }

    private func historyItem(
        named name: String,
        in app: XCUIApplication
    ) -> XCUIElement {
        app.staticTexts
            .matching(NSPredicate(format: "value BEGINSWITH %@", name))
            .firstMatch
    }
}
