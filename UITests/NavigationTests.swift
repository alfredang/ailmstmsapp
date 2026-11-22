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
  /// The home header card: one button that carries the full name and opens Account.
  func homeHeader(_ fullName: String, timeout: TimeInterval) -> Bool {
    let card = app.buttons["my-profile"]
    return card.waitForExistence(timeout: timeout) && card.label.contains(fullName)
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
  /// Class page sections start collapsed; opens one by its title.
  func open(_ section: String) {
    let header = app.buttons["section-\(section)"]
    // Rows are built lazily: scroll back to the top, then down until the header exists.
    if !header.waitForExistence(timeout: 3) {
      for _ in 0..<3 { app.swipeDown(velocity: .fast) }
      reveal(header)
    }
    XCTAssertTrue(header.exists, "No section \(section)")
    reveal(header)
    if header.value as? String != "Expanded" { header.tap() }
  }
  func testLearnerAndTrainerNavigation() {
    let demo = app.buttons["demo"]
    XCTAssertTrue(demo.waitForExistence(timeout: 15))
    demo.tap()
    app.buttons["As a learner"].tap()
    XCTAssertTrue(homeHeader("Jamie Lim", timeout: 10))
    capture("01-learner-today")
    app.buttons["My Classes"].firstMatch.tap()
    XCTAssertTrue(app.staticTexts["Responsible Generative AI Basics"].waitForExistence(timeout: 10))
    capture("02-courseware")
    app.staticTexts["Responsible Generative AI Basics"].firstMatch.tap()
    open("Courseware")
    XCTAssertTrue(app.buttons["Learner Guide"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["Trainer Slides"].exists)
    capture("03-course-detail")
    app.buttons["Calendar"].firstMatch.tap()
    XCTAssertTrue(app.buttons["Calendar"].firstMatch.waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["Calendar"].firstMatch.isSelected)
    if app.buttons["Jump to next class"].exists { app.buttons["Jump to next class"].tap() }
    capture("04-calendar")
    app.buttons["Account"].firstMatch.tap()
    reveal(app.buttons["Exit demo"]).tap()
    XCTAssertTrue(demo.waitForExistence(timeout: 5))
    demo.tap()
    app.buttons["As a trainer"].tap()
    XCTAssertTrue(homeHeader("Alex Tan", timeout: 5))
    capture("05-trainer-today")
    app.buttons["My Classes"].firstMatch.tap()
    app.staticTexts["Responsible Generative AI Basics"].firstMatch.tap()
    open("Courseware")
    XCTAssertTrue(reveal(app.buttons["Trainer Slides"]).exists)
    capture("06-trainer-materials")
  }
  /// Walks the class tools added for TIA TMS in sample mode: in-app PDF, QR check-in,
  /// assessment, course feedback, profile and theme (learner); attendance and grading (trainer).
  func testClassToolsInSampleMode() {
    let demo = app.buttons["demo"]
    XCTAssertTrue(demo.waitForExistence(timeout: 15))
    demo.tap()
    app.buttons["As a learner"].tap()
    app.buttons["My Classes"].firstMatch.tap()
    app.staticTexts["Responsible Generative AI Basics"].firstMatch.tap()

    // Courseware opens in the in-app PDF reader.
    open("Courseware")
    XCTAssertTrue(app.buttons["Learner Guide"].waitForExistence(timeout: 10))
    app.buttons["Learner Guide"].tap()
    XCTAssertTrue(app.buttons["Open in browser"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.buttons["download-document"].exists)
    capture("07-pdf-reader")
    app.buttons["Done"].tap()

    // QR check-in marks the session present.
    open("E-Attendance")
    reveal(app.buttons["scan-checkin"]).tap()
    XCTAssertTrue(app.buttons["sample-checkin"].waitForExistence(timeout: 10))
    app.buttons["sample-checkin"].tap()
    XCTAssertTrue(app.staticTexts["You are checked in. (Sample)"].waitForExistence(timeout: 10))
    app.buttons["OK"].tap()
    XCTAssertTrue(app.staticTexts["Present"].waitForExistence(timeout: 5))
    capture("08-attendance-learner")

    // The class quiz section opens the sample quiz.
    open("Lesson")
    reveal(app.buttons["sample-quiz"]).tap()
    XCTAssertTrue(app.staticTexts["Question 1 of 3"].waitForExistence(timeout: 10))
    app.buttons["quiz-close"].tap()

    // Assessment screen.
    open("Assessment")
    reveal(app.staticTexts["Written Assessment"].firstMatch).tap()
    XCTAssertTrue(app.buttons["submit-file"].waitForExistence(timeout: 10))
    capture("09-assessment")
    app.navigationBars.buttons.firstMatch.tap()

    // Course feedback: required ratings, then sent.
    open("Course Feedback & TRAQOM Survey")
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
    XCTAssertTrue(app.textFields["profile-name"].waitForExistence(timeout: 5))
    capture("11-profile")
    reveal(app.buttons["save-profile"]).tap()
    XCTAssertTrue(app.staticTexts["Profile saved."].waitForExistence(timeout: 5))
    app.buttons["OK"].tap()
    XCTAssertTrue(app.segmentedControls["appearance"].exists || app.staticTexts["Appearance"].exists)
    reveal(app.buttons["Exit demo"]).tap()

    // Trainer: attendance sheet with QR and manual marking, then grading.
    XCTAssertTrue(demo.waitForExistence(timeout: 5))
    demo.tap()
    app.buttons["As a trainer"].tap()
    app.buttons["My Classes"].firstMatch.tap()
    app.staticTexts["Responsible Generative AI Basics"].firstMatch.tap()
    open("Courseware")
    XCTAssertTrue(app.buttons["Lesson Plan"].waitForExistence(timeout: 10))
    open("E-Attendance")
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
    open("Assessment Grading")
    reveal(app.buttons["grading"]).tap()
    XCTAssertTrue(app.staticTexts["Jamie Lim (sample)"].waitForExistence(timeout: 5))
    capture("14-trainer-grading")
    app.navigationBars.buttons.firstMatch.tap()
    // Trainer-only sections: Publish switches and the feedback summary; no learner surveys.
    open("Assessment")
    XCTAssertTrue(reveal(app.switches["publish-writtenAssessment"]).exists)
    XCTAssertFalse(app.buttons["section-Course Feedback & TRAQOM Survey"].exists)
    open("Post Course Feedback Summary")
    XCTAssertTrue(reveal(app.staticTexts["Overall average"]).exists)
    capture("15-trainer-feedback-summary")
    // Trainer tabs.
    app.buttons["Payout"].firstMatch.tap()
    XCTAssertTrue(app.staticTexts["Total paid"].waitForExistence(timeout: 5))
    app.buttons["Hours"].firstMatch.tap()
    XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 5))
  }

  /// A quiz QR code link: arrives while signed out, waits for sign-in, then the quiz opens.
  /// Answers every question, checks the marked result, retakes, and sees the last score next time.
  func testQuizLinkOpensQuizInSampleMode() {
    let link = URL(
      string: "https://lms-tms.tertiaryinfotech.com/quiz/3f2a1b4c-5d6e-4f70-8a9b-0c1d2e3f4a5b/sample-quiz")!
    let demo = app.buttons["demo"]
    XCTAssertTrue(demo.waitForExistence(timeout: 15))
    app.open(link)
    XCTAssertTrue(app.staticTexts["quiz-pending"].waitForExistence(timeout: 15))
    capture("15-quiz-sign-in-first")
    reveal(demo).tap()
    app.buttons["As a learner"].tap()

    // First attempt: straight to question 1.
    XCTAssertTrue(app.staticTexts["Question 1 of 3"].waitForExistence(timeout: 15))
    XCTAssertFalse(app.buttons["quiz-next"].isEnabled)
    app.buttons["quiz-option-1"].tap()
    capture("16-quiz-question")
    app.buttons["quiz-next"].tap()
    XCTAssertTrue(app.staticTexts["Question 2 of 3"].waitForExistence(timeout: 5))
    app.buttons["quiz-option-2"].tap()
    app.buttons["quiz-next"].tap()
    XCTAssertTrue(app.staticTexts["Question 3 of 3"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["quiz-next"].exists)
    app.buttons["quiz-option-2"].tap()
    app.buttons["quiz-submit"].tap()

    // Result: 2 of 3, with the wrong one marked and its correct option shown.
    XCTAssertTrue(app.staticTexts["2 / 3"].waitForExistence(timeout: 10))
    capture("17-quiz-result")
    XCTAssertTrue(reveal(app.staticTexts["Question 2 · Incorrect"]).exists)
    XCTAssertTrue(app.staticTexts["Question 1 · Correct"].exists)
    capture("18-quiz-review")
    reveal(app.buttons["quiz-done"]).tap()
    XCTAssertTrue(homeHeader("Jamie Lim", timeout: 10))

    // Scanned from the class page: the same quiz now shows the last score first.
    app.buttons["My Classes"].firstMatch.tap()
    app.staticTexts["Responsible Generative AI Basics"].firstMatch.tap()
    open("E-Attendance")
    reveal(app.buttons["scan-checkin"]).tap()
    let field = app.textFields["scan-link"]
    XCTAssertTrue(field.waitForExistence(timeout: 10))
    field.tap()
    field.typeText(link.absoluteString)
    XCTAssertEqual(app.buttons["scan-link-go"].label, "Open quiz")
    app.buttons["scan-link-go"].tap()
    XCTAssertTrue(app.staticTexts["2 / 3"].waitForExistence(timeout: 15))
    XCTAssertTrue(app.buttons["quiz-retake"].exists)
    capture("19-quiz-last-score")
    app.buttons["quiz-retake"].tap()
    XCTAssertTrue(app.staticTexts["Question 1 of 3"].waitForExistence(timeout: 5))
    app.buttons["quiz-option-1"].tap()
    app.buttons["quiz-next"].tap()
    app.buttons["quiz-option-0"].tap()
    app.buttons["quiz-next"].tap()
    app.buttons["quiz-option-2"].tap()
    app.buttons["quiz-submit"].tap()
    XCTAssertTrue(app.staticTexts["3 / 3"].waitForExistence(timeout: 10))
    reveal(app.buttons["quiz-done"]).tap()
    XCTAssertFalse(app.buttons["quiz-done"].waitForExistence(timeout: 2))

    // Already signed in when the link arrives: the quiz opens at once.
    app.launchEnvironment["DEMO_ROLE"] = "learner"
    app.open(link)
    XCTAssertTrue(app.staticTexts["Question 1 of 3"].waitForExistence(timeout: 15))
    XCTAssertTrue(app.staticTexts["SAMPLE QUIZ"].exists)
    app.buttons["quiz-close"].tap()
    XCTAssertTrue(homeHeader("Jamie Lim", timeout: 10))
  }
}
