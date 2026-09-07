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
  static let accent = Color(
    uiColor: UIColor { traits in
      traits.userInterfaceStyle == .dark
        ? UIColor(red: 0.25, green: 0.83, blue: 0.80, alpha: 1)
        : UIColor(red: 0.00, green: 0.40, blue: 0.43, alpha: 1)
    })
  static let hero = Color(red: 0.00, green: 0.42, blue: 0.45)
  static let name = "Tertiary LMS"
}
