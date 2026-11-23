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
      // .task and .sheet sit on this one row: on a Group they would be copied onto every row.
      LabeledContent("Assessment Result", value: assessmentStatus ?? "Pending")
        .task { await load() }
        .sheet(isPresented: $setup) {
          SignatureSetupSheet(kind: .learner, signing: true) { saved in
            setup = false
            if saved { Task { await sign() } }
          }
          .environmentObject(store)
        }
      if let reply {
        let record = reply.record
        SignedRow(title: "Candidate (you)", party: record?.learner)
        SignedRow(title: "Assessor", party: record?.trainer)
        // Every signature is drawn on the phone at the moment of signing.
        Button {
          setup = true
        } label: {
          Label(
            busy ? "Signing…" : record?.learner == nil ? "Sign my Assessment Summary Record" : "Sign again",
            systemImage: "signature"
          )
          .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent).tint(record?.learner == nil ? Theme.accent : .gray).disabled(busy)
        .accessibilityIdentifier("sign-summary-record")
        if let file = record?.file {
          MaterialLink(title: "Open signed record (PDF)", icon: "doc.richtext", raw: file.url)
        }
      } else if problem == nil {
        ProgressView()
      }
      if let problem {
        Text(problem).font(.footnote).foregroundStyle(.red)
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

  private func sign() async {
    if store.demo {
      problem = "Signed in the sample only. Sign in with your account to sign your record."
      return
    }
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
      // The tiles row is always shown and carries .task and .sheet (a Group would copy them per row).
      HStack(spacing: 8) {
        HoursTile(label: "Learners", value: learners.map { "\($0.count)" } ?? "…")
        HoursTile(label: "Candidate signed", value: learners.map { "\($0.filter { $0.record?.learner != nil }.count)" } ?? "…")
        HoursTile(label: "Assessor signed", value: learners.map { "\($0.filter { $0.record?.trainer != nil }.count)" } ?? "…", strong: true)
      }
      .padding(.vertical, 4)
      .task { await load() }
      .sheet(isPresented: $setup) {
        SignatureSetupSheet(kind: .assessor, signing: true, count: pending.count) { saved in
          setup = false
          let ids = pending
          pending = []
          if saved, !ids.isEmpty { Task { await sign(ids) } }
        }
        .environmentObject(store)
      }
      if let learners {
        if awaitingMe.count > 1 {
          Button {
            pending = awaitingMe.map(\.learnerUserId)
            setup = true
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
            sign: {
              pending = [learner.learnerUserId]
              setup = true
            })
        }
      } else if problem == nil {
        ProgressView()
      }
      if let problem {
        Text(problem).font(.footnote).foregroundStyle(.red)
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

  private func sign(_ ids: [String]) async {
    if store.demo {
      problem = "Signed in the sample only. Sign in with your account to sign records."
      return
    }
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
        Button(busy ? "Signing…" : learner.record?.trainer == nil ? "Sign" : "Sign again", action: sign)
          .buttonStyle(.bordered).tint(learner.record?.trainer == nil ? Theme.accent : .gray).disabled(busy)
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
  @EnvironmentObject var store: Store
  let kind: SignerKind
  /// Signing a record: the signature must be drawn now, and the button reads "Sign".
  var signing = false
  /// How many records this signature goes on (trainer "Sign all").
  var count = 1
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
            signing
              ? "Your signature, name and today's date are stamped on the Assessment Summary Record"
                + (count > 1 ? " of \(count) learners." : ".")
              : hadSignature && strokes.isEmpty
                ? "Leave blank to keep your saved signature." : "Sign inside the box.")
        }
        if let problem {
          Text(problem).foregroundStyle(.red).font(.footnote)
        }
      }
      .navigationTitle(signing ? "Sign Summary Record" : kind.title).navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { done(false) } }
        ToolbarItem(placement: .confirmationAction) {
          Button(saving ? "Saving…" : signing ? "Sign" : "Save") { Task { await save() } }
            .disabled(saving || name.trimmingCharacters(in: .whitespaces).isEmpty
              || (strokes.isEmpty && (signing || !hadSignature)))
            .accessibilityIdentifier("confirm-signature")
        }
      }
      .task { await load() }
    }
    .interactiveDismissDisabled(saving)
  }

  private func load() async {
    // Sample mode has no session: a server call would answer 401 and sign the sample out.
    if store.demo {
      name = kind == .learner ? "Jamie Lim (sample)" : "Alex Tan (sample)"
      return
    }
    if let reply: SignerReply = try? await API.shared.request(kind.path) {
      name = reply.data?.name ?? ""
      nric = reply.data?.nric ?? ""
      hadSignature = (reply.data?.signature_png ?? "").isEmpty == false
    }
  }

  private func save() async {
    if store.demo {
      done(true)
      return
    }
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
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Signature pad")
      .accessibilityHint("Sign with your finger inside the box")
      .accessibilityAddTraits(.allowsDirectInteraction)
      .accessibilityIdentifier("signature-pad")
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
