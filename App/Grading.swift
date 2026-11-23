import SwiftUI

// Assessment Grading for the class trainer, in the website's grading-roster form, through the
// website's own routes (each checks that the caller trains this class):
//   GET  /api/trainer/class-students?courseRunId=&withMeta=1   roster + assessment methods
//   POST /api/trainer/grade-student     {enrolmentIds, source, isCompetent}
//   POST /api/trainer/traqom-status     {enrolmentIds, completed}   (SSG gives no completion feed)
//   POST /api/trainer/sign-assessments  {courseRunId, learnerUserIds, signed}
//        stamps the assessor signature on every file the learner submitted (WA and PP)

struct RosterStudent: Decodable, Identifiable, Hashable {
  var id: String { enrolment_id }
  let enrolment_id: String
  let user_id: String?
  let student_name: String
  let competent_status: String?
  let source: String?
  let is_competent: Bool?
  let submitted_assessments: [String]?
  var traqom_completed: Bool?
  let submission_count: Int?
  var assessor_signed: Bool?
  let assessment_folder_url: String?
  let enrolment_ids: [String]?
  let user_ids: [String]?

  var enrolmentIDs: [String] { (enrolment_ids?.isEmpty == false ? enrolment_ids : nil) ?? [enrolment_id] }
  var userIDs: [String] { (user_ids?.isEmpty == false ? user_ids : nil) ?? [user_id].compactMap { $0 } }
  func submitted(_ method: String) -> Bool { submitted_assessments?.contains(method) == true }
  var hasSubmissions: Bool { (submission_count ?? 0) > 0 || !(submitted_assessments ?? []).isEmpty }
}
struct RosterReply: Decodable {
  let students: [RosterStudent]
  let assessment_methods: [String]?
}

enum AssessmentMethod {
  static let info: [String: (abbr: String, label: String)] = [
    "writtenAssessment": ("WA", "Written Assessment"),
    "practicalExam": ("PP", "Practical Performance"),
    "caseStudy": ("CS", "Case Study"),
    "rolePlay": ("RP", "Role Play"),
    "oralQuestioning": ("OQ", "Oral Questioning"),
    "project": ("PJ", "Project"),
    "assignment": ("AS", "Assignment"),
  ]
  static func abbr(_ m: String) -> String { info[m]?.abbr ?? m }
  static func label(_ m: String) -> String { info[m]?.label ?? m }
}

struct GradingView: View {
  @EnvironmentObject var store: Store
  let courseID: String
  @State private var students: [RosterStudent]?
  @State private var methods: [String] = ["writtenAssessment", "practicalExam"]
  @State private var problem: String?
  @State private var busy: Set<String> = []
  @State private var pendingGrade: (student: RosterStudent, competent: Bool)?
  @State private var pendingUnsign: RosterStudent?
  @State private var signing: [RosterStudent] = []
  @State private var showSign = false

  var body: some View {
    List {
      if let students {
        Section {
          LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
            ForEach(methods, id: \.self) { m in
              HoursTile(label: "\(AssessmentMethod.abbr(m)) submitted", value: "\(students.filter { $0.submitted(m) }.count)/\(students.count)")
            }
            HoursTile(label: "TRAQOM done", value: "\(students.filter { $0.traqom_completed == true }.count)/\(students.count)")
            HoursTile(label: "Signed", value: "\(students.filter { $0.assessor_signed == true }.count)/\(students.count)")
            HoursTile(label: "Competent", value: "\(students.filter { $0.is_competent == true }.count)/\(students.count)", strong: true)
          }
          .padding(.vertical, 4)
          let unsigned = students.filter { $0.hasSubmissions && $0.assessor_signed != true && !$0.userIDs.isEmpty }
          if unsigned.count > 1 {
            Button {
              signing = unsigned
              showSign = true
            } label: {
              Label("Sign all \(unsigned.count) submitted", systemImage: "signature")
                .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent).tint(Theme.accent).disabled(!busy.isEmpty)
            .accessibilityIdentifier("sign-all-submissions")
          }
        } footer: {
          Text(methods.map { "\(AssessmentMethod.abbr($0)) = \(AssessmentMethod.label($0))" }.joined(separator: " · ")
            + " · Signed = your assessor signature stamped on the learner's submitted files. TRAQOM is ticked by you: SSG does not report completion.")
        }
        if students.isEmpty {
          Label("No learners on this class yet", systemImage: "person.2.slash").foregroundStyle(.secondary)
        }
        ForEach(students) { s in row(s) }
      } else if let problem {
        Label(problem, systemImage: "wifi.exclamationmark").foregroundStyle(.secondary)
        Button("Try again") { Task { await load() } }
      } else {
        ProgressView()
      }
    }
    .navigationTitle("Assessment Grading").navigationBarTitleDisplayMode(.inline)
    .task { await load() }
    .refreshable { await load() }
    .sheet(isPresented: $showSign) {
      SignatureSetupSheet(
        kind: .assessor, signing: true, count: signing.count,
        what: "every file the learner submitted", title: "Sign Assessments"
      ) { saved in
        showSign = false
        let list = signing
        signing = []
        if saved { Task { await sign(list, true) } }
      }
      .environmentObject(store)
    }
    .confirmationDialog(
      pendingGrade.map { "Mark \($0.student.student_name) as \($0.competent ? "Competent" : "Not Yet Competent")?" } ?? "",
      isPresented: Binding(get: { pendingGrade != nil }, set: { if !$0 { pendingGrade = nil } }),
      titleVisibility: .visible
    ) {
      Button("Confirm result") {
        guard let choice = pendingGrade else { return }
        Task { await grade(choice.student, choice.competent) }
      }
    } message: {
      Text("Review the learner's submitted files before confirming.")
    }
    .confirmationDialog(
      "Remove your signature from \(pendingUnsign?.student_name ?? "")'s files?",
      isPresented: Binding(get: { pendingUnsign != nil }, set: { if !$0 { pendingUnsign = nil } }),
      titleVisibility: .visible
    ) {
      Button("Remove signature", role: .destructive) {
        guard let s = pendingUnsign else { return }
        Task { await sign([s], false) }
      }
    } message: {
      Text("The original files are restored.")
    }
  }

  private func row(_ s: RosterStudent) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline) {
        Text(s.student_name).font(.headline)
        Spacer()
        if busy.contains(s.id) { ProgressView() }
      }
      // Submission status per assessment, e.g. ☑ WA ☐ PP (read-only).
      HStack(spacing: 14) {
        ForEach(methods, id: \.self) { m in
          Label(AssessmentMethod.abbr(m), systemImage: s.submitted(m) ? "checkmark.square.fill" : "square")
            .foregroundStyle(s.submitted(m) ? Color.green : Color.secondary)
            .accessibilityLabel("\(AssessmentMethod.label(m)): \(s.submitted(m) ? "submitted" : "not submitted")")
        }
        Spacer()
        if let folder = s.assessment_folder_url, !folder.isEmpty {
          Link(destination: URL(string: folder) ?? URL(string: "https://drive.google.com")!) {
            Label("Files", systemImage: "folder")
          }
          .font(.subheadline)
        }
      }
      .font(.subheadline.weight(.semibold))
      // Trainer ticks: TRAQOM done, and the assessor signature on both assessments.
      HStack(spacing: 10) {
        CheckChip(
          title: "TRAQOM done", on: s.traqom_completed == true, enabled: !busy.contains(s.id)
        ) { Task { await setTraqom(s, !(s.traqom_completed == true)) } }
        .accessibilityIdentifier("traqom-\(s.id)")
        CheckChip(
          title: "Signed", on: s.assessor_signed == true,
          enabled: !busy.contains(s.id) && s.hasSubmissions && !s.userIDs.isEmpty
        ) {
          if s.assessor_signed == true {
            pendingUnsign = s
          } else {
            signing = [s]
            showSign = true
          }
        }
        .accessibilityIdentifier("sign-\(s.id)")
      }
      HStack {
        Button("Competent") { pendingGrade = (s, true) }
          .buttonStyle(.borderedProminent).tint(.green).disabled(s.is_competent == true || busy.contains(s.id))
        Button("Not Yet Competent") { pendingGrade = (s, false) }
          .buttonStyle(.bordered).disabled((s.is_competent == false && (s.competent_status ?? "").localizedCaseInsensitiveContains("not")) || busy.contains(s.id))
      }
      Text(s.competent_status?.isEmpty == false ? "Result: \(s.competent_status!)" : "Result: not graded")
        .font(.caption).foregroundStyle(.secondary)
    }
    .buttonStyle(.borderless)
    .padding(.vertical, 6)
  }

  // MARK: Actions

  private func update(_ id: String, _ change: (inout RosterStudent) -> Void) {
    guard let i = students?.firstIndex(where: { $0.id == id }) else { return }
    change(&students![i])
  }

  private func load() async {
    if store.demo {
      if students == nil {
        students = [
          RosterStudent(enrolment_id: "d1", user_id: "u1", student_name: "Jamie Lim (sample)", competent_status: "", source: "manual",
                        is_competent: false, submitted_assessments: ["writtenAssessment", "practicalExam"], traqom_completed: false,
                        submission_count: 2, assessor_signed: false, assessment_folder_url: nil, enrolment_ids: nil, user_ids: nil),
          RosterStudent(enrolment_id: "d2", user_id: "u2", student_name: "Priya Nair (sample)", competent_status: "Competent", source: "manual",
                        is_competent: true, submitted_assessments: ["writtenAssessment", "practicalExam"], traqom_completed: true,
                        submission_count: 2, assessor_signed: true, assessment_folder_url: nil, enrolment_ids: nil, user_ids: nil),
          RosterStudent(enrolment_id: "d3", user_id: "u3", student_name: "Wei Ming (sample)", competent_status: "", source: "manual",
                        is_competent: false, submitted_assessments: ["writtenAssessment"], traqom_completed: false,
                        submission_count: 1, assessor_signed: false, assessment_folder_url: nil, enrolment_ids: nil, user_ids: nil),
        ]
      }
      return
    }
    do {
      let reply: RosterReply = try await API.shared.request(
        "trainer/class-students", query: ["courseRunId": courseID, "withMeta": "1"])
      students = reply.students
      if let m = reply.assessment_methods, !m.isEmpty { methods = m }
      problem = nil
    } catch { problem = error.localizedDescription }
  }

  private func grade(_ s: RosterStudent, _ competent: Bool) async {
    if store.demo {
      update(s.id) { _ in }
      return
    }
    busy.insert(s.id)
    defer { busy.remove(s.id) }
    do {
      let _: EmptyReply = try await API.shared.request(
        "trainer/grade-student", method: "POST",
        body: ["enrolmentIds": s.enrolmentIDs, "source": s.source ?? "manual", "isCompetent": competent])
      await load()
    } catch { problem = error.localizedDescription }
  }

  private func setTraqom(_ s: RosterStudent, _ done: Bool) async {
    update(s.id) { $0.traqom_completed = done }
    if store.demo { return }
    busy.insert(s.id)
    defer { busy.remove(s.id) }
    do {
      let _: EmptyReply = try await API.shared.request(
        "trainer/traqom-status", method: "POST", body: ["enrolmentIds": s.enrolmentIDs, "completed": done])
    } catch {
      update(s.id) { $0.traqom_completed = !done }
      problem = error.localizedDescription
    }
  }

  private func sign(_ list: [RosterStudent], _ signed: Bool) async {
    for s in list {
      if store.demo {
        update(s.id) { $0.assessor_signed = signed }
        continue
      }
      busy.insert(s.id)
      do {
        let _: EmptyReply = try await API.shared.request(
          "trainer/sign-assessments", method: "POST",
          body: ["courseRunId": courseID, "learnerUserIds": s.userIDs, "signed": signed])
        update(s.id) { $0.assessor_signed = signed }
      } catch {
        problem = error.localizedDescription
        busy.remove(s.id)
        break
      }
      busy.remove(s.id)
    }
  }
}

/// A tappable checkbox chip, e.g. "☑ TRAQOM done".
struct CheckChip: View {
  let title: String
  let on: Bool
  var enabled = true
  let action: () -> Void
  var body: some View {
    Button(action: action) {
      Label(title, systemImage: on ? "checkmark.square.fill" : "square")
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 10).padding(.vertical, 6)
        .foregroundStyle(on ? Color.green : Theme.accent)
        .background((on ? Color.green : Theme.accent).opacity(0.1), in: Capsule())
    }
    .buttonStyle(.borderless)
    .disabled(!enabled)
    .opacity(enabled ? 1 : 0.5)
    .accessibilityValue(on ? "Checked" : "Unchecked")
  }
}
