import XCTest

/// End-to-end flows against a DEBUG build started with `-UITestReset` (fresh temp vault, fast KDF).
@MainActor
final class SecureVaultUITests: XCTestCase {
  let password = "example-master-password"
  var app: XCUIApplication!

  override func setUp() async throws {
    continueAfterFailure = false
    app = XCUIApplication()
    app.launchArguments = ["-UITestReset"]
    app.launch()
  }

  private func createVault() {
    let field = app.secureTextFields["masterPassword"]
    XCTAssertTrue(field.waitForExistence(timeout: 10))
    field.tap()
    field.typeText(password)
    let confirm = app.secureTextFields["confirmPassword"]
    confirm.tap()
    confirm.typeText(password)
    app.buttons["unlockButton"].tap()
    XCTAssertTrue(app.buttons["addButton"].waitForExistence(timeout: 10))
  }

  private func addPassword(title: String) {
    app.buttons["addButton"].tap()
    let titleField = app.textFields["titleField"]
    XCTAssertTrue(titleField.waitForExistence(timeout: 5))
    titleField.tap()
    titleField.typeText(title)
    app.textFields["usernameField"].tap()
    app.textFields["usernameField"].typeText("alice@example.com")
    app.secureTextFields["passwordField"].tap()
    app.secureTextFields["passwordField"].typeText("Not-A-Real-Password-1!")
    app.buttons["saveButton"].tap()
  }

  func testCreateVaultAndAddPassword() {
    createVault()
    addPassword(title: "Example Mail")
    XCTAssertTrue(app.staticTexts["Example Mail"].waitForExistence(timeout: 5))
  }

  func testAddAuthenticatorShowsLiveCode() {
    createVault()
    app.tabBars.buttons["Códigos"].tap()
    app.buttons["addButton"].tap()
    let title = app.textFields["titleField"]
    XCTAssertTrue(title.waitForExistence(timeout: 5))
    title.tap()
    title.typeText("Example Corp")
    let secret = app.textFields["secretField"]
    secret.tap()
    secret.typeText("GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ")
    app.buttons["saveButton"].tap()
    XCTAssertTrue(app.staticTexts["Example Corp"].waitForExistence(timeout: 5))
    let code = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "\\d{3} \\d{3}")).firstMatch
    XCTAssertTrue(code.waitForExistence(timeout: 5), "a 6-digit code grouped as 'NNN NNN' is displayed")
  }

  func testLockAndUnlock() {
    createVault()
    app.tabBars.buttons["Ajustes"].tap()
    app.buttons["lockNow"].tap()
    let field = app.secureTextFields["masterPassword"]
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    field.tap()
    field.typeText("wrong password")
    app.buttons["unlockButton"].tap()
    XCTAssertTrue(app.staticTexts["errorMessage"].waitForExistence(timeout: 5))
    field.tap()
    field.typeText(password)
    app.buttons["unlockButton"].tap()
    XCTAssertTrue(app.buttons["addButton"].waitForExistence(timeout: 10))
  }

  func testDeleteRequiresConfirmation() {
    createVault()
    addPassword(title: "To Delete")
    app.staticTexts["To Delete"].tap()
    app.buttons["deleteButton"].tap()
    // The iOS 26 confirmation dialog is a popover: only the destructive action is a button; tapping outside cancels.
    let confirm = app.buttons.matching(
      NSPredicate(format: "label == 'Excluir' AND identifier != 'deleteButton'")
    ).firstMatch
    XCTAssertTrue(confirm.waitForExistence(timeout: 5))
    app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.6)).tap()
    XCTAssertTrue(app.buttons["deleteButton"].waitForExistence(timeout: 5), "dismissing keeps the item")
    XCTAssertFalse(confirm.exists)
    app.buttons["deleteButton"].tap()
    XCTAssertTrue(confirm.waitForExistence(timeout: 5))
    confirm.tap()
    XCTAssertTrue(app.buttons["addButton"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.staticTexts["To Delete"].exists)
  }

  func testGoingToBackgroundLocksTheVault() {
    createVault()
    XCUIDevice.shared.press(.home)
    XCTAssertTrue(app.wait(for: .runningBackgroundSuspended, timeout: 5) || app.state != .runningForeground)
    app.activate()
    XCTAssertTrue(
      app.secureTextFields["masterPassword"].waitForExistence(timeout: 10), "vault is locked after returning")
    XCTAssertFalse(app.buttons["addButton"].exists)
  }

  func testSecretsAreMaskedUntilRevealed() {
    createVault()
    addPassword(title: "Masked")
    app.staticTexts["Masked"].tap()
    let value = app.staticTexts["value-Senha"]
    XCTAssertTrue(value.waitForExistence(timeout: 5))
    XCTAssertEqual(value.label, "Senha, oculto")
    app.buttons["Revelar Senha"].tap()
    XCTAssertEqual(value.label, "Senha, Not-A-Real-Password-1!")
  }
}
