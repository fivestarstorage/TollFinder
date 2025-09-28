//
//  TollFinderUITests.swift
//  TollFinderUITests
//
//  Created by Riley Martin on 24/9/2025.
//

import XCTest

final class TollFinderUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
    }

    @MainActor
    func testAppLaunch() throws {
        let app = XCUIApplication()
        app.launch()
        
        XCTAssertTrue(app.buttons["Find Tolls"].exists)
        XCTAssertTrue(app.buttons["folder"].exists)
    }

    @MainActor
    func testFindTollsButtonOpensSheet() throws {
        let app = XCUIApplication()
        app.launch()
        
        let findTollsButton = app.buttons["Find Tolls"]
        XCTAssertTrue(findTollsButton.exists)
        
        findTollsButton.tap()
        
        XCTAssertTrue(app.navigationBars["Plan your trip"].exists)
        XCTAssertTrue(app.buttons["Cancel"].exists)
        XCTAssertTrue(app.buttons["plus"].exists)
    }

    @MainActor
    func testAddressInputSheetHasStopFields() throws {
        let app = XCUIApplication()
        app.launch()
        
        app.buttons["Find Tolls"].tap()
        
        XCTAssertTrue(app.textFields["Stop 1"].exists)
        XCTAssertTrue(app.textFields["Stop 2"].exists)
        XCTAssertTrue(app.buttons["Use Current Location"].exists)
        XCTAssertTrue(app.buttons["Calculate Tolls"].exists)
    }

    @MainActor
    func testAddStopButton() throws {
        let app = XCUIApplication()
        app.launch()
        
        app.buttons["Find Tolls"].tap()
        
        let addButton = app.buttons["plus"]
        XCTAssertTrue(addButton.exists)
        
        addButton.tap()
        
        XCTAssertTrue(app.textFields["Stop 3"].exists)
    }

    @MainActor
    func testRemoveStopButton() throws {
        let app = XCUIApplication()
        app.launch()
        
        app.buttons["Find Tolls"].tap()
        
        app.buttons["plus"].tap()
        
        XCTAssertTrue(app.textFields["Stop 3"].exists)
        
        let minusButtons = app.buttons.matching(identifier: "minus.circle.fill")
        if minusButtons.count > 0 {
            minusButtons.firstMatch.tap()
            XCTAssertFalse(app.textFields["Stop 3"].exists)
        }
    }

    @MainActor
    func testCancelButtonClosesSheet() throws {
        let app = XCUIApplication()
        app.launch()
        
        app.buttons["Find Tolls"].tap()
        
        XCTAssertTrue(app.navigationBars["Plan your trip"].exists)
        
        app.buttons["Cancel"].tap()
        
        XCTAssertFalse(app.navigationBars["Plan your trip"].exists)
        XCTAssertTrue(app.buttons["Find Tolls"].exists)
    }

    @MainActor
    func testSavedTollsButton() throws {
        let app = XCUIApplication()
        app.launch()
        
        let folderButton = app.buttons["folder"]
        XCTAssertTrue(folderButton.exists)
        
        folderButton.tap()
        
        XCTAssertTrue(app.navigationBars["Saved Tolls"].exists)
    }

    @MainActor
    func testTextFieldFocusAndInput() throws {
        let app = XCUIApplication()
        app.launch()
        
        app.buttons["Find Tolls"].tap()
        
        let stop1Field = app.textFields["Stop 1"]
        XCTAssertTrue(stop1Field.exists)
        
        stop1Field.tap()
        stop1Field.typeText("Sydney")
        
        XCTAssertEqual(stop1Field.value as? String, "Sydney")
    }

    @MainActor
    func testCalculateTollsButtonState() throws {
        let app = XCUIApplication()
        app.launch()
        
        app.buttons["Find Tolls"].tap()
        
        let calculateButton = app.buttons["Calculate Tolls"]
        XCTAssertTrue(calculateButton.exists)
        XCTAssertFalse(calculateButton.isEnabled)
        
        let stop1Field = app.textFields["Stop 1"]
        stop1Field.tap()
        stop1Field.typeText("Sydney Opera House")
        
        let expectation = XCTestExpectation(description: "Search results appear for stop 1")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if app.images["mappin.circle.fill"].exists {
                expectation.fulfill()
            }
        }
        wait(for: [expectation], timeout: 5.0)
        
        if app.images["mappin.circle.fill"].exists {
            app.images["mappin.circle.fill"].firstMatch.tap()
        }
        
        let stop2Field = app.textFields["Stop 2"]
        stop2Field.tap()
        stop2Field.typeText("Harbour Bridge")
        
        let expectation2 = XCTestExpectation(description: "Search results appear for stop 2")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if app.images["mappin.circle.fill"].exists {
                expectation2.fulfill()
            }
        }
        wait(for: [expectation2], timeout: 5.0)
        
        if app.images["mappin.circle.fill"].exists {
            app.images["mappin.circle.fill"].firstMatch.tap()
        }
        
        XCTAssertTrue(calculateButton.isEnabled)
    }

    @MainActor
    func testUseCurrentLocationButton() throws {
        let app = XCUIApplication()
        app.launch()
        
        app.buttons["Find Tolls"].tap()
        
        let currentLocationButton = app.buttons["Use Current Location"]
        XCTAssertTrue(currentLocationButton.exists)
        
        currentLocationButton.tap()
    }

    @MainActor
    func testDragHandlesExist() throws {
        let app = XCUIApplication()
        app.launch()
        
        app.buttons["Find Tolls"].tap()
        
        let dragHandles = app.images.matching(identifier: "line.3.horizontal")
        XCTAssertTrue(dragHandles.count >= 2)
    }

    @MainActor
    func testMaximumStopsLimit() throws {
        let app = XCUIApplication()
        app.launch()
        
        app.buttons["Find Tolls"].tap()
        
        let addButton = app.buttons["plus"]
        
        addButton.tap()
        addButton.tap()
        addButton.tap()
        
        XCTAssertTrue(app.textFields["Stop 5"].exists)
        XCTAssertFalse(addButton.isEnabled)
    }

    @MainActor
    func testNavigationStructure() throws {
        let app = XCUIApplication()
        app.launch()
        
        app.buttons["Find Tolls"].tap()
        XCTAssertTrue(app.navigationBars["Plan your trip"].exists)
        
        app.buttons["Cancel"].tap()
        
        app.buttons["folder"].tap()
        XCTAssertTrue(app.navigationBars["Saved Tolls"].exists)
    }

    @MainActor
    func testSearchResultsAppear() throws {
        let app = XCUIApplication()
        app.launch()
        
        app.buttons["Find Tolls"].tap()
        
        let stop1Field = app.textFields["Stop 1"]
        stop1Field.tap()
        stop1Field.typeText("Sydney")
        
        let expectation = XCTestExpectation(description: "Search results appear")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if app.images["mappin.circle.fill"].exists {
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 5.0)
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    @MainActor
    func testMemoryUsage() throws {
        let app = XCUIApplication()
        
        measure(metrics: [XCTMemoryMetric()]) {
            app.launch()
            app.buttons["Find Tolls"].tap()
            app.buttons["Cancel"].tap()
            app.buttons["folder"].tap()
            app.terminate()
        }
    }

    @MainActor
    func testScrollPerformance() throws {
        let app = XCUIApplication()
        app.launch()
        
        app.buttons["Find Tolls"].tap()
        
        let stop1Field = app.textFields["Stop 1"]
        stop1Field.tap()
        stop1Field.typeText("Sydney")
        
        measure(metrics: [XCTOSSignpostMetric.scrollingAndDecelerationMetric]) {
            let table = app.tables.firstMatch
            if table.exists {
                table.swipeUp()
                table.swipeDown()
            }
        }
    }

}
