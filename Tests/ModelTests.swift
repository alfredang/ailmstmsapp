import XCTest

@testable import TertiaryLearning

final class ModelTests: XCTestCase {
  func testSingaporeDateFormats() {
    let a = ClassSession.date("2026-09-10", "09:00")
    let b = ClassSession.date("20260910", "0900")
    XCTAssertEqual(a, b)
    XCTAssertEqual(a?.timeIntervalSince1970, 1_789_002_000)
  }
  @MainActor func testCalendarKeepsConfirmedClassesOnly() throws {
    let json = Data(
      #"""
      {"courses":[
        {"id":"a","title":"Confirmed class","classStatus":"Confirmed"},
        {"id":"b","title":"Pending class","classStatus":"Pending"},
        {"id":"c","title":"No status"}],
       "sessions":[
        {"id":"s1","courseID":"a","title":"Confirmed class","startDate":"2026-11-21","subtitle":"S1"},
        {"id":"s2","courseID":"b","title":"Pending class","startDate":"2026-11-22","subtitle":"S1"},
        {"id":"s3","courseID":"c","title":"No status","startDate":"2026-11-23","subtitle":"S1"}]}
      """#.utf8)
    let store = Store()
    store.dashboard = try JSONDecoder().decode(Dashboard.self, from: json)
    XCTAssertEqual(store.confirmedSessions.map(\.id), ["s1"])
  }
  func testTaughtHoursDecodeAndGroupByMonth() throws {
    let json = Data(
      #"{"data":[{"id":"1","title":"A","code":null,"runCode":"R1","startDate":"2026-11-20","endDate":"2026-11-21","trainingHours":14,"assessmentHours":2.5}]}"#
        .utf8)
    let item = try JSONDecoder().decode(HoursReply.self, from: json).data[0]
    XCTAssertEqual(item.totalHours, 16.5)
    XCTAssertEqual(item.monthKey, "2026-11")
    XCTAssertEqual(Fmt.month("2026-11"), "November 2026")
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
    // Website Courseware order: learners see the guide, then their slides, then the labs.
    XCTAssertEqual(course.materials(for: "learner").map(\.id), ["guide", "slides", "activities"])
    XCTAssertEqual(course.materials(for: "trainer").map(\.id), ["guide", "trainer-slides", "activities"])
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
    XCTAssertEqual(trainer.materials.first?.id, "courseware-link")
    XCTAssertTrue(trainer.materials.contains { $0.id == "trainer-slides" })
    XCTAssertFalse(trainer.materials.contains { $0.id == "slides" })
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

  // MARK: Quiz QR code links

  func testQuizLinkParsing() throws {
    let course = "3f2a1b4c-5d6e-4f70-8a9b-0c1d2e3f4a5b"
    let link = try XCTUnwrap(
      QuizLink.parse(URL(string: "https://lms-tms.tertiaryinfotech.com/quiz/\(course)/quiz-17")!))
    XCTAssertEqual(link.courseID, course)
    XCTAssertEqual(link.quizID, "quiz-17")
    // Trailing slash, query, upper-case host and surrounding whitespace from a QR reader.
    XCTAssertEqual(
      QuizLink.parse(" https://LMS-TMS.tertiaryinfotech.com/quiz/\(course)/quiz-17/?src=qr\n"), link)
    XCTAssertEqual(
      QuizLink.parse("https://lms-tms.tertiaryinfotech.com/quiz/\(course)/a%20b")?.quizID, "a b")
    // Anything else is not a quiz link.
    for bad in [
      "http://lms-tms.tertiaryinfotech.com/quiz/\(course)/quiz-17",
      "https://example.com/quiz/\(course)/quiz-17",
      "https://lms-tms.tertiaryinfotech.com.evil.example/quiz/\(course)/quiz-17",
      "https://lms-tms.tertiaryinfotech.com/quiz/\(course)",
      "https://lms-tms.tertiaryinfotech.com/quiz/\(course)/quiz-17/extra",
      "https://lms-tms.tertiaryinfotech.com/checkin/\(String(repeating: "a", count: 32))",
      "https://lms-tms.tertiaryinfotech.com/",
      "tiatms://quiz/\(course)/quiz-17", "not a link", "",
    ] {
      XCTAssertNil(QuizLink.parse(bad), bad)
    }
    // A check-in code is still a check-in code, and a quiz link is not one.
    XCTAssertNil(
      DocumentLink.checkinCode("https://lms-tms.tertiaryinfotech.com/quiz/\(course)/quiz-17"))
  }

  func testQuizScoring() {
    let quiz = Sample.quiz(link: QuizLink(courseID: "c", quizID: "q"))
    XCTAssertEqual(quiz.questions.count, 3)
    XCTAssertTrue(
      quiz.questions.allSatisfy { q in q.correctIndex.map(q.options.indices.contains) == true })
    let all = quiz.score(answers: ["q1": 1, "q2": 0, "q3": 2])
    XCTAssertEqual([all.score, all.total, all.percent], [3, 3, 100])
    XCTAssertTrue(all.breakdown.allSatisfy(\.correct))
    // One wrong, one unanswered.
    let some = quiz.score(answers: ["q1": 1, "q2": 3])
    XCTAssertEqual([some.score, some.total, some.percent], [1, 3, 33])
    XCTAssertEqual(some.breakdown.map(\.correct), [true, false, false])
    XCTAssertEqual(some.breakdown.map(\.selectedIndex), [1, 3, nil])
    XCTAssertEqual(quiz.score(answers: [:]).score, 0)
    XCTAssertEqual(QuizResult.percent(score: 0, total: 0), 0)
    XCTAssertEqual(QuizResult.percent(score: 2, total: 3), 67)
  }

  func testQuizResultReviewMapsServerMarking() throws {
    let reply = try fixture("quiz", as: QuizReply.self)
    XCTAssertEqual(reply.quiz.title, "Module 1 quiz")
    XCTAssertEqual(reply.quiz.courseCode, "APPTEST")
    XCTAssertEqual(reply.quiz.questions.map(\.id), ["q-1", "2", "q-3"])
    XCTAssertEqual(reply.previous?.score, 1)
    XCTAssertEqual(reply.previous?.percent, 33)
    XCTAssertEqual(reply.previous?.completedLabel, "20 Nov 2026, 14:05")
    XCTAssertNil(try fixture("quiz-first-attempt", as: QuizReply.self).previous)

    let result = try fixture("quiz-result", as: QuizResult.self)
    XCTAssertEqual([result.score, result.total, result.percent], [2, 3, 67])
    XCTAssertEqual(result.attemptId, "812")
    let review = result.review(for: reply.quiz, answers: ["q-1": 0, "2": 2, "q-3": 1])
    XCTAssertEqual(review.map(\.number), [1, 2, 3])
    XCTAssertEqual(review.map(\.correct), [true, false, true])
    XCTAssertEqual(review.map(\.selectedIndex), [0, 2, 1])
    // The server's answer key wins over the one sent with the questions.
    XCTAssertEqual(review.map(\.correctIndex), [0, 1, 1])
    XCTAssertEqual(review[1].options.count, 4)

    // A question the server did not mark falls back to the learner's answer and the quiz key.
    let partial = QuizResult(
      attemptId: "1", completedAt: nil, score: 1, total: 3,
      breakdown: [QuizResult.Item(questionId: "q-1", correct: true, correctIndex: 0, selectedIndex: 0)])
    let fallback = partial.review(for: reply.quiz, answers: ["q-1": 0, "2": 1])
    XCTAssertEqual(fallback.map(\.correct), [true, true, false])
    XCTAssertEqual(fallback.map(\.selectedIndex), [0, 1, nil])
  }

  /// Four roles in switcher order; Developer and Admin are back-office views with no class
  /// data, and a sample (demo) session never offers the owner's role switch.
  @MainActor func testRoleNamesAndStaffViews() async {
    XCTAssertEqual(Store.knownRoles, ["learner", "trainer", "developer", "admin"])
    XCTAssertEqual(
      Store.knownRoles.map(Store.roleName), ["Learner", "Trainer", "Developer", "Admin"])
    let store = Store()
    store.openDemo("admin")
    XCTAssertTrue(store.isStaffView)
    XCTAssertTrue(store.dashboard.courses.isEmpty)
    XCTAssertFalse(store.canSwitchRole)
    await store.refresh()
    XCTAssertTrue(store.dashboard.sessions.isEmpty)
    store.openDemo("trainer")
    XCTAssertFalse(store.isStaffView)
    XCTAssertFalse(store.dashboard.courses.isEmpty)
    store.clear()
  }

  /// One email that is both a learner and a trainer switches between the two, and each role
  /// loads its own classes. A role the account does not hold is never offered or applied.
  @MainActor func testMultiRoleAccountSwitchesRoles() async {
    let store = Store()
    store.openDemo("trainer")
    XCTAssertEqual(store.availableRoles, ["learner", "trainer"])
    XCTAssertTrue(store.canSwitchRole)
    store.selectedTab = Store.accountTab
    await store.setViewRole("learner")
    XCTAssertEqual(store.role, "learner")
    XCTAssertEqual(store.selectedTab, 0)
    XCTAssertEqual(
      store.dashboard.courses.map(\.id), Sample.data(role: "learner").courses.map(\.id))
    await store.setViewRole("developer")
    XCTAssertEqual(store.role, "learner")
    await store.setViewRole("trainer")
    XCTAssertEqual(store.role, "trainer")
    XCTAssertEqual(
      store.dashboard.courses.map(\.id), Sample.data(role: "trainer").courses.map(\.id))
    store.clear()
    XCTAssertNil(UserDefaults.standard.string(forKey: "viewRole"))
  }

  @MainActor func testQuizLinkWaitsForSignInAndSampleQuizScores() async throws {
    let store = Store()
    XCTAssertFalse(store.handle(url: URL(string: "https://lms-tms.tertiaryinfotech.com/mobile/privacy.html")!))
    XCTAssertNil(store.pendingQuiz)
    let url = URL(string: "https://lms-tms.tertiaryinfotech.com/quiz/3f2a1b4c-5d6e-4f70-8a9b-0c1d2e3f4a5b/quiz-17")!
    XCTAssertTrue(store.handle(url: url))
    // Signed out: the quiz is kept for after sign-in.
    XCTAssertNil(store.user)
    let link = try XCTUnwrap(store.pendingQuiz)
    store.openDemo("learner")
    XCTAssertEqual(store.pendingQuiz, link)
    let first = try await store.quiz(link)
    XCTAssertNil(first.previous)
    let result = try await store.submit(quiz: first.quiz, link: link, answers: ["q1": 1, "q2": 1, "q3": 2])
    XCTAssertEqual([result.score, result.total], [2, 3])
    let again = try await store.quiz(link)
    XCTAssertEqual(again.previous?.score, 2)
    XCTAssertEqual(again.previous?.total, 3)
    store.clear()
  }

  /// The live path, against a stubbed portal: the requests the app sends for a quiz link and
  /// what it makes of the server's replies (shapes taken from the two /api/courses routes).
  @MainActor func testQuizRequestsMatchThePortalContract() async throws {
    URLProtocol.registerClass(PortalStub.self)
    defer {
      URLProtocol.unregisterClass(PortalStub.self)
      PortalStub.seen = []
      Keychain.clear()
    }
    try Keychain.save("lms_test_token")
    let store = Store()
    store.user = User(
      id: "user-1", email: "learner@example.test", fullName: "Test Learner", role: "learner",
      roles: ["learner"])
    let course = "31000000-0000-0000-0000-000000000001"
    let link = try XCTUnwrap(
      QuizLink.parse("https://lms-tms.tertiaryinfotech.com/quiz/\(course)/quiz-17"))

    let reply = try await store.quiz(link)
    XCTAssertEqual(reply.quiz.questions.count, 3)
    XCTAssertEqual(reply.previous?.score, 1)
    let get = try XCTUnwrap(PortalStub.seen.last)
    XCTAssertEqual(get.method, "GET")
    XCTAssertEqual(
      get.url, "https://lms-tms.tertiaryinfotech.com/api/courses/quiz?courseId=\(course)&quizId=quiz-17")
    XCTAssertEqual(get.authorization, "Bearer lms_test_token")

    let answers = ["q-1": 0, "2": 2, "q-3": 1]
    let result = try await store.submit(quiz: reply.quiz, link: link, answers: answers)
    XCTAssertEqual([result.score, result.total], [2, 3])
    XCTAssertEqual(result.review(for: reply.quiz, answers: answers).map(\.correct), [true, false, true])
    let post = try XCTUnwrap(PortalStub.seen.last)
    XCTAssertEqual(post.method, "POST")
    XCTAssertEqual(post.url, "https://lms-tms.tertiaryinfotech.com/api/courses/submit-quiz")
    XCTAssertEqual(post.authorization, "Bearer lms_test_token")
    XCTAssertEqual(post.body["userId"] as? String, "user-1")
    XCTAssertEqual(post.body["courseId"] as? String, course)
    XCTAssertEqual(post.body["quizId"] as? String, "quiz-17")
    XCTAssertEqual(post.body["answers"] as? [String: Int], answers)

    // A quiz the trainer removed: the server's 404 message reaches the screen.
    let gone = QuizLink(courseID: course, quizID: "removed")
    do {
      _ = try await store.quiz(gone)
      XCTFail("Expected the removed quiz to fail")
    } catch { XCTAssertEqual(error.localizedDescription, "Quiz not found") }
  }
  func testWhatsAppTrainerMessageAndLink() {
    let item = StaffClass(
      id: "x", runCode: "1361797", title: "Agentic AI Applications with Claude Code", code: "TGS-2025052468",
      startDate: "2026-11-21", endDate: "2026-11-22", format: "Hybrid", classStatus: "Confirmed",
      hasMeetingLink: true, trainers: [], learners: 3, venue: "12 Woodland Square, Singapore 737715")
    let t = StaffTrainer(name: "Alex Tan", email: nil, phone: "+6591234567")
    let text = TrainerWhatsAppPicker.message(for: t, item: item)
    XCTAssertTrue(text.hasPrefix("Hi Alex,"))
    XCTAssertTrue(text.contains("Course Run: 1361797"))
    XCTAssertTrue(text.contains("Venue: 12 Woodland Square"))
    let url = TrainerWhatsAppPicker.whatsAppURL(phone: t.phone!, text: text)!
    XCTAssertEqual(url.host, "wa.me")
    XCTAssertEqual(url.path, "/6591234567")
    XCTAssertTrue(url.absoluteString.contains("text=Hi%20Alex"))
    XCTAssertNil(TrainerWhatsAppPicker.whatsAppURL(phone: "", text: "x"))
  }
}

/// Answers the two quiz routes from the recorded fixtures and records what was asked.
final class PortalStub: URLProtocol {
  struct Seen {
    let method: String
    let url: String
    let authorization: String?
    let body: [String: Any]
  }
  static var seen: [Seen] = []
  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.path.hasPrefix("/api/courses/") == true
  }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    var data = request.httpBody ?? Data()
    if let stream = request.httpBodyStream {
      stream.open()
      var buffer = [UInt8](repeating: 0, count: 4096)
      while stream.hasBytesAvailable {
        let read = stream.read(&buffer, maxLength: buffer.count)
        if read <= 0 { break }
        data.append(buffer, count: read)
      }
      stream.close()
    }
    let url = request.url!
    Self.seen.append(
      Seen(
        method: request.httpMethod ?? "GET", url: url.absoluteString,
        authorization: request.value(forHTTPHeaderField: "Authorization"),
        body: ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any]) ?? [:]))
    let removed = url.query?.contains("quizId=removed") == true
    let name = url.path.hasSuffix("submit-quiz") ? "quiz-result" : "quiz"
    let payload =
      removed
      ? Data(#"{"success":false,"error":"Quiz not found"}"#.utf8)
      : try! Data(
        contentsOf: Bundle(for: PortalStub.self).url(forResource: name, withExtension: "json")!)
    let response = HTTPURLResponse(
      url: url, statusCode: removed ? 404 : 200, httpVersion: "HTTP/1.1",
      headerFields: ["Content-Type": "application/json"])!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: payload)
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}

}
