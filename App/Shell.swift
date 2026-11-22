import SwiftUI

// The signed-in shell: bottom tabs by role, the My Classes home, the single Account page,
// the trainer's Payout tab, and the tabs whose data arrives in a later phase.

// MARK: - Tabs

struct MainView: View {
  @EnvironmentObject var store: Store
  var body: some View {
    VStack(spacing: 0) {
      if store.demo {
        Text("SAMPLE DATA · \(store.role.uppercased()) DEMO").font(.caption.weight(.semibold))
          .frame(maxWidth: .infinity).padding(6).background(.yellow.opacity(0.2))
      }
      TabView(selection: $store.selectedTab) {
        NavigationStack { ClassesView() }
          .tabItem { Label("My Classes", systemImage: "graduationcap.fill") }.tag(0)
        NavigationStack { CalendarView() }
          .tabItem { Label("Calendar", systemImage: "calendar") }.tag(Store.calendarTab)
        // A trainer sees what they are paid and the hours they have taught;
        // a learner sees certificates and billing. A later role adds its own pair here.
        if store.role == "trainer" {
          NavigationStack { PayoutView() }
            .tabItem { Label("Payout", systemImage: "banknote.fill") }.tag(2)
          NavigationStack { TrainingHoursView() }
            .tabItem { Label("Hours", systemImage: "clock.fill") }.tag(3)
        } else {
          NavigationStack { CertificatesView() }
            .tabItem { Label("Certificates", systemImage: "rosette") }.tag(2)
          NavigationStack { BillingView() }
            .tabItem { Label("Billing", systemImage: "creditcard.fill") }.tag(3)
        }
        NavigationStack { AccountView() }
          .tabItem { Label("Account", systemImage: "person.crop.circle.fill") }
          .tag(Store.accountTab)
      }
    }
  }
}

// MARK: - Shared pieces

/// Brand mark at the top of every tab: the TIA badge and the app name.
struct BrandHeader: View {
  var body: some View {
    HStack(spacing: 8) {
      Text("TIA").font(.system(size: 11, weight: .black, design: .rounded)).foregroundStyle(.white)
        .frame(width: 30, height: 30)
        .background(
          LinearGradient(
            colors: [Theme.brandBlue, Theme.brandNavy], startPoint: .topLeading,
            endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
      Text(Theme.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.accent)
    }
    .accessibilityElement(children: .combine).accessibilityLabel(Theme.name)
  }
}

extension View {
  /// Places the brand mark in the navigation bar. Apply inside each tab's NavigationStack.
  func brandToolbar() -> some View {
    toolbar { ToolbarItem(placement: .principal) { BrandHeader() } }
  }
}

struct InfoCard<Content: View>: View {
  @ViewBuilder let content: Content
  var body: some View {
    content.padding(16).frame(maxWidth: .infinity, alignment: .leading)
      .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.cardBorder, lineWidth: 1))
  }
}

struct StatusChip: View {
  let text: String
  let color: Color
  var body: some View {
    Text(text).font(.system(size: 11, weight: .bold)).padding(.horizontal, 7).padding(.vertical, 3)
      .foregroundStyle(color).background(color.opacity(0.12), in: Capsule())
  }
}

struct ErrorCard: View {
  let message: String
  let retry: () -> Void
  var body: some View {
    InfoCard {
      VStack(alignment: .leading, spacing: 10) {
        Label(message, systemImage: "wifi.exclamationmark").font(.subheadline)
        Button("Try Again", action: retry).buttonStyle(.bordered)
      }
    }
  }
}

/// The profile picture when the academy has one on file, else the person's initials.
struct AvatarView: View {
  let picture: String?
  let name: String
  var size: CGFloat = 80

  private var initials: String {
    let parts = name.split(separator: " ").prefix(2).compactMap { $0.first }
    return parts.isEmpty ? "?" : String(parts).uppercased()
  }
  private var url: URL? {
    guard let picture, let url = URL(string: picture), url.scheme == "https" else { return nil }
    return url
  }
  private var fallback: some View {
    ZStack {
      Theme.brand
      Text(initials).font(.system(size: size * 0.38, weight: .semibold)).foregroundStyle(.white)
    }
  }

  var body: some View {
    Group {
      if let url {
        AsyncImage(url: url) { phase in
          if let image = phase.image { image.resizable().scaledToFill() } else { fallback }
        }
      } else {
        fallback
      }
    }
    .frame(width: size, height: size).clipShape(Circle()).accessibilityHidden(true)
  }
}

/// One scrolling tab page in the card layout.
struct TabPage<Content: View>: View {
  let title: String
  @ViewBuilder let content: Content
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) { content }.padding(20).frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
    }
    .background(Theme.page).navigationTitle(title).navigationBarTitleDisplayMode(.inline)
    .brandToolbar()
  }
}

// MARK: - My Classes (home)

/// Top of My Classes, in the TIA house layout: a "Welcome back" card with the full name,
/// the role and a My Profile link, then (for the owner account only) a "View as" row.
struct HomeHeader: View {
  @EnvironmentObject var store: Store

  private var fullName: String { store.profile?.fullName ?? store.user?.fullName ?? "" }
  private var name: String { fullName.isEmpty ? "Welcome" : fullName.uppercased() }
  private var card: RoundedRectangle { RoundedRectangle(cornerRadius: 18) }

  var body: some View {
    VStack(spacing: 12) {
      Button {
        store.selectedTab = Store.accountTab
      } label: {
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Text("Welcome back").font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
              .foregroundStyle(.tertiary)
          }
          Text(name).font(.system(size: 26, weight: .heavy)).foregroundStyle(.primary)
            .multilineTextAlignment(.leading).lineLimit(2).minimumScaleFactor(0.6)
          HStack(spacing: 12) {
            Text(Store.roleName(store.role)).font(.subheadline.weight(.semibold))
              .foregroundStyle(Theme.accent).padding(.horizontal, 12).padding(.vertical, 5)
              .background(Theme.accentSoft, in: Capsule())
            Label("My Profile", systemImage: "person.crop.circle")
              .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent)
          }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: card).overlay(card.stroke(Theme.cardBorder))
        .contentShape(card)
      }
      .buttonStyle(.plain).accessibilityElement(children: .combine)
      .accessibilityLabel("Welcome back, \(fullName). \(Store.roleName(store.role)). My Profile")
      .accessibilityIdentifier("my-profile")

      if store.canSwitchRole {
        Menu {
          Picker(
            "View as",
            selection: Binding(
              get: { store.role }, set: { role in Task { await store.setViewRole(role) } })
          ) {
            ForEach(store.availableRoles, id: \.self) { Text(Store.roleName($0)).tag($0) }
          }
        } label: {
          HStack(spacing: 12) {
            Image(systemName: "eye.fill").foregroundStyle(Theme.accent)
            Text("View as").foregroundStyle(.secondary)
            Spacer()
            Text(Store.roleName(store.role)).fontWeight(.semibold).foregroundStyle(.primary)
            Image(systemName: "chevron.up.chevron.down").font(.footnote.weight(.semibold))
              .foregroundStyle(.secondary)
          }
          .font(.body).padding(.horizontal, 18).padding(.vertical, 14)
          .background(Theme.card, in: card).overlay(card.stroke(Theme.cardBorder))
        }
        .accessibilityIdentifier("view-as")
      }
    }
  }
}

/// My Classes: the classes assigned to this role (current, upcoming and past), then what
/// the old Today tab showed: the next sessions, the next class's kit and the reminder prompt.
struct ClassesView: View {
  @EnvironmentObject var store: Store

  enum Bucket: String, CaseIterable, Identifiable {
    case current = "Current"
    case upcoming = "Upcoming"
    case past = "Past"
    var id: String { rawValue }
  }

  @State private var picked: Bucket?
  @State private var query = ""

  private var trainer: Bool { store.role == "trainer" }

  private func bucket(of course: Course) -> Bucket {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Singapore")!
    let today = calendar.startOfDay(for: Date())
    guard let start = Fmt.day(course.startDate) else { return .upcoming }
    if (Fmt.day(course.endDate) ?? start) < today { return .past }
    return start > today ? .upcoming : .current
  }
  private func courses(_ bucket: Bucket) -> [Course] {
    store.dashboard.courses.filter {
      self.bucket(of: $0) == bucket
        && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)
          || ($0.code ?? "").localizedCaseInsensitiveContains(query))
    }
  }
  /// The most useful list first: a class running now, else the next one, else history.
  private var shown: Bucket {
    picked ?? Bucket.allCases.first { !courses($0).isEmpty } ?? .current
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        HomeHeader()

        Picker("Classes", selection: Binding(get: { shown }, set: { picked = $0 })) {
          ForEach(Bucket.allCases) { b in Text("\(b.rawValue) (\(courses(b).count))").tag(b) }
        }
        .pickerStyle(.segmented).accessibilityIdentifier("class-bucket")

        if courses(shown).isEmpty {
          ContentUnavailableView {
            Label(emptyTitle, systemImage: "calendar.badge.clock")
          } description: {
            Text(emptyText)
          }
          .padding(.top, 10)
        }
        ForEach(courses(shown)) { course in
          NavigationLink {
            CourseDetail(course: course)
          } label: {
            ClassCard(course: course, running: shown == .current)
          }
          .buttonStyle(.plain)
        }

        HStack {
          Text("Up next").font(.title3.bold())
          Spacer()
          Button("See calendar") { store.selectedTab = Store.calendarTab }
            .font(.subheadline.weight(.semibold))
        }
        .padding(.top, 6)
        if store.upcoming.isEmpty {
          InfoCard {
            Label("Your scheduled class sessions will appear here.", systemImage: "calendar")
              .font(.subheadline).foregroundStyle(.secondary)
          }
        }
        ForEach(store.upcoming.prefix(3)) { session in
          NavigationLink {
            SessionDetail(session: session)
          } label: {
            SessionCard(session: session)
          }
          .buttonStyle(.plain)
        }

        RoleWorkspaceCard()

        if !store.notifications {
          Button {
            Task { await store.enableNotifications() }
          } label: {
            Label("Enable 3-day and 1-day reminders", systemImage: "bell.badge")
              .frame(maxWidth: .infinity).padding(6)
          }
          .buttonStyle(.bordered)
        }
        Text("Class times are shown in Singapore time (SGT).").font(.footnote)
          .foregroundStyle(.secondary)
      }
      .padding(20).frame(maxWidth: 760).frame(maxWidth: .infinity)
    }
    .background(Theme.page).navigationTitle("My Classes").navigationBarTitleDisplayMode(.inline)
    .brandToolbar()
    .searchable(text: $query, prompt: "Find your course")
    .refreshable { await store.refresh() }
  }

  private var emptyTitle: String {
    if !query.isEmpty { return "No courses found" }
    switch shown {
    case .current: return "No class today"
    case .upcoming: return "No upcoming classes"
    case .past: return "No past classes yet"
    }
  }
  private var emptyText: String {
    if !query.isEmpty { return "Try another course title or code." }
    switch shown {
    case .current:
      return trainer
        ? "Classes running now appear here, with attendance and the teaching kit."
        : "Classes that are running now appear here, with check-in and your courseware."
    case .upcoming:
      return trainer
        ? "Classes you are scheduled to teach appear here."
        : "Courses your academy assigns to you appear here."
    case .past:
      return trainer
        ? "Completed classes you taught appear here."
        : "Completed classes and their assessments appear here."
    }
  }
}

struct ClassCard: View {
  @EnvironmentObject var store: Store
  let course: Course
  var running = false

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: "book.closed.fill").font(.title3).foregroundStyle(Theme.accent)
          .frame(width: 56, height: 56)
          .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 4) {
          Text(course.code ?? "Course").font(.caption.weight(.semibold))
            .foregroundStyle(Theme.accent)
          HStack(spacing: 6) {
            if store.role == "trainer" { StatusChip(text: "Teaching", color: Theme.accent) }
            if running { StatusChip(text: "In progress", color: Theme.success) }
          }
          Text(course.title).font(.headline).foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
        }
        Spacer(minLength: 0)
        Image(systemName: "chevron.right").font(.caption.weight(.semibold))
          .foregroundStyle(.tertiary)
      }
      VStack(alignment: .leading, spacing: 5) {
        Label(Fmt.range(course.startDate, course.endDate), systemImage: "calendar")
        if let format = course.format, !format.isEmpty {
          Label(
            format,
            systemImage: format.localizedCaseInsensitiveContains("online")
              ? "video.fill" : "building.2.fill")
        }
        if let venue = course.venue, !venue.isEmpty {
          Label(venue, systemImage: "mappin.and.ellipse")
        }
      }
      .font(.footnote).foregroundStyle(.secondary)
      JourneyProgress(course: course)
    }
    .padding(16)
    .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.cardBorder, lineWidth: 1))
  }
}

// MARK: - Payout (trainer tab)

struct PayoutView: View {
  @EnvironmentObject var store: Store
  @State private var payouts: [Payout]?
  @State private var problem: String?

  var body: some View {
    TabPage(title: "Payout") {
      if let payouts {
        if payouts.isEmpty {
          ContentUnavailableView {
            Label("No payouts yet", systemImage: "banknote")
          } description: {
            Text("Payouts for the classes you teach appear here once they are paid.")
          }
          .padding(.top, 40)
        } else {
          SummaryCard(
            title: "Total paid", value: Fmt.money(payouts.reduce(0) { $0 + $1.amount }),
            caption: "\(payouts.count) payout\(payouts.count == 1 ? "" : "s")")
          ForEach(payouts) { PayoutCard(payout: $0) }
        }
      } else if let problem {
        ErrorCard(message: problem) { Task { await load() } }
      } else {
        ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
      }
    }
    .refreshable { await load() }
    .task { if payouts == nil { await load() } }
  }

  private func load() async {
    do {
      payouts = try await store.loadPayouts()
      problem = nil
    } catch {
      if payouts == nil { problem = error.localizedDescription }
    }
  }
}

struct SummaryCard: View {
  let title: String
  let value: String
  let caption: String
  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title).font(.subheadline).foregroundStyle(.white.opacity(0.85))
      Text(value).font(.system(size: 32, weight: .bold)).foregroundStyle(.white)
      Text(caption).font(.footnote).foregroundStyle(.white.opacity(0.85))
    }
    .frame(maxWidth: .infinity, alignment: .leading).padding(18)
    .background(Theme.brand, in: RoundedRectangle(cornerRadius: 16))
    .accessibilityElement(children: .combine)
  }
}

struct PayoutCard: View {
  let payout: Payout
  var body: some View {
    InfoCard {
      VStack(alignment: .leading, spacing: 8) {
        HStack(alignment: .top) {
          Text(payout.title.isEmpty ? "Class" : payout.title).font(.headline)
            .fixedSize(horizontal: false, vertical: true)
          Spacer(minLength: 12)
          Text(Fmt.money(payout.amount)).font(.headline).foregroundStyle(Theme.success)
        }
        Group {
          if !payout.startDate.isEmpty {
            LabeledContent("Class", value: Fmt.range(payout.startDate, payout.endDate))
          }
          if !payout.paymentDate.isEmpty {
            LabeledContent("Paid", value: Fmt.longDate(payout.paymentDate))
          }
          if let learners = payout.learners, learners > 0 {
            LabeledContent("Learners", value: String(learners))
          }
          if !payout.courseCode.isEmpty { LabeledContent("Course", value: payout.courseCode) }
        }
        .font(.footnote).foregroundStyle(.secondary)
      }
    }
  }
}

// MARK: - Tabs that arrive in a later phase
//
// Hours, Certificates and Billing have no secure endpoint yet, so each shows what it will
// hold. To finish one, give it the PayoutView shape: a `Store.load…()` call, then swap
// `ComingSoon` for the loaded cards with the same empty and error states. Do not point them
// at /api/learner/certificates, /api/billing/history or /api/courses/trainer-hours: those
// routes trust a user id in the query and are not for the app.

struct ComingSoon: View {
  let icon: String
  let title: String
  let text: String
  var body: some View {
    ContentUnavailableView {
      Label(title, systemImage: icon)
    } description: {
      Text(text)
    }
    .padding(.top, 40)
  }
}

struct TrainingHoursView: View {
  var body: some View {
    TabPage(title: "Training Hours") {
      ComingSoon(
        icon: "clock", title: "Coming soon",
        text: "The hours you have taught, by month and by class, will appear here.")
    }
  }
}

struct CertificatesView: View {
  var body: some View {
    TabPage(title: "Certificates") {
      ComingSoon(
        icon: "rosette", title: "Coming soon",
        text: "Your course certificates will appear here to view and download.")
    }
  }
}

struct BillingView: View {
  var body: some View {
    TabPage(title: "Billing") {
      ComingSoon(
        icon: "creditcard", title: "Coming soon",
        text: "Your invoices and payment receipts will appear here.")
    }
  }
}

// MARK: - Account (one page: who you are, your details, settings)

/// One contact detail; tapping it calls, emails, opens WhatsApp or the LinkedIn profile.
struct ContactRow: View {
  let icon: String
  let title: String
  let value: String
  let url: URL?
  @Environment(\.openURL) private var openURL

  var body: some View {
    Button {
      if let url { openURL(url) }
    } label: {
      HStack(spacing: 12) {
        Image(systemName: icon).font(.system(size: 14, weight: .semibold))
          .foregroundStyle(Theme.accent).frame(width: 30, height: 30)
          .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 8))
        VStack(alignment: .leading, spacing: 1) {
          Text(title).font(.caption).foregroundStyle(.secondary)
          Text(value).font(.subheadline).foregroundStyle(.primary).lineLimit(1)
            .truncationMode(.middle)
        }
        Spacer()
        Image(systemName: "arrow.up.right").font(.caption.weight(.semibold))
          .foregroundStyle(.tertiary)
      }
    }
    .buttonStyle(.plain).accessibilityElement(children: .combine)
    .accessibilityLabel("\(title): \(value)")
  }
}

/// Lays chips out left to right, wrapping to new centred rows. Used for qualification
/// badges under the name once the profile carries them.
struct FlowLayout: Layout {
  var spacing: CGFloat = 6

  private func rows(_ subviews: Subviews, width: CGFloat) -> [[(Int, CGSize)]] {
    var rows: [[(Int, CGSize)]] = [[]]
    var x: CGFloat = 0
    for (i, v) in subviews.enumerated() {
      let size = v.sizeThatFits(.unspecified)
      if x + size.width > width, !(rows.last?.isEmpty ?? true) {
        rows.append([])
        x = 0
      }
      rows[rows.count - 1].append((i, size))
      x += size.width + spacing
    }
    return rows
  }
  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let width = proposal.width ?? 320
    let r = rows(subviews, width: width)
    let height =
      r.reduce(0) { $0 + ($1.map { $0.1.height }.max() ?? 0) }
      + spacing * CGFloat(max(r.count - 1, 0))
    return CGSize(width: width, height: height)
  }
  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    var y = bounds.minY
    for row in rows(subviews, width: bounds.width) {
      let rowWidth =
        row.reduce(0) { $0 + $1.1.width } + spacing * CGFloat(max(row.count - 1, 0))
      var x = bounds.minX + (bounds.width - rowWidth) / 2
      let h = row.map { $0.1.height }.max() ?? 0
      for (i, size) in row {
        subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
        x += size.width + spacing
      }
      y += h + spacing
    }
  }
}

struct AccountView: View {
  @EnvironmentObject var store: Store
  @State private var name = ""
  @State private var phone = ""
  @State private var company = ""
  @State private var employment = ""
  @State private var linkedin = ""
  /// The profile the fields were last filled from, so a refresh does not undo typing.
  @State private var filledFrom: Profile?
  @State private var saving = false
  @State private var message: String?
  @State private var confirmSignOut = false
  @State private var confirmDelete = false

  private var fullName: String { store.profile?.fullName ?? store.user?.fullName ?? "" }
  private var email: String { store.profile?.email ?? store.user?.email ?? "" }

  private static func digits(_ phone: String, plus: Bool = false) -> String {
    (plus && phone.trimmingCharacters(in: .whitespaces).hasPrefix("+") ? "+" : "")
      + phone.filter(\.isNumber)
  }
  /// wa.me needs the country code: a bare 8-digit Singapore number gets 65.
  private static func whatsApp(_ phone: String) -> String {
    let d = digits(phone)
    return d.count == 8 ? "65" + d : d
  }

  var body: some View {
    List {
      // Who you are: picture, name and the role this sign-in shows.
      Section {
        VStack(spacing: 10) {
          AvatarView(picture: store.profile?.pictureURL, name: fullName, size: 104)
          Text(fullName.isEmpty ? "My account" : fullName).font(.title2.weight(.bold))
            .multilineTextAlignment(.center)
          FlowLayout(spacing: 6) {
            StatusChip(text: Store.roleName(store.role), color: Theme.accent)
            if let academy = store.profile?.academy, !academy.isEmpty {
              StatusChip(text: academy, color: .secondary)
            }
          }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8).listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
      }

      Section("Contact") {
        ContactRow(
          icon: "envelope.fill", title: "Email", value: email, url: URL(string: "mailto:" + email))
        if let p = store.profile?.phone, !p.isEmpty {
          ContactRow(
            icon: "phone.fill", title: "Phone", value: p,
            url: URL(string: "tel:" + Self.digits(p, plus: true)))
          ContactRow(
            icon: "message.fill", title: "WhatsApp", value: p,
            url: URL(string: "https://wa.me/" + Self.whatsApp(p)))
        }
        if let link = store.profile?.linkedinURL, !link.isEmpty, let url = URL(string: link) {
          ContactRow(
            icon: "link", title: "LinkedIn",
            value: link.replacingOccurrences(of: "https://", with: ""), url: url)
        }
      }

      Section("Name") {
        TextField("Full name", text: $name).textContentType(.name)
          .accessibilityIdentifier("profile-name")
      }
      Section {
        TextField("Phone number", text: $phone).keyboardType(.phonePad)
          .textContentType(.telephoneNumber).accessibilityIdentifier("profile-phone")
        if store.roles.contains("learner") {
          TextField("Company", text: $company)
          Picker("Employment status", selection: $employment) {
            Text("Not set").tag("")
            ForEach(["Employed", "Unemployed", "Looking for Job"], id: \.self) { Text($0).tag($0) }
          }
        }
        if store.roles.contains("trainer") {
          TextField("LinkedIn link (https://…)", text: $linkedin).keyboardType(.URL)
            .textInputAutocapitalization(.never).autocorrectionDisabled()
        }
      } header: {
        Text("Edit details")
      } footer: {
        Text(
          "Your phone number is also used for WhatsApp. To change your email address or NRIC, contact your academy."
        )
      }

      Section {
        Picker(
          "Appearance",
          selection: Binding(
            get: { store.theme },
            set: { choice in
              store.theme = choice
              Task {
                if let problem = await store.saveProfile(["theme": choice]) { message = problem }
              }
            })
        ) {
          Text("System").tag("system")
          Text("Light").tag("light")
          Text("Dark").tag("dark")
        }
        .pickerStyle(.segmented).accessibilityIdentifier("appearance")
      } header: {
        Text("Appearance")
      } footer: {
        Text(
          "System follows your device's light or dark setting. Your choice is saved to your account."
        )
      }

      Section {
        Button {
          Task { await save() }
        } label: {
          HStack {
            Spacer()
            if saving { ProgressView() }
            Text("Save Changes").fontWeight(.semibold)
            Spacer()
          }
        }
        .disabled(saving || name.trimmingCharacters(in: .whitespaces).count < 2)
        .accessibilityIdentifier("save-profile")
      }

      if !store.demo {
        Section {
          NavigationLink {
            ChangePasswordView()
          } label: {
            Label("Change Password", systemImage: "key.fill")
          }
        }
      }

      Section {
        Label("3 days before class", systemImage: "bell")
        Label("1 day before class", systemImage: "bell.badge")
        Label("On the morning of class", systemImage: "sunrise")
        Button(store.notifications ? "Notification settings" : "Enable notifications") {
          if store.notifications {
            UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
          } else {
            Task { await store.enableNotifications() }
          }
        }
      } header: {
        Text("Class reminders")
      } footer: {
        Text(
          store.demo
            ? "Sample mode does not register a device for real class reminders."
            : "Notifications follow your current class assignments.")
      }

      Section("Support") {
        NavigationLink {
          FeedbackView()
        } label: {
          Label("Send Feedback", systemImage: "bubble.left.and.bubble.right.fill")
        }
        NavigationLink {
          AboutView()
        } label: {
          Label("About", systemImage: "info.circle.fill")
        }
        Link(destination: URL(string: "https://lms-tms.tertiaryinfotech.com/mobile/privacy.html")!)
        {
          Label("Privacy Policy", systemImage: "hand.raised.fill")
        }
      }

      Section {
        Button(store.demo ? "Exit demo" : "Sign Out") {
          if store.demo { Task { await store.signOut() } } else { confirmSignOut = true }
        }
      }

      Section {
        Button(role: .destructive) {
          confirmDelete = true
        } label: {
          Label("Delete Account", systemImage: "trash")
        }
      } footer: {
        Text(
          "Initiate permanent account deletion. Training records that must be retained will be handled by your training provider."
        )
      }
    }
    .navigationTitle("Account").navigationBarTitleDisplayMode(.inline).brandToolbar()
    .onAppear { fill() }
    .onChange(of: store.profile) { _, _ in fill() }
    .task { if store.profile == nil { await store.loadProfile() } }
    .refreshable { await store.loadProfile() }
    .confirmationDialog(
      "Sign out of \(Theme.name)?", isPresented: $confirmSignOut, titleVisibility: .visible
    ) {
      Button("Sign Out", role: .destructive) { Task { await store.signOut() } }
    }
    .confirmationDialog(
      "Delete your account?", isPresented: $confirmDelete, titleVisibility: .visible
    ) {
      Button("Permanently delete account", role: .destructive) {
        Task { await store.deleteAccount() }
      }
    } message: {
      Text(
        "You will be signed out and reminders stopped. Your shared learning-portal login and profile identity will be permanently removed. Required training and financial records are retained by the provider. Sample mode only clears sample data."
      )
    }
    .alert(
      "Profile", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })
    ) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(message ?? "")
    }
  }

  private func fill() {
    // Compared without the theme, so changing Appearance does not undo unsaved typing.
    var current = store.profile
    current?.theme = ""
    guard current != filledFrom || (name.isEmpty && current == nil) else { return }
    filledFrom = current
    name = fullName
    phone = store.profile?.phone ?? ""
    company = store.profile?.company ?? ""
    employment = store.profile?.employmentStatus ?? ""
    linkedin = store.profile?.linkedinURL ?? ""
  }

  private func save() async {
    saving = true
    defer { saving = false }
    var fields: [String: Any] = [
      "fullName": name.trimmingCharacters(in: .whitespaces),
      "phone": phone.trimmingCharacters(in: .whitespaces),
    ]
    if store.roles.contains("learner") {
      fields["company"] = company
      fields["employmentStatus"] = employment
    }
    if store.roles.contains("trainer") {
      fields["linkedinURL"] = linkedin.trimmingCharacters(in: .whitespaces)
    }
    message = await store.saveProfile(fields) ?? "Profile saved."
  }
}
