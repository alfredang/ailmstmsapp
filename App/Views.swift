import EventKit
import EventKitUI
import SafariServices
import SwiftUI

@main struct LearningApp: App {
  @UIApplicationDelegateAdaptor(Push.self) var delegate
  @StateObject var store = Store()
  var body: some Scene {
    WindowGroup {
      RootView().environmentObject(store).tint(Theme.accent)
        .preferredColorScheme(store.colorScheme).task { await store.restore() }
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
struct LoginView: View {
  @EnvironmentObject var store: Store
  @State var email = ""
  @State var otp = ""
  @State var sent = false
  @State var sending = false
  @State var resendAt = Date.distantPast
  @State var usePassword = false
  @State var password = ""
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          AcademyHeader()
            .padding(.top, 32)
          Text("Your academy day,\nready when you are.").font(.largeTitle.bold())
          Text(
            "Secure access to the Tertiary courses, teaching kits and Singapore class sessions assigned to you."
          )
          .foregroundStyle(.secondary)
          if store.pendingQuiz != nil {
            Label(
              "Sign in to take your class quiz. It opens as soon as you are signed in.",
              systemImage: "qrcode.viewfinder"
            )
            .font(.subheadline.weight(.medium)).padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            .accessibilityIdentifier("quiz-pending")
          }
          VStack(alignment: .leading, spacing: 16) {
            Text("Sign in").font(.title2.bold())
            VStack(alignment: .leading, spacing: 6) {
              Text("Sign in as").font(.subheadline.weight(.semibold))
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
            Picker("Sign-in method", selection: $usePassword) {
              Text("Email code").tag(false)
              Text("Password").tag(true)
            }.pickerStyle(.segmented).disabled(sent).accessibilityIdentifier("sign-in-method")
            TextField("Registered email address", text: $email).textContentType(.emailAddress)
              .keyboardType(.emailAddress).textInputAutocapitalization(.never)
              .autocorrectionDisabled().padding().background(
                .background, in: RoundedRectangle(cornerRadius: 12)
              ).disabled(sent && !usePassword).accessibilityIdentifier("email")
            if usePassword {
              SecureField("Password", text: $password).textContentType(.password).padding()
                .background(.background, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("password")
              Button {
                Task {
                  await store.login(
                    email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                    password: password)
                  password = ""
                }
              } label: {
                Text(store.busy ? "Signing in…" : "Sign in").frame(maxWidth: .infinity).padding(6)
              }.buttonStyle(.borderedProminent).disabled(
                store.busy || !email.contains("@") || password.isEmpty)
              Text("Use the same password as lms-tms.tertiaryinfotech.com.").font(.footnote)
                .foregroundStyle(.secondary)
            } else {
              if sent {
                Text("Enter the six-digit code sent to your email.").font(.subheadline)
                TextField("Verification code", text: $otp).keyboardType(.numberPad).textContentType(
                  .oneTimeCode
                ).padding().background(.background, in: RoundedRectangle(cornerRadius: 12))
                  .accessibilityIdentifier("otp").onChange(of: otp) { _, v in
                    otp = String(v.filter(\.isNumber).prefix(6))
                  }
                Button {
                  Task {
                    await store.login(
                      email: email.trimmingCharacters(in: .whitespacesAndNewlines), otp: otp)
                  }
                } label: {
                  Text(store.busy ? "Signing in…" : "Sign in").frame(maxWidth: .infinity).padding(6)
                }.buttonStyle(.borderedProminent).disabled(store.busy || otp.count != 6)
                Button("Use a different email") {
                  sent = false
                  otp = ""
                }
              }
              TimelineView(.periodic(from: .now, by: 1)) { context in
                Button(
                  sent
                    ? (context.date < resendAt
                      ? "Resend code in \(max(1,Int(resendAt.timeIntervalSince(context.date))))s"
                      : "Resend code") : "Send verification code"
                ) { Task { await send() } }.buttonStyle(.bordered).disabled(
                  sending || !email.contains("@") || context.date < resendAt)
              }
            }
          }.padding(20).background(
            Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
          HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.shield.fill").foregroundStyle(Theme.brandBlue)
            Text(
              "This is Tertiary Infotech Academy's first-party learning workspace. Sign-in and course access are verified by the academy's own training management system."
            ).font(.footnote).foregroundStyle(.secondary)
          }
          Menu("Explore sample app") {
            Button("Learner demo") { store.openDemo("learner") }
            Button("Trainer demo") { store.openDemo("trainer") }
          }.accessibilityIdentifier("demo")
          Link(
            "Privacy policy",
            destination: URL(string: "https://lms-tms.tertiaryinfotech.com/mobile/privacy.html")!
          ).font(.footnote)
        }.padding(24).frame(maxWidth: 620)
      }.background(Color(.systemGroupedBackground)).navigationTitle(Theme.name)
        .navigationBarTitleDisplayMode(.inline)
    }
  }
  func send() async {
    sending = true
    defer { sending = false }
    do {
      let _: EmptyReply = try await API.shared.request(
        "mobile/auth", method: "POST",
        body: ["action": "send", "email": email.trimmingCharacters(in: .whitespacesAndNewlines)])
      sent = true
      resendAt = Date().addingTimeInterval(60)
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
struct CalendarView: View {
  @EnvironmentObject var store: Store
  var calendar: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Asia/Singapore")!
    return c
  }
  var daily: [ClassSession] {
    store.dashboard.sessions.filter {
      if let d = $0.start { return calendar.isDate(d, inSameDayAs: store.selectedDate) }
      return false
    }
  }
  var body: some View {
    List {
      Section {
        DatePicker("Class date", selection: $store.selectedDate, displayedComponents: .date)
          .datePickerStyle(.graphical).environment(
            \.timeZone, TimeZone(identifier: "Asia/Singapore")!)
      }
      Section("Classes · Singapore time") {
        if daily.isEmpty {
          ContentUnavailableView(
            "No classes on this day", systemImage: "calendar",
            description: Text("Select another date or jump to your next class."))
          if let next = store.upcoming.first?.start {
            Button("Jump to next class") { store.selectedDate = next }
          }
        }
        ForEach(daily) { s in
          NavigationLink {
            SessionDetail(session: s)
          } label: {
            VStack(alignment: .leading, spacing: 6) {
              Text(s.title).font(.headline)
              Text("\(s.timeLabel)–\(s.endTimeLabel) · \(s.subtitle)").font(
                .subheadline
              ).foregroundStyle(.secondary)
            }
          }
        }
      }
    }.navigationTitle("Calendar").refreshable { await store.refresh() }
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
