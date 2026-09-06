import Foundation

enum Sample {
  static func data(role: String) -> Dashboard {
    let date = DateFormatter()
    date.dateFormat = "yyyy-MM-dd"
    date.timeZone = TimeZone(identifier: "Asia/Singapore")
    let day = date.string(from: Date().addingTimeInterval(3 * 86400))
    let day2 = date.string(from: Date().addingTimeInterval(5 * 86400))
    let courses = [
      Course(
        id: "sample-ai", title: "Build practical AI workflows", code: "SAMPLE · AI FOUNDATIONS",
        startDate: day, endDate: day2, format: "Classroom", meetingURL: nil,
        venue: "Training room 1, Singapore",
        slidesURL: "https://lms-tms.tertiaryinfotech.com/mobile/sample-slides.html",
        guideURL: "https://lms-tms.tertiaryinfotech.com/mobile/sample-guide.html",
        activitiesURL: "https://lms-tms.tertiaryinfotech.com/mobile/sample-activity.html",
        trainerSlidesURL: "https://lms-tms.tertiaryinfotech.com/mobile/sample-trainer.html"),
      Course(
        id: "sample-data", title: "Turn data into decisions", code: "SAMPLE · DATA SKILLS",
        startDate: day2, endDate: day2, format: "Classroom", meetingURL: nil,
        venue: "Training room 2, Singapore",
        slidesURL: "https://lms-tms.tertiaryinfotech.com/mobile/sample-slides.html",
        guideURL: "https://lms-tms.tertiaryinfotech.com/mobile/sample-guide.html",
        activitiesURL: "https://lms-tms.tertiaryinfotech.com/mobile/sample-activity.html",
        trainerSlidesURL: nil),
    ]
    let sessions = [
      ClassSession(
        id: "session-ai", courseID: "sample-ai", title: courses[0].title, startDate: day,
        endDate: day, startTime: "09:00", endTime: "17:00",
        subtitle: role == "trainer"
          ? "Session 1 · Facilitate the workshop" : "Session 1 · From idea to workflow",
        format: "Classroom", meetingURL: nil, venue: "Training room 1, Singapore"),
      ClassSession(
        id: "session-ai-2", courseID: "sample-ai", title: courses[0].title, startDate: day2,
        endDate: day2, startTime: "09:00", endTime: "12:00",
        subtitle: "Session 2 · Test and improve", format: "Classroom", meetingURL: nil,
        venue: "Training room 1, Singapore"),
      ClassSession(
        id: "session-data", courseID: "sample-data", title: courses[1].title, startDate: day2,
        endDate: day2, startTime: "14:00", endTime: "17:00",
        subtitle: "Session 1 · Explore your dataset", format: "Classroom", meetingURL: nil,
        venue: "Training room 2, Singapore"),
    ]
    return Dashboard(courses: courses, sessions: sessions)
  }
}
