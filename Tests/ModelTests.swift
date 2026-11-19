import XCTest

@testable import TertiaryLearning

final class ModelTests: XCTestCase {
  func testSingaporeDateFormats() {
    let a = ClassSession.date("2026-09-10", "09:00")
    let b = ClassSession.date("20260910", "0900")
    XCTAssertEqual(a, b)
    XCTAssertEqual(a?.timeIntervalSince1970, 1_789_002_000)
  }
  func testInvalidDate() {
    XCTAssertNil(ClassSession.date(nil, "09:00"))
    XCTAssertNil(ClassSession.date("garbage", "09:00"))
  }
  func testDemoHasDistinctSessionsAndMaterials() {
    let d = Sample.data(role: "learner")
    XCTAssertEqual(Set(d.sessions.map(\.id)).count, d.sessions.count)
    XCTAssertTrue(d.courses.allSatisfy { $0.guideURL != nil })
    XCTAssertTrue(d.sessions.allSatisfy { $0.end! > $0.start! })
  }
  func testRoleSpecificAcademyMaterials() {
    let course = Sample.data(role: "learner").courses[0]
    XCTAssertEqual(course.materials(for: "learner").map(\.id), ["slides", "guide", "activities"])
    XCTAssertEqual(course.materials(for: "trainer").first?.id, "trainer-slides")
    XCTAssertTrue(course.materials(for: "trainer").allSatisfy(\.isPublished))
  }
  func testCoursewareLinksBecomePDFDownloads() {
    XCTAssertEqual(
      DocumentLink.pdfURL(for: "https://drive.google.com/file/d/1AbCdEfGhIjKlMnOp/view?usp=sharing")?
        .absoluteString,
      "https://drive.google.com/uc?export=download&id=1AbCdEfGhIjKlMnOp")
    XCTAssertEqual(
      DocumentLink.pdfURL(for: "https://docs.google.com/presentation/d/1AbCdEfGhIjKlMnOp/edit")?
        .absoluteString,
      "https://docs.google.com/presentation/d/1AbCdEfGhIjKlMnOp/export/pdf")
    XCTAssertEqual(
      DocumentLink.pdfURL(for: "https://example.com/files/guide.pdf")?.absoluteString,
      "https://example.com/files/guide.pdf")
    XCTAssertNil(DocumentLink.pdfURL(for: "https://drive.google.com/drive/folders/1AbCdEfGhIjKlMnOp"))
    XCTAssertNil(DocumentLink.pdfURL(for: "http://example.com/guide.pdf"))
    XCTAssertNil(DocumentLink.pdfURL(for: "https://example.com/page.html"))
  }
  func testCheckinCodeAcceptsOnlyClassCodes() {
    let token = String(repeating: "a1", count: 16)
    XCTAssertEqual(
      DocumentLink.checkinCode("https://lms-tms.tertiaryinfotech.com/checkin/\(token)"), token)
    XCTAssertEqual(DocumentLink.checkinCode(" \(token.uppercased()) "), token)
    XCTAssertNil(DocumentLink.checkinCode("https://example.com/other/\(token)"))
    XCTAssertNil(DocumentLink.checkinCode("https://www.myskillsfuture.gov.sg/api/take-attendance/RA123456"))
  }
  func testMorningAlertTime() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Singapore")!
    let nine = ClassSession.date("2026-12-01", "09:00")!
    XCTAssertEqual(ClassAlerts.fireDate(for: nine, calendar: calendar), ClassSession.date("2026-12-01", "08:00"))
    let early = ClassSession.date("2026-12-01", "08:15")!
    XCTAssertEqual(ClassAlerts.fireDate(for: early, calendar: calendar), ClassSession.date("2026-12-01", "07:15"))
  }
  func testSampleClassDetailIsRoleSpecific() {
    let learner = Sample.detail(id: "sample-ai", role: "learner", dashboard: Sample.data(role: "learner"))
    XCTAssertNil(learner.roster)
    XCTAssertFalse(learner.materials.contains { $0.id == "trainer-slides" })
    XCTAssertTrue(learner.assessments.allSatisfy(\.published))
    let trainer = Sample.detail(id: "sample-ai", role: "trainer", dashboard: Sample.data(role: "trainer"))
    XCTAssertEqual(trainer.roster?.count, 3)
    XCTAssertEqual(trainer.materials.first?.id, "trainer-slides")
    XCTAssertNotNil(Sample.pdf(title: "Learner Guide"))
  }
  /// Responses recorded from the backend's /api/mobile routes; the app must decode them as-is.
  func fixture<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
    let url = try XCTUnwrap(Bundle(for: ModelTests.self).url(forResource: name, withExtension: "json"))
    return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
  }
  func testDecodesRecordedServerResponses() throws {
    let learner = try fixture("class-learner", as: Reply<ClassDetail>.self).data
    XCTAssertEqual(learner.runCode, "APPTEST-RUN")
    XCTAssertEqual(learner.materials.map(\.id), ["slides"])
    XCTAssertEqual(learner.sessions.first?.attendance, "absent")
    XCTAssertEqual(learner.assessments.map(\.type), ["writtenAssessment"])
    XCTAssertEqual(learner.feedback?.enabled, true)
    XCTAssertNil(learner.roster)
    XCTAssertNotNil(learner.ssgAttendanceURL)

    let trainer = try fixture("class-trainer", as: Reply<ClassDetail>.self).data
    XCTAssertEqual(trainer.roster?.count, 2)
    XCTAssertEqual(trainer.assessments.count, 2)
    XCTAssertTrue(trainer.materials.contains { $0.id == "facilitator-guide" })
    XCTAssertNotNil(trainer.sessions.first?.presentCount)

    let sheet = try fixture("attendance", as: Reply<AttendanceSheet>.self).data
    XCTAssertEqual(sheet.learners.count, 2)
    XCTAssertNotNil(DocumentLink.checkinCode(sheet.checkinURL ?? ""))

    let form = try fixture("feedback", as: Reply<FeedbackForm>.self).data
    XCTAssertFalse(form.sections.flatMap(\.fields).isEmpty)

    let profile = try fixture("profile", as: Reply<Profile>.self).data
    XCTAssertTrue(["system", "light", "dark"].contains(profile.theme))

    let dashboard = try fixture("dashboard", as: Dashboard.self)
    XCTAssertEqual(dashboard.courses.count, 1)
  }
}
