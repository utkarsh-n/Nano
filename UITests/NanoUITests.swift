import XCTest

@MainActor
final class NanoUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testPausedParticleInterventionAndWorldControls() throws {
        let app = launchPausedUniverse()
        attachScreenshot(of: app, named: "Fresh paused universe")

        let inspect = app.buttons["diveIntoWorld"]
        XCTAssertTrue(inspect.waitForExistence(timeout: 5))
        inspect.tap()
        XCTAssertTrue(app.navigationBars["Aster"].waitForExistence(timeout: 5))

        let polarity = app.staticTexts["particlePolarity"]
        reveal(polarity, in: app)
        let initialPolarity = polarityName(of: polarity)
        XCTAssertTrue(["Positive", "Negative"].contains(initialPolarity), "The selected particle must expose its polarity.")
        let expectedPolarity = initialPolarity == "Positive" ? "Negative" : "Positive"

        let flip = app.buttons["flipPolarity"]
        reveal(flip, in: app)
        flip.tap()

        let flippedPolarity = app.staticTexts.matching(NSPredicate(
            format: "identifier == %@ AND (label CONTAINS[c] %@ OR value CONTAINS[c] %@)",
            "particlePolarity", expectedPolarity, expectedPolarity
        )).firstMatch
        XCTAssertTrue(flippedPolarity.waitForExistence(timeout: 5), "A paused intervention must update the selected particle immediately.")
        XCTAssertEqual(polarityName(of: polarity), expectedPolarity)
        attachScreenshot(of: app, named: "Particle polarity changed while paused")

        let controls = app.buttons["worldControls"]
        XCTAssertTrue(controls.waitForExistence(timeout: 5))
        controls.tap()
        XCTAssertTrue(app.navigationBars["Aster controls"].waitForExistence(timeout: 5))

        let energy = app.sliders.matching(identifier: "energyInput").firstMatch
        reveal(energy, in: app, toward: .top)
        let initialEnergy = try XCTUnwrap(energy.value as? String)
        energy.adjust(toNormalizedSliderPosition: 0.85)
        let editedEnergy = try XCTUnwrap(energy.value as? String)
        XCTAssertNotEqual(initialEnergy, editedEnergy, "The energy input control must change its value.")

        let fieldsRow = app.switches.matching(identifier: "showFields").firstMatch
        reveal(fieldsRow, in: app)
        let fields = nativeSwitch(in: fieldsRow)
        let initialFields = try XCTUnwrap(fields.value as? String)
        XCTAssertTrue(["0", "1"].contains(initialFields))
        let expectedFields = initialFields == "1" ? "0" : "1"
        tapSwitch(fields)
        let fieldsChanged = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", expectedFields), object: fields
        )
        XCTAssertEqual(XCTWaiter.wait(for: [fieldsChanged], timeout: 5), .completed,
            "The field-line switch must reach its exact opposite value after the tap.")
        let editedFields = try XCTUnwrap(fields.value as? String)
        XCTAssertEqual(editedFields, expectedFields)

        let done = app.buttons["Done"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        XCTAssertTrue(app.navigationBars["Aster"].waitForExistence(timeout: 5))

        // Reopening catches a control that changes visually without updating shared state.
        controls.tap()
        XCTAssertTrue(app.navigationBars["Aster controls"].waitForExistence(timeout: 5))
        reveal(energy, in: app, toward: .top)
        XCTAssertEqual(energy.value as? String, editedEnergy)
        reveal(fieldsRow, in: app)
        XCTAssertEqual(nativeSwitch(in: fieldsRow).value as? String, editedFields)
        done.tap()
        XCTAssertTrue(app.navigationBars["Aster"].waitForExistence(timeout: 5))
        reveal(polarity, in: app, toward: .top)
        XCTAssertEqual(polarityName(of: polarity), expectedPolarity)
        attachScreenshot(of: app, named: "Updated world controls retained")
    }

    func testStardustAndTuningStayWithTheirWorld() throws {
        let app = launchPausedUniverse()

        let stardust = app.buttons["scatterStardust"]
        reveal(stardust, in: app)
        stardust.tap()
        let response = app.descendants(matching: .any).matching(identifier: "worldResponse").firstMatch
        XCTAssertTrue(response.waitForExistence(timeout: 5))
        assertEventually(
            NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "A little possibility, planted.", "Press play"),
            on: response,
            message: "Scattering dust while paused must acknowledge the action and explain how to see it unfold."
        )

        let dial = openWarmth(in: app)
        let initialValue = try XCTUnwrap(dial.value as? String)
        let initialPercent = try tuningPercent(in: initialValue)
        XCTAssertEqual(initialPercent, 46, "Fresh Aster starts with its balanced energy input.")

        let increase = app.buttons["increaseTuning"]
        reveal(increase, in: app, alongEdge: true)
        increase.tap()
        assertEventually(
            NSPredicate(format: "value != %@", initialValue), on: dial,
            message: "The increase button must update the accessible dial value."
        )
        let editedValue = try XCTUnwrap(dial.value as? String)
        XCTAssertEqual(try tuningPercent(in: editedValue), initialPercent + 5)
        closeTuning(in: app)

        let reopenedDial = openWarmth(in: app)
        XCTAssertEqual(reopenedDial.value as? String, editedValue,
                       "Reopening the sheet must preserve Aster's edited setting.")
        closeTuning(in: app)

        selectWorld(named: "Mica", in: app)
        let micaDial = openWarmth(in: app)
        let micaValue = try XCTUnwrap(micaDial.value as? String)
        XCTAssertEqual(try tuningPercent(in: micaValue), 86,
                       "Tuning Aster must leave Mica's original high-energy setting untouched.")
        closeTuning(in: app)

        selectWorld(named: "Aster", in: app)
        XCTAssertEqual(openWarmth(in: app).value as? String, editedValue,
                       "Switching worlds must retain the setting belonging to Aster.")
        closeTuning(in: app)

        let playback = app.buttons["universePlayPause"]
        reveal(playback, in: app, toward: .top)
        XCTAssertEqual(playback.label, "Let it unfold", "Editing and switching worlds must preserve the paused state.")
        playback.tap()
        assertEventually(NSPredicate(format: "label == %@", "Pause universe"), on: playback,
                         message: "Play must start the shared universe clock.")
        playback.tap()
        assertEventually(NSPredicate(format: "label == %@", "Let it unfold"), on: playback,
                         message: "Pause must return the universe to its resting state.")
        attachScreenshot(of: app, named: "Tuned Aster resting after playback")
    }

    private func launchPausedUniverse() -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.utkarsh.nano")
        app.launchArguments = ["-uitesting"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Your universe"].waitForExistence(timeout: 10))
        let playback = app.buttons["universePlayPause"]
        XCTAssertTrue(playback.waitForExistence(timeout: 5))
        XCTAssertEqual(playback.label, "Let it unfold", "The fresh test fixture must start paused.")
        return app
    }

    private func openWarmth(in app: XCUIApplication) -> XCUIElement {
        let warmth = app.buttons["tune-warmth"]
        reveal(warmth, in: app)
        warmth.tap()
        XCTAssertTrue(app.navigationBars["Warmth"].waitForExistence(timeout: 5))
        let dial = app.descendants(matching: .any).matching(identifier: "tuningDial").firstMatch
        XCTAssertTrue(dial.waitForExistence(timeout: 5))
        reveal(dial, in: app, toward: .top, alongEdge: true)
        return dial
    }

    private func closeTuning(in app: XCUIApplication) {
        let done = app.buttons["doneTuning"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        assertEventually(NSPredicate(format: "exists == false"), on: app.navigationBars["Warmth"],
                         message: "Done must dismiss the tuning sheet before the next interaction.")
    }

    private func selectWorld(named name: String, in app: XCUIApplication) {
        let shelf = app.buttons["chooseUniverse"]
        reveal(shelf, in: app, toward: .top)
        shelf.tap()
        XCTAssertTrue(app.navigationBars["Your worlds"].waitForExistence(timeout: 5))
        // The native list button combines its world name and population into one label.
        let choice = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 5))
        choice.tap()
        assertEventually(NSPredicate(format: "exists == false"), on: app.navigationBars["Your worlds"],
                         message: "Choosing a world must dismiss the shelf.")
        assertEventually(NSPredicate(format: "label CONTAINS %@", name), on: shelf,
                         message: "The universe header must identify the selected world.")
    }

    private func tuningPercent(in value: String) throws -> Int {
        let number = value.components(separatedBy: CharacterSet.decimalDigits.inverted)
            .compactMap { Int($0) }.first
        let percent = try XCTUnwrap(number, "The adjustable dial must expose its numeric percent.")
        XCTAssertTrue((0...100).contains(percent))
        return percent
    }

    private func assertEventually(
        _ predicate: NSPredicate,
        on element: XCUIElement,
        message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed,
                       message, file: file, line: line)
    }

    private func polarityName(of element: XCUIElement) -> String {
        let content = [element.label, element.value as? String ?? ""].joined(separator: " ")
        if content.localizedCaseInsensitiveContains("Positive") { return "Positive" }
        if content.localizedCaseInsensitiveContains("Negative") { return "Negative" }
        return content
    }

    private enum ScrollDestination {
        case top, bottom

        var opposite: ScrollDestination { self == .top ? .bottom : .top }
    }

    private func reveal(
        _ element: XCUIElement,
        in app: XCUIApplication,
        toward preferredDestination: ScrollDestination = .bottom,
        alongEdge: Bool = false,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        // Form can omit offscreen rows from the accessibility tree until a scroll creates them.
        // A reopened sheet may also restore its former scroll position, so search both directions.
        for destination in [preferredDestination, preferredDestination.opposite] {
            for _ in 0..<6 {
                if element.exists && element.isHittable { return }
                let surface = visibleScrollSurface(in: app) ?? app
                if alongEdge {
                    // A center swipe on the tuning sheet would change the dial instead of scrolling.
                    let startY = destination == .top ? 0.25 : 0.75
                    let endY = destination == .top ? 0.75 : 0.25
                    surface.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: startY))
                        .press(forDuration: 0.05, thenDragTo: surface.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: endY)))
                } else {
                    switch destination {
                    case .top: surface.swipeDown()
                    case .bottom: surface.swipeUp()
                    }
                }
            }
        }
        XCTAssertTrue(element.waitForExistence(timeout: 2), "The expected control must be created when its row is revealed.", file: file, line: line)
        XCTAssertTrue(element.isHittable, "The expected control must be reachable by scrolling.", file: file, line: line)
    }

    private func visibleScrollSurface(in app: XCUIApplication) -> XCUIElement? {
        // Native SwiftUI Form uses a collection view or table depending on platform/version.
        // Prefer a hittable container so the obscured screen behind a sheet is never scrolled.
        for query in [app.collectionViews, app.tables, app.scrollViews] {
            if let surface = query.allElementsBoundByIndex.reversed().first(where: {
                $0.exists && $0.isHittable && $0.frame.height > 150 && $0.frame.width > 150
            }) {
                return surface
            }
        }
        return nil
    }

    private func nativeSwitch(in identifiedElement: XCUIElement) -> XCUIElement {
        // SwiftUI can expose both a labelled Form row and its nested native switch as switches.
        let candidates = [identifiedElement] + identifiedElement.descendants(matching: .switch).allElementsBoundByIndex
        return candidates.filter {
            $0.exists && $0.isHittable && ["0", "1"].contains($0.value as? String ?? "")
        }.min {
            $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height
        } ?? identifiedElement
    }

    private func tapSwitch(_ element: XCUIElement) {
        if element.frame.width > 120 {
            // If accessibility combines the control and label, tap the trailing switch area.
            element.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5))
                .withOffset(CGVector(dx: -28, dy: 0)).tap()
        } else {
            element.tap()
        }
    }

    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
