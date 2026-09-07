import XCTest
final class NavigationTests:XCTestCase {
 let app=XCUIApplication()
 override func setUp(){continueAfterFailure=false;app.launch()}
 func capture(_ name:String){let a=XCTAttachment(screenshot:app.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)}
 func testLearnerAndTrainerNavigation(){
  XCTAssertTrue(app.navigationBars["Tertiary LMS"].waitForExistence(timeout:15))
  let demo=app.buttons["demo"];XCTAssertTrue(demo.waitForExistence(timeout:15));demo.tap();app.buttons["Learner demo"].tap()
  XCTAssertTrue(app.staticTexts["Hello, Jamie."].waitForExistence(timeout:10));capture("01-learner-today")
  app.buttons["Courseware"].firstMatch.tap();XCTAssertTrue(app.staticTexts["Build practical AI workflows"].waitForExistence(timeout:10));capture("02-courseware")
  app.staticTexts["Build practical AI workflows"].firstMatch.tap();XCTAssertTrue(app.buttons["Learner guide"].waitForExistence(timeout:5));XCTAssertFalse(app.buttons["Trainer slides"].exists);capture("03-course-detail")
  app.buttons["Calendar"].firstMatch.tap();XCTAssertTrue(app.staticTexts["Classes · Singapore time"].waitForExistence(timeout:5));if app.buttons["Jump to next class"].exists{app.buttons["Jump to next class"].tap()};capture("04-calendar")
  app.buttons["Account"].firstMatch.tap();app.swipeUp();app.buttons["Exit demo"].tap();XCTAssertTrue(demo.waitForExistence(timeout:5));demo.tap();app.buttons["Trainer demo"].tap();XCTAssertTrue(app.staticTexts["Hello, Alex."].waitForExistence(timeout:5));capture("05-trainer-today")
  app.buttons["Courseware"].firstMatch.tap();app.staticTexts["Build practical AI workflows"].firstMatch.tap();XCTAssertTrue(app.buttons["Trainer slides"].waitForExistence(timeout:5));capture("06-trainer-materials")
 }
}
