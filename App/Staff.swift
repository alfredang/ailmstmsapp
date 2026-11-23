import SwiftUI

// Admin and Developer views, from GET /api/mobile/staff (read-only; the server checks the role).
//   Admin:     Home = Current and Upcoming classes; Calendar = every class by day; Courses tab.
//   Developer: Home and Courses tab = the course catalogue.

// MARK: - Models

struct StaffClass: Decodable, Identifiable, Hashable {
  let id: String
  let runCode: String?
  let title: String
  let code: String?
  let startDate: String?
  let endDate: String?
  let format: String?
  let classStatus: String?
  let hasMeetingLink: Bool?
  let trainers: [String]
  let learners: Int
  let venue: String?

  var start: Date? { Fmt.day(startDate) }
  var end: Date? { Fmt.day(endDate ?? startDate) }
  func covers(_ day: Date) -> Bool {
    guard let start, let end else { return false }
    let d = Calendar.current.startOfDay(for: day)
    return d >= Calendar.current.startOfDay(for: start) && d <= Calendar.current.startOfDay(for: end)
  }
  var cancelled: Bool { (classStatus ?? "").lowercased().hasPrefix("cancel") }
}
struct StaffClassesReply: Decodable { let classes: [StaffClass] }

struct StaffCourse: Decodable, Identifiable, Hashable {
  let id: String
  let title: String
  let code: String?
  let courseType: String?
  let status: String?
  let tscTitle: String?
  let tscCode: String?
  let trainingHours: Double?
  let assessmentHours: Double?
  var fundingValidityStart: String? = nil
  let fundingValidityEnd: String?
  let upcomingRuns: Int
  let nextRun: String?

  var fundingEnd: Date? { Fmt.day(fundingValidityEnd) }
  var expired: Bool { title.localizedCaseInsensitiveContains("(expired)") || (fundingEnd.map { $0 < Date() } ?? false) }
  /// Days until funding ends, when that is within 3 months (90 days) and not yet past.
  var expiringInDays: Int? {
    guard !expired, let end = fundingEnd else { return nil }
    let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: end).day ?? 0
    return days <= 90 ? max(days, 0) : nil
  }
}
struct StaffCoursesReply: Decodable { let courses: [StaffCourse] }

enum StaffAPI {
  static let iso: DateFormatter = {
    let f = DateFormatter()
    f.calendar = Calendar(identifier: .gregorian)
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(identifier: "Asia/Singapore")
    f.dateFormat = "yyyy-MM-dd"
    return f
  }()
  static func classes(from: Date, to: Date) async throws -> [StaffClass] {
    let reply: StaffClassesReply = try await API.shared.request(
      "mobile/staff", query: ["view": "classes", "from": iso.string(from: from), "to": iso.string(from: to)])
    return reply.classes
  }
  static func courses() async throws -> [StaffCourse] {
    let reply: StaffCoursesReply = try await API.shared.request("mobile/staff", query: ["view": "courses"])
    return reply.courses
  }
}

private func statusColor(_ status: String?) -> Color {
  switch (status ?? "").lowercased() {
  case "confirmed": return .green
  case let s where s.hasPrefix("cancel"): return .red
  default: return .orange
  }
}

// MARK: - Home (tab 0)

/// The staff home under the Welcome card.
struct StaffHome: View {
  let role: String
  var body: some View {
    if role == "admin" { AdminClassesView() } else { CourseCatalogView(embedded: true) }
  }
}

// MARK: - Admin: Current and Upcoming classes

struct AdminClassesView: View {
  @EnvironmentObject var store: Store
  enum Bucket: String, CaseIterable, Identifiable {
    case current = "Current", upcoming = "Upcoming"
    var id: String { rawValue }
  }
  @State private var classes: [StaffClass]?
  @State private var bucket: Bucket = .current
  @State private var query = ""
  @State private var problem: String?
  @State private var hideCancelled = true

  private var today: Date { Calendar.current.startOfDay(for: Date()) }

  private func list(_ b: Bucket) -> [StaffClass] {
    (classes ?? []).filter { c in
      if hideCancelled && c.cancelled { return false }
      let inBucket = b == .current ? c.covers(today) : (c.start.map { $0 > today } ?? false)
      guard inBucket else { return false }
      return query.isEmpty || c.title.localizedCaseInsensitiveContains(query)
        || (c.code ?? "").localizedCaseInsensitiveContains(query)
        || (c.runCode ?? "").contains(query)
        || c.trainers.contains { $0.localizedCaseInsensitiveContains(query) }
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      if let classes {
        let current = list(.current), upcoming = list(.upcoming)
        HStack(spacing: 8) {
          HoursTile(label: "Running today", value: "\(current.count)")
          HoursTile(label: "Next 30 days", value: "\(upcoming.count)")
          HoursTile(label: "Learners today", value: "\(current.reduce(0) { $0 + $1.learners })", strong: true)
        }
        Picker("Classes", selection: $bucket) {
          ForEach(Bucket.allCases) { b in
            Text("\(b.rawValue) (\(b == .current ? current.count : upcoming.count))").tag(b)
          }
        }
        .pickerStyle(.segmented)
        HStack {
          Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
          TextField("Search course, run ID or trainer", text: $query)
            .textInputAutocapitalization(.never).autocorrectionDisabled()
        }
        .padding(10).background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
        Toggle("Hide cancelled classes", isOn: $hideCancelled).font(.subheadline)
        let shown = bucket == .current ? current : upcoming
        if shown.isEmpty {
          ComingSoon(
            icon: "calendar.badge.checkmark", title: bucket == .current ? "No classes running today" : "No upcoming classes",
            text: classes.isEmpty ? "Pull down to refresh." : "Try another search.")
        }
        LazyVStack(spacing: 10) {
          ForEach(shown) { c in StaffClassRow(item: c) }
        }
      } else if let problem {
        ErrorCard(message: problem) { Task { await load() } }
      } else {
        ProgressView("Loading classes…").frame(maxWidth: .infinity).padding(.top, 30)
      }
    }
    .task { if classes == nil { await load() } }
    .refreshable { await load() }
  }

  private func load() async {
    if store.demo {
      classes = StaffSample.classes
      return
    }
    do {
      classes = try await StaffAPI.classes(from: today, to: today.addingTimeInterval(30 * 86400))
      problem = nil
    } catch { problem = error.localizedDescription }
  }
}

/// One class in an admin list; tap for the summary.
struct StaffClassRow: View {
  let item: StaffClass
  @State private var showing = false
  var body: some View {
    Button {
      showing = true
    } label: {
      VStack(alignment: .leading, spacing: 6) {
        HStack(alignment: .firstTextBaseline) {
          Text(item.code ?? "Course").font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
          Spacer()
          StatusChip(text: item.classStatus ?? "Pending", color: statusColor(item.classStatus))
        }
        Text(item.title).font(.headline).foregroundStyle(.primary).multilineTextAlignment(.leading)
        Label(Fmt.range(item.startDate, item.endDate), systemImage: "calendar")
        Label(
          item.trainers.isEmpty ? "No trainer assigned" : item.trainers.joined(separator: ", "),
          systemImage: "person.fill"
        )
        .foregroundStyle(item.trainers.isEmpty ? Color.orange : Color.secondary)
        HStack(spacing: 14) {
          Label("\(item.learners) learners", systemImage: "person.3.fill")
          if let format = item.format, !format.isEmpty {
            Label(format, systemImage: format.localizedCaseInsensitiveContains("physical") ? "building.2.fill" : "video.fill")
          }
        }
      }
      .font(.footnote).foregroundStyle(.secondary)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(14)
      .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.cardBorder, lineWidth: 1))
    }
    .buttonStyle(.plain)
    .sheet(isPresented: $showing) { StaffClassSheet(item: item) }
  }
}

/// A class's summary for the admin.
struct StaffClassSheet: View {
  let item: StaffClass
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    NavigationStack {
      List {
        Section {
          VStack(alignment: .leading, spacing: 8) {
            Text(item.title).font(.title3.weight(.bold))
            Text([item.code, item.runCode.map { "Run \($0)" }].compactMap { $0 }.joined(separator: "  ·  "))
              .font(.subheadline).foregroundStyle(.secondary)
            HStack {
              if let format = item.format { StatusChip(text: format, color: Theme.accent) }
              StatusChip(text: item.classStatus ?? "Pending", color: statusColor(item.classStatus))
            }
          }
          .padding(.vertical, 4)
        }
        Section("Class") {
          InfoRow("Dates", Fmt.range(item.startDate, item.endDate))
          InfoRow("Learners", "\(item.learners)")
          InfoRow(item.trainers.count > 1 ? "Trainers" : "Trainer",
                  item.trainers.isEmpty ? "Not assigned" : item.trainers.joined(separator: "\n"))
          if let venue = item.venue { VenueLink(address: venue) }
          if item.hasMeetingLink == true { InfoRow("Virtual class link", "Set") }
        }
        Section {
          NavigationLink {
            TrainerWhatsAppPicker(item: item)
          } label: {
            Label("WhatsApp a trainer", systemImage: "message.fill")
          }
          .accessibilityIdentifier("whatsapp-trainer")
        } header: {
          Text("Trainer")
        } footer: {
          Text("Opens WhatsApp with a message asking the trainer to take this class. Record the assignment on lms-tms.tertiaryinfotech.com, where TPGateway is updated.")
        }
      }
      .navigationTitle("Class").navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
  }
}

// MARK: - WhatsApp a trainer

struct StaffTrainer: Decodable, Identifiable, Hashable {
  var id: String { (email ?? "") + name }
  let name: String
  let email: String?
  let phone: String?
}
struct StaffTrainersReply: Decodable { let trainers: [StaffTrainer] }

/// Pick a trainer, then WhatsApp opens on this phone with a message about the class.
struct TrainerWhatsAppPicker: View {
  @EnvironmentObject var store: Store
  let item: StaffClass
  @Environment(\.openURL) private var openURL
  @State private var trainers: [StaffTrainer]?
  @State private var query = ""
  @State private var problem: String?

  private func matches(_ t: StaffTrainer) -> Bool {
    query.isEmpty || t.name.localizedCaseInsensitiveContains(query)
      || (t.email ?? "").localizedCaseInsensitiveContains(query)
  }
  private func assigned(_ t: StaffTrainer) -> Bool {
    item.trainers.contains { $0.caseInsensitiveCompare(t.name) == .orderedSame }
  }

  /// The message the admin sends; they can edit it in WhatsApp before sending.
  static func message(for t: StaffTrainer, item: StaffClass) -> String {
    let first = t.name.split(separator: " ").first.map(String.init) ?? t.name
    var lines = [
      "Hi \(first), this is Tertiary Infotech Academy.",
      "Are you available to train this class?",
      "",
      "\(item.title)" + (item.code.map { " (\($0))" } ?? ""),
    ]
    if let run = item.runCode { lines.append("Course Run: \(run)") }
    lines.append("Dates: \(Fmt.range(item.startDate, item.endDate))")
    if let format = item.format { lines.append("Class type: \(format)") }
    if let venue = item.venue { lines.append("Venue: \(venue)") }
    lines += ["", "Please reply to confirm. Thank you!"]
    return lines.joined(separator: "\n")
  }

  static func whatsAppURL(phone: String, text: String) -> URL? {
    let digits = phone.filter(\.isNumber)
    guard !digits.isEmpty else { return nil }
    var c = URLComponents(string: "https://wa.me/\(digits)")
    c?.queryItems = [URLQueryItem(name: "text", value: text)]
    return c?.url
  }

  var body: some View {
    List {
      if let trainers {
        let mine = trainers.filter { assigned($0) && matches($0) }
        let others = trainers.filter { !assigned($0) && matches($0) }
        if !mine.isEmpty {
          Section("Assigned to this class") { ForEach(mine) { row($0) } }
        }
        Section("All trainers (\(others.count))") { ForEach(others) { row($0) } }
      } else if let problem {
        Text(problem).foregroundStyle(.red)
        Button("Try again") { Task { await load() } }
      } else {
        ProgressView("Loading trainers…")
      }
    }
    .searchable(text: $query, prompt: "Search trainers")
    .navigationTitle("WhatsApp a trainer").navigationBarTitleDisplayMode(.inline)
    .task { if trainers == nil { await load() } }
  }

  private func row(_ t: StaffTrainer) -> some View {
    Button {
      if let phone = t.phone, let url = Self.whatsAppURL(phone: phone, text: Self.message(for: t, item: item)) {
        openURL(url)
      }
    } label: {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text(t.name).foregroundStyle(.primary)
          Text(t.phone ?? "No WhatsApp number on profile").font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
        if t.phone != nil {
          Image(systemName: "message.fill").foregroundStyle(.green)
        }
      }
    }
    .disabled(t.phone == nil)
  }

  private func load() async {
    if store.demo {
      trainers = [
        StaffTrainer(name: "Alex Tan (sample)", email: nil, phone: "+6580000000"),
        StaffTrainer(name: "Priya Nair (sample)", email: nil, phone: nil),
      ]
      return
    }
    do {
      let reply: StaffTrainersReply = try await API.shared.request("mobile/staff", query: ["view": "trainers"])
      trainers = reply.trainers
      problem = nil
    } catch { problem = error.localizedDescription }
  }
}

// MARK: - Admin calendar

/// Every academy class by day: a month calendar with dots, then the chosen day's classes.
struct AdminCalendarView: View {
  @EnvironmentObject var store: Store
  @State private var day = Calendar.current.startOfDay(for: Date())
  @State private var loadedMonth: Date?
  @State private var classes: [StaffClass] = []
  @State private var loading = false
  @State private var problem: String?
  @State private var hideCancelled = true

  private func monthStart(_ d: Date) -> Date {
    Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: d)) ?? d
  }
  private var dayClasses: [StaffClass] {
    classes.filter { $0.covers(day) && !(hideCancelled && $0.cancelled) }
  }

  var body: some View {
    TabPage(title: "Academy Calendar") {
      InfoCard {
        DatePicker("Day", selection: $day, displayedComponents: .date)
          .datePickerStyle(.graphical).tint(Theme.accent)
      }
      HStack {
        Text(day.formatted(.dateTime.weekday(.wide).day().month(.wide))).font(.headline)
        Spacer()
        if loading { ProgressView() }
        Text("\(dayClasses.count) \(dayClasses.count == 1 ? "class" : "classes")").font(.subheadline).foregroundStyle(.secondary)
      }
      Toggle("Hide cancelled classes", isOn: $hideCancelled).font(.subheadline)
      if let problem { ErrorCard(message: problem) { Task { await load(force: true) } } }
      if dayClasses.isEmpty && !loading {
        ComingSoon(icon: "calendar", title: "No classes", text: "No classes on this day.")
      }
      LazyVStack(spacing: 10) {
        ForEach(dayClasses) { c in StaffClassRow(item: c) }
      }
    }
    .task(id: monthStart(day)) { await load(force: false) }
    .refreshable { await load(force: true) }
  }

  private func load(force: Bool) async {
    let month = monthStart(day)
    guard force || loadedMonth != month else { return }
    if store.demo {
      classes = StaffSample.classes
      loadedMonth = month
      return
    }
    loading = true
    defer { loading = false }
    // The whole month plus the edges, so multi-day classes from the previous month show.
    let from = Calendar.current.date(byAdding: .day, value: -7, to: month) ?? month
    let to = Calendar.current.date(byAdding: DateComponents(month: 1, day: 6), to: month) ?? month
    do {
      classes = try await StaffAPI.classes(from: from, to: to)
      loadedMonth = month
      problem = nil
    } catch { problem = error.localizedDescription }
  }
}

// MARK: - Course catalogue (admin and developer)

struct CourseCatalogView: View {
  @EnvironmentObject var store: Store
  /// Inside the Home scroll view (no own page chrome).
  var embedded = false
  enum Filter: String, CaseIterable, Identifiable {
    case all = "All", running = "With classes", expiring = "Expiring", expired = "Expired"
    var id: String { rawValue }
  }
  @State private var courses: [StaffCourse]?
  @State private var query = ""
  @State private var filter: Filter = .all
  @State private var problem: String?

  private var shown: [StaffCourse] {
    (courses ?? []).filter { c in
      switch filter {
      case .all: break
      case .running: if c.upcomingRuns == 0 { return false }
      case .expiring: if c.expiringInDays == nil { return false }
      case .expired: if !c.expired { return false }
      }
      return query.isEmpty || c.title.localizedCaseInsensitiveContains(query)
        || (c.code ?? "").localizedCaseInsensitiveContains(query)
        || (c.tscCode ?? "").localizedCaseInsensitiveContains(query)
    }
  }

  var body: some View {
    if embedded {
      content
    } else {
      TabPage(title: "Courses") { content }
    }
  }

  @ViewBuilder private var content: some View {
    VStack(alignment: .leading, spacing: 14) {
      if let courses {
        HStack(spacing: 8) {
          HoursTile(label: "Courses", value: "\(courses.count)")
          HoursTile(label: "Expiring ≤ 3 mo", value: "\(courses.filter { $0.expiringInDays != nil }.count)")
          HoursTile(label: "Expired", value: "\(courses.filter(\.expired).count)", strong: true)
        }
        Picker("Show", selection: $filter) {
          ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        HStack {
          Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
          TextField("Search title, course code or TSC code", text: $query)
            .textInputAutocapitalization(.never).autocorrectionDisabled()
        }
        .padding(10).background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
        Text("\(shown.count) courses").font(.caption).foregroundStyle(.secondary)
        LazyVStack(spacing: 10) {
          ForEach(shown) { c in CourseRow(item: c) }
        }
      } else if let problem {
        ErrorCard(message: problem) { Task { await load() } }
      } else {
        ProgressView("Loading courses…").frame(maxWidth: .infinity).padding(.top, 30)
      }
    }
    .task { if courses == nil { await load() } }
    .refreshable { await load() }
  }

  private func load() async {
    if store.demo {
      courses = StaffSample.courses
      return
    }
    do {
      courses = try await StaffAPI.courses()
      problem = nil
    } catch { problem = error.localizedDescription }
  }
}

private struct CourseRow: View {
  let item: StaffCourse
  @State private var open = false
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Button {
        withAnimation(.snappy) { open.toggle() }
      } label: {
        VStack(alignment: .leading, spacing: 6) {
          HStack(alignment: .firstTextBaseline) {
            Text(item.code ?? "No code").font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
            if let type = item.courseType, !type.isEmpty { StatusChip(text: type, color: Theme.accent) }
            StatusChip(text: item.expired ? "Expired" : "Active", color: item.expired ? .red : .green)
            Spacer()
            Image(systemName: "chevron.down").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
              .rotationEffect(.degrees(open ? 180 : 0))
          }
          Text(item.title).font(.headline).foregroundStyle(.primary).multilineTextAlignment(.leading)
          if item.fundingValidityStart != nil || item.fundingValidityEnd != nil {
            Label(
              "Funding validity: "
                + [item.fundingValidityStart, item.fundingValidityEnd]
                .map { $0.map { Fmt.longDate($0) } ?? "N/A" }.joined(separator: " – "),
              systemImage: "checkmark.seal"
            )
            .font(.footnote).foregroundStyle(item.expired ? Color.red : Color.secondary)
          }
          if let days = item.expiringInDays {
            ExpiringBadge(days: days)
          }
          Label(item.upcomingRuns == 0 ? "No upcoming classes" : "\(item.upcomingRuns) upcoming", systemImage: "calendar")
            .font(.footnote).foregroundStyle(.secondary)
        }
      }
      .buttonStyle(.plain)
      if open {
        Divider()
        if let t = item.tscTitle, !t.isEmpty { InfoRow("TSC Title", t) }
        if let t = item.tscCode, !t.isEmpty { InfoRow("TSC Code", t) }
        if item.trainingHours != nil || item.assessmentHours != nil {
          InfoRow("Duration", "\(Int(item.trainingHours ?? 0)) h training · \(Int(item.assessmentHours ?? 0)) h assessment")
        }
        if let next = item.nextRun { InfoRow("Next class", Fmt.longDate(next)) }
      }
    }
    .font(.subheadline)
    .padding(14)
    .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.cardBorder, lineWidth: 1))
  }
}

/// A blinking alert when course funding ends within 3 months.
struct ExpiringBadge: View {
  let days: Int
  @State private var dim = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    Label(days == 0 ? "Funding expires today" : "Funding expires in \(days) day\(days == 1 ? "" : "s")",
          systemImage: "exclamationmark.triangle.fill")
      .font(.caption.weight(.bold)).foregroundStyle(.white)
      .padding(.horizontal, 10).padding(.vertical, 5)
      .background(Color.orange, in: Capsule())
      .opacity(dim ? 0.35 : 1)
      .onAppear {
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { dim = true }
      }
      .accessibilityLabel("Alert: funding expires in \(days) days")
  }
}

// MARK: - Tab 2

/// The Admin or Developer tab: the course catalogue.
struct StaffView: View {
  let role: String
  static func icon(_ role: String) -> String { "books.vertical.fill" }
  static func label(_ role: String) -> String { "Courses" }
  var body: some View { CourseCatalogView() }
}

// MARK: - Demo data

enum StaffSample {
  static var classes: [StaffClass] {
    let f = StaffAPI.iso
    let today = Date()
    func day(_ n: Int) -> String { f.string(from: today.addingTimeInterval(Double(n) * 86400)) }
    return [
      StaffClass(id: "s1", runCode: "100001", title: "Agentic AI Applications with Claude Code (sample)", code: "TGS-2025052468",
                 startDate: day(0), endDate: day(1), format: "Hybrid", classStatus: "Confirmed", hasMeetingLink: true,
                 trainers: ["Alex Tan (sample)"], learners: 18, venue: "12 Woodlands Square, Singapore 737715"),
      StaffClass(id: "s2", runCode: "100002", title: "Advanced Prompt Engineering (sample)", code: "TGS-2026067306",
                 startDate: day(3), endDate: day(3), format: "Physical", classStatus: "Pending", hasMeetingLink: false,
                 trainers: [], learners: 6, venue: nil),
    ]
  }
  static var courses: [StaffCourse] {
    [
      StaffCourse(id: "c1", title: "Agentic AI Applications with Claude Code (sample)", code: "TGS-2025052468", courseType: "WSQ",
                  status: nil, tscTitle: "Artificial Intelligence Application", tscCode: "EGS-TEM-3026-1.1",
                  trainingHours: 7, assessmentHours: 1, fundingValidityEnd: "2027-01-29", upcomingRuns: 4, nextRun: nil),
    ]
  }
}
