import XCTest

final class FFMpegasusNativeXCUITests: XCTestCase {
    private var app: XCUIApplication!

    private var packageRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 {
            url.deleteLastPathComponent()
        }
        return url
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        if let app, app.state != .notRunning {
            captureDiagnostics(for: app, name: "teardown")
            app.terminate()
        }
        app = nil
        try super.tearDownWithError()
    }

    func testLaunchAccessibilitySmoke() throws {
        app = launchApp()

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(element("main.content").waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["playback.play"].exists)
        XCTAssertTrue(app.buttons["playback.pause"].exists)
        XCTAssertTrue(app.buttons["playback.stop"].exists)

        let timeline = app.sliders["playback.timeline"]
        XCTAssertTrue(timeline.exists)
        XCTAssertFalse(timeline.isEnabled)
        XCTAssertFalse(app.alerts.firstMatch.exists)

        assertEditingSectionsAreDiscoverable()
    }

    func testLoadedMediaControlState() throws {
        app = launchApp(fixtureURL: try standardFixtureURL())

        XCTAssertTrue(element("toolbar.loadedFile").waitForExistence(timeout: 10))
        XCTAssertTrue(waitUntil(timeout: 10) { self.app.buttons["playback.play"].isEnabled })
        XCTAssertTrue(waitUntil(timeout: 10) { self.app.buttons["playback.stop"].isEnabled })
        XCTAssertTrue(waitUntil(timeout: 10) { self.app.sliders["playback.timeline"].isEnabled })

        let duration = app.staticTexts["playback.duration"]
        XCTAssertTrue(duration.exists)
        XCTAssertNotEqual(accessibleText(duration), "00:00.000")

        assertEditingSectionsAreDiscoverable()
    }

    func testPlaybackButtonsThroughAccessibility() throws {
        app = launchApp(fixtureURL: try standardFixtureURL())
        XCTAssertTrue(waitUntil(timeout: 10) { self.app.sliders["playback.timeline"].isEnabled })

        let currentTime = app.staticTexts["playback.currentTime"]
        let initial = accessibleText(currentTime)
        app.buttons["playback.play"].click()
        XCTAssertTrue(waitUntil(timeout: 6) { self.accessibleText(currentTime) != initial })

        let playingTime = accessibleText(currentTime)
        app.buttons["playback.pause"].click()
        let pausedTime = accessibleText(currentTime)
        XCTAssertTrue(waitUntil(timeout: 4) { self.app.buttons["playback.play"].isEnabled })
        Thread.sleep(forTimeInterval: 0.4)
        XCTAssertEqual(accessibleText(currentTime), pausedTime)
        XCTAssertNotEqual(playingTime, "00:00.000")

        app.buttons["playback.stop"].click()
        XCTAssertTrue(waitUntil(timeout: 5) { self.accessibleText(currentTime) == "00:00.000" })
    }

    func testTimelineCanBeAdjustedThroughAccessibility() throws {
        app = launchApp(fixtureURL: try standardFixtureURL())
        let timeline = app.sliders["playback.timeline"]
        XCTAssertTrue(waitUntil(timeout: 10) { timeline.isEnabled })

        let currentTime = app.staticTexts["playback.currentTime"]
        let initial = accessibleText(currentTime)
        timeline.adjust(toNormalizedSliderPosition: 0.35)
        XCTAssertTrue(waitUntil(timeout: 8) {
            let text = self.accessibleText(currentTime)
            return text != initial && text != "00:00.000"
        })
        XCTAssertTrue(app.windows.firstMatch.exists)
    }

    func testCurrentFrameExportThroughVisibleControls() throws {
        let outputDirectory = try temporaryDirectory(named: "xcui-frame-export")
        let outputURL = outputDirectory.appendingPathComponent("frame-xcui.png")
        app = launchApp(fixtureURL: try standardFixtureURL(), frameOutputURL: outputURL)
        XCTAssertTrue(waitUntil(timeout: 10) { self.app.sliders["playback.timeline"].isEnabled })

        app.buttons["playback.play"].click()
        XCTAssertTrue(waitUntil(timeout: 8) { self.accessibleText(self.app.staticTexts["playback.currentTime"]) != "00:00.000" })
        app.buttons["playback.pause"].click()
        XCTAssertTrue(waitUntil(timeout: 4) { self.app.buttons["playback.play"].isEnabled })

        let formatPicker = element("frameExport.formatPicker")
        XCTAssertTrue(scrollToElement(formatPicker))
        XCTAssertTrue(formatPicker.exists)

        let exportButton = app.buttons["frameExport.exportButton"]
        XCTAssertTrue(scrollToElement(exportButton))
        XCTAssertTrue(waitUntil(timeout: 10) { exportButton.isEnabled })
        exportButton.click()

        XCTAssertTrue(waitUntil(timeout: 12) {
            FileManager.default.fileExists(atPath: outputURL.path)
        })
        let attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        let size = try XCTUnwrap(attributes[.size] as? NSNumber)
        XCTAssertGreaterThan(size.uint64Value, 0)

        let operationStatus = element("operation.status")
        XCTAssertTrue(waitUntil(timeout: 8) {
            operationStatus.exists && self.accessibleText(operationStatus).contains("Frame export complete")
        })
    }

    private func launchApp(fixtureURL: URL? = nil, frameOutputURL: URL? = nil) -> XCUIApplication {
        let application = XCUIApplication()
        application.launchEnvironment["FFMPEGASUS_XCUITEST_MODE"] = "1"
        application.launchEnvironment["FFMPEGASUS_XCUITEST_RESET_DEFAULTS"] = "1"
        if let fixtureURL {
            application.launchEnvironment["FFMPEGASUS_XCUITEST_FIXTURE"] = fixtureURL.path
        }
        if let frameOutputURL {
            application.launchEnvironment["FFMPEGASUS_XCUITEST_FRAME_OUTPUT"] = frameOutputURL.path
        }
        application.launch()
        return application
    }

    private func assertEditingSectionsAreDiscoverable() {
        for identifier in [
            "editing.trim",
            "editing.removeAudio",
            "editing.combinedExport",
            "editing.transform",
            "editing.compression",
            "editing.speed",
            "editing.frameExport",
            "editing.intervalFrameExport"
        ] {
            XCTAssertTrue(scrollToElement(element(identifier)), "Missing accessible section: \(identifier)")
        }
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func accessibleText(_ element: XCUIElement) -> String {
        if let value = element.value as? String, !value.isEmpty {
            return value
        }
        return element.label
    }

    private func scrollToElement(_ target: XCUIElement, maxSwipes: Int = 8) -> Bool {
        if target.waitForExistence(timeout: 0.5) {
            return true
        }
        let scrollView = app.scrollViews["main.content"].exists ? app.scrollViews["main.content"] : app.scrollViews.firstMatch
        guard scrollView.exists else {
            return target.waitForExistence(timeout: 1)
        }
        for _ in 0..<maxSwipes {
            scrollView.scroll(byDeltaX: 0, deltaY: -12)
            if target.waitForExistence(timeout: 0.5) {
                return true
            }
        }
        for _ in 0..<maxSwipes {
            scrollView.scroll(byDeltaX: 0, deltaY: 12)
        }
        return target.waitForExistence(timeout: 0.5)
    }

    private func waitUntil(timeout: TimeInterval, condition: @escaping () -> Bool) -> Bool {
        let predicate = NSPredicate { _, _ in condition() }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func standardFixtureURL() throws -> URL {
        let url = packageRoot.appendingPathComponent("Tests/Fixtures/generated/standard-landscape.mp4")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Missing generated fixture. Run `make fixtures` before `make xcui-test`.")
        }
        return url
    }

    private func temporaryDirectory(named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ffmpegasus-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func captureDiagnostics(for app: XCUIApplication, name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "\(name)-screenshot"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "\(name)-accessibility-hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }
}
