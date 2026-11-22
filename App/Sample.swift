import PDFKit
import UIKit

enum Sample {
  static func data(role: String) -> Dashboard {
    let date = DateFormatter()
    date.dateFormat = "yyyy-MM-dd"
    date.timeZone = TimeZone(identifier: "Asia/Singapore")
    let day = date.string(from: Date().addingTimeInterval(3 * 86400))
    let day2 = date.string(from: Date().addingTimeInterval(5 * 86400))
    let courses = [
      Course(
        id: "sample-ai", title: "Responsible Generative AI Basics", code: "TGS-2025060472 · SAMPLE",
        startDate: day, endDate: day2, format: "Classroom", meetingURL: nil,
        venue: "Training room 1, Singapore",
        slidesURL: "https://lms-tms.tertiaryinfotech.com/mobile/sample-slides.html",
        guideURL: "https://lms-tms.tertiaryinfotech.com/mobile/sample-guide.html",
        activitiesURL: "https://lms-tms.tertiaryinfotech.com/mobile/sample-activity.html",
        trainerSlidesURL: "https://lms-tms.tertiaryinfotech.com/mobile/sample-trainer.html"),
      Course(
        id: "sample-data", title: "Fundamentals of AI Ethics and Responsible AI",
        code: "TGS-2023021102 · SAMPLE",
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
          ? "Session 1 · Facilitate the workshop" : "Session 1 · Responsible AI foundations",
        format: "Classroom", meetingURL: nil, venue: "Training room 1, Singapore"),
      ClassSession(
        id: "session-ai-2", courseID: "sample-ai", title: courses[0].title, startDate: day2,
        endDate: day2, startTime: "09:00", endTime: "12:00",
        subtitle: "Session 2 · Governance in practice", format: "Classroom", meetingURL: nil,
        venue: "Training room 1, Singapore"),
      ClassSession(
        id: "session-data", courseID: "sample-data", title: courses[1].title, startDate: day2,
        endDate: day2, startTime: "14:00", endTime: "17:00",
        subtitle: "Session 1 · Human oversight and accountability", format: "Classroom",
        meetingURL: nil,
        venue: "Training room 2, Singapore"),
    ]
    return Dashboard(courses: courses, sessions: sessions)
  }

  static func profile(role: String, theme: String) -> Profile {
    Profile(
      id: "demo", email: "sample@example.com",
      fullName: role == "trainer" ? "Alex Tan" : "Jamie Lim", theme: theme,
      phone: "+65 6000 0000", company: role == "trainer" ? nil : "Sample Company Pte Ltd",
      employmentStatus: role == "trainer" ? nil : "Employed", linkedinURL: nil,
      academy: "Tertiary Infotech Academy")
  }

  /// Sample payouts for the trainer demo. Nothing here is a real payment.
  static func payouts() -> [Payout] {
    let date = DateFormatter()
    date.dateFormat = "yyyy-MM-dd"
    date.timeZone = TimeZone(identifier: "Asia/Singapore")
    func day(_ back: Double) -> String { date.string(from: Date().addingTimeInterval(-back * 86400)) }
    return [
      Payout(
        id: "sample-1", title: "Responsible Generative AI Basics (sample)",
        courseCode: "TGS-2025060472", learners: 12, amount: 1200, paymentDate: day(9),
        startDate: day(24), endDate: day(23)),
      Payout(
        id: "sample-2", title: "Fundamentals of AI Ethics and Responsible AI (sample)",
        courseCode: "TGS-2023021102", learners: 8, amount: 850.5, paymentDate: day(40),
        startDate: day(55), endDate: day(55)),
    ]
  }

  static func detail(id: String, role: String, dashboard: Dashboard) -> ClassDetail {
    let course = dashboard.courses.first { $0.id == id }
    let trainer = role == "trainer"
    let page = "https://lms-tms.tertiaryinfotech.com/mobile/"
    var materials = [
      ClassMaterial(id: "slides", title: "Learner slides", url: page + "sample-slides.html"),
      ClassMaterial(id: "guide", title: "Learner Guide", url: page + "sample-guide.html"),
      ClassMaterial(id: "activities", title: "Labs & activities", url: page + "sample-activity.html"),
    ]
    if trainer {
      materials.insert(
        ClassMaterial(id: "trainer-slides", title: "Trainer slides", url: page + "sample-trainer.html"),
        at: 0)
      materials.append(
        ClassMaterial(id: "lesson-plan", title: "Lesson Plan", url: page + "sample-guide.html"))
    }
    let sessions = dashboard.sessions.filter { $0.courseID == id }.enumerated().map { index, s in
      DetailSession(
        id: s.id, label: "Day \(index + 1) · \(s.dateLabel)", date: s.startDate,
        startTime: s.startTime, endTime: s.endTime, attendance: nil,
        presentCount: trainer ? 0 : nil)
    }
    return ClassDetail(
      id: id, runCode: "SAMPLE-RUN", title: course?.title ?? "Sample course", code: course?.code,
      startDate: course?.startDate, endDate: course?.endDate, format: course?.format,
      classStatus: "Confirmed", venue: course?.venue, meetingURL: nil, materials: materials,
      sessions: sessions,
      ssgAttendanceURL: page + "support.html",
      assessments: [
        Assessment(
          type: "writtenAssessment", label: "Written Assessment",
          questionURL: page + "sample-activity.html", published: true, submissions: []),
        Assessment(
          type: "practicalExam", label: "Practical Performance", questionURL: nil,
          published: trainer ? false : true, submissions: []),
      ],
      traqomURL: page + "support.html",
      assessmentStatus: nil,
      feedback: trainer ? nil : FeedbackState(enabled: true, externalURL: nil, submitted: false),
      roster: trainer
        ? [
          RosterLearner(enrolmentId: "sample-1", name: "Jamie Lim (sample)", status: nil, traqomCompleted: false, submissions: 1),
          RosterLearner(enrolmentId: "sample-2", name: "Priya Nair (sample)", status: "Competent", traqomCompleted: true, submissions: 2),
          RosterLearner(enrolmentId: "sample-3", name: "Wei Ming (sample)", status: nil, traqomCompleted: false, submissions: 0),
        ] : nil,
      feedbackCount: trainer ? 2 : nil)
  }

  static func sheet(sessionID: String) -> AttendanceSheet {
    AttendanceSheet(
      checkinURL: "https://lms-tms.tertiaryinfotech.com/checkin/" + String(repeating: "a", count: 32),
      learners: [
        AttendanceLearner(enrolmentId: "sample-1", name: "Jamie Lim (sample)", isPresent: true, reason: ""),
        AttendanceLearner(enrolmentId: "sample-2", name: "Priya Nair (sample)", isPresent: nil, reason: ""),
        AttendanceLearner(enrolmentId: "sample-3", name: "Wei Ming (sample)", isPresent: nil, reason: ""),
      ])
  }

  static func feedbackForm(submitted: Bool) -> FeedbackForm {
    FeedbackForm(
      title: "Course Feedback (sample)",
      sections: [
        FeedbackSection(
          id: "course", title: "Your course",
          fields: [
            FeedbackField(id: "course_title", label: "Course", type: "text", required: false, options: nil, autofill: "course_title")
          ]),
        FeedbackSection(
          id: "ratings", title: "Your ratings",
          fields: [
            FeedbackField(id: "trainer", label: "The trainer explained clearly", type: "rating1to5", required: true, options: nil, autofill: nil),
            FeedbackField(id: "materials", label: "The courseware was useful", type: "rating1to5", required: true, options: nil, autofill: nil),
            FeedbackField(id: "comments", label: "Anything else you would like to tell us", type: "textarea", required: false, options: nil, autofill: nil),
          ]),
      ], submitted: submitted, autofill: ["course_title": "Responsible Generative AI Basics"])
  }

  /// The quiz shown for any quiz link in sample mode. Nothing is sent to the academy.
  static func quiz(link: QuizLink) -> Quiz {
    Quiz(
      id: link.quizID, courseId: link.courseID, title: "Responsible AI check-in quiz",
      courseTitle: "Responsible Generative AI Basics", courseCode: "TGS-2025060472 · SAMPLE",
      questions: [
        QuizQuestion(
          id: "q1",
          question: "Which practice best supports the responsible use of generative AI at work?",
          options: [
            "Pasting confidential client data into any public chatbot",
            "Checking AI output for accuracy before you rely on it",
            "Presenting AI-written text as verified fact",
            "Turning off human review to save time",
          ], correctIndex: 1),
        QuizQuestion(
          id: "q2", question: "What is an AI \"hallucination\"?",
          options: [
            "A confident answer that is false or made up",
            "A slow response from the model",
            "An image created from a text prompt",
            "A model that refuses to answer",
          ], correctIndex: 0),
        QuizQuestion(
          id: "q3",
          question: "Who stays accountable for a decision made with the help of an AI tool?",
          options: [
            "The AI vendor only",
            "Nobody, because the tool decided",
            "The people and organisation using the tool",
            "The person who wrote the prompt template",
          ], correctIndex: 2),
      ])
  }

  /// A small on-device PDF so the in-app reader can be explored without an account.
  static func pdf(title: String) -> PDFDocument? {
    let page = CGRect(x: 0, y: 0, width: 595, height: 842)
    let data = UIGraphicsPDFRenderer(bounds: page).pdfData { context in
      for number in 1...3 {
        context.beginPage()
        UIColor(red: 0.04, green: 0.24, blue: 0.56, alpha: 1).setFill()
        context.fill(CGRect(x: 0, y: 0, width: 595, height: 110))
        ("Tertiary Infotech Academy" as NSString).draw(
          at: CGPoint(x: 40, y: 30),
          withAttributes: [.font: UIFont.boldSystemFont(ofSize: 22), .foregroundColor: UIColor.white])
        ("SAMPLE · \(title)" as NSString).draw(
          at: CGPoint(x: 40, y: 66),
          withAttributes: [.font: UIFont.systemFont(ofSize: 14), .foregroundColor: UIColor.white])
        ("Page \(number) of 3" as NSString).draw(
          at: CGPoint(x: 40, y: 150),
          withAttributes: [.font: UIFont.boldSystemFont(ofSize: 28), .foregroundColor: UIColor.black])
        let body =
          "This sample document shows how courseware opens inside TIA TMS. Sign in with your academy account to read the slides, Learner Guide and activities published for your own classes. Pinch to zoom and scroll to turn pages."
        (body as NSString).draw(
          in: CGRect(x: 40, y: 200, width: 515, height: 300),
          withAttributes: [.font: UIFont.systemFont(ofSize: 16), .foregroundColor: UIColor.darkGray])
      }
    }
    return PDFDocument(data: data)
  }
}
