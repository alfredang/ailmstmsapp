import AVFoundation
import CoreImage.CIFilterBuiltins
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

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

  private var trainer: Bool { store.role == "trainer" }

  var body: some View {
    List {
      Section {
        Text(course.title).font(.title2.bold())
        LabeledContent("Course code", value: course.code ?? "—")
        if let run = detail?.runCode, !run.isEmpty { LabeledContent("Class", value: run) }
        LabeledContent("Delivery", value: course.format ?? "—")
        if let venue = course.venue, !venue.isEmpty { Label(venue, systemImage: "mappin.and.ellipse") }
        if let link = course.meetingURL, !link.isEmpty {
          MaterialLink(title: "Join online class", icon: "video", raw: link)
        }
        JourneyProgress(course: course)
      }

      materials

      if let detail {
        attendance(detail)
        if !trainer { quizzes }
        assessments(detail)
        if trainer { roster(detail) }
        surveys(detail)
      } else if let problem {
        Section {
          Label(problem, systemImage: "wifi.exclamationmark").foregroundStyle(.secondary)
          Button("Try again") { Task { await load() } }
        }
      } else {
        Section { ProgressView("Loading attendance and assessments…") }
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

  // Courseware comes from the class detail when loaded (it carries the role's full kit);
  // until then the dashboard's links are shown so the screen is useful immediately.
  @ViewBuilder private var materials: some View {
    Section {
      if let detail {
        if detail.materials.isEmpty {
          Label("No courseware published yet", systemImage: "tray").foregroundStyle(.secondary)
        }
        ForEach(detail.materials) { item in
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
    } header: {
      Text(trainer ? "Teaching kit" : "Courseware")
    } footer: {
      Text("PDF courseware opens inside the app. Other links open in the browser.")
    }
  }

  @ViewBuilder private func attendance(_ detail: ClassDetail) -> some View {
    Section {
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
      if let link = detail.ssgAttendanceURL {
        MaterialLink(
          title: trainer ? "Open SSG attendance QR" : "SSG e-attendance (Singpass)",
          icon: "person.badge.shield.checkmark", raw: link)
      }
    } header: {
      Text("Attendance")
    } footer: {
      Text(
        trainer
          ? "Open a session to show its check-in QR code or mark attendance yourself. SSG e-attendance is taken on MySkillsFuture."
          : "Scan the QR code your trainer shows in class. SSG e-attendance is taken separately on MySkillsFuture with Singpass."
      )
    }
  }

  private var quizzes: some View {
    Section {
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
    } header: {
      Text("Class quiz")
    } footer: {
      Text(
        "When your trainer shows a quiz QR code, scan it here or with your phone camera. The quiz opens in the app and your score is saved to your class."
      )
    }
  }

  @ViewBuilder private func assessments(_ detail: ClassDetail) -> some View {
    Section {
      if detail.assessments.isEmpty {
        Label(
          trainer ? "No assessments set for this course" : "No assessment is open yet",
          systemImage: "doc.text.magnifyingglass"
        ).foregroundStyle(.secondary)
      }
      ForEach(detail.assessments) { item in
        if trainer {
          VStack(alignment: .leading, spacing: 4) {
            Text(item.label)
            Text(item.published ? "Published to learners" : "Not published yet").font(.caption)
              .foregroundStyle(.secondary)
          }
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
      if !trainer, let status = detail.assessmentStatus, !status.isEmpty {
        LabeledContent("Result", value: status)
      }
    } header: {
      Text("Assessments")
    }
  }

  @ViewBuilder private func roster(_ detail: ClassDetail) -> some View {
    Section {
      NavigationLink {
        GradingView(courseID: course.id)
      } label: {
        Label("Review and grade learners (\(detail.roster?.count ?? 0))", systemImage: "checkmark.seal")
      }.accessibilityIdentifier("grading")
    } header: {
      Text("Learners")
    }
  }

  @ViewBuilder private func surveys(_ detail: ClassDetail) -> some View {
    Section {
      if !trainer, let feedback = detail.feedback {
        if let external = feedback.externalURL {
          MaterialLink(title: "Course feedback form", icon: "star.bubble", raw: external)
        } else if feedback.submitted {
          Label("Course feedback sent. Thank you.", systemImage: "checkmark.circle.fill")
            .foregroundStyle(Theme.accent)
        } else if feedback.enabled {
          NavigationLink {
            CourseFeedbackView(courseID: course.id) { Task { await load() } }
          } label: {
            Label("Give course feedback", systemImage: "star.bubble")
          }.accessibilityIdentifier("course-feedback")
        }
      }
      if trainer, let count = detail.feedbackCount {
        LabeledContent("Course feedback received", value: "\(count)")
      }
      if let traqom = detail.traqomURL {
        MaterialLink(title: "TRAQOM survey", icon: "list.clipboard", raw: traqom)
      }
    } header: {
      Text("Feedback & TRAQOM")
    } footer: {
      Text("TRAQOM is the SkillsFuture Singapore training quality survey. It opens in the browser.")
    }
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
/// in the app; anything else falls back to the in-app browser.
struct DocumentViewer: View {
  @EnvironmentObject var store: Store
  @Environment(\.dismiss) var dismiss
  let title: String
  let url: URL
  @State private var document: PDFDocument?
  @State private var useBrowser = false
  @State private var loading = true

  var body: some View {
    if useBrowser {
      Browser(url: url).ignoresSafeArea()
    } else {
      NavigationStack {
        Group {
          if let document {
            PDFReader(document: document)
          } else {
            ProgressView("Opening \(title)…")
          }
        }
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
          ToolbarItem(placement: .primaryAction) {
            Button {
              useBrowser = true
            } label: {
              Label("Open in browser", systemImage: "safari")
            }
          }
        }
      }
      .task { await open() }
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
      useBrowser = true
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
        useBrowser = true
        return
      }
      document = pdf
    } catch {
      useBrowser = true
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

struct QRCodeSheet: View {
  @Environment(\.dismiss) var dismiss
  let title: String
  let text: String

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
      VStack(spacing: 20) {
        Text("Scan to check in").font(.title2.bold())
        if let image {
          Image(uiImage: image).interpolation(.none).resizable().scaledToFit()
            .padding(16).background(.white, in: RoundedRectangle(cornerRadius: 20))
            .frame(maxWidth: 420)
            .accessibilityLabel("Check-in QR code for \(title)")
        }
        Text(title).font(.headline)
        Text("Keep this screen open while learners scan it.").font(.footnote).foregroundStyle(
          .secondary)
        Button("Close QR code") { dismiss() }.buttonStyle(.bordered)
          .accessibilityIdentifier("close-qr")
      }
      .padding(24)
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
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

// MARK: - Profile

struct ProfileEditor: View {
  @EnvironmentObject var store: Store
  @Environment(\.dismiss) var dismiss
  @State private var name = ""
  @State private var phone = ""
  @State private var company = ""
  @State private var employment = ""
  @State private var linkedin = ""
  @State private var saving = false
  @State private var problem: String?

  var body: some View {
    Form {
      Section("Your details") {
        TextField("Full name", text: $name).textContentType(.name)
          .accessibilityIdentifier("profile-name")
        LabeledContent("Email", value: store.profile?.email ?? store.user?.email ?? "")
        TextField("Phone number", text: $phone).keyboardType(.phonePad).textContentType(
          .telephoneNumber)
      }
      if store.roles.contains("learner") {
        Section("Work") {
          TextField("Company", text: $company)
          Picker("Employment status", selection: $employment) {
            Text("Not set").tag("")
            ForEach(["Employed", "Unemployed", "Looking for Job"], id: \.self) { Text($0).tag($0) }
          }
        }
      }
      if store.roles.contains("trainer") {
        Section("Trainer profile") {
          TextField("LinkedIn link (https://…)", text: $linkedin).keyboardType(.URL)
            .textInputAutocapitalization(.never).autocorrectionDisabled()
        }
      }
      Section {
        Button {
          Task { await save() }
        } label: {
          Text(saving ? "Saving…" : "Save profile").frame(maxWidth: .infinity)
        }.buttonStyle(.borderedProminent).disabled(saving || name.count < 2)
          .accessibilityIdentifier("save-profile")
      } footer: {
        Text("To change your email address or NRIC, contact your academy.")
      }
    }
    .navigationTitle("Edit profile").navigationBarTitleDisplayMode(.inline)
    .onAppear {
      name = store.profile?.fullName ?? store.user?.fullName ?? ""
      phone = store.profile?.phone ?? ""
      company = store.profile?.company ?? ""
      employment = store.profile?.employmentStatus ?? ""
      linkedin = store.profile?.linkedinURL ?? ""
    }
    .alert(
      "Profile", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })
    ) {
      Button("OK") { problem = nil }
    } message: {
      Text(problem ?? "")
    }
  }

  private func save() async {
    saving = true
    defer { saving = false }
    var fields: [String: Any] = ["fullName": name, "phone": phone]
    if store.roles.contains("learner") {
      fields["company"] = company
      fields["employmentStatus"] = employment
    }
    if store.roles.contains("trainer") { fields["linkedinURL"] = linkedin }
    if let message = await store.saveProfile(fields) {
      problem = message
    } else {
      dismiss()
    }
  }
}

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
