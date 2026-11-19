import Foundation
import SwiftUI

struct User: Codable {
  let id: String
  let email: String
  let fullName: String
  let role: String
  let roles: [String]
}
struct LoginReply: Decodable { let data: LoginData }
struct LoginData: Decodable {
  let user: User
  let token: String
}
struct Dashboard: Codable {
  var courses: [Course]
  var sessions: [ClassSession]
}
struct Course: Codable, Identifiable {
  let id: String
  let title: String
  let code: String?
  let startDate: String?
  let endDate: String?
  let format: String?
  let meetingURL: String?
  let venue: String?
  let slidesURL: String?
  let guideURL: String?
  let activitiesURL: String?
  let trainerSlidesURL: String?

  func materials(for role: String) -> [CourseMaterial] {
    var items = [
      CourseMaterial(
        id: "slides", title: "Learner slides", symbol: "rectangle.on.rectangle", rawURL: slidesURL),
      CourseMaterial(
        id: "guide", title: "Learner Guide", symbol: "book.closed.fill", rawURL: guideURL),
      CourseMaterial(
        id: "activities", title: "Labs & activities", symbol: "laptopcomputer",
        rawURL: activitiesURL),
    ]
    if role == "trainer" {
      items.insert(
        CourseMaterial(
          id: "trainer-slides", title: "Trainer slides", symbol: "person.crop.rectangle",
          rawURL: trainerSlidesURL),
        at: 0)
    }
    return items
  }
}
struct CourseMaterial: Identifiable {
  let id: String
  let title: String
  let symbol: String
  let rawURL: String?
  var isPublished: Bool { rawURL?.isEmpty == false }
}
struct ClassSession: Codable, Identifiable {
  let id: String
  let courseID: String
  let title: String
  let startDate: String?
  let endDate: String?
  let startTime: String?
  let endTime: String?
  let subtitle: String
  let format: String?
  let meetingURL: String?
  let venue: String?
  var dateLabel: String {
    guard let start else { return "To be confirmed" }
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_SG")
    f.timeZone = TimeZone(identifier: "Asia/Singapore")
    f.dateFormat = "d MMM yyyy"
    return f.string(from: start)
  }
  var timeLabel: String { Self.clockLabel(startTime) }
  var endTimeLabel: String { Self.clockLabel(endTime) }
  static func clockLabel(_ raw: String?) -> String {
    guard let raw else { return "TBC" }
    let digits = raw.filter(\.isNumber)
    guard digits.count >= 4 else { return "TBC" }
    return "\(digits.prefix(2)):\(digits.dropFirst(2).prefix(2))"
  }
  var start: Date? { Self.date(startDate, startTime) }
  var end: Date? { Self.date(endDate ?? startDate, endTime) }
  static func date(_ day: String?, _ time: String?) -> Date? {
    guard let day else { return nil }
    let digits = day.filter(\.isNumber)
    guard digits.count >= 8 else { return nil }
    let date =
      day.contains("-")
      ? String(day.prefix(10))
      : "\(digits.prefix(4))-\(digits.dropFirst(4).prefix(2))-\(digits.dropFirst(6).prefix(2))"
    let td = (time ?? "09:00").filter(\.isNumber)
    let clock = td.count >= 4 ? "\(td.prefix(2)):\(td.dropFirst(2).prefix(2))" : "09:00"
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "Asia/Singapore")
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    return formatter.date(from: date + " " + clock)
  }
}
enum Theme {
  /// Premium blue. Lighter in dark mode so text and icons keep their contrast.
  static let accent = Color(
    uiColor: UIColor { traits in
      traits.userInterfaceStyle == .dark
        ? UIColor(red: 0.54, green: 0.71, blue: 0.97, alpha: 1)
        : UIColor(red: 0.04, green: 0.24, blue: 0.56, alpha: 1)
    })
  static let hero = Color(red: 0.05, green: 0.30, blue: 0.68)
  static let brandBlue = Color(red: 0.04, green: 0.24, blue: 0.56)
  static let brandNavy = Color(red: 0.02, green: 0.11, blue: 0.28)
  static let name = "TIA TMS"
}

// MARK: - Class detail, profile and feedback (GET /api/mobile/class, /profile, /feedback)

struct Reply<T: Decodable>: Decodable { let data: T }

struct Profile: Codable, Equatable {
  var id: String
  var email: String
  var fullName: String
  var theme: String
  var phone: String?
  var company: String?
  var employmentStatus: String?
  var linkedinURL: String?
  var academy: String?
}

struct ClassMaterial: Codable, Identifiable, Hashable {
  let id: String
  let title: String
  let url: String
  var symbol: String {
    switch id {
    case "trainer-slides": return "person.crop.rectangle"
    case "slides": return "rectangle.on.rectangle"
    case "guide": return "book.closed.fill"
    case "activities": return "laptopcomputer"
    case "lesson-plan": return "list.bullet.clipboard"
    case "facilitator-guide": return "person.2.badge.gearshape"
    case "assessment-plan": return "checklist"
    default: return "doc"
    }
  }
}

struct DetailSession: Codable, Identifiable {
  let id: String
  let label: String
  let date: String?
  let startTime: String?
  let endTime: String?
  var attendance: String?
  var presentCount: Int?
}

struct Submission: Codable, Identifiable {
  let id: String
  let fileName: String
  let fileURL: String
  var signed: Bool?
}

struct Assessment: Codable, Identifiable {
  var id: String { type }
  let type: String
  let label: String
  let questionURL: String?
  let published: Bool
  var submissions: [Submission]
}

struct FeedbackState: Codable {
  var enabled: Bool
  var externalURL: String?
  var submitted: Bool
}

struct RosterLearner: Codable, Identifiable {
  var id: String { enrolmentId }
  let enrolmentId: String
  let name: String
  var status: String?
  var traqomCompleted: Bool?
  var submissions: Int?
  var isCompetent: Bool? {
    guard let status else { return nil }
    if ["competent", "passed"].contains(status.lowercased()) { return true }
    return status.lowercased().hasPrefix("not") ? false : nil
  }
}

struct ClassDetail: Codable {
  let id: String
  var runCode: String?
  let title: String
  var code: String?
  var startDate: String?
  var endDate: String?
  var format: String?
  var classStatus: String?
  var venue: String?
  var meetingURL: String?
  var materials: [ClassMaterial]
  var sessions: [DetailSession]
  var ssgAttendanceURL: String?
  var assessments: [Assessment]
  var traqomURL: String?
  var assessmentStatus: String?
  var feedback: FeedbackState?
  var roster: [RosterLearner]?
  var feedbackCount: Int?
}

struct AttendanceLearner: Codable, Identifiable {
  var id: String { enrolmentId }
  let enrolmentId: String
  let name: String
  var isPresent: Bool?
  var reason: String?
}

struct AttendanceSheet: Codable {
  var checkinURL: String?
  var learners: [AttendanceLearner]
}

struct FeedbackField: Codable, Identifiable {
  let id: String
  let label: String
  let type: String
  var required: Bool?
  var options: [String]?
  var autofill: String?
}

struct FeedbackSection: Codable, Identifiable {
  let id: String
  let title: String
  let fields: [FeedbackField]
}

struct FeedbackForm: Codable {
  let title: String
  let sections: [FeedbackSection]
  var submitted: Bool
  var autofill: [String: String?]?
}

/// Turns a courseware link into one that downloads a PDF when the host can export one.
/// Returns nil when the link should simply open in the browser (folders, web pages).
enum DocumentLink {
  static func pdfURL(for raw: String) -> URL? {
    guard let url = URL(string: raw), url.scheme == "https", let host = url.host?.lowercased()
    else { return nil }
    let parts = url.pathComponents
    func id(after marker: String) -> String? {
      guard let i = parts.firstIndex(of: marker), parts.count > i + 1 else { return nil }
      let value = parts[i + 1]
      return value.range(of: "^[A-Za-z0-9_-]{10,}$", options: .regularExpression) != nil
        ? value : nil
    }
    if host == "drive.google.com", parts.contains("file"), let file = id(after: "d") {
      return URL(string: "https://drive.google.com/uc?export=download&id=\(file)")
    }
    if host == "docs.google.com", let doc = id(after: "d") {
      if parts.contains("presentation") {
        return URL(string: "https://docs.google.com/presentation/d/\(doc)/export/pdf")
      }
      if parts.contains("document") {
        return URL(string: "https://docs.google.com/document/d/\(doc)/export?format=pdf")
      }
      return nil
    }
    return url.pathExtension.lowercased() == "pdf" ? url : nil
  }

  /// The 32-character token inside a class check-in QR code, or nil for any other code.
  static func checkinCode(_ scanned: String) -> String? {
    let text = scanned.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard let range = text.range(of: "[0-9a-f]{32}/?$", options: .regularExpression) else {
      return nil
    }
    let token = text[range].replacingOccurrences(of: "/", with: "")
    return text == token || text.contains("/checkin/") ? token : nil
  }
}
