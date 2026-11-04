import XCTest

final class AvoHelperUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testEmptySelectionState() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["选择滚动截图"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["选择截图"].exists)
    }

    func testSwitchesWorkflowsAndVideoEngines() {
        let app = XCUIApplication()
        app.launch()
        let menu = app.buttons["workflow-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap()
        app.buttons["视频转长截图"].tap()
        XCTAssertTrue(app.staticTexts["选择滚动录屏"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["从相册选择"].exists)
        XCTAssertTrue(app.buttons["从文件选择"].exists)
        XCTAssertFalse(app.buttons["生成长截图"].isEnabled)
        let algorithmMenu = app.buttons["video-algorithm-menu"]
        XCTAssertTrue(algorithmMenu.exists)
        algorithmMenu.tap()
        app.buttons["hypr-longshot"].tap()
        XCTAssertTrue(app.staticTexts["适合平稳向下滚动；遇到无法连接的内容会分段保留。"].exists)
        algorithmMenu.tap()
        app.buttons["Long Screen"].tap()
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "视频转换页面"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        menu.tap()
        app.buttons["多张截图拼接"].tap()
        XCTAssertTrue(app.staticTexts["选择滚动截图"].waitForExistence(timeout: 3))
    }

    func testOpensCropEditorFromDemoResult() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo-result"]
        app.launch()

        let cropButton = app.buttons["裁剪"]
        XCTAssertTrue(cropButton.waitForExistence(timeout: 3))
        cropButton.tap()

        XCTAssertTrue(app.navigationBars["裁剪"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["拖动边角或边缘调整裁剪范围"].exists)
        XCTAssertTrue(app.buttons["完成"].exists)
    }

    func testDraggingTopCornerKeepsOppositeBottomCornerFixed() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo-result"]
        app.launch()
        app.buttons["裁剪"].tap()

        let topLeft = app.buttons["crop-handle-topLeft"]
        let bottomRight = app.buttons["crop-handle-bottomRight"]
        XCTAssertTrue(topLeft.waitForExistence(timeout: 3))
        XCTAssertTrue(bottomRight.exists)

        let originalTopLeftFrame = topLeft.frame
        let originalBottomRightFrame = bottomRight.frame
        let start = topLeft.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = start.withOffset(CGVector(dx: 24, dy: 100))
        start.press(forDuration: 0.1, thenDragTo: end)

        XCTAssertGreaterThan(topLeft.frame.midY, originalTopLeftFrame.midY + 60)
        XCTAssertEqual(bottomRight.frame.midX, originalBottomRightFrame.midX, accuracy: 2)
        XCTAssertEqual(bottomRight.frame.midY, originalBottomRightFrame.midY, accuracy: 2)
    }

    func testInteriorTapDoesNothingAndTopEdgeMovesInParallel() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo-result"]
        app.launch()
        app.buttons["裁剪"].tap()

        let topLeft = app.buttons["crop-handle-topLeft"]
        let top = app.buttons["crop-handle-top"]
        let topRight = app.buttons["crop-handle-topRight"]
        let bottomRight = app.buttons["crop-handle-bottomRight"]
        XCTAssertTrue(top.waitForExistence(timeout: 3))

        let originalTopLeftFrame = topLeft.frame
        let originalTopRightFrame = topRight.frame
        let originalBottomRightFrame = bottomRight.frame

        let window = app.windows.element(boundBy: 0)
        let windowFrame = window.frame
        let cropCenter = CGPoint(
            x: (originalTopLeftFrame.midX + originalBottomRightFrame.midX) / 2,
            y: (originalTopLeftFrame.midY + originalBottomRightFrame.midY) / 2
        )
        window.coordinate(
            withNormalizedOffset: CGVector(
                dx: cropCenter.x / windowFrame.width,
                dy: cropCenter.y / windowFrame.height
            )
        ).tap()

        XCTAssertEqual(topLeft.frame.midX, originalTopLeftFrame.midX, accuracy: 1)
        XCTAssertEqual(topLeft.frame.midY, originalTopLeftFrame.midY, accuracy: 1)
        XCTAssertEqual(bottomRight.frame.midX, originalBottomRightFrame.midX, accuracy: 1)
        XCTAssertEqual(bottomRight.frame.midY, originalBottomRightFrame.midY, accuracy: 1)

        let start = top.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = start.withOffset(CGVector(dx: 0, dy: 90))
        start.press(forDuration: 0.1, thenDragTo: end)

        XCTAssertGreaterThan(topLeft.frame.midY, originalTopLeftFrame.midY + 60)
        XCTAssertGreaterThan(topRight.frame.midY, originalTopRightFrame.midY + 60)
        XCTAssertEqual(topLeft.frame.midX, originalTopLeftFrame.midX, accuracy: 2)
        XCTAssertEqual(topRight.frame.midX, originalTopRightFrame.midX, accuracy: 2)
        XCTAssertEqual(bottomRight.frame.midX, originalBottomRightFrame.midX, accuracy: 2)
        XCTAssertEqual(bottomRight.frame.midY, originalBottomRightFrame.midY, accuracy: 2)
    }
}
