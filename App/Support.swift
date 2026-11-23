import SwiftUI

// Learner Support tab and the trainer's credentials, through the mobile API:
//   GET/POST /api/mobile/support           contacts; feedback emailed to the academy
//   GET/POST /api/mobile/trainer-profile   ACLP / DDDPL / TAEPP, domain expertise, skill tags

// MARK: - Support

struct SupportInfo: Decodable {
  let email: String?
  let phone: String?
  let whatsapp: String?
  let address: String?
  let feedback: Bool?
}

/// Support: a feedback form emailed to the academy, then the ways to reach it directly.
struct SupportView: View {
  @EnvironmentObject var store: Store
  @State private var info: SupportInfo?
  @State private var subject = ""
  @State private var message = ""
  @State private var sending = false
  @State private var notice: String?
  @State private var problem: String?

  private static let sample = SupportInfo(
    email: "enquiry@tertiaryinfotech.com", phone: "61000613", whatsapp: "+65 8866 6375",
    address: "12 Woodlands Square, Woods Square Tower 1, Singapore 737715", feedback: true)

  private static func digits(_ s: String) -> String {
    let d = s.filter(\.isNumber)
    return d.count == 8 ? "65" + d : d
  }

  var body: some View {
    List {
      Section {
        TextField("Subject", text: $subject).accessibilityIdentifier("support-subject")
        TextField("How can we help? Tell us what happened.", text: $message, axis: .vertical)
          .lineLimit(4...10).accessibilityIdentifier("support-message")
        Button {
          Task { await send() }
        } label: {
          Text(sending ? "Sending…" : "Send feedback").font(.headline).frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent).tint(Theme.accent)
        .disabled(
          sending || subject.trimmingCharacters(in: .whitespaces).isEmpty
            || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .accessibilityIdentifier("support-send")
        if let notice { Label(notice, systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.subheadline) }
        if let problem { Text(problem).font(.footnote).foregroundStyle(.red) }
      } header: {
        Text("Feedback")
      } footer: {
        Text("Your message is emailed to the academy with your name and email, so we can reply.")
      }

      if let info {
        Section("Contact us") {
          if let email = info.email {
            ContactRow(icon: "envelope.fill", title: "Email", value: email, url: URL(string: "mailto:" + email))
          }
          if let phone = info.phone {
            ContactRow(icon: "phone.fill", title: "Tel", value: phone, url: URL(string: "tel:+" + Self.digits(phone)))
          }
          if let wa = info.whatsapp {
            ContactRow(
              icon: "message.fill", title: "WhatsApp", value: wa,
              url: URL(string: "https://wa.me/" + Self.digits(wa)))
          }
        }
        if let address = info.address {
          Section("Address") { VenueLink(address: address) }
        }
      } else {
        Section { ProgressView() }
      }
    }
    .navigationTitle("Support").navigationBarTitleDisplayMode(.inline)
    .brandToolbar()
    .task { if info == nil { await load() } }
  }

  private func load() async {
    if store.demo {
      info = Self.sample
      return
    }
    info = (try? await API.shared.request("mobile/support")) ?? Self.sample
  }

  private func send() async {
    notice = nil
    problem = nil
    if store.demo {
      notice = "Sent (sample). Sign in with your account to send feedback."
      return
    }
    sending = true
    defer { sending = false }
    do {
      let _: EmptyReply = try await API.shared.request(
        "mobile/support", method: "POST", body: ["subject": subject, "message": message])
      subject = ""
      message = ""
      notice = "Thank you. Your feedback has been sent."
    } catch { problem = error.localizedDescription }
  }
}

// MARK: - Trainer credentials

struct TrainerCredentials: Decodable, Equatable {
  var aclp: Bool
  var dddpl: Bool
  var taepp: Bool
  var areasOfExpertise: [String]
  var skillsTags: [String]

  /// The badges to show, in a fixed order.
  var badges: [String] {
    [aclp ? "ACLP" : nil, dddpl ? "DDDPL" : nil, taepp ? "TAEPP" : nil].compactMap { $0 }
  }
}

/// A credential badge, e.g. ACLP.
struct CredentialBadge: View {
  let text: String
  var body: some View {
    Label(text, systemImage: "checkmark.seal.fill")
      .font(.caption.weight(.bold)).foregroundStyle(.white)
      .padding(.horizontal, 10).padding(.vertical, 5)
      .background(Theme.accent, in: Capsule())
      .accessibilityLabel("\(text) certified")
  }
}

/// The trainer's Account sections: badges, the three toggles, domain expertise and skill tags.
struct TrainerCredentialsSections: View {
  @EnvironmentObject var store: Store
  @State private var creds: TrainerCredentials?
  @State private var problem: String?
  @State private var newExpertise = ""
  @State private var newSkill = ""

  var body: some View {
    if let creds {
      Section {
        if !creds.badges.isEmpty {
          FlowLayout(spacing: 6) {
            ForEach(creds.badges, id: \.self) { CredentialBadge(text: $0) }
          }
          .padding(.vertical, 2)
        }
        toggle("ACLP", "Advanced Certificate in Learning and Performance", \.aclp, "aclp")
        toggle("DDDPL", "Diploma in Design and Development of Learning for Performance", \.dddpl, "dddpl")
        toggle("TAEPP", "Training and Adult Education Professional Pathway", \.taepp, "taepp")
        if let problem { Text(problem).font(.footnote).foregroundStyle(.red) }
      } header: {
        Text("Trainer credentials")
      } footer: {
        Text("Turn on the credentials you hold. They show as badges on your profile.")
      }
      tagSection(
        "Domain expertise", "Add a domain, e.g. AI, Cybersecurity", \.areasOfExpertise,
        "areasOfExpertise", $newExpertise)
      tagSection("Skill tags", "Add a skill, e.g. Python, Power BI", \.skillsTags, "skillsTags", $newSkill)
    } else {
      // The first row carries the load so it runs once.
      Section("Trainer credentials") {
        if let problem {
          Text(problem).font(.footnote).foregroundStyle(.secondary)
        } else {
          ProgressView()
        }
      }
      .task { await load() }
    }
  }

  private func toggle(
    _ title: String, _ subtitle: String, _ key: WritableKeyPath<TrainerCredentials, Bool>, _ field: String
  ) -> some View {
    Toggle(
      isOn: Binding(
        get: { creds?[keyPath: key] ?? false },
        set: { value in
          creds?[keyPath: key] = value
          Task { await save([field: value]) }
        })
    ) {
      VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.body.weight(.semibold))
        Text(subtitle).font(.caption).foregroundStyle(.secondary)
      }
    }
    .tint(Theme.accent)
    .accessibilityIdentifier("credential-\(field)")
  }

  private func tagSection(
    _ title: String, _ prompt: String, _ key: WritableKeyPath<TrainerCredentials, [String]>,
    _ field: String, _ text: Binding<String>
  ) -> some View {
    Section(title) {
      let items = creds?[keyPath: key] ?? []
      if !items.isEmpty {
        FlowLayout(spacing: 6) {
          ForEach(items, id: \.self) { tag in
            Button {
              var next = items
              next.removeAll { $0 == tag }
              creds?[keyPath: key] = next
              Task { await save([field: next]) }
            } label: {
              HStack(spacing: 4) {
                Text(tag)
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
              }
              .font(.subheadline).padding(.horizontal, 10).padding(.vertical, 5)
              .background(Theme.accentSoft, in: Capsule())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Remove \(tag)")
          }
        }
        .padding(.vertical, 2)
      }
      HStack {
        TextField(prompt, text: text).submitLabel(.done)
          .onSubmit { add(text, key, field) }
          .accessibilityIdentifier("add-\(field)")
        Button("Add") { add(text, key, field) }
          .buttonStyle(.borderless)
          .disabled(text.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty)
      }
    }
  }

  private func add(
    _ text: Binding<String>, _ key: WritableKeyPath<TrainerCredentials, [String]>, _ field: String
  ) {
    let tag = text.wrappedValue.trimmingCharacters(in: .whitespaces)
    guard !tag.isEmpty, var next = creds?[keyPath: key] else { return }
    guard !next.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) else {
      text.wrappedValue = ""
      return
    }
    next.append(tag)
    creds?[keyPath: key] = next
    text.wrappedValue = ""
    Task { await save([field: next]) }
  }

  private func load() async {
    if store.demo {
      creds = TrainerCredentials(
        aclp: true, dddpl: false, taepp: false, areasOfExpertise: ["AI"], skillsTags: ["Python"])
      return
    }
    do {
      creds = try await API.shared.request("mobile/trainer-profile")
      problem = nil
    } catch { problem = error.localizedDescription }
  }

  private func save(_ body: [String: Any]) async {
    if store.demo { return }
    do {
      creds = try await API.shared.request("mobile/trainer-profile", method: "POST", body: body)
      problem = nil
    } catch {
      problem = error.localizedDescription
      await load()
    }
  }
}
