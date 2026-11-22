import SwiftUI
import UIKit

// Assessment Summary Record e-signing on the phone, with the website's own APIs:
//   /api/assessments/summary-record   read the record(s); sign as candidate or assessor
//   /api/learner/signature            the learner's saved name, NRIC and drawn signature
//   /api/trainer/assessor-signature   the trainer's saved assessor name, NRIC and signature
// The server stamps the signature onto the record's PDF and returns the Drive link.

// MARK: - Models

struct SummaryParty: Decodable, Hashable {
  let name: String?
  let signDate: String?
  let signedAt: String?
}
struct SummaryFile: Decodable, Hashable {
  let url: String
  let name: String?
}
struct SummaryRecordView: Decodable, Hashable {
  let learner: SummaryParty?
  let trainer: SummaryParty?
  let file: SummaryFile?
}
struct LearnerSummaryStatus: Decodable, Identifiable, Hashable {
  var id: String { learnerUserId }
  let learnerUserId: String
  let learnerName: String
  let record: SummaryRecordView?
}
struct SummaryRunInfo: Decodable {
  let hasTemplate: Bool?
}
struct SummaryReply: Decodable {
  let run: SummaryRunInfo?
  let record: SummaryRecordView?
  let learners: [LearnerSummaryStatus]?
  let hasSignature: Bool?
}
struct SignReply: Decodable {
  let success: Bool?
  let fileUrl: String?
  let generationError: String?
}
/// Saved signer details. The learner and assessor endpoints name the fields differently.
struct SignerRecord: Decodable {
  let learner_name: String?
  let assessor_name: String?
  let nric: String?
  let signature_png: String?
  var name: String { learner_name ?? assessor_name ?? "" }
}
struct SignerReply: Decodable {
  let exists: Bool?
  let data: SignerRecord?
}

enum SignerKind {
  case learner, assessor
  var path: String { self == .learner ? "learner/signature" : "trainer/assessor-signature" }
  var title: String { self == .learner ? "Your signature" : "Assessor signature" }
  var nameLabel: String { self == .learner ? "Full name (as in NRIC)" : "Assessor name" }
}

private func fmtDay(_ raw: String?) -> String {
  guard let raw, !raw.isEmpty else { return "" }
  return Fmt.longDate(String(raw.prefix(10)))
}

// MARK: - Learner: sign my record

/// The learner's Assessment Summary Record: their Candidate signature, the assessor's, and the PDF.
struct LearnerSummaryRecordView: View {
  @EnvironmentObject var store: Store
  let runID: String
  let assessmentStatus: String?
  @State private var reply: SummaryReply?
  @State private var busy = false
  @State private var problem: String?
  @State private var setup = false

  var body: some View {
    Group {
      LabeledContent("Assessment Result", value: assessmentStatus ?? "Pending")
      if let reply {
        let record = reply.record
        SignedRow(title: "Candidate (you)", party: record?.learner)
        SignedRow(title: "Assessor", party: record?.trainer)
        if record?.learner == nil {
          Button {
            Task { await signTapped() }
          } label: {
            Label(busy ? "Signing…" : "Sign my Assessment Summary Record", systemImage: "signature")
              .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
          }
          .buttonStyle(.borderedProminent).tint(Theme.accent).disabled(busy)
          .accessibilityIdentifier("sign-summary-record")
        }
        if let file = record?.file {
          MaterialLink(title: "Open signed record (PDF)", icon: "doc.richtext", raw: file.url)
        }
        Button("Change my saved signature") { setup = true }.font(.footnote).buttonStyle(.borderless)
      } else if problem == nil {
        ProgressView()
      }
      if let problem {
        Text(problem).font(.footnote).foregroundStyle(.red)
      }
    }
    .task { await load() }
    .sheet(isPresented: $setup) {
      SignatureSetupSheet(kind: .learner) { saved in
        setup = false
        if saved { Task { await sign() } }
      }
    }
  }

  private func load() async {
    guard !store.demo else {
      reply = SummaryReply(run: nil, record: nil, learners: nil, hasSignature: false)
      return
    }
    do {
      reply = try await API.shared.request(
        "assessments/summary-record", query: ["courseRunId": runID, "view": "learner"])
      problem = nil
    } catch { problem = error.localizedDescription }
  }

  private func signTapped() async {
    if store.demo {
      problem = "Signing is available when you sign in with your account."
      return
    }
    if reply?.hasSignature == true { await sign() } else { setup = true }
  }

  private func sign() async {
    busy = true
    defer { busy = false }
    do {
      let out: SignReply = try await API.shared.request(
        "assessments/summary-record", method: "POST",
        body: ["courseRunId": runID, "party": "learner"])
      problem = out.generationError.map { "Signed. The PDF will follow: \($0)" }
      await load()
    } catch {
      // 409: no saved signature yet, so set it up first.
      if error.localizedDescription.localizedCaseInsensitiveContains("signature") {
        setup = true
      } else {
        problem = error.localizedDescription
      }
    }
  }
}

// MARK: - Trainer: sign every learner's record

/// The trainer's Assessment Summary Record: one row per learner with both signatures.
struct TrainerSummaryRecordView: View {
  @EnvironmentObject var store: Store
  let runID: String
  @State private var learners: [LearnerSummaryStatus]?
  @State private var busy: Set<String> = []
  @State private var problem: String?
  @State private var setup = false
  @State private var pending: [String] = []

  private var awaitingMe: [LearnerSummaryStatus] {
    (learners ?? []).filter { $0.record?.trainer == nil }
  }

  var body: some View {
    Group {
      if let learners {
        let signedByLearner = learners.filter { $0.record?.learner != nil }.count
        let signedByMe = learners.filter { $0.record?.trainer != nil }.count
        HStack(spacing: 8) {
          HoursTile(label: "Learners", value: "\(learners.count)")
          HoursTile(label: "Candidate signed", value: "\(signedByLearner)")
          HoursTile(label: "Assessor signed", value: "\(signedByMe)", strong: true)
        }
        .padding(.vertical, 4)
        if awaitingMe.count > 1 {
          Button {
            Task { await signTapped(awaitingMe.map(\.learnerUserId)) }
          } label: {
            Label("Sign all \(awaitingMe.count) as assessor", systemImage: "signature")
              .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
          }
          .buttonStyle(.borderedProminent).tint(Theme.accent).disabled(!busy.isEmpty)
          .accessibilityIdentifier("sign-all-summary")
        }
        if learners.isEmpty {
          Text("No learners on this class yet.").font(.subheadline).foregroundStyle(.secondary)
        }
        ForEach(learners) { learner in
          TrainerSummaryRow(
            learner: learner, busy: busy.contains(learner.learnerUserId),
            sign: { Task { await signTapped([learner.learnerUserId]) } })
        }
        Button("Change my assessor signature") { setup = true }.font(.footnote)
          .buttonStyle(.borderless)
      } else if problem == nil {
        ProgressView()
      }
      if let problem {
        Text(problem).font(.footnote).foregroundStyle(.red)
      }
    }
    .task { await load() }
    .sheet(isPresented: $setup) {
      SignatureSetupSheet(kind: .assessor) { saved in
        setup = false
        let ids = pending
        pending = []
        if saved, !ids.isEmpty { Task { await sign(ids) } }
      }
    }
  }

  private func load() async {
    guard !store.demo else {
      learners = []
      return
    }
    do {
      let reply: SummaryReply = try await API.shared.request(
        "assessments/summary-record", query: ["courseRunId": runID])
      learners = reply.learners ?? []
      problem = nil
    } catch { problem = error.localizedDescription }
  }

  private func signTapped(_ ids: [String]) async {
    // The assessor profile is checked by the server; a missing one asks for setup first.
    await sign(ids)
  }

  private func sign(_ ids: [String]) async {
    for id in ids {
      busy.insert(id)
      defer { busy.remove(id) }
      do {
        let out: SignReply = try await API.shared.request(
          "assessments/summary-record", method: "POST",
          body: ["courseRunId": runID, "learnerUserId": id, "party": "trainer"])
        if let err = out.generationError { problem = "Signed. The PDF will follow: \(err)" }
      } catch {
        if error.localizedDescription.localizedCaseInsensitiveContains("signature")
          || error.localizedDescription.localizedCaseInsensitiveContains("assessor")
        {
          pending = Array(ids.drop { $0 != id })
          setup = true
          return
        }
        problem = error.localizedDescription
        break
      }
    }
    await load()
  }
}

private struct TrainerSummaryRow: View {
  let learner: LearnerSummaryStatus
  let busy: Bool
  let sign: () -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(learner.learnerName).font(.body.weight(.semibold))
      HStack(spacing: 8) {
        StatusChip(
          text: learner.record?.learner != nil ? "Candidate signed" : "Candidate pending",
          color: learner.record?.learner != nil ? .green : .orange)
        StatusChip(
          text: learner.record?.trainer != nil ? "Assessor signed" : "Assessor pending",
          color: learner.record?.trainer != nil ? .green : .orange)
      }
      HStack {
        if let file = learner.record?.file {
          MaterialLink(title: "PDF", icon: "doc.richtext", raw: file.url)
        }
        Spacer()
        if learner.record?.trainer == nil {
          Button(busy ? "Signing…" : "Sign", action: sign)
            .buttonStyle(.bordered).tint(Theme.accent).disabled(busy)
        }
      }
    }
    .padding(.vertical, 4)
  }
}

private struct SignedRow: View {
  let title: String
  let party: SummaryParty?
  var body: some View {
    HStack {
      Text(title)
      Spacer()
      if let party {
        Label("Signed \(fmtDay(party.signDate ?? party.signedAt))", systemImage: "checkmark.seal.fill")
          .foregroundStyle(.green).font(.subheadline)
      } else {
        Text("Not signed").foregroundStyle(.orange).font(.subheadline)
      }
    }
  }
}

// MARK: - Signature setup

/// Name, NRIC and a drawn signature, saved once and reused for every record (as on the website).
struct SignatureSetupSheet: View {
  let kind: SignerKind
  let done: (Bool) -> Void
  @State private var name = ""
  @State private var nric = ""
  @State private var strokes: [[CGPoint]] = []
  @State private var hadSignature = false
  @State private var saving = false
  @State private var problem: String?

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField(kind.nameLabel, text: $name).textContentType(.name)
            .textInputAutocapitalization(.characters)
          TextField("NRIC / FIN", text: $nric).textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
        } footer: {
          Text("Printed on the Assessment Summary Record beside your signature.")
        }
        Section {
          SignaturePad(strokes: $strokes)
            .frame(height: 180)
            .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
          Button("Clear", role: .destructive) { strokes = [] }.disabled(strokes.isEmpty)
        } header: {
          Text("Sign with your finger")
        } footer: {
          Text(
            hadSignature && strokes.isEmpty
              ? "Leave blank to keep your saved signature." : "Sign inside the box.")
        }
        if let problem {
          Text(problem).foregroundStyle(.red).font(.footnote)
        }
      }
      .navigationTitle(kind.title).navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { done(false) } }
        ToolbarItem(placement: .confirmationAction) {
          Button(saving ? "Saving…" : "Save") { Task { await save() } }
            .disabled(saving || name.trimmingCharacters(in: .whitespaces).isEmpty
              || (strokes.isEmpty && !hadSignature))
        }
      }
      .task { await load() }
    }
    .interactiveDismissDisabled(saving)
  }

  private func load() async {
    if let reply: SignerReply = try? await API.shared.request(kind.path) {
      name = reply.data?.name ?? ""
      nric = reply.data?.nric ?? ""
      hadSignature = (reply.data?.signature_png ?? "").isEmpty == false
    }
  }

  private func save() async {
    saving = true
    defer { saving = false }
    var body: [String: Any] = ["name": name, "nric": nric]
    if kind == .assessor { body["signDate"] = String(ISO8601DateFormatter().string(from: Date()).prefix(10)) }
    if !strokes.isEmpty {
      guard let png = SignaturePad.png(strokes) else {
        problem = "The signature could not be read. Please sign again."
        return
      }
      body["signaturePng"] = "data:image/png;base64," + png.base64EncodedString()
    }
    do {
      let _: EmptyReply = try await API.shared.request(kind.path, method: "POST", body: body)
      done(true)
    } catch { problem = error.localizedDescription }
  }
}

/// A finger-drawn signature. Strokes are kept as points so the PNG is drawn at the website's
/// pad size (560 × 180), dark ink on a clear background.
struct SignaturePad: View {
  @Binding var strokes: [[CGPoint]]
  @State private var drawing = false

  static let output = CGSize(width: 560, height: 180)

  var body: some View {
    GeometryReader { geo in
      ZStack {
        RoundedRectangle(cornerRadius: 12).fill(Color.white)
        RoundedRectangle(cornerRadius: 12).strokeBorder(Color.secondary.opacity(0.4), style: .init(lineWidth: 1, dash: [5]))
        if strokes.isEmpty {
          Text("Sign here").foregroundStyle(.secondary.opacity(0.6))
        }
      }
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { value in
            let p = CGPoint(
              x: min(max(value.location.x, 0), geo.size.width) / max(geo.size.width, 1),
              y: min(max(value.location.y, 0), geo.size.height) / max(geo.size.height, 1))
            if !drawing {
              drawing = true
              strokes.append([])
            }
            strokes[strokes.count - 1].append(p)
          }
          .onEnded { _ in drawing = false }
      )
      // Strokes are stored 0…1 so the drawing survives a size change; draw them scaled.
      .overlay {
        Path { path in
          for stroke in strokes {
            guard let first = stroke.first else { continue }
            path.move(to: CGPoint(x: first.x * geo.size.width, y: first.y * geo.size.height))
            for p in stroke.dropFirst() {
              path.addLine(to: CGPoint(x: p.x * geo.size.width, y: p.y * geo.size.height))
            }
          }
        }
        .stroke(Color.black, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        .allowsHitTesting(false)
      }
      .accessibilityLabel("Signature pad")
    }
  }

  /// The strokes as a PNG at the website's pad size.
  static func png(_ strokes: [[CGPoint]]) -> Data? {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = false
    let image = UIGraphicsImageRenderer(size: output, format: format).image { ctx in
      let c = ctx.cgContext
      c.setStrokeColor(UIColor.black.cgColor)
      c.setLineWidth(3)
      c.setLineCap(.round)
      c.setLineJoin(.round)
      for stroke in strokes {
        guard let first = stroke.first else { continue }
        c.move(to: CGPoint(x: first.x * output.width, y: first.y * output.height))
        if stroke.count == 1 {
          c.addLine(to: CGPoint(x: first.x * output.width + 0.5, y: first.y * output.height))
        }
        for p in stroke.dropFirst() {
          c.addLine(to: CGPoint(x: p.x * output.width, y: p.y * output.height))
        }
      }
      c.strokePath()
    }
    return image.pngData()
  }
}

// MARK: - Trainer: publish an assessment

/// The website's Publish switch for one assessment of the class (PUT /api/assessments/publish-link).
/// Published assessments open for the learners to submit.
struct PublishToggle: View {
  @EnvironmentObject var store: Store
  let runID: String
  let item: Assessment
  let changed: () -> Void
  @State private var on: Bool? = nil
  @State private var busy = false
  @State private var problem: String?

  var body: some View {
    let isOn = on ?? item.published
    VStack(alignment: .leading, spacing: 4) {
      Toggle(isOn: Binding(get: { isOn }, set: { value in Task { await set(value) } })) {
        VStack(alignment: .leading, spacing: 3) {
          Text(item.label)
          Text(busy ? "Saving…" : isOn ? "Published to learners" : "Not published yet")
            .font(.caption).foregroundStyle(isOn ? .green : .secondary)
        }
      }
      .tint(.green).disabled(busy)
      .accessibilityIdentifier("publish-\(item.type)")
      if let problem { Text(problem).font(.caption).foregroundStyle(.red) }
    }
  }

  private func set(_ value: Bool) async {
    if store.demo {
      on = value
      return
    }
    busy = true
    defer { busy = false }
    let previous = on ?? item.published
    on = value
    do {
      let _: EmptyReply = try await API.shared.request(
        "assessments/publish-link", method: "PUT",
        body: ["courseRunId": runID, "field": item.type, "published": value])
      // The written and practical papers also carry an older per-class flag; keep it in step
      // so unpublishing really hides the paper.
      if let legacy = ["writtenAssessment": "written", "practicalExam": "practical"][item.type] {
        let _: EmptyReply = try await API.shared.request(
          "assessments/publish-link", method: "PUT",
          body: ["courseRunId": runID, "field": legacy, "published": value])
      }
      problem = nil
      changed()
    } catch {
      on = previous
      problem = error.localizedDescription
    }
  }
}
