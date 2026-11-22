import EventKit
import EventKitUI
import SafariServices
import SwiftUI
import AuthenticationServices
import CryptoKit

@main struct LearningApp: App {
  @UIApplicationDelegateAdaptor(Push.self) var delegate
  @StateObject var store = Store()
  var body: some Scene {
    WindowGroup {
      RootView().environmentObject(store).tint(Theme.accent)
        .preferredColorScheme(store.user == nil ? .light : store.colorScheme)
        .task { await store.restore() }
        // Quiz QR codes carry a universal link; the camera hands it to the app here.
        .onOpenURL { store.handle(url: $0) }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
          if let url = activity.webpageURL { store.handle(url: url) }
        }
    }
  }
}
struct RootView: View {
  @EnvironmentObject var store: Store
  @Environment(\.scenePhase) var phase
  var body: some View {
    Group {
      if store.user != nil && store.mustChangePassword {
        NavigationStack { ChangePasswordView(forced: true) }
      } else if store.user != nil {
        if ProcessInfo.processInfo.environment["START_COURSE_DETAIL"] == "1",
          let course = store.dashboard.courses.first
        {
          NavigationStack { CourseDetail(course: course) }
        } else {
          MainView()
        }
      } else {
        LoginView()
      }
    }
    .sheet(
      item: Binding(
        get: { store.user != nil && !store.mustChangePassword ? store.pendingQuiz : nil },
        set: { store.pendingQuiz = $0 })
    ) { link in
      QuizView(link: link) { store.pendingQuiz = nil }.environmentObject(store)
        .tint(Theme.accent).preferredColorScheme(store.colorScheme).pageSizedSheet()
    }
    .alert(
      "Signed in",
      isPresented: Binding(
        get: { store.user != nil && store.error == nil && store.roleNotice != nil },
        set: { if !$0 { store.roleNotice = nil } })
    ) {
      Button("OK", role: .cancel) { store.roleNotice = nil }
    } message: {
      Text(store.roleNotice ?? "")
    }
    .alert(
      "TIA TMS",
      isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })
    ) {
      Button("OK") { store.error = nil }
    } message: {
      Text(store.error ?? "")
    }
    .onReceive(NotificationCenter.default.publisher(for: .sessionExpired)) { _ in
      store.clear()
      store.error = "Your session expired. Please sign in again."
    }
    .onReceive(NotificationCenter.default.publisher(for: Notification.Name("pushError"))) {
      note in store.error = note.object as? String
    }
    .onReceive(NotificationCenter.default.publisher(for: .openClass)) { note in
      Task {
        await store.refresh()
        store.selectedTab = Store.calendarTab
        if let id = note.object as? String,
          let session = store.dashboard.sessions.first(where: { $0.id == id }),
          let date = session.start
        {
          store.selectedDate = date
        }
      }
    }
    .onChange(of: phase) { _, value in
      if value == .active && store.user != nil {
        Task {
          await store.refresh()
          await store.updateNotificationStatus()
        }
      }
    }
  }
}
/// Sign in with an emailed code (the default) or the LMS/TMS password. Layout follows
/// the TIA house sign-in: app mark, name, one card, quiet links at the foot.
struct LoginView: View {
  @EnvironmentObject var store: Store
  @State var email = UserDefaults.standard.string(forKey: "rememberedEmail") ?? ""
  @State var remember = UserDefaults.standard.object(forKey: "rememberEmail") as? Bool ?? true
  @State var otp = ""
  @State var sent = false
  @State var sending = false
  @State var resendAt = Date.distantPast
  @State var usePassword = false
  @State var password = ""
  @State private var google = GoogleAdminSignIn()
  @State private var googleBusy = false
  @State private var showAdmin = false
  @State private var adminError: String?
  @FocusState private var focus: Field?
  private enum Field { case email, password, code }

  private var trimmedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }
  private var emailValid: Bool { trimmedEmail.contains("@") && trimmedEmail.contains(".") }
  private var busy: Bool { store.busy || sending || googleBusy }
  private var primaryDisabled: Bool {
    if busy || !emailValid { return true }
    if usePassword { return password.isEmpty }
    return sent && otp.count != 6
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 22) {
          // Academy logo, name, then this app's name
          AcademyBrandHeader(appName: Theme.name)
            .padding(.top, 12)

          if store.pendingQuiz != nil {
            Label(
              "Sign in to take your class quiz. It opens as soon as you are signed in.",
              systemImage: "qrcode.viewfinder"
            )
            .font(.subheadline.weight(.medium)).padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 14))
            .accessibilityIdentifier("quiz-pending")
          }

          // The sign-in card
          VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
              Text("Sign in").font(.title2.bold())
              Text(
                sent && !usePassword
                  ? "Enter the 6-digit code we emailed you."
                  : "Enter the email you registered with to continue."
              )
              .font(.subheadline).foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
              Picker("Sign in as", selection: $store.loginChoice) {
                Text("Learner").tag("learner")
                Text("Trainer").tag("trainer")
              }.pickerStyle(.segmented).accessibilityIdentifier("login-role")
              Text(
                store.loginChoice == "trainer"
                  ? "See the classes you teach, attendance, payout and training hours."
                  : "See the courses you are taking. Trainers attending a course sign in as a learner."
              ).font(.footnote).foregroundStyle(.secondary)
            }

            inputRow(icon: "envelope.fill") {
              TextField("Email", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focus, equals: .email)
                .submitLabel(usePassword ? .next : .continue)
                .onSubmit { if usePassword { focus = .password } else { Task { await primary() } } }
                .onChange(of: email) { _, _ in
                  sent = false
                  otp = ""
                }
                .accessibilityIdentifier("email")
            }

            if usePassword {
              inputRow(icon: "lock.fill") {
                SecureField("LMS/TMS password", text: $password)
                  .textContentType(.password)
                  .focused($focus, equals: .password)
                  .submitLabel(.go)
                  .onSubmit { Task { await primary() } }
                  .accessibilityIdentifier("password")
              }
            } else if sent {
              inputRow(icon: "number") {
                TextField("6-digit code", text: $otp)
                  .keyboardType(.numberPad)
                  .textContentType(.oneTimeCode)
                  .focused($focus, equals: .code)
                  .onChange(of: otp) { _, v in otp = String(v.filter(\.isNumber).prefix(6)) }
                  .accessibilityIdentifier("otp")
              }
            }

            Toggle(isOn: $remember) { Text("Remember my email").font(.subheadline) }
              .tint(Theme.brand)
              .onChange(of: remember) { _, on in
                UserDefaults.standard.set(on, forKey: "rememberEmail")
                if !on { UserDefaults.standard.removeObject(forKey: "rememberedEmail") }
              }

            Button {
              Task { await primary() }
            } label: {
              HStack(spacing: 8) {
                if busy { ProgressView().tint(.white) } else { Image(systemName: "arrow.right") }
                Text(usePassword ? "Sign In" : (sent ? "Verify & Sign In" : "Continue"))
              }
              .font(.headline)
              .frame(maxWidth: .infinity)
              .padding(.vertical, 15)
              .foregroundStyle(.white)
              .background(
                Theme.brand.opacity(primaryDisabled ? 0.45 : 1),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(primaryDisabled)
            .accessibilityIdentifier(usePassword ? "sign-in" : "continue")

            HStack {
              if !usePassword, sent {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                  Button(
                    context.date < resendAt
                      ? "New code in \(max(1, Int(resendAt.timeIntervalSince(context.date))))s"
                      : "Send a new code"
                  ) { Task { await send() } }
                  .disabled(busy || context.date < resendAt)
                }
              } else if usePassword {
                Link(
                  "Forgot your password?",
                  destination: URL(string: "https://lms-tms.tertiaryinfotech.com/")!)
              }
              Spacer()
              Button(usePassword ? "Use email code instead" : "Use password instead") {
                usePassword.toggle()
                sent = false
                otp = ""
                password = ""
              }
              .accessibilityIdentifier("sign-in-method")
            }
            .font(.footnote.weight(.medium))
          }
          .padding(20)
          .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
          .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.cardBorder))

          VStack(spacing: 10) {
            Text("Use the email your training provider registered for your class.")
              .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack(spacing: 16) {
              // A look around with sample data, for anyone without an account (and App Review).
              Menu("Try a demo") {
                Button("As a learner") { store.openDemo("learner") }
                Button("As a trainer") { store.openDemo("trainer") }
              }.accessibilityIdentifier("demo")
              Link(
                "Privacy policy",
                destination: URL(string: "https://lms-tms.tertiaryinfotech.com/mobile/privacy.html")!)
              // Deliberately quiet: staff know it is here. Opens the admin page.
              Button("Admin sign-in") {
                adminError = nil
                showAdmin = true
              }
              .disabled(busy)
              .accessibilityIdentifier("admin-sign-in")
            }
            .font(.footnote)
            .tint(.secondary)
          }
          .padding(.horizontal, 8)
        }
        .padding(20)
        .frame(maxWidth: 620)
        .frame(maxWidth: .infinity)
      }
      .background(
        LinearGradient(colors: [Theme.page, Theme.accentSoft], startPoint: .top, endPoint: .bottom)
          .ignoresSafeArea()
      )
      .scrollDismissesKeyboard(.interactively)
      .toolbar(.hidden, for: .navigationBar)
      .sheet(isPresented: $showAdmin) {
        AdminSignInPage(appName: Theme.name, busy: googleBusy, error: adminError) { remember in
          Task { await signInAsAdmin(remember: remember) }
        }
      }
    }
  }

  private func inputRow<Content: View>(icon: String, @ViewBuilder content: () -> Content)
    -> some View
  {
    HStack(spacing: 12) {
      Image(systemName: icon).foregroundStyle(.secondary).frame(width: 22)
      content()
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 14)
    .background(Theme.page, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.cardBorder, lineWidth: 1))
  }

  private func rememberEmail() {
    if remember { UserDefaults.standard.set(trimmedEmail, forKey: "rememberedEmail") }
  }

  private func primary() async {
    guard !primaryDisabled else { return }
    rememberEmail()
    if usePassword {
      await store.login(email: trimmedEmail, password: password)
      password = ""
    } else if sent {
      await store.login(email: trimmedEmail, otp: otp)
    } else {
      await send()
    }
  }

  /// Admin sign-in: Google in the system sign-in sheet, for allow-listed admin accounts only.
  private func signInAsAdmin(remember: Bool) async {
    googleBusy = true
    adminError = nil
    defer { googleBusy = false }
    do {
      let result = try await google.start(ephemeral: !remember)
      try await store.loginWithGoogle(code: result.code, verifier: result.verifier)
      AdminRemember.signedIn(email: store.user?.email ?? "")
      showAdmin = false
    } catch GoogleAdminSignIn.Failure.cancelled {
      // Closed the Google sheet: nothing to report.
    } catch {
      adminError = error.localizedDescription
    }
  }

  func send() async {
    sending = true
    defer { sending = false }
    do {
      let _: EmptyReply = try await API.shared.request(
        "mobile/auth", method: "POST", body: ["action": "send", "email": trimmedEmail])
      sent = true
      otp = ""
      resendAt = Date().addingTimeInterval(60)
      focus = .code
    } catch { store.error = error.localizedDescription }
  }
}
struct SessionCard: View {
  let session: ClassSession
  var body: some View {
    HStack(alignment: .top, spacing: 16) {
      VStack {
        Text(
          session.start?.formatted(
            Date.FormatStyle(
              date: .omitted, time: .omitted, timeZone: TimeZone(identifier: "Asia/Singapore")!
            ).month(.abbreviated)) ?? "TBC"
        ).font(.caption.bold())
        Text(
          session.start?.formatted(
            Date.FormatStyle(
              date: .omitted, time: .omitted, timeZone: TimeZone(identifier: "Asia/Singapore")!
            ).day()) ?? "—"
        ).font(.title.bold())
      }.foregroundStyle(Theme.accent).frame(width: 52).padding(.vertical, 12).background(
        Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
      VStack(alignment: .leading, spacing: 6) {
        Text(session.title).font(.headline)
        Text(session.subtitle).font(.subheadline).foregroundStyle(.secondary)
        Text("\(session.timeLabel) · \(session.format ?? "Class")").font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
      Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
    }.padding(16).background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.cardBorder, lineWidth: 1))
  }
}
struct MaterialLink: View {
  let title: String
  let icon: String
  let raw: String?
  @State var showing = false
  var url: URL? {
    guard let raw, !raw.isEmpty,
      let url = URL(string: raw, relativeTo: API.shared.base)?.absoluteURL, url.scheme == "https"
    else { return nil }
    return url
  }
  var body: some View {
    if let url {
      Button {
        showing = true
      } label: {
        Label(title, systemImage: icon)
      }.sheet(isPresented: $showing) { Browser(url: url).ignoresSafeArea() }
    } else {
      Label("\(title) · not published yet", systemImage: icon).foregroundStyle(.secondary)
    }
  }
}
struct Browser: UIViewControllerRepresentable {
  let url: URL
  func makeUIViewController(context: Context) -> SFSafariViewController {
    SFSafariViewController(url: url)
  }
  func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
/// A standard month calendar: one box per day, each listing that day's confirmed classes.
/// Past and upcoming classes both show (past ones muted); pending, unconfirmed and
/// rescheduled classes do not. Tap a day to list its classes below the grid.
struct CalendarView: View {
  @EnvironmentObject var store: Store
  @Environment(\.horizontalSizeClass) private var sizeClass
  @State private var month = Date()

  private static let zone = TimeZone(identifier: "Asia/Singapore")!
  private var calendar: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = Self.zone
    c.locale = Locale(identifier: "en_SG")
    return c
  }
  private var wide: Bool { sizeClass == .regular }

  /// Confirmed sessions by day (midnight SGT). A run without published sessions covers
  /// every day from its start to its end date.
  private func index() -> [Date: [ClassSession]] {
    var out: [Date: [ClassSession]] = [:]
    for s in store.confirmedSessions {
      guard let first = Fmt.day(s.startDate) else { continue }
      let last = Fmt.day(s.endDate) ?? first
      var day = calendar.startOfDay(for: first)
      var guardCount = 0
      while day <= last && guardCount < 62 {
        out[day, default: []].append(s)
        day = calendar.date(byAdding: .day, value: 1, to: day)!
        guardCount += 1
      }
    }
    for key in out.keys {
      out[key]?.sort { ($0.startTime ?? "99") < ($1.startTime ?? "99") }
    }
    return out
  }

  private var monthStart: Date {
    calendar.date(from: calendar.dateComponents([.year, .month], from: month))!
  }
  /// The grid's days: leading blanks (nil) up to the first weekday, then each day.
  private var gridDays: [Date?] {
    let first = monthStart
    let lead = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
    let count = calendar.range(of: .day, in: .month, for: first)!.count
    var days: [Date?] = Array(repeating: nil, count: lead)
    for i in 0..<count { days.append(calendar.date(byAdding: .day, value: i, to: first)) }
    while days.count % 7 != 0 { days.append(nil) }
    return days
  }
  private var monthTitle: String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_SG")
    f.timeZone = Self.zone
    f.dateFormat = "MMMM yyyy"
    return f.string(from: monthStart)
  }
  private func monthClassCount(_ byDay: [Date: [ClassSession]]) -> Int {
    let ids = byDay.filter { calendar.isDate($0.key, equalTo: monthStart, toGranularity: .month) }
      .flatMap { $0.value.map(\.courseID) }
    return Set(ids).count
  }
  private var selectedDay: Date { calendar.startOfDay(for: store.selectedDate) }

  var body: some View {
    let byDay = index()
    return TabPage(title: "Calendar") {
      VStack(spacing: 0) {
        header.padding(.horizontal, 14).padding(.vertical, 12)
        weekdayRow
        grid(byDay)
      }
      .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.cardBorder))
      .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
      .gesture(
        DragGesture(minimumDistance: 30).onEnded { value in
          guard abs(value.translation.width) > abs(value.translation.height) else { return }
          shift(value.translation.width < 0 ? 1 : -1)
        })

      HStack(spacing: 14) {
        legend(color: Theme.brand, text: "Upcoming")
        legend(color: Color(.systemGray3), text: "Past")
        Spacer()
        let count = monthClassCount(byDay)
        Text("\(count) confirmed class\(count == 1 ? "" : "es")")
      }
      .font(.caption).foregroundStyle(.secondary)

      dayList(byDay[selectedDay] ?? [])
    }
    .refreshable { await store.refresh() }
    .onAppear { month = store.selectedDate }
    .onChange(of: store.selectedDate) { _, date in
      if !calendar.isDate(date, equalTo: month, toGranularity: .month) { month = date }
    }
  }

  private var header: some View {
    HStack(spacing: 6) {
      Text(monthTitle).font(.title3.bold())
      Spacer()
      Button("Today") {
        store.selectedDate = Date()
        month = Date()
      }
      .font(.subheadline.weight(.semibold)).buttonStyle(.bordered).controlSize(.small)
      Button { shift(-1) } label: {
        Image(systemName: "chevron.left").frame(width: 34, height: 34)
      }.accessibilityLabel("Previous month")
      Button { shift(1) } label: {
        Image(systemName: "chevron.right").frame(width: 34, height: 34)
      }.accessibilityLabel("Next month")
    }
    .font(.body.weight(.semibold))
  }

  private var weekdayRow: some View {
    let symbols = calendar.shortWeekdaySymbols
    let ordered = Array(symbols[(calendar.firstWeekday - 1)...] + symbols[..<(calendar.firstWeekday - 1)])
    return HStack(spacing: 0) {
      ForEach(ordered, id: \.self) { name in
        Text(name.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
          .frame(maxWidth: .infinity).padding(.vertical, 6)
      }
    }
    .background(Theme.page)
    .overlay(alignment: .bottom) { Rectangle().fill(Theme.cardBorder).frame(height: 1) }
  }

  private func grid(_ byDay: [Date: [ClassSession]]) -> some View {
    let days = gridDays
    return VStack(spacing: 0) {
      ForEach(0..<(days.count / 7), id: \.self) { row in
        HStack(spacing: 0) {
          ForEach(0..<7, id: \.self) { col in
            cell(days[row * 7 + col], byDay)
              .overlay(alignment: .trailing) {
                if col < 6 { Rectangle().fill(Theme.cardBorder).frame(width: 1) }
              }
          }
        }
        .overlay(alignment: .bottom) {
          if row < days.count / 7 - 1 { Rectangle().fill(Theme.cardBorder).frame(height: 1) }
        }
      }
    }
  }

  @ViewBuilder private func cell(_ day: Date?, _ byDay: [Date: [ClassSession]]) -> some View {
    let height: CGFloat = wide ? 104 : 72
    if let day {
      let classes = byDay[day] ?? []
      let isToday = calendar.isDateInToday(day)
      let isSelected = calendar.isDate(day, inSameDayAs: selectedDay)
      let past = day < calendar.startOfDay(for: Date())
      let limit = wide ? 3 : 2
      Button {
        store.selectedDate = day
      } label: {
        VStack(alignment: .leading, spacing: 2) {
          Text("\(calendar.component(.day, from: day))")
            .font(.footnote.weight(isToday || isSelected ? .bold : .regular))
            .foregroundStyle(isSelected ? Color.white : isToday ? Theme.accent : .primary)
            .frame(width: 24, height: 24)
            .background {
              if isSelected { Circle().fill(Theme.brand) } else if isToday {
                Circle().fill(Theme.accentSoft)
              }
            }
          ForEach(classes.prefix(limit)) { s in
            Text(s.title)
              .font(.system(size: wide ? 11 : 9, weight: .semibold))
              .lineLimit(1)
              .padding(.horizontal, 3).padding(.vertical, 1)
              .frame(maxWidth: .infinity, alignment: .leading)
              .foregroundStyle(past ? Color.primary.opacity(0.7) : Color.white)
              .background(
                past ? Color(.systemGray4) : Theme.brand,
                in: RoundedRectangle(cornerRadius: 3, style: .continuous))
          }
          if classes.count > limit {
            Text("+\(classes.count - limit) more").font(.system(size: 9, weight: .medium))
              .foregroundStyle(.secondary)
          }
          Spacer(minLength: 0)
        }
        .padding(3)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
        .background(Rectangle().fill(isSelected ? Theme.accentSoft : Color.clear))
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(accessibilityLabel(day, classes.count))
      .accessibilityAddTraits(isSelected ? .isSelected : [])
    } else {
      Color(.systemGray6).opacity(0.5)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
    }
  }

  @ViewBuilder private func dayList(_ daily: [ClassSession]) -> some View {
    Text("\(Fmt.longDate(Self.key(selectedDay))) · Singapore time")
      .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 4)
    if daily.isEmpty {
      InfoCard {
        VStack(alignment: .leading, spacing: 8) {
          Text("No confirmed classes on this day").font(.headline)
          Text("Pick another day, or swipe the calendar to change month.")
            .font(.subheadline).foregroundStyle(.secondary)
          if let next = store.upcoming.first(where: { s in
            store.dashboard.courses.contains { $0.id == s.courseID && $0.isConfirmed }
          })?.start {
            Button("Jump to next class") { store.selectedDate = next }.buttonStyle(.bordered)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    ForEach(daily) { s in
      NavigationLink {
        SessionDetail(session: s)
      } label: {
        InfoCard {
          HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2).fill(
              (s.end ?? s.start ?? .distantPast) < Date() ? Color(.systemGray3) : Theme.brand
            ).frame(width: 4)
            VStack(alignment: .leading, spacing: 4) {
              Text(s.title).font(.headline).foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
              Text(
                s.startTime == nil
                  ? s.subtitle : "\(s.timeLabel)–\(s.endTimeLabel) · \(s.subtitle)"
              )
              .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
              .foregroundStyle(.tertiary)
          }
        }
      }
      .buttonStyle(.plain)
    }
  }

  private func legend(color: Color, text: String) -> some View {
    HStack(spacing: 5) {
      RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 12, height: 8)
      Text(text)
    }
  }

  private func shift(_ months: Int) {
    if let next = calendar.date(byAdding: .month, value: months, to: monthStart) {
      withAnimation(.easeInOut(duration: 0.2)) { month = next }
    }
  }

  private func accessibilityLabel(_ day: Date, _ count: Int) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_SG")
    f.timeZone = Self.zone
    f.dateFormat = "EEEE d MMMM"
    let classes = count == 0 ? "no classes" : "\(count) class\(count == 1 ? "" : "es")"
    return "\(f.string(from: day)), \(classes)"
  }

  private static func key(_ day: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = zone
    f.dateFormat = "yyyy-MM-dd"
    return f.string(from: day)
  }
}
struct SessionDetail: View {
  @EnvironmentObject var store: Store
  let session: ClassSession
  @State var add = false
  var body: some View {
    List {
      Section {
        Text(session.title).font(.title2.bold())
        Text(session.subtitle).foregroundStyle(.secondary)
      }
      Section("When & where") {
        LabeledContent("Date", value: session.dateLabel)
        LabeledContent(
          "Time (SGT)", value: "\(session.timeLabel)–\(session.endTimeLabel)")
        LabeledContent("Format", value: session.format ?? "Class")
        Text(session.venue?.isEmpty == false ? session.venue! : "Venue to be confirmed")
        if let url = session.meetingURL, !url.isEmpty {
          MaterialLink(title: "Join online class", icon: "video", raw: url)
        }
      }
      Section {
        if session.start != nil && session.startTime != nil {
          Button {
            add = true
          } label: {
            Label("Add to Apple Calendar", systemImage: "calendar.badge.plus")
          }
        }
      }
      Section("Your class") {
        if let course = store.dashboard.courses.first(where: { $0.id == session.courseID }) {
          NavigationLink("Open class: courseware, attendance, assessments") {
            CourseDetail(course: course)
          }
        }
      }
      Section("Reminders") {
        Text(
          "With notifications enabled, reminders arrive 3 days and 1 day before class and on the morning of class. Delivery depends on your device settings and connectivity."
        ).font(.subheadline)
      }
    }.navigationTitle("Class details").navigationBarTitleDisplayMode(.inline).sheet(
      isPresented: $add
    ) { EventEditor(session: session) }
  }
}
struct EventEditor: UIViewControllerRepresentable {
  let session: ClassSession
  @Environment(\.dismiss) var dismiss
  func makeCoordinator() -> Coordinator { Coordinator(self) }
  func makeUIViewController(context: Context) -> EKEventEditViewController {
    let c = EKEventEditViewController()
    c.eventStore = EKEventStore()
    let e = EKEvent(eventStore: c.eventStore)
    e.title = session.title
    e.startDate = session.start
    e.endDate = session.end ?? session.start?.addingTimeInterval(3600)
    e.timeZone = TimeZone(identifier: "Asia/Singapore")
    e.location = session.venue
    e.notes = session.subtitle
    e.url = URL(string: session.meetingURL ?? "")
    c.event = e
    c.editViewDelegate = context.coordinator
    return c
  }
  func updateUIViewController(_ c: EKEventEditViewController, context: Context) {}
  class Coordinator: NSObject, EKEventEditViewDelegate {
    let parent: EventEditor
    init(_ p: EventEditor) { parent = p }
    func eventEditViewController(
      _ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction
    ) { parent.dismiss() }
  }
}
struct FeedbackView: View {
  @State var title = ""
  @State var message = ""
  @Environment(\.openURL) var openURL
  var body: some View {
    Form {
      Section("Send feedback") {
        TextField("Title", text: $title)
        TextEditor(text: $message).frame(minHeight: 150).accessibilityLabel("Message")
        Button("Send via WhatsApp") {
          var c = URLComponents(string: "https://wa.me/6588666375")!
          c.queryItems = [
            URLQueryItem(name: "text", value: "TIA TMS: \(title)\n\(message)")
          ]
          if let url = c.url { openURL(url) }
        }.disabled(title.isEmpty || message.isEmpty)
      }
      Section {
        Text("WhatsApp opens with your draft. You choose whether to send it.").font(.footnote)
      }
    }.navigationTitle("Feedback")
  }
}
struct AboutView: View {
  var body: some View {
    List {
      Section(Theme.name) {
        AcademyHeader(compact: true)
        Label("Learning, in your pocket", systemImage: "graduationcap.fill").font(.headline)
        Text(
          "The official Tertiary Infotech Academy app for learners and trainers: classes, courseware, attendance, assessments, course feedback and reminders."
        )
      }
      Section("Developer") {
        Text("Tertiary Infotech Academy Pte Ltd")
        Link("tertiaryinfotech.com", destination: URL(string: "https://tertiaryinfotech.com")!)
      }
      Section {
        LabeledContent(
          "Version",
          value:
            "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"))"
        )
      }
    }.navigationTitle("About")
  }
}

/// Admin sign-in with Google, through the LMS/TMS's own Google sign-in. The app sends the
/// hash of a random verifier; the server answers at tiatms://auth with a single-use code,
/// which only this verifier can exchange for a session.
@MainActor
final class GoogleAdminSignIn: NSObject, ASWebAuthenticationPresentationContextProviding {
  enum Failure: LocalizedError {
    case cancelled
    case message(String)
    var errorDescription: String? {
      switch self {
      case .cancelled: "Sign-in was cancelled."
      case .message(let m): m
      }
    }
  }

  private var session: ASWebAuthenticationSession?

  /// `ephemeral`: do not keep the Google sign-in in the browser (Remember me off).
  func start(ephemeral: Bool = false) async throws -> (code: String, verifier: String) {
    var bytes = [UInt8](repeating: 0, count: 32)
    _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    let verifier = bytes.map { String(format: "%02x", $0) }.joined()
    let challenge = SHA256.hash(data: Data(verifier.utf8)).map { String(format: "%02x", $0) }
      .joined()
    var components = URLComponents(
      url: API.shared.base.appendingPathComponent("api/mobile/google-start"),
      resolvingAgainstBaseURL: false)!
    components.queryItems = [URLQueryItem(name: "challenge", value: challenge)]

    let callback: URL = try await withCheckedThrowingContinuation { continuation in
      let s = ASWebAuthenticationSession(url: components.url!, callbackURLScheme: "tiatms") {
        url, error in
        if let url {
          continuation.resume(returning: url)
        } else if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
          continuation.resume(throwing: Failure.cancelled)
        } else {
          continuation.resume(
            throwing: Failure.message("Google sign-in could not start. Please try again."))
        }
      }
      s.presentationContextProvider = self
      s.prefersEphemeralWebBrowserSession = ephemeral
      session = s
      if !s.start() {
        continuation.resume(
          throwing: Failure.message("Google sign-in could not start. Please try again."))
      }
    }
    session = nil
    let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
    if let message = items.first(where: { $0.name == "error" })?.value {
      throw Failure.message(message)
    }
    guard let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
      throw Failure.message("Google sign-in did not complete. Please try again.")
    }
    return (code, verifier)
  }

  func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
    UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
      ?? ASPresentationAnchor()
  }
}
