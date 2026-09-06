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
}
