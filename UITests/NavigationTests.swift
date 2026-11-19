import XCTest

final class NavigationTests: XCTestCase {
  let app = XCUIApplication()
  override func setUp() {
    continueAfterFailure = false
    app.launch()
  }
  func capture(_ name: String) {
    let a = XCTAttachment(screenshot: app.screenshot())
    a.name = name
    a.lifetime = .keepAlways
    add(a)
  }
  /// Scrolls until the element is on screen (lists build rows lazily), then returns it.
  @discardableResult func reveal(_ element: XCUIElement) -> XCUIElement {
    var tries = 0
    while !(element.exists && element.isHittable) && tries < 6 {
      app.swipeUp(velocity: .slow)
      tries += 1
    }
    XCTAssertTrue(element.exists, "Not found: \(element)")
    return element
  }
  func testLearnerAndTrainerNavigation() {
    XCTAssertTrue(app.navigationBars["TIA TMS"].waitForExistence(timeout: 15))
    let demo = app.buttons["demo"]
    XCTAssertTrue(demo.waitForExistence(timeout: 15))
    demo.tap()
    app.buttons["Learner demo"].tap()
    XCTAssertTrue(app.staticTexts["Hello, Jamie."].waitForExistence(timeout: 10))
    capture("01-learner-today")
    app.buttons["My Learning"].firstMatch.tap()
    XCTAssertTrue(app.staticTexts["Responsible Generative AI Basics"].waitForExistence(timeout: 10))
    capture("02-courseware")
    app.staticTexts["Responsible Generative AI Basics"].firstMatch.tap()
    XCTAssertTrue(app.buttons["Learner Guide"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["Trainer slides"].exists)
    capture("03-course-detail")
    app.buttons["Calendar"].firstMatch.tap()
    XCTAssertTrue(app.staticTexts["Classes · Singapore time"].waitForExistence(timeout: 5))
    if app.buttons["Jump to next class"].exists { app.buttons["Jump to next class"].tap() }
    capture("04-calendar")
    app.buttons["Account"].firstMatch.tap()
    app.swipeUp()
    app.buttons["Exit demo"].tap()
    XCTAssertTrue(demo.waitForExistence(timeout: 5))
    demo.tap()
    app.buttons["Trainer demo"].tap()
    XCTAssertTrue(app.staticTexts["Hello, Alex."].waitForExistence(timeout: 5))
    capture("05-trainer-today")
    app.buttons["Teaching Kit"].firstMatch.tap()
    app.staticTexts["Responsible Generative AI Basics"].firstMatch.tap()
    XCTAssertTrue(app.buttons["Trainer slides"].waitForExistence(timeout: 5))
    capture("06-trainer-materials")
  }
  /// Walks the class tools added for TIA TMS in sample mode: in-app PDF, QR check-in,
  /// assessment, course feedback, profile and theme (learner); attendance and grading (trainer).
  func testClassToolsInSampleMode() {
    let demo = app.buttons["demo"]
    XCTAssertTrue(demo.waitForExistence(timeout: 15))
    demo.tap()
    app.buttons["Learner demo"].tap()
    app.buttons["My Learning"].firstMatch.tap()
    app.staticTexts["Responsible Generative AI Basics"].firstMatch.tap()

    // Courseware opens in the in-app PDF reader.
    XCTAssertTrue(app.buttons["Learner Guide"].waitForExistence(timeout: 10))
    app.buttons["Learner Guide"].tap()
    XCTAssertTrue(app.buttons["Open in browser"].waitForExistence(timeout: 10))
    capture("07-pdf-reader")
    app.buttons["Done"].tap()

    // QR check-in marks the session present.
    reveal(app.buttons["scan-checkin"]).tap()
    XCTAssertTrue(app.buttons["sample-checkin"].waitForExistence(timeout: 10))
    app.buttons["sample-checkin"].tap()
    XCTAssertTrue(app.staticTexts["You are checked in. (Sample)"].waitForExistence(timeout: 10))
    app.buttons["OK"].tap()
    XCTAssertTrue(app.staticTexts["Present"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["SSG e-attendance (Singpass)"].exists)
    capture("08-attendance-learner")

    // Assessment screen.
    reveal(app.staticTexts["Written Assessment"].firstMatch).tap()
    XCTAssertTrue(app.buttons["submit-file"].waitForExistence(timeout: 10))
    capture("09-assessment")
    app.navigationBars.buttons.firstMatch.tap()

    // Course feedback: required ratings, then sent.
    reveal(app.buttons["course-feedback"]).tap()
    XCTAssertTrue(app.buttons["send-feedback"].waitForExistence(timeout: 10))
    reveal(app.buttons["5 of 5 for The trainer explained clearly"]).tap()
    reveal(app.buttons["4 of 5 for The courseware was useful"]).tap()
    capture("10-course-feedback")
    reveal(app.buttons["send-feedback"]).tap()
    XCTAssertTrue(
      app.staticTexts["Course feedback sent. Thank you."].waitForExistence(timeout: 10))

    // Profile edit and theme.
    app.buttons["Account"].firstMatch.tap()
    XCTAssertTrue(app.buttons["edit-profile"].waitForExistence(timeout: 5))
    app.buttons["edit-profile"].tap()
    XCTAssertTrue(app.textFields["profile-name"].waitForExistence(timeout: 5))
    capture("11-profile")
    reveal(app.buttons["save-profile"]).tap()
    XCTAssertTrue(app.buttons["edit-profile"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["appearance"].exists || app.staticTexts["Appearance"].exists)
    reveal(app.buttons["Exit demo"]).tap()

    // Trainer: attendance sheet with QR and manual marking, then grading.
    XCTAssertTrue(demo.waitForExistence(timeout: 5))
    demo.tap()
    app.buttons["Trainer demo"].tap()
    app.buttons["Teaching Kit"].firstMatch.tap()
    app.staticTexts["Responsible Generative AI Basics"].firstMatch.tap()
    XCTAssertTrue(app.buttons["Lesson Plan"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.buttons["scan-checkin"].exists)
    reveal(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Day 1'")).firstMatch)
      .tap()
    XCTAssertTrue(app.buttons["show-qr"].waitForExistence(timeout: 10))
    app.buttons["show-qr"].tap()
    XCTAssertTrue(app.staticTexts["Scan to check in"].waitForExistence(timeout: 5))
    capture("12-trainer-qr")
    app.buttons["close-qr"].tap()
    capture("13-trainer-attendance")
    reveal(app.buttons["save-attendance"]).tap()
    let saved = expectation(
      for: NSPredicate(format: "label == 'Saved'"), evaluatedWith: app.buttons["save-attendance"])
    wait(for: [saved], timeout: 5)
    app.navigationBars.buttons.firstMatch.tap()
    reveal(app.buttons["grading"]).tap()
    XCTAssertTrue(app.staticTexts["Jamie Lim (sample)"].waitForExistence(timeout: 5))
    capture("14-trainer-grading")
  }
}
