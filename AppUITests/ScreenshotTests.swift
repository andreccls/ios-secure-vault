import XCTest

/// Not a regression test: captures README screenshots from fictional seed data. Runs only when
/// SCREENSHOT_DIR is set (scripts/screenshots.sh). Appearance/text size are set by the script via simctl.
@MainActor
final class ScreenshotTests: XCTestCase {
  func testCaptureScreens() throws {
    let env = ProcessInfo.processInfo.environment
    let directory = try XCTUnwrap(
      env["SCREENSHOT_DIR"] ?? env["TEST_RUNNER_SCREENSHOT_DIR"], "SCREENSHOT_DIR not set")
    let suffix = env["SHOT_SUFFIX"] ?? env["TEST_RUNNER_SHOT_SUFFIX"] ?? "light"
    try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    func shot(_ name: String) {
      let data = XCUIScreen.main.screenshot().pngRepresentation
      try? data.write(to: URL(fileURLWithPath: "\(directory)/\(name)-\(suffix).png"))
    }

    let app = XCUIApplication()
    app.launchArguments = ["-UITestSeed"]
    app.launch()
    let field = app.secureTextFields["masterPassword"]
    XCTAssertTrue(field.waitForExistence(timeout: 10))
    shot("01-locked")
    field.tap()
    field.typeText("example-master-password")
    app.buttons["unlockButton"].tap()
    XCTAssertTrue(app.buttons["addButton"].waitForExistence(timeout: 10))
    shot("02-passwords")

    app.staticTexts["Example Mail"].tap()
    XCTAssertTrue(app.buttons["Revelar Senha"].waitForExistence(timeout: 5))
    shot("03-detail-masked")
    app.buttons["Revelar Senha"].tap()
    shot("04-detail-revealed")
    app.navigationBars.buttons.firstMatch.tap()

    app.buttons["Gerador de senha"].tap()
    XCTAssertTrue(app.staticTexts["generatedPassword"].waitForExistence(timeout: 5))
    shot("05-generator")
    app.buttons["Fechar"].tap()

    app.tabBars.buttons["Códigos"].tap()
    XCTAssertTrue(app.staticTexts["Example Corp"].waitForExistence(timeout: 5))
    shot("06-authenticators")

    app.tabBars.buttons["Chaves"].tap()
    XCTAssertTrue(app.staticTexts["Chave de API (pagamentos)"].waitForExistence(timeout: 5))
    shot("07-keys")

    app.tabBars.buttons["Ajustes"].tap()
    XCTAssertTrue(app.buttons["lockNow"].waitForExistence(timeout: 5))
    shot("08-settings")
  }

  func testCapturePrivacyShield() throws {
    let env = ProcessInfo.processInfo.environment
    let directory = try XCTUnwrap(env["SCREENSHOT_DIR"] ?? env["TEST_RUNNER_SCREENSHOT_DIR"])
    let suffix = env["SHOT_SUFFIX"] ?? env["TEST_RUNNER_SHOT_SUFFIX"] ?? "light"
    let app = XCUIApplication()
    app.launchArguments = ["-UITestSeed", "-UITestShield"]
    app.launch()
    XCTAssertTrue(
      app.descendants(matching: .any).matching(
        NSPredicate(format: "identifier == 'privacyShield' OR label CONTAINS 'Conteúdo oculto'")
      ).firstMatch.waitForExistence(timeout: 10))
    try XCUIScreen.main.screenshot().pngRepresentation.write(
      to: URL(fileURLWithPath: "\(directory)/09-privacy-\(suffix).png"))
  }
}
