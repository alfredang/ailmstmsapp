import AVFoundation
import CoreImage.CIFilterBuiltins
import PDFKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

// Class detail and everything a learner or trainer does inside a class:
// courseware (PDF reader), attendance, assessments, course feedback and TRAQOM.

// MARK: - Class data (live or sample)

extension Store {
  func classDetail(_ id: String) async throws -> ClassDetail {
    if demo {
      if let saved = demoDetails[id] { return saved }
      let made = Sample.detail(id: id, role: role, dashboard: dashboard)
      demoDetails[id] = made
      return made
    }
    let reply: Reply<ClassDetail> = try await API.shared.request(
      "mobile/class", query: ["id": id, "role": role])
    return reply.data
  }

  func attendanceSheet(sessionID: String, courseID: String) async throws -> AttendanceSheet {
    if demo {
      return demoSheets[sessionID] ?? Sample.sheet(sessionID: sessionID)
    }
    let reply: Reply<AttendanceSheet> = try await API.shared.request(
      "mobile/attendance", query: ["sessionId": sessionID])
    return reply.data
  }

  func saveAttendance(sessionID: String, sheet: AttendanceSheet) async throws -> AttendanceSheet {
    if demo {
      demoSheets[sessionID] = sheet
      return sheet
    }
    let records: [[String: Any]] = sheet.learners.compactMap { learner in
      guard let present = learner.isPresent else { return nil }
      return [
        "enrolmentId": learner.enrolmentId, "isPresent": present, "reason": learner.reason ?? "",
      ]
    }
    let reply: Reply<AttendanceSheet> = try await API.shared.request(
      "mobile/attendance", method: "POST",
      body: ["action": "mark", "sessionId": sessionID, "records": records])
    var saved = reply.data
    saved.checkinURL = sheet.checkinURL
    return saved
  }

  /// Checks the learner in with a scanned class QR code. Returns the message to show.
  func checkIn(code: String, courseID: String) async throws -> String {
    guard DocumentLink.checkinCode(code) != nil else {
      throw APIError(
        message: "This is not a class check-in code. Scan the QR code your trainer is showing.")
    }
    if demo {
      if var detail = demoDetails[courseID], !detail.sessions.isEmpty {
        detail.sessions[0].attendance = "present"
        demoDetails[courseID] = detail
      }
      return "You are checked in. (Sample)"
    }
    struct Result: Decodable { let message: String }
    let result: Result = try await API.shared.request(
      "mobile/attendance", method: "POST", body: ["action": "checkin", "code": code])
    return result.message
  }

  func submitAssessment(detail: ClassDetail, type: String, file: URL) async throws {
    let name = file.lastPathComponent
    if demo {
      if var copy = demoDetails[detail.id],
        let index = copy.assessments.firstIndex(where: { $0.type == type })
      {
        copy.assessments[index].submissions.insert(
          Submission(
            id: UUID().uuidString, fileName: name,
            fileURL: "https://lms-tms.tertiaryinfotech.com/mobile/sample-activity.html",
            signed: false), at: 0)
        demoDetails[detail.id] = copy
      }
      return
    }
    let access = file.startAccessingSecurityScopedResource()
    defer { if access { file.stopAccessingSecurityScopedResource() } }
    let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    guard size <= 100 * 1024 * 1024 else {
      throw APIError(message: "This file is larger than 100 MB. Please choose a smaller file.")
    }
    let uploaded = try await API.shared.upload(
      file: file, studentName: user?.fullName ?? "Learner", runCode: detail.runCode ?? "")
    var body: [String: Any] = [
      "action": "submit", "runId": detail.id, "type": type, "fileName": name,
      "fileURL": uploaded.url,
    ]
    if let folder = uploaded.folder { body["folderId"] = folder }
    let _: EmptyReply = try await API.shared.request(
      "mobile/assessments", method: "POST", body: body)
  }

  func deleteSubmission(_ id: String, courseID: String) async throws {
    if demo {
      if var copy = demoDetails[courseID] {
        for index in copy.assessments.indices {
          copy.assessments[index].submissions.removeAll { $0.id == id }
        }
        demoDetails[courseID] = copy
      }
      return
    }
    let _: EmptyReply = try await API.shared.request(
      "mobile/assessments", method: "DELETE", body: ["submissionId": id])
  }

  func grade(enrolmentID: String, competent: Bool, courseID: String) async throws {
    if demo {
      if var copy = demoDetails[courseID],
        let index = copy.roster?.firstIndex(where: { $0.enrolmentId == enrolmentID })
      {
        copy.roster?[index].status = competent ? "Competent" : "Not Yet Competent"
        demoDetails[courseID] = copy
      }
      return
    }
    let _: EmptyReply = try await API.shared.request(
      "mobile/assessments", method: "POST",
      body: ["action": "grade", "enrolmentIds": [enrolmentID], "isCompetent": competent])
  }

  func feedbackForm(courseID: String) async throws -> FeedbackForm {
    if demo { return Sample.feedbackForm(submitted: demoDetails[courseID]?.feedback?.submitted ?? false) }
    let reply: Reply<FeedbackForm> = try await API.shared.request(
      "mobile/feedback", query: ["runId": courseID])
    return reply.data
  }

  func sendFeedback(courseID: String, answers: [String: Any]) async throws {
    if demo {
      demoDetails[courseID]?.feedback?.submitted = true
      return
    }
    let _: EmptyReply = try await API.shared.request(
      "mobile/feedback", method: "POST", body: ["runId": courseID, "answers": answers])
  }
}

// MARK: - Class detail

struct CourseDetail: View {
  @EnvironmentObject var store: Store
  let course: Course
  @State private var detail: ClassDetail?
  @State private var problem: String?
  @State private var notice: String?
  @State private var scanning = false
  /// Sections the user has opened. Every section starts collapsed, like the website's cards.
  @State private var open: Set<String> = []

  private var trainer: Bool { store.role == "trainer" }
  /// The Course Run ID as the website prints it ("Open E-Attendance for Course Run 1361797").
  private var runID: String { detail?.runCode ?? "" }


  // Same sections, names and order as the class page on lms-tms.tertiaryinfotech.com.
  var body: some View {
    List {
      summary
      courseDetails

      if let detail {
        eAttendance(detail)
        if trainer { swdaEnrolment(detail.swdaEnrolmentURL ?? "/enrol/\(detail.id)") }
        announcements(detail)
        courseware
        if !trainer { quizzes }
        // Course Feedback, TRAQOM and the Briefing are for learners; trainers do not fill them in.
        if !trainer {
          feedbackAndTraqom(detail)
          briefing(detail)
        }
        assessment(detail)
        summaryRecord(detail)
        if trainer {
          grading(detail)
          feedbackSummary(detail)
        }
      } else if let problem {
        courseware
        Section {
          Label(problem, systemImage: "wifi.exclamationmark").foregroundStyle(.secondary)
          Button("Try again") { Task { await load() } }
        }
      } else {
        courseware
        Section { ProgressView("Loading class details…") }
      }
    }
    .navigationTitle("Class details").navigationBarTitleDisplayMode(.inline)
    .task { await load() }
    .refreshable { await load() }
    .alert("TIA TMS", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } }))
    {
      Button("OK") { notice = nil }
    } message: {
      Text(notice ?? "")
    }
    .sheet(isPresented: $scanning) {
      QRScannerSheet { code in
        scanning = false
        // A quiz QR code scanned here opens the quiz instead of failing as a check-in code.
        if let quiz = QuizLink.parse(code) {
          store.open(quiz: quiz)
          return
        }
        Task {
          do {
            notice = try await store.checkIn(code: code, courseID: course.id)
            await load()
          } catch { notice = error.localizedDescription }
        }
      }
    }
  }

  private func load() async {
    do {
      detail = try await store.classDetail(course.id)
      problem = nil
    } catch {
      if detail == nil { problem = error.localizedDescription }
    }
  }

  private static func hrs(_ value: Double?) -> String {
    guard let value else { return "N/A" }
    let text = value.formatted(.number.precision(.fractionLength(value.rounded() == value ? 0 : 1)))
    return "\(text) \(value == 1 ? "hr" : "hrs")"
  }

  // MARK: Collapsible cards

  /// A website-style card: a tappable title row with a chevron; the rows show only when open.
  private func fold<C: View, F: View>(
    _ title: String, icon: String, @ViewBuilder _ content: () -> C,
    @ViewBuilder footer: () -> F
  ) -> some View {
    let isOpen = open.contains(title)
    return Section {
      Button {
        withAnimation(.snappy) {
          if isOpen { open.remove(title) } else { open.insert(title) }
        }
      } label: {
        HStack(spacing: 12) {
          Image(systemName: icon).font(.body.weight(.semibold)).foregroundStyle(Theme.accent)
            .frame(width: 26)
          Text(title).font(.headline).foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
          Image(systemName: "chevron.down").font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.accent).rotationEffect(.degrees(isOpen ? 180 : 0))
        }
        .padding(.vertical, 6).contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("section-\(title)")
      .accessibilityValue(isOpen ? "Expanded" : "Collapsed")
      if isOpen { content() }
    } footer: {
      if isOpen { footer() }
    }
  }

  private func fold<C: View>(_ title: String, icon: String, @ViewBuilder _ content: () -> C)
    -> some View
  {
    fold(title, icon: icon, content) { EmptyView() }
  }

  // MARK: Summary / Course Details / Class Details

  /// Non-empty text, or nil, so empty fields are left out on the phone instead of "N/A".
  private static func value(_ raw: String?) -> String? {
    guard let raw, !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
    return raw
  }
  private static func day(_ raw: String?) -> String? {
    value(raw).map { Fmt.longDate($0) }.flatMap(value)
  }

  /// Always-visible class summary at the top: what, when, where, who.
  private var summary: some View {
    let status = detail?.classStatus ?? course.classStatus
    let start = Self.day(detail?.startDate ?? course.startDate)
    let end = Self.day(detail?.endDate ?? course.endDate)
    let trainers = detail?.trainerNames ?? []
    return Section {
      VStack(alignment: .leading, spacing: 10) {
        Text(detail?.title ?? course.title).font(.title3.weight(.bold))
          .fixedSize(horizontal: false, vertical: true)
        Text(
          [Self.value(detail?.code ?? course.code), Self.value(detail?.runCode).map { "Run \($0)" }]
            .compactMap { $0 }.joined(separator: "  ·  ")
        ).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
        HStack(spacing: 8) {
          StatusChip(text: detail?.format ?? course.format ?? "Physical", color: Theme.accent)
          if let status {
            StatusChip(
              text: status,
              color: status.lowercased() == "confirmed"
                ? .green : status.lowercased() == "cancelled" ? .red : .orange)
          }
        }
        if let start {
          Label(end.map { $0 == start ? start : "\(start) – \($0)" } ?? start, systemImage: "calendar")
            .font(.subheadline)
        }
        if let venue = Self.value(detail?.venue) {
          VenueLink(address: venue)
        }
        if !trainers.isEmpty {
          Label {
            Text(trainers.count > 1 ? "Trainers: " : "Trainer: ").foregroundStyle(.secondary)
              + Text(trainers.joined(separator: ", ")).fontWeight(.semibold)
          } icon: {
            Image(systemName: "person.fill")
          }
          .font(.subheadline).accessibilityIdentifier("summary-trainer")
        }
        // Hybrid and online classes: the meeting link one tap away, not inside a folded card.
        if let link = meetingLink {
          JoinMeetingButton(raw: link, prominent: true).padding(.top, 4)
        }
      }
      .padding(.vertical, 6)
    }
  }

  private var courseDetails: some View {
    let info = detail?.courseDetails
    let fundStart = Self.day(info?.fundingValidityStart)
    let fundEnd = Self.day(info?.fundingValidityEnd)
    let expired = Fmt.day(info?.fundingValidityEnd).map { $0 < Date() }
    let training = info?.trainingHours
    let assessment = info?.assessmentHours
    // Title, code, run, dates, class type and status are on the summary card; only the rest is here.
    let hasAny = [info?.tscTitle, info?.tscCode, info?.caslSkills, fundStart, fundEnd]
      .contains { Self.value($0) != nil } || training != nil || assessment != nil
    return Group {
      if hasAny { courseDetailsCard(info, fundStart, fundEnd, expired, training, assessment) }
    }
  }

  private func courseDetailsCard(
    _ info: CourseDetails?, _ fundStart: String?, _ fundEnd: String?, _ expired: Bool?,
    _ training: Double?, _ assessment: Double?
  ) -> some View {
    fold("Course Details", icon: "info.circle") {
      if let title = Self.value(info?.tscTitle) { InfoRow("TSC Title", title) }
      if let code = Self.value(info?.tscCode) { InfoRow("TSC Code", code) }
      if let casl = Self.value(info?.caslSkills) { InfoRow("CASL Skills", casl) }
      if fundStart != nil || fundEnd != nil {
        VStack(alignment: .leading, spacing: 6) {
          Text("Funding Validity").font(.caption).foregroundStyle(.secondary)
          HStack(alignment: .firstTextBaseline) {
            Text("\(fundStart ?? "N/A") – \(fundEnd ?? "N/A")").font(.body.monospacedDigit())
            Spacer(minLength: 8)
            if let expired {
              StatusChip(text: expired ? "Expired" : "Valid", color: expired ? .red : .green)
            }
          }
        }
      }
      if training != nil || assessment != nil {
        HStack(spacing: 8) {
          HoursTile(label: "Training", value: Self.hrs(training))
          HoursTile(label: "Assessment", value: Self.hrs(assessment))
          HoursTile(label: "Total", value: Self.hrs((training ?? 0) + (assessment ?? 0)), strong: true)
        }
        .padding(.vertical, 4)
      }
    }
  }

  // MARK: E-Attendance / SWDA Enrolment

  @ViewBuilder private func eAttendance(_ detail: ClassDetail) -> some View {
    fold("E-Attendance", icon: "checklist.checked") {
      if let da = Self.value(detail.digitalAttendanceId) {
        InfoRow("Digital Attendance ID", da)
      }
      if trainer, let da = Self.value(detail.digitalAttendanceId) {
        // The website's trainer E-Attendance links, built from the Digital Attendance ID.
        HStack(spacing: 10) {
          SSGLinkButton(
            title: "SSG QR Attendance", icon: "qrcode",
            raw: "https://www.myskillsfuture.gov.sg/spface/splogin/select-session?course-run-code=\(da)")
          SSGLinkButton(
            title: "SSG E-Attendance List", icon: "list.bullet.rectangle",
            raw: "https://www.myskillsfuture.gov.sg/api/take-attendance/\(da)")
        }
        .padding(.vertical, 4)
      } else if let link = detail.ssgAttendanceURL {
        PortalLink(
          title: "E-Attendance", subtitle: "Open E-Attendance for Course Run \(runID)",
          icon: "checklist.checked", raw: link)
      } else if !trainer {
        Text("E-Attendance link not yet available for this course run.").font(.subheadline)
          .italic().foregroundStyle(.secondary)
      }
      if detail.sessions.isEmpty {
        Label("Session times to be confirmed", systemImage: "clock").foregroundStyle(.secondary)
      }
      ForEach(detail.sessions) { session in
        if trainer {
          NavigationLink {
            SessionAttendanceView(courseID: course.id, session: session)
          } label: {
            SessionRow(session: session, trainer: true)
          }
        } else {
          SessionRow(session: session, trainer: false)
        }
      }
      if !trainer {
        Button {
          scanning = true
        } label: {
          Label("Scan class QR to check in", systemImage: "qrcode.viewfinder")
        }.accessibilityIdentifier("scan-checkin")
      }
    } footer: {
      Text(
        trainer
          ? "SSG QR Attendance and SSG E-Attendance List open on MySkillsFuture. Open a session below to mark attendance in the LMS."
          : "E-Attendance is taken on MySkillsFuture with Singpass. Also scan the class QR code your trainer shows."
      )
    }
  }

  private func swdaEnrolment(_ link: String) -> some View {
    fold("SWDA Enrolment", icon: "person.crop.circle.badge.plus") {
      PortalLink(
        title: "Open SWDA Enrolment Form",
        subtitle: [
          (detail?.code ?? course.code).map { "Course Code: \($0)" },
          runID.isEmpty ? nil : "Course Run ID: \(runID)",
        ].compactMap { $0 }.joined(separator: " · "),
        icon: "person.crop.circle.badge.plus", raw: link)
    } footer: {
      Text("For learners not yet enrolled on SWDA. The academy then enrols them on TPGateway.")
    }
  }

  // MARK: Announcements / Virtual Class Link / Courseware

  @ViewBuilder private func announcements(_ detail: ClassDetail) -> some View {
    fold("Announcements", icon: "megaphone") {
      let items = detail.announcements ?? []
      if items.isEmpty {
        Text("No announcements yet.").font(.subheadline).foregroundStyle(.secondary)
      }
      ForEach(items) { item in
        VStack(alignment: .leading, spacing: 6) {
          if let title = item.title, !title.isEmpty { Text(title).font(.headline) }
          if let message = item.message, !message.isEmpty { Text(message).font(.subheadline) }
          Text(
            [item.postedBy, item.createdAt.map { Fmt.longDate(String($0.prefix(10))) }]
              .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
          ).font(.caption).foregroundStyle(.secondary)
          if let link = item.linkURL { MaterialLink(title: "Open link", icon: "link", raw: link) }
          if let file = item.fileURL {
            MaterialLink(title: item.fileName ?? "Attachment", icon: "paperclip", raw: file)
          }
        }
        .padding(.vertical, 2)
      }
    }
  }

  private var meetingLink: String? { Self.value(detail?.meetingURL ?? course.meetingURL) }

  // Courseware comes from the class detail when loaded (it carries the role's full list);
  // until then the dashboard's links are shown so the screen is useful immediately.
  @ViewBuilder private var courseware: some View {
    fold("Courseware", icon: "folder") {
      if let detail {
        let items = detail.materials.asOnWebsite(trainer: trainer)
        if items.isEmpty {
          Label("No courseware published yet", systemImage: "tray").foregroundStyle(.secondary)
        }
        ForEach(items) { item in
          DocumentRow(
            courseID: course.id,
            material: CourseMaterial(
              id: item.id, title: item.title, symbol: item.symbol, rawURL: item.url))
        }
      } else {
        ForEach(course.materials(for: store.role)) { material in
          DocumentRow(courseID: course.id, material: material)
        }
      }
    } footer: {
      Text("PDF courseware opens inside the app. Other links open in the browser.")
    }
  }

  private var quizzes: some View {
    fold("Lesson", icon: "book") {
      Button {
        scanning = true
      } label: {
        Label("Scan a quiz QR code", systemImage: "questionmark.circle")
      }.accessibilityIdentifier("scan-quiz")
      if store.demo {
        Button {
          store.open(quiz: QuizLink(courseID: course.id, quizID: "sample-quiz"))
        } label: {
          Label("Try the sample quiz", systemImage: "play.circle")
        }.accessibilityIdentifier("sample-quiz")
      }
    } footer: {
      Text(
        "When your trainer shows a quiz QR code, scan it here or with your phone camera. The quiz opens in the app and your score is saved to your class."
      )
    }
  }

  // MARK: Course Feedback & TRAQOM Survey / Briefing on Assessment

  @ViewBuilder private func feedbackAndTraqom(_ detail: ClassDetail) -> some View {
    // An older server sends no flag; show Course Feedback then, as the website does for this academy.
    let withFeedback = detail.showCourseFeedback ?? true
    let feedbackLink = detail.courseFeedbackURL ?? "/feedback/\(detail.id)"
    fold(withFeedback ? "Course Feedback & TRAQOM Survey" : "TRAQOM Survey", icon: "star.bubble") {
      if !trainer, let feedback = detail.feedback {
        if let external = feedback.externalURL {
          MaterialLink(title: "Course Feedback", icon: "star.bubble", raw: external)
        } else if feedback.submitted {
          Label("Course feedback sent. Thank you.", systemImage: "checkmark.circle.fill")
            .foregroundStyle(Theme.accent)
        } else if feedback.enabled {
          NavigationLink {
            CourseFeedbackView(courseID: course.id) { Task { await load() } }
          } label: {
            Label("Course Feedback", systemImage: "star.bubble")
          }.accessibilityIdentifier("course-feedback")
        }
      }
      if trainer, withFeedback {
        PortalLink(
          title: "Open Course Feedback Form", subtitle: "Opens the form in the app",
          icon: "star.bubble", raw: feedbackLink
        ).accessibilityIdentifier("open-feedback-form")
      }
      if let traqom = detail.traqomURL {
        MaterialLink(title: "TRAQOM Survey", icon: "list.clipboard", raw: traqom)
      }
    } footer: {
      Text("Your feedback helps us improve. TRAQOM is the SkillsFuture Singapore training quality survey.")
    }
  }

  @ViewBuilder private func briefing(_ detail: ClassDetail) -> some View {
    if let points = detail.briefingOnAssessment, !points.isEmpty {
      fold("Briefing on Assessment", icon: "list.bullet.clipboard") {
        ForEach(points, id: \.self) { point in
          Label(point, systemImage: "circle.fill").labelStyle(BulletLabel())
            .font(.subheadline)
        }
      }
    }
  }

  // MARK: Assessment and records

  @ViewBuilder private func assessment(_ detail: ClassDetail) -> some View {
    fold("Assessment", icon: "doc.text") {
      if detail.assessments.isEmpty {
        Label(
          trainer ? "No assessments set for this course" : "No assessment is open yet",
          systemImage: "doc.text.magnifyingglass"
        ).foregroundStyle(.secondary)
      }
      ForEach(detail.assessments) { item in
        if trainer {
          PublishToggle(runID: detail.id, item: item) { Task { await load() } }
        } else {
          NavigationLink {
            AssessmentView(courseID: course.id, type: item.type)
          } label: {
            VStack(alignment: .leading, spacing: 4) {
              Text(item.label)
              Text(
                item.submissions.isEmpty
                  ? "Not submitted" : "\(item.submissions.count) file(s) submitted"
              ).font(.caption).foregroundStyle(.secondary)
            }
          }
        }
      }
    }
  }

  private func summaryRecord(_ detail: ClassDetail) -> some View {
    fold("Assessment Summary Record", icon: "checkmark.seal") {
      if trainer {
        TrainerSummaryRecordView(runID: detail.id)
      } else {
        LearnerSummaryRecordView(runID: detail.id, assessmentStatus: detail.assessmentStatus)
      }
    }
  }

  private func grading(_ detail: ClassDetail) -> some View {
    fold("Assessment Grading", icon: "square.and.pencil") {
      NavigationLink {
        GradingView(courseID: course.id)
      } label: {
        VStack(alignment: .leading, spacing: 3) {
          Label("Assessment Grading", systemImage: "square.and.pencil")
          Text("Open Assessment Grading for Course Run \(runID) · \(detail.roster?.count ?? 0) learners")
            .font(.caption).foregroundStyle(.secondary)
        }
      }.accessibilityIdentifier("grading")
    }
  }

  private func feedbackSummary(_ detail: ClassDetail) -> some View {
    fold("Post Course Feedback Summary", icon: "chart.bar") {
      if let summary = detail.feedbackSummary, summary.count > 0 {
        FeedbackSummaryView(summary: summary)
      } else {
        Text(
          (detail.feedbackCount ?? 0) > 0
            ? "\(detail.feedbackCount ?? 0) responses received." : "No feedback yet for this class."
        ).font(.subheadline).foregroundStyle(.secondary)
      }
    }
  }
}

/// The Post Course Feedback Summary laid out for a phone: overall score, a bar per question,
/// then the comments (three shown, the rest on "Show all").
struct FeedbackSummaryView: View {
  let summary: FeedbackSummary
  @State private var allComments = false

  private static func score(_ v: Double?) -> String {
    guard let v else { return "—" }
    return v.formatted(.number.precision(.fractionLength(v.rounded() == v ? 0 : 1)))
  }
  private static func tint(_ v: Double?) -> Color {
    guard let v else { return .secondary }
    return v >= 4 ? .green : v >= 3 ? .orange : .red
  }

  var body: some View {
    Group {
      HStack(alignment: .center, spacing: 16) {
        VStack(spacing: 0) {
          Text(Self.score(summary.overall)).font(.system(size: 40, weight: .bold, design: .rounded))
            .foregroundStyle(Self.tint(summary.overall))
          Text("out of 5").font(.caption).foregroundStyle(.secondary)
        }
        VStack(alignment: .leading, spacing: 6) {
          HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { i in
              let v = summary.overall ?? 0
              Image(systemName: v >= Double(i) ? "star.fill" : v >= Double(i) - 0.5 ? "star.leadinghalf.filled" : "star")
                .foregroundStyle(.yellow)
            }
          }.font(.subheadline)
          Text("Overall average").font(.subheadline.weight(.semibold))
          Text("\(summary.count) \(summary.count == 1 ? "response" : "responses")").font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer(minLength: 0)
      }
      .padding(.vertical, 6)
      .accessibilityElement(children: .combine)

      ForEach(Array(summary.questions.enumerated()), id: \.offset) { i, q in
        VStack(alignment: .leading, spacing: 8) {
          HStack(alignment: .firstTextBaseline) {
            Text("\(i + 1). \(q.label)").font(.subheadline).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Text("\(Self.score(q.average))/5").font(.subheadline.weight(.bold).monospacedDigit())
          }
          ProgressView(value: min(max(q.average ?? 0, 0), 5), total: 5).tint(Self.tint(q.average))
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
      }

      if !summary.comments.isEmpty {
        VStack(alignment: .leading, spacing: 10) {
          Text("Comments").font(.subheadline.weight(.semibold))
          ForEach(Array((allComments ? summary.comments : Array(summary.comments.prefix(3))).enumerated()), id: \.offset) { _, c in
            HStack(alignment: .top, spacing: 8) {
              Image(systemName: "quote.opening").font(.caption).foregroundStyle(Theme.accent)
              Text(c).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            }
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
          }
          if summary.comments.count > 3 {
            Button(allComments ? "Show fewer" : "Show all \(summary.comments.count) comments") {
              withAnimation { allComments.toggle() }
            }
            .font(.subheadline.weight(.semibold)).buttonStyle(.borderless)
          }
        }
        .padding(.vertical, 4)
      }
    }
  }
}

/// A label and value that sit side by side when they fit and stack on narrow phones,
/// so long labels such as "Digital Attendance ID" never squeeze the value.
struct InfoRow: View {
  let label: String
  let value: String
  init(_ label: String, _ value: String) {
    self.label = label
    self.value = value
  }
  var body: some View {
    ViewThatFits(in: .horizontal) {
      HStack(alignment: .firstTextBaseline, spacing: 12) {
        Text(label).foregroundStyle(.secondary).lineLimit(1).fixedSize()
        Spacer(minLength: 8)
        Text(value).multilineTextAlignment(.trailing).lineLimit(1).fixedSize()
      }
      VStack(alignment: .leading, spacing: 3) {
        Text(label).font(.caption).foregroundStyle(.secondary)
        Text(value).fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .accessibilityElement(children: .combine)
  }
}

/// One of the three Course Duration figures (Training, Assessment, Total).
struct HoursTile: View {
  let label: String
  let value: String
  var strong = false
  var body: some View {
    VStack(spacing: 2) {
      Text(value).font(.headline.monospacedDigit())
        .foregroundStyle(strong ? Theme.accent : .primary)
      Text(label).font(.caption).foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity).padding(.vertical, 8)
    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
  }
}

/// One of the two SSG attendance links on MySkillsFuture. Opens in Safari so Singpass works.
struct SSGLinkButton: View {
  let title: String
  let icon: String
  let raw: String
  @Environment(\.openURL) private var openURL
  var body: some View {
    Button {
      if let url = URL(string: raw) { openURL(url) }
    } label: {
      VStack(spacing: 6) {
        Image(systemName: icon).font(.title3)
        Text(title).font(.subheadline.weight(.semibold)).multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, minHeight: 64).padding(.vertical, 6)
    }
    .buttonStyle(.bordered).tint(Theme.accent)
    .accessibilityIdentifier(title)
  }
}

/// The class venue's address; tapping opens it in Google Maps.
struct VenueLink: View {
  let address: String
  @Environment(\.openURL) private var openURL
  private var mapURL: URL? {
    var c = URLComponents(string: "https://www.google.com/maps/search/")
    c?.queryItems = [URLQueryItem(name: "api", value: "1"), URLQueryItem(name: "query", value: address)]
    return c?.url
  }
  var body: some View {
    Button {
      if let mapURL { openURL(mapURL) }
    } label: {
      Label {
        VStack(alignment: .leading, spacing: 2) {
          Text(address).foregroundStyle(.primary).multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
          Text("Open in Google Maps").font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
        }
      } icon: {
        Image(systemName: "mappin.and.ellipse").foregroundStyle(Theme.accent)
      }
      .font(.subheadline)
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("venue-map")
  }
}

/// "Join Google Meet" / "Join Zoom" / "Join Microsoft Teams", named like the website's
/// Virtual Class Link. Opens outside the app so the meeting app takes over.
struct JoinMeetingButton: View {
  let raw: String
  let prominent: Bool
  @Environment(\.openURL) private var openURL
  private var url: URL? {
    guard let url = URL(string: raw.trimmingCharacters(in: .whitespaces)), url.scheme == "https"
    else { return nil }
    return url
  }
  static func provider(_ raw: String) -> String {
    let host = URL(string: raw)?.host?.lowercased() ?? ""
    if host.contains("zoom.") { return "Zoom" }
    if host.contains("teams.") || host.contains("microsoft") { return "Microsoft Teams" }
    if host.contains("meet.google") { return "Google Meet" }
    return "online class"
  }
  var body: some View {
    let title = "Join \(Self.provider(raw))"
    if prominent {
      Button {
        if let url { openURL(url) }
      } label: {
        Text(title).font(.headline).multilineTextAlignment(.center)
          .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 6)
      }
      .buttonStyle(.borderedProminent).tint(Theme.accent).disabled(url == nil)
      .accessibilityIdentifier("join-meeting")
    } else {
      Button {
        if let url { openURL(url) }
      } label: {
        HStack(spacing: 12) {
          Image(systemName: "video.fill").foregroundStyle(.green).frame(width: 26)
          VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.body.weight(.semibold)).foregroundStyle(.primary)
            Text(raw).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
          }
          Spacer()
          Image(systemName: "arrow.up.right.square").foregroundStyle(.secondary)
        }
      }
      .disabled(url == nil)
    }
  }
}

/// A bullet point for short lists such as the Briefing on Assessment.
struct BulletLabel: LabelStyle {
  func makeBody(configuration: Configuration) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text("•").foregroundStyle(.secondary)
      configuration.title
    }
  }
}

/// A portal link with the website's two-line card text, e.g. "E-Attendance" over
/// "Open E-Attendance for Course Run 1361797". Opens in the in-app browser.
struct PortalLink: View {
  let title: String
  let subtitle: String
  let icon: String
  let raw: String
  @State private var showing = false
  private var url: URL? {
    guard let url = URL(string: raw, relativeTo: API.shared.base)?.absoluteURL,
      url.scheme == "https"
    else { return nil }
    return url
  }
  var body: some View {
    Button {
      showing = true
    } label: {
      HStack(spacing: 12) {
        Image(systemName: icon).foregroundStyle(Theme.accent).frame(width: 26)
        VStack(alignment: .leading, spacing: 2) {
          Text(title).font(.body.weight(.semibold)).foregroundStyle(.primary)
          if !subtitle.isEmpty {
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
          }
        }
        Spacer()
        Image(systemName: "arrow.up.right.square").foregroundStyle(.secondary)
      }
    }
    .disabled(url == nil)
    .sheet(isPresented: $showing) { if let url { Browser(url: url).ignoresSafeArea() } }
  }
}

struct SessionRow: View {
  let session: DetailSession
  let trainer: Bool
  var body: some View {
    HStack {
      VStack(alignment: .leading, spacing: 4) {
        Text(session.label.isEmpty ? "Class session" : session.label)
        Text(
          [session.startTime, session.endTime].compactMap { $0 }.map {
            ClassSession.clockLabel($0)
          }.joined(separator: "–") + " SGT"
        ).font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
      if trainer {
        Text("\(session.presentCount ?? 0) present").font(.caption).foregroundStyle(.secondary)
      } else if session.attendance == "present" {
        Label("Present", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(
          .green)
      } else if session.attendance == "absent" {
        Label("Absent", systemImage: "xmark.circle").font(.caption).foregroundStyle(.orange)
      } else {
        Text("Not taken").font(.caption).foregroundStyle(.secondary)
      }
    }
  }
}

// MARK: - Courseware reader

struct DocumentRow: View {
  @EnvironmentObject var store: Store
  let courseID: String
  let material: CourseMaterial
  @State private var showing = false

  private var url: URL? {
    guard let raw = material.rawURL, let url = URL(string: raw), url.scheme == "https" else {
      return nil
    }
    return url
  }

  var body: some View {
    if let url {
      Button {
        store.markMaterialOpened(courseID: courseID, materialID: material.id)
        showing = true
      } label: {
        HStack {
          Label(material.title, systemImage: material.symbol)
          Spacer()
          if store.hasOpened(courseID: courseID, materialID: material.id) {
            Label("Opened", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(
              Theme.accent)
          } else {
            Text("Ready").font(.caption).foregroundStyle(.secondary)
          }
        }
      }
      .accessibilityLabel(material.title)
      .accessibilityValue(
        store.hasOpened(courseID: courseID, materialID: material.id) ? "Opened" : "Ready")
      .sheet(isPresented: $showing) { DocumentViewer(title: material.title, url: url) }
    } else {
      Label("\(material.title) · not published yet", systemImage: material.symbol)
        .foregroundStyle(.secondary)
    }
  }
}

/// Opens a courseware link. A PDF (or a Google file that exports as one) is downloaded and shown
/// in the app; anything else is shown as a web page. Download fetches the file itself and hands
/// it to the system share sheet (Save to Files, Print, AirDrop).
struct DocumentViewer: View {
  @EnvironmentObject var store: Store
  @Environment(\.dismiss) var dismiss
  let title: String
  let url: URL
  @State private var document: PDFDocument?
  @State private var showWeb = false
  @State private var useBrowser = false
  @State private var loading = true
  @State private var webLoading = true
  @State private var webFailure: String?
  @State private var downloading = false
  @State private var downloaded: DownloadedFile?
  @State private var downloadError: String?

  var body: some View {
    if useBrowser {
      Browser(url: url).ignoresSafeArea()
    } else {
      NavigationStack {
        ZStack {
          if let document {
            PDFReader(document: document)
          } else if showWeb {
            WebPage(url: url, loading: $webLoading, failure: $webFailure)
              .ignoresSafeArea(edges: .bottom)
            if let webFailure {
              ContentUnavailableView {
                Label("Can't open this document", systemImage: "doc.questionmark")
              } description: {
                Text(webFailure)
              } actions: {
                Button("Open in browser") { useBrowser = true }.buttonStyle(.borderedProminent)
              }
              .background(Theme.page)
            } else if webLoading {
              ProgressView().controlSize(.large)
            }
          } else {
            ProgressView("Opening \(title)…")
          }
        }
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
          ToolbarItemGroup(placement: .primaryAction) {
            if downloading {
              ProgressView()
            } else {
              Button {
                download()
              } label: {
                Label("Download", systemImage: "arrow.down.circle")
              }
              .accessibilityIdentifier("download-document")
            }
            Button {
              useBrowser = true
            } label: {
              Label("Open in browser", systemImage: "safari")
            }
          }
        }
        .sheet(item: $downloaded) { FileShareSheet(file: $0.url) }
        .alert(
          "Download",
          isPresented: Binding(get: { downloadError != nil }, set: { if !$0 { downloadError = nil } })
        ) {
          Button("Open in browser") { useBrowser = true }
          Button("OK", role: .cancel) {}
        } message: {
          Text(downloadError ?? "")
        }
      }
      .task { await open() }
    }
  }

  private func download() {
    downloading = true
    Task {
      do {
        // A PDF already on screen is saved as it is; anything else is fetched from its link.
        if let data = document?.dataRepresentation() {
          downloaded = DownloadedFile(url: try DocumentDownload.save(data, name: title + ".pdf"))
        } else {
          downloaded = DownloadedFile(url: try await DocumentDownload.fetch(url, title: title))
        }
      } catch { downloadError = error.localizedDescription }
      downloading = false
    }
  }

  private func open() async {
    guard loading else { return }
    loading = false
    if store.demo {
      document = Sample.pdf(title: title)
      return
    }
    guard let source = DocumentLink.pdfURL(for: url.absoluteString) else {
      showWeb = true
      return
    }
    do {
      var request = URLRequest(url: source)
      request.timeoutInterval = 60
      let (file, response) = try await URLSession.shared.download(for: request)
      defer { try? FileManager.default.removeItem(at: file) }
      let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
      guard (response as? HTTPURLResponse)?.statusCode == 200, size > 4, size < 80 * 1024 * 1024,
        let data = try? Data(contentsOf: file, options: .mappedIfSafe),
        data.prefix(4) == Data("%PDF".utf8), let pdf = PDFDocument(data: Data(data))
      else {
        showWeb = true
        return
      }
      document = pdf
    } catch {
      showWeb = true
    }
  }
}

/// Fetches a document to a temporary file so it can be saved to Files, printed or shared.
enum DocumentDownload {
  /// Where the file itself can be fetched: Google Drive and Docs viewer links are turned into
  /// their download / PDF-export form; any other link is used as it is. Nil for things that
  /// are not one file (a Drive folder).
  static func source(for url: URL) -> URL? {
    let host = (url.host ?? "").lowercased()
    let parts = url.pathComponents
    func id(after key: String) -> String? {
      guard let i = parts.firstIndex(of: key), i + 1 < parts.count else { return nil }
      return parts[i + 1]
    }
    if host == "drive.google.com" {
      if parts.contains("folders") { return nil }
      let fileID =
        id(after: "d")
        ?? URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first {
          $0.name == "id"
        }?.value
      guard let fileID else { return nil }
      return URL(
        string:
          "https://drive.usercontent.google.com/download?id=\(fileID)&export=download&confirm=t")
    }
    if host == "docs.google.com", let docID = id(after: "d"), parts.count > 1 {
      // /document/d/ID, /presentation/d/ID, /spreadsheets/d/ID
      return URL(string: "https://docs.google.com/\(parts[1])/d/\(docID)/export?format=pdf")
    }
    return url
  }

  static func fetch(_ url: URL, title: String) async throws -> URL {
    guard let source = source(for: url) else {
      throw APIError(
        message: "This is a folder, not a single file. Open it in the browser to download its files."
      )
    }
    var request = URLRequest(url: source)
    request.timeoutInterval = 120
    let (temp, response): (URL, URLResponse)
    do { (temp, response) = try await URLSession.shared.download(for: request) } catch {
      throw APIError(
        message: "The download did not finish. Check your connection and try again.")
    }
    let http = response as? HTTPURLResponse
    let type = (http?.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
    // A web page instead of a file means the owner has not allowed downloads, or it needs a sign-in.
    guard (200..<300).contains(http?.statusCode ?? 0), !type.hasPrefix("text/html") else {
      try? FileManager.default.removeItem(at: temp)
      throw APIError(
        message: "This document can't be downloaded here. Open it in the browser instead.")
    }
    var name = response.suggestedFilename ?? ""
    if name.isEmpty || name == "download" || name == "export" || name == "Unknown" {
      let ext =
        type.contains("pdf") ? "pdf" : (source.pathExtension.isEmpty ? "pdf" : source.pathExtension)
      name = title + "." + ext
    }
    let destination = try folder().appendingPathComponent(clean(name))
    try FileManager.default.moveItem(at: temp, to: destination)
    return destination
  }

  static func save(_ data: Data, name: String) throws -> URL {
    let destination = try folder().appendingPathComponent(clean(name))
    try data.write(to: destination)
    return destination
  }

  private static func clean(_ name: String) -> String {
    name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
  }
  private static func folder() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
  }
}

struct DownloadedFile: Identifiable {
  let url: URL
  var id: URL { url }
}

/// The system share sheet for a downloaded file: Save to Files, Print, AirDrop, other apps.
struct FileShareSheet: UIViewControllerRepresentable {
  let file: URL
  func makeUIViewController(context: Context) -> UIActivityViewController {
    UIActivityViewController(activityItems: [file], applicationActivities: nil)
  }
  func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Courseware that is not a PDF (web pages, Google Drive viewer pages), shown in the reader.
struct WebPage: UIViewRepresentable {
  let url: URL
  @Binding var loading: Bool
  @Binding var failure: String?

  func makeCoordinator() -> Coordinator { Coordinator(self) }
  func makeUIView(context: Context) -> WKWebView {
    let view = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
    view.navigationDelegate = context.coordinator
    view.uiDelegate = context.coordinator
    view.allowsBackForwardNavigationGestures = true
    view.load(URLRequest(url: url))
    return view
  }
  func updateUIView(_ view: WKWebView, context: Context) {}

  final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
    let parent: WebPage
    init(_ parent: WebPage) { self.parent = parent }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
      parent.loading = false
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
      fail(error)
    }
    func webView(
      _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
      withError error: Error
    ) { fail(error) }

    /// Links that leave the web (mailto:, tel:, app links) go to the system.
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async
      -> WKNavigationActionPolicy
    {
      if let url = action.request.url, let scheme = url.scheme?.lowercased(),
        !["http", "https", "about", "blob", "data"].contains(scheme)
      {
        await UIApplication.shared.open(url)
        return .cancel
      }
      return .allow
    }

    /// A link that asks for a new window (common on Google Drive) opens in this one.
    func webView(
      _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
      for action: WKNavigationAction, windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
      if action.targetFrame == nil, let url = action.request.url {
        webView.load(URLRequest(url: url))
      }
      return nil
    }

    private func fail(_ error: Error) {
      let ns = error as NSError
      // -999 = a navigation replaced by another; 102 = a download took over the frame.
      if ns.code == NSURLErrorCancelled { return }
      parent.loading = false
      if ns.domain == "WebKitErrorDomain" && ns.code == 102 { return }
      parent.failure = error.localizedDescription
    }
  }
}

struct PDFReader: UIViewRepresentable {
  let document: PDFDocument
  func makeUIView(context: Context) -> PDFView {
    let view = PDFView()
    view.autoScales = true
    view.displayMode = .singlePageContinuous
    view.displayDirection = .vertical
    view.document = document
    return view
  }
  func updateUIView(_ view: PDFView, context: Context) {
    if view.document !== document { view.document = document }
  }
}

// MARK: - Attendance

struct SessionAttendanceView: View {
  @EnvironmentObject var store: Store
  let courseID: String
  let session: DetailSession
  @State private var sheet: AttendanceSheet?
  @State private var problem: String?
  @State private var saving = false
  @State private var saved = false
  @State private var showQR = false

  var body: some View {
    List {
      if let link = sheet?.checkinURL {
        Section {
          Button {
            showQR = true
          } label: {
            Label("Show check-in QR code", systemImage: "qrcode")
          }.accessibilityIdentifier("show-qr")
        } footer: {
          Text("Learners scan this code in their TIA TMS app, or with their phone camera.")
        }
      }
      if let sheet {
        Section {
          if sheet.learners.isEmpty {
            Label("No learners on this class yet", systemImage: "person.2.slash").foregroundStyle(
              .secondary)
          }
          ForEach(sheet.learners.indices, id: \.self) { index in
            AttendanceToggleRow(
              learner: Binding(
                get: { self.sheet?.learners[index] ?? sheet.learners[index] },
                set: {
                  self.sheet?.learners[index] = $0
                  saved = false
                }))
          }
        } header: {
          Text("Manual attendance")
        } footer: {
          Text("Mark each learner, then save. Learners who check in by QR code appear as present.")
        }
        Section {
          Button {
            Task { await save() }
          } label: {
            Text(saving ? "Saving…" : saved ? "Saved" : "Save attendance").frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent).disabled(saving || saved)
          .accessibilityIdentifier("save-attendance")
        }
      } else if let problem {
        Section {
          Label(problem, systemImage: "wifi.exclamationmark").foregroundStyle(.secondary)
          Button("Try again") { Task { await load() } }
        }
      } else {
        Section { ProgressView() }
      }
    }
    .navigationTitle(session.label.isEmpty ? "Attendance" : session.label)
    .navigationBarTitleDisplayMode(.inline)
    .sheet(isPresented: $showQR) {
      QRCodeSheet(title: session.label, text: sheet?.checkinURL ?? "")
    }
    .task { await load() }
    .refreshable { await load() }
  }

  private func load() async {
    do {
      sheet = try await store.attendanceSheet(sessionID: session.id, courseID: courseID)
      problem = nil
    } catch { problem = error.localizedDescription }
  }

  private func save() async {
    guard let current = sheet else { return }
    saving = true
    defer { saving = false }
    do {
      sheet = try await store.saveAttendance(sessionID: session.id, sheet: current)
      saved = true
    } catch { store.error = error.localizedDescription }
  }
}

struct AttendanceToggleRow: View {
  @Binding var learner: AttendanceLearner
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(learner.name)
      Picker(
        "Attendance for \(learner.name)",
        selection: Binding(
          get: { learner.isPresent.map { $0 ? 1 : 2 } ?? 0 },
          set: { learner.isPresent = $0 == 0 ? nil : $0 == 1 })
      ) {
        Text("Not taken").tag(0)
        Text("Present").tag(1)
        Text("Absent").tag(2)
      }.pickerStyle(.segmented)
      if learner.isPresent == false {
        TextField(
          "Reason for absence (optional)",
          text: Binding(get: { learner.reason ?? "" }, set: { learner.reason = $0 }))
      }
    }.padding(.vertical, 4)
  }
}

/// A link as a QR code for the class to scan: the session check-in or a survey.
struct QRCodeSheet: View {
  @Environment(\.dismiss) var dismiss
  let title: String
  let text: String
  var heading = "Scan to check in"
  var hint = "Keep this screen open while learners scan it."
  var shareLabel = "Share Check-in Link"

  private var image: UIImage? {
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(text.utf8)
    filter.correctionLevel = "M"
    guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)),
      let cg = CIContext().createCGImage(output, from: output.extent)
    else { return nil }
    return UIImage(cgImage: cg)
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 18) {
          Text(heading).font(.title2.bold()).multilineTextAlignment(.center)
          if let image {
            Image(uiImage: image).interpolation(.none).resizable().scaledToFit()
              .padding(14)
              // A QR code must stay dark-on-white to scan, in either theme.
              .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
              .frame(maxWidth: 340)
              .accessibilityLabel("\(heading): QR code for \(title)")
          }
          if !title.isEmpty { Text(title).font(.headline).multilineTextAlignment(.center) }
          Text(hint).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
          if let url = URL(string: text), !text.isEmpty {
            ShareLink(item: url) {
              Label(shareLabel, systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered).accessibilityIdentifier("share-qr-link")
          }
          Button("Close QR code") { dismiss() }.buttonStyle(.bordered)
            .accessibilityIdentifier("close-qr")
        }
        .padding(24).frame(maxWidth: .infinity)
      }
      .background(Theme.page)
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
  }
}

/// Camera QR scanner with a typed fallback for devices where the camera is unavailable or denied.
struct QRScannerSheet: View {
  @Environment(\.dismiss) var dismiss
  @EnvironmentObject var store: Store
  let onCode: (String) -> Void
  @State private var typed = ""
  @State private var cameraAllowed: Bool?

  var body: some View {
    NavigationStack {
      VStack(spacing: 16) {
        if cameraAllowed == true {
          CameraScanner(onCode: onCode).clipShape(RoundedRectangle(cornerRadius: 20))
            .frame(maxHeight: 420)
          Text("Point the camera at the QR code your trainer is showing.").font(.subheadline)
            .multilineTextAlignment(.center)
        } else if cameraAllowed == false {
          ContentUnavailableView(
            "Camera not available", systemImage: "camera.fill",
            description: Text(
              "Allow camera access in Settings to scan, or enter the link below."))
        } else {
          ProgressView()
        }
        if store.demo {
          Button("Use sample check-in code") { onCode(String(repeating: "a", count: 32)) }
            .buttonStyle(.borderedProminent).accessibilityIdentifier("sample-checkin")
        }
        HStack {
          TextField("Or paste the link", text: $typed).textInputAutocapitalization(.never)
            .autocorrectionDisabled().textFieldStyle(.roundedBorder)
            .accessibilityIdentifier("scan-link")
          Button(QuizLink.parse(typed) != nil ? "Open quiz" : "Check in") { onCode(typed) }
            .disabled(DocumentLink.checkinCode(typed) == nil && QuizLink.parse(typed) == nil)
            .accessibilityIdentifier("scan-link-go")
        }
        Spacer(minLength: 0)
      }
      .padding(20)
      .navigationTitle("Scan class QR code").navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
      .task {
        guard AVCaptureDevice.default(for: .video) != nil else {
          cameraAllowed = false
          return
        }
        cameraAllowed = await AVCaptureDevice.requestAccess(for: .video)
      }
    }
  }
}

struct CameraScanner: UIViewControllerRepresentable {
  let onCode: (String) -> Void
  func makeUIViewController(context: Context) -> ScannerController {
    let controller = ScannerController()
    controller.onCode = onCode
    return controller
  }
  func updateUIViewController(_ controller: ScannerController, context: Context) {}
}

final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
  var onCode: ((String) -> Void)?
  private let session = AVCaptureSession()
  private var preview: AVCaptureVideoPreviewLayer?
  private var delivered = false

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
    guard let device = AVCaptureDevice.default(for: .video),
      let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input)
    else { return }
    session.addInput(input)
    let output = AVCaptureMetadataOutput()
    guard session.canAddOutput(output) else { return }
    session.addOutput(output)
    output.setMetadataObjectsDelegate(self, queue: .main)
    if output.availableMetadataObjectTypes.contains(.qr) { output.metadataObjectTypes = [.qr] }
    let layer = AVCaptureVideoPreviewLayer(session: session)
    layer.videoGravity = .resizeAspectFill
    view.layer.addSublayer(layer)
    preview = layer
  }
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    preview?.frame = view.bounds
  }
  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    let session = session
    DispatchQueue.global(qos: .userInitiated).async { if !session.isRunning { session.startRunning() } }
  }
  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    let session = session
    DispatchQueue.global(qos: .userInitiated).async { if session.isRunning { session.stopRunning() } }
  }
  func metadataOutput(
    _ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject],
    from connection: AVCaptureConnection
  ) {
    guard !delivered,
      let text = (objects.first as? AVMetadataMachineReadableCodeObject)?.stringValue
    else { return }
    delivered = true
    onCode?(text)
  }
}

// MARK: - Assessments

struct AssessmentView: View {
  @EnvironmentObject var store: Store
  let courseID: String
  let type: String
  @State private var detail: ClassDetail?
  @State private var picking = false
  @State private var uploading = false
  @State private var message: String?
  @State private var removing: Submission?

  private var assessment: Assessment? { detail?.assessments.first { $0.type == type } }

  var body: some View {
    List {
      if let assessment {
        Section {
          if let paper = assessment.questionURL {
            DocumentRow(
              courseID: courseID,
              material: CourseMaterial(
                id: "paper-" + type, title: "Question paper", symbol: "doc.text", rawURL: paper))
          } else {
            Label("Your trainer will hand out the question paper", systemImage: "doc.text")
              .foregroundStyle(.secondary)
          }
        } header: {
          Text(assessment.label)
        }
        Section {
          if assessment.submissions.isEmpty {
            Label("Nothing submitted yet", systemImage: "tray").foregroundStyle(.secondary)
          }
          ForEach(assessment.submissions) { file in
            HStack {
              VStack(alignment: .leading, spacing: 4) {
                Text(file.fileName).lineLimit(2)
                Text(file.signed == true ? "Marked by your assessor" : "Submitted").font(.caption)
                  .foregroundStyle(.secondary)
              }
              Spacer()
              if file.signed != true {
                Button(role: .destructive) {
                  removing = file
                } label: {
                  Image(systemName: "trash")
                }.buttonStyle(.borderless).accessibilityLabel("Remove \(file.fileName)")
              }
            }
          }
          Button {
            picking = true
          } label: {
            if uploading {
              HStack {
                ProgressView()
                Text("Uploading…")
              }
            } else {
              Label("Submit a file", systemImage: "square.and.arrow.up")
            }
          }.disabled(uploading).accessibilityIdentifier("submit-file")
        } header: {
          Text("Your submission")
        } footer: {
          Text(
            "Choose a PDF, document or photo of your completed assessment (up to 100 MB). It is sent to your academy's assessment records."
          )
        }
      } else if detail == nil {
        Section { ProgressView() }
      } else {
        Section { Label("This assessment is not open yet", systemImage: "lock") }
      }
    }
    .navigationTitle("Assessment").navigationBarTitleDisplayMode(.inline)
    .task { await load() }
    .fileImporter(isPresented: $picking, allowedContentTypes: [.pdf, .image, .data]) { result in
      guard case .success(let file) = result else { return }
      Task { await submit(file) }
    }
    .alert(
      "Assessment", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })
    ) {
      Button("OK") { message = nil }
    } message: {
      Text(message ?? "")
    }
    .confirmationDialog(
      "Remove this file?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
      titleVisibility: .visible
    ) {
      Button("Remove file", role: .destructive) {
        guard let file = removing else { return }
        Task {
          do {
            try await store.deleteSubmission(file.id, courseID: courseID)
            await load()
          } catch { message = error.localizedDescription }
        }
      }
    }
  }

  private func load() async {
    if let fresh = try? await store.classDetail(courseID) { detail = fresh }
  }

  private func submit(_ file: URL) async {
    guard let detail else { return }
    uploading = true
    defer { uploading = false }
    do {
      try await store.submitAssessment(detail: detail, type: type, file: file)
      message = "Your file was submitted."
      await load()
    } catch { message = error.localizedDescription }
  }
}

struct GradingView: View {
  @EnvironmentObject var store: Store
  let courseID: String
  @State private var detail: ClassDetail?
  @State private var pending: (learner: RosterLearner, competent: Bool)?
  @State private var problem: String?

  var body: some View {
    List {
      if let roster = detail?.roster {
        if roster.isEmpty {
          Label("No learners on this class yet", systemImage: "person.2.slash").foregroundStyle(
            .secondary)
        }
        ForEach(roster) { learner in
          VStack(alignment: .leading, spacing: 8) {
            Text(learner.name).font(.headline)
            Text(
              "\(learner.submissions ?? 0) file(s) submitted · \(learner.status?.isEmpty == false ? learner.status! : "Not graded")"
            ).font(.caption).foregroundStyle(.secondary)
            HStack {
              Button("Competent") { pending = (learner, true) }
                .buttonStyle(.borderedProminent).disabled(learner.isCompetent == true)
              Button("Not Yet Competent") { pending = (learner, false) }
                .buttonStyle(.bordered).disabled(learner.isCompetent == false)
            }
          }.padding(.vertical, 4)
        }
      } else if let problem {
        Label(problem, systemImage: "wifi.exclamationmark").foregroundStyle(.secondary)
      } else {
        ProgressView()
      }
    }
    .navigationTitle("Grading").navigationBarTitleDisplayMode(.inline)
    .task { await load() }
    .refreshable { await load() }
    .confirmationDialog(
      pending.map {
        "Mark \($0.learner.name) as \($0.competent ? "Competent" : "Not Yet Competent")?"
      } ?? "", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
      titleVisibility: .visible
    ) {
      Button("Confirm result") {
        guard let choice = pending else { return }
        Task {
          do {
            try await store.grade(
              enrolmentID: choice.learner.enrolmentId, competent: choice.competent,
              courseID: courseID)
            await load()
          } catch { store.error = error.localizedDescription }
        }
      }
    } message: {
      Text("Review each learner's submitted files in the portal before confirming.")
    }
  }

  private func load() async {
    do {
      detail = try await store.classDetail(courseID)
      problem = nil
    } catch { problem = error.localizedDescription }
  }
}

// MARK: - Course feedback

struct CourseFeedbackView: View {
  @EnvironmentObject var store: Store
  @Environment(\.dismiss) var dismiss
  let courseID: String
  let onSent: () -> Void
  @State private var form: FeedbackForm?
  @State private var text: [String: String] = [:]
  @State private var rating: [String: Int] = [:]
  @State private var sending = false
  @State private var problem: String?

  var body: some View {
    Form {
      if let form {
        if form.submitted {
          Section { Label("Feedback sent. Thank you.", systemImage: "checkmark.circle.fill") }
        } else {
          ForEach(form.sections) { section in
            Section(section.title) {
              ForEach(section.fields) { field in fieldView(field, form: form) }
            }
          }
          Section {
            Button {
              Task { await send(form) }
            } label: {
              Text(sending ? "Sending…" : "Send feedback").frame(maxWidth: .infinity)
            }.buttonStyle(.borderedProminent).disabled(sending)
              .accessibilityIdentifier("send-feedback")
          }
        }
      } else if let problem {
        Section { Label(problem, systemImage: "wifi.exclamationmark") }
      } else {
        Section { ProgressView() }
      }
    }
    .navigationTitle(form?.title ?? "Course feedback").navigationBarTitleDisplayMode(.inline)
    .task {
      do { form = try await store.feedbackForm(courseID: courseID) } catch {
        problem = error.localizedDescription
      }
    }
    .alert(
      "Course feedback",
      isPresented: Binding(get: { problem != nil && form != nil }, set: { if !$0 { problem = nil } })
    ) {
      Button("OK") { problem = nil }
    } message: {
      Text(problem ?? "")
    }
  }

  @ViewBuilder private func fieldView(_ field: FeedbackField, form: FeedbackForm) -> some View {
    let label = field.label + (field.required == true ? " *" : "")
    if let key = field.autofill {
      LabeledContent(field.label, value: (form.autofill?[key] ?? nil) ?? "—")
    } else {
      switch field.type {
      case "rating1to5":
        VStack(alignment: .leading, spacing: 8) {
          Text(label)
          HStack(spacing: 10) {
            ForEach(1...5, id: \.self) { star in
              Button {
                rating[field.id] = star
              } label: {
                Image(systemName: star <= (rating[field.id] ?? 0) ? "star.fill" : "star")
                  .font(.title2).foregroundStyle(Theme.accent)
              }.buttonStyle(.plain).accessibilityLabel("\(star) of 5 for \(field.label)")
            }
          }
        }
      case "select":
        Picker(label, selection: Binding(get: { text[field.id] ?? "" }, set: { text[field.id] = $0 }))
        {
          Text("Choose").tag("")
          ForEach(field.options ?? [], id: \.self) { Text($0).tag($0) }
        }
      case "textarea":
        VStack(alignment: .leading) {
          Text(label)
          TextEditor(text: Binding(get: { text[field.id] ?? "" }, set: { text[field.id] = $0 }))
            .frame(minHeight: 90).accessibilityLabel(field.label)
        }
      case "email":
        LabeledContent(field.label, value: store.user?.email ?? "")
      case "date":
        DatePicker(
          label,
          selection: Binding(
            get: { Self.day.date(from: text[field.id] ?? "") ?? Date() },
            set: { text[field.id] = Self.day.string(from: $0) }), displayedComponents: .date)
      default:
        TextField(label, text: Binding(get: { text[field.id] ?? "" }, set: { text[field.id] = $0 }))
      }
    }
  }

  static let day: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "Asia/Singapore")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
  }()

  private func send(_ form: FeedbackForm) async {
    var answers: [String: Any] = [:]
    for field in form.sections.flatMap(\.fields) where field.autofill == nil {
      if field.type == "rating1to5" {
        if let value = rating[field.id] { answers[field.id] = value }
      } else if field.type == "date" {
        answers[field.id] = text[field.id] ?? Self.day.string(from: Date())
      } else if let value = text[field.id]?.trimmingCharacters(in: .whitespacesAndNewlines),
        !value.isEmpty
      {
        answers[field.id] = value
      }
      if field.required == true, answers[field.id] == nil, field.type != "email" {
        problem = "Please answer: \(field.label)"
        return
      }
    }
    sending = true
    defer { sending = false }
    do {
      try await store.sendFeedback(courseID: courseID, answers: answers)
      onSent()
      dismiss()
    } catch { problem = error.localizedDescription }
  }
}

// MARK: - Password

struct ChangePasswordView: View {
  @EnvironmentObject var store: Store
  @Environment(\.dismiss) var dismiss
  var forced = false
  @State private var current = ""
  @State private var new = ""
  @State private var again = ""
  @State private var saving = false
  @State private var problem: String?

  var body: some View {
    Form {
      if forced {
        Section {
          Text("For your security, choose a new password before you continue.")
        }
      }
      Section {
        SecureField("Current password", text: $current).textContentType(.password)
        SecureField("New password (8 or more characters)", text: $new).textContentType(
          .newPassword)
        SecureField("New password again", text: $again).textContentType(.newPassword)
      }
      if let problem { Section { Text(problem).foregroundStyle(.red) } }
      Section {
        Button {
          Task {
            saving = true
            problem = await store.changePassword(current: current, new: new)
            saving = false
            if problem == nil && !forced { dismiss() }
          }
        } label: {
          Text(saving ? "Saving…" : "Change password").frame(maxWidth: .infinity)
        }.buttonStyle(.borderedProminent).disabled(
          saving || current.isEmpty || new.count < 8 || new != again)
        if forced { Button("Sign out", role: .destructive) { Task { await store.signOut() } } }
      }
    }
    .navigationTitle("Change password").navigationBarTitleDisplayMode(.inline)
  }
}
