import EventKit
import EventKitUI
import SafariServices
import SwiftUI

@main struct LearningApp: App {
  @UIApplicationDelegateAdaptor(Push.self) var delegate
  @StateObject var store = Store()
  var body: some Scene {
    WindowGroup {
      RootView().environmentObject(store).tint(Theme.accent).task { await store.restore() }
    }
  }
}
struct RootView: View {
  @EnvironmentObject var store: Store
  @Environment(\.scenePhase) var phase
  var body: some View {
    Group { if store.user != nil { MainView() } else { LoginView() } }
      .alert(
        "Learning portal",
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
          store.selectedTab = 2
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
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          Image(systemName: "graduationcap.fill").font(.system(size: 52)).foregroundStyle(
            Theme.accent
          )
          .padding(.top, 40)
          Text("Your learning.\nAll in one place.").font(.largeTitle.bold())
          Text("Course materials, class schedules and timely reminders for learners and trainers.")
            .foregroundStyle(.secondary)
          VStack(alignment: .leading, spacing: 16) {
            Text("Sign in with email").font(.title2.bold())
            TextField("Registered email address", text: $email).textContentType(.emailAddress)
              .keyboardType(.emailAddress).textInputAutocapitalization(.never)
              .autocorrectionDisabled().padding().background(
                .background, in: RoundedRectangle(cornerRadius: 12)
              ).disabled(sent).accessibilityIdentifier("email")
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
          }.padding(20).background(
            Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
          Text(
            "Use the email registered with your training provider. Only learner and trainer roles are available in this app."
          ).font(.footnote).foregroundStyle(.secondary)
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
struct MainView: View {
  @EnvironmentObject var store: Store
  var body: some View {
    VStack(spacing: 0) {
      if store.demo {
        Text("SAMPLE DATA · \(store.role.uppercased()) DEMO").font(.caption.weight(.semibold))
          .frame(maxWidth: .infinity).padding(6).background(.yellow.opacity(0.2))
      }
      TabView(selection: $store.selectedTab) {
        NavigationStack { HomeView() }.tabItem { Label("Today", systemImage: "sun.max.fill") }.tag(
          0)
        NavigationStack { CoursesView() }.tabItem {
          Label("Courseware", systemImage: "books.vertical.fill")
        }.tag(1)
        NavigationStack { CalendarView() }.tabItem { Label("Calendar", systemImage: "calendar") }
          .tag(
            2)
        NavigationStack { AccountView() }.tabItem {
          Label("Account", systemImage: "person.crop.circle")
        }.tag(3)
      }
    }
  }
}
struct HomeView: View {
  @EnvironmentObject var store: Store
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        VStack(alignment: .leading, spacing: 10) {
          Text(store.role == "trainer" ? "READY TO INSPIRE" : "KEEP LEARNING").font(.caption.bold())
            .tracking(2)
          Text("Hello, \(store.user?.fullName.components(separatedBy:" ").first ?? "there").").font(
            .largeTitle.bold())
          Text(
            store.role == "trainer"
              ? "Your teaching day, organised." : "Your next step starts here."
          ).font(.headline)
        }.foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading).padding(26)
          .background(
            LinearGradient(
              colors: [Theme.hero, Color(red: 0.04, green: 0.24, blue: 0.32)],
              startPoint: .topLeading,
              endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 28))
        HStack {
          Stat(value: "\(store.dashboard.courses.count)", label: "Courses", icon: "books.vertical")
          Stat(value: "\(store.upcoming.count)", label: "Upcoming classes", icon: "calendar")
        }
        HStack {
          Text("Up next").font(.title2.bold())
          Spacer()
          Button("See calendar") { store.selectedTab = 2 }
        }
        if store.upcoming.isEmpty {
          ContentUnavailableView(
            "No upcoming classes", systemImage: "calendar.badge.checkmark",
            description: Text("Your scheduled classes will appear here."))
        }
        ForEach(store.upcoming.prefix(3)) { s in
          NavigationLink {
            SessionDetail(session: s)
          } label: {
            SessionCard(session: s)
          }.buttonStyle(.plain)
        }
        if !store.notifications {
          Button {
            Task { await store.enableNotifications() }
          } label: {
            Label("Enable 3-day and 1-day reminders", systemImage: "bell.badge").frame(
              maxWidth: .infinity
            ).padding(12)
          }.buttonStyle(.bordered)
        }
        Text("Class times are shown in Singapore time (SGT).").font(.footnote).foregroundStyle(
          .secondary)
      }.padding(20).frame(maxWidth: 760)
    }.background(Color(.systemGroupedBackground)).navigationTitle("Today").refreshable {
      await store.refresh()
    }
  }
}
struct Stat: View {
  let value: String
  let label: String
  let icon: String
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Image(systemName: icon).foregroundStyle(Theme.accent)
      Text(value).font(.largeTitle.bold())
      Text(label).font(.subheadline).foregroundStyle(.secondary)
    }.frame(maxWidth: .infinity, alignment: .leading).padding(18).background(
      .background, in: RoundedRectangle(cornerRadius: 20))
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
        .teal.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
      VStack(alignment: .leading, spacing: 6) {
        Text(session.title).font(.headline)
        Text(session.subtitle).font(.subheadline).foregroundStyle(.secondary)
        Text("\(session.timeLabel) · \(session.format ?? "Class")").font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
      Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
    }.padding(16).background(.background, in: RoundedRectangle(cornerRadius: 20))
  }
}
struct CoursesView: View {
  @EnvironmentObject var store: Store
  @State var query = ""
  var filtered: [Course] {
    store.dashboard.courses.filter {
      query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)
        || ($0.code ?? "").localizedCaseInsensitiveContains(query)
    }
  }
  var body: some View {
    List {
      if filtered.isEmpty {
        ContentUnavailableView(
          "No courses found", systemImage: "books.vertical",
          description: Text("Courses assigned to your account will appear here."))
      }
      ForEach(filtered) { c in
        NavigationLink {
          CourseDetail(course: c)
        } label: {
          VStack(alignment: .leading, spacing: 10) {
            Label(c.code ?? "Course", systemImage: "book.closed.fill").font(.caption)
              .foregroundStyle(Theme.accent)
            Text(c.title).font(.headline)
            Text("\(c.startDate ?? "Dates to be confirmed") · \(c.format ?? "Class")").font(
              .caption
            ).foregroundStyle(.secondary)
          }.padding(.vertical, 12)
        }
      }
    }.navigationTitle("Courseware").searchable(text: $query, prompt: "Find your course").refreshable
    { await store.refresh() }
  }
}
struct CourseDetail: View {
  @EnvironmentObject var store: Store
  let course: Course
  var body: some View {
    List {
      Section {
        Text(course.title).font(.title2.bold())
        LabeledContent("Course code", value: course.code ?? "—")
        LabeledContent("Delivery", value: course.format ?? "—")
      }
      Section("Learning materials") {
        MaterialLink(title: "Slides", icon: "rectangle.on.rectangle", raw: course.slidesURL)
        MaterialLink(title: "Learner guide", icon: "book", raw: course.guideURL)
        MaterialLink(title: "Labs & activities", icon: "laptopcomputer", raw: course.activitiesURL)
        if store.role == "trainer" {
          MaterialLink(
            title: "Trainer slides", icon: "person.crop.rectangle", raw: course.trainerSlidesURL)
        }
      }
      Section("Class sessions") {
        ForEach(store.dashboard.sessions.filter { $0.courseID == course.id }) { s in
          NavigationLink {
            SessionDetail(session: s)
          } label: {
            VStack(alignment: .leading) {
              Text(s.subtitle)
              Text("\(s.dateLabel) · \(s.timeLabel) SGT").font(.caption)
                .foregroundStyle(.secondary)
            }
          }
        }
      }
    }.navigationTitle("Course details").navigationBarTitleDisplayMode(.inline)
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
      Section("Courseware") {
        if let course = store.dashboard.courses.first(where: { $0.id == session.courseID }) {
          NavigationLink("Open learning materials") { CourseDetail(course: course) }
        }
      }
      Section("Reminders") {
        Text(
          "With notifications enabled, reminders are sent 3 days and 1 day before class. Delivery depends on your device settings and connectivity."
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
struct AccountView: View {
  @EnvironmentObject var store: Store
  @State var confirmDelete = false
  var body: some View {
    List {
      Section("Your account") {
        Text(store.user?.fullName ?? "").font(.headline)
        Text(store.user?.email ?? "").foregroundStyle(.secondary)
        if store.roles.count > 1 {
          Picker("View as", selection: $store.role) {
            ForEach(store.roles, id: \.self) { Text($0.capitalized).tag($0) }
          }.onChange(of: store.role) { _, _ in
            store.dashboard = Dashboard(courses: [], sessions: [])
            Task { await store.refresh() }
          }
        } else {
          LabeledContent("Role", value: store.role.capitalized)
        }
      }
      Section("Class reminders") {
        Label("3 days before class", systemImage: "bell")
        Label("1 day before class", systemImage: "bell.badge")
        Button(store.notifications ? "Notification settings" : "Enable notifications") {
          if store.notifications {
            UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
          } else {
            Task { await store.enableNotifications() }
          }
        }
        Text(
          store.demo
            ? "Sample mode does not register a device for real class reminders."
            : "Notifications follow your current class assignments."
        ).font(.footnote).foregroundStyle(.secondary)
      }
      Section {
        NavigationLink("Feedback") { FeedbackView() }
        NavigationLink("About") { AboutView() }
        Link(
          "Privacy policy",
          destination: URL(string: "https://lms-tms.tertiaryinfotech.com/mobile/privacy.html")!)
        Button(store.demo ? "Exit demo" : "Sign out", role: .destructive) {
          Task { await store.signOut() }
        }
      }
      Section {
        Button("Delete account", role: .destructive) { confirmDelete = true }
      } footer: {
        Text(
          "Initiate permanent account deletion. Training records that must be retained will be handled by your training provider."
        )
      }
    }.navigationTitle("Account").confirmationDialog(
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
            URLQueryItem(name: "text", value: "Tertiary LMS: \(title)\n\(message)")
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
        Label("Learning, in your pocket", systemImage: "graduationcap.fill").font(.headline)
        Text(
          "Access your assigned courseware, plan your classes and receive reminders. Built for learners and trainers using the Tertiary learning portal."
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
