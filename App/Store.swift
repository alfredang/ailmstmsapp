import SwiftUI
import UserNotifications

@MainActor final class Store: ObservableObject {
  @Published var user: User?
  @Published var role = "learner"
  @Published var dashboard = Dashboard(courses: [], sessions: [])
  @Published var busy = false
  @Published var error: String?
  @Published var demo = false
  @Published var notifications = false
  @Published var selectedTab = Int(ProcessInfo.processInfo.environment["START_TAB"] ?? "0") ?? 0
  @Published var selectedDate = Date()
  @Published private(set) var openedMaterials: Set<String> = []
  @Published var profile: Profile?
  /// Sample-mode state, so check-ins, submissions and grades made in the demo are visible.
  var demoDetails: [String: ClassDetail] = [:]
  var demoSheets: [String: AttendanceSheet] = [:]
  var demoQuizAttempts: [String: QuizAttempt] = [:]
  /// The quiz a QR code link asked for. Kept while signed out, so it opens right after sign-in.
  @Published var pendingQuiz: QuizLink?
  @Published var mustChangePassword = false
  /// "system", "light" or "dark". Follows the user's profile; cached so it applies at launch.
  @Published var theme = UserDefaults.standard.string(forKey: "theme") ?? "system" {
    didSet { UserDefaults.standard.set(theme, forKey: "theme") }
  }
  var colorScheme: ColorScheme? { theme == "dark" ? .dark : theme == "light" ? .light : nil }

  // MARK: Roles
  //
  // The app shows one role per sign-in: the one picked on the sign-in screen. Only the
  // owner account can switch, and only between roles the server says it holds. The choice
  // changes what this device shows, never what the server allows.

  /// Every role the app can show, in display order. A later phase appends "developer" here
  /// (and its name below); the tabs, chip and switcher follow this list.
  static let knownRoles = ["learner", "trainer"]
  static func roleName(_ role: String) -> String {
    switch role {
    case "trainer": return "Trainer"
    case "developer": return "Developer"
    default: return "Learner"
    }
  }
  static let ownerEmail = "angch@tertiaryinfotech.com"
  static let accountTab = 4
  static let calendarTab = 1

  /// The Learner / Trainer choice on the sign-in screen. Stored once sign-in succeeds.
  @Published var loginChoice = "learner"
  /// Shown once after sign-in when the chosen role is not available on the account.
  @Published var roleNotice: String?
  /// The roles this account holds on the server, limited to the ones the app shows.
  var roles: [String] { Self.knownRoles.filter { user?.roles.contains($0) ?? false } }
  var isOwner: Bool { !demo && user?.email.lowercased() == Self.ownerEmail }
  /// The roles offered in the "Viewing as" switcher: more than one for the owner only.
  var availableRoles: [String] { isOwner ? roles : [role] }
  var canSwitchRole: Bool { availableRoles.count > 1 }

  /// The role to show for `user`. `chosen` is the sign-in screen's choice, or nil for a
  /// session saved before the choice existed (which keeps the trainer view for a trainer).
  private func resolveRole(for user: User, chosen: String?, announce: Bool) -> String? {
    let held = Self.knownRoles.filter { user.roles.contains($0) }
    guard let fallback = held.first else { return nil }
    if user.email.lowercased() == Self.ownerEmail,
      let viewing = UserDefaults.standard.string(forKey: "viewRole"), held.contains(viewing)
    {
      return viewing
    }
    guard let chosen else { return held.contains("trainer") ? "trainer" : fallback }
    if held.contains(chosen) { return chosen }
    if announce {
      roleNotice =
        chosen == "trainer"
        ? "This account does not teach any classes, so you are signed in as a learner."
        : "This account is a trainer account only, so you are signed in as a trainer."
    }
    return held.contains("learner") ? "learner" : fallback
  }

  /// Owner only: look at the app as another role this account holds.
  func setViewRole(_ new: String) async {
    guard canSwitchRole, availableRoles.contains(new), new != role else { return }
    UserDefaults.standard.set(new, forKey: "viewRole")
    role = new
    dashboard = Dashboard(courses: [], sessions: [])
    selectedTab = 0
    await refresh()
  }

  /// Completed payouts for the signed-in trainer. This is the WSQ app, so every payout is shown.
  func loadPayouts() async throws -> [Payout] {
    if demo { return Sample.payouts() }
    guard let id = user?.id else { return [] }
    let reply: PayoutReply = try await API.shared.request("trainer/\(id)/payout-history")
    return reply.data
  }

  var upcoming: [ClassSession] {
    dashboard.sessions.filter { ($0.end ?? $0.start ?? .distantPast) >= Date() }.sorted {
      ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture)
    }
  }
  func login(email: String, otp: String) async {
    busy = true
    error = nil
    defer { busy = false }
    do {
      let reply: LoginReply = try await API.shared.request(
        "mobile/auth", method: "POST", body: ["action": "verify", "email": email, "otp": otp])
      guard
        let allowed = resolveRole(for: reply.data.user, chosen: loginChoice, announce: true)
      else {
        throw APIError(
          message: "This app is for learners and trainers. Your account has neither role.")
      }
      UserDefaults.standard.set(loginChoice, forKey: "loginRole")
      try Keychain.save(reply.data.token)
      user = reply.data.user
      role = allowed
      demo = false
      loadLearningProgress()
      await refresh()
      await loadProfile()
      await updateNotificationStatus()
    } catch { self.error = error.localizedDescription }
  }
  /// Admin sign-in with Google (allow-listed accounts only): trades the single-use code
  /// from the Google callback, plus this device's verifier, for a session.
  func loginWithGoogle(code: String, verifier: String) async throws {
    let reply: LoginReply = try await API.shared.request(
      "mobile/google-exchange", method: "POST", body: ["code": code, "verifier": verifier])
    guard
      let allowed = resolveRole(for: reply.data.user, chosen: loginChoice, announce: true)
    else {
      throw APIError(
        message: "This app is for learners and trainers. Your account has neither role.")
    }
    UserDefaults.standard.set(loginChoice, forKey: "loginRole")
    try Keychain.save(reply.data.token)
    user = reply.data.user
    role = allowed
    demo = false
    loadLearningProgress()
    await refresh()
    await loadProfile()
    await updateNotificationStatus()
  }
  func login(email: String, password: String) async {
    busy = true
    error = nil
    defer { busy = false }
    do {
      struct PasswordReply: Decodable {
        let data: Value
        struct Value: Decodable {
          let user: User
          let token: String
          let forcePasswordChange: Bool?
        }
      }
      let reply: PasswordReply = try await API.shared.request(
        "mobile/login", method: "POST", body: ["email": email, "password": password])
      guard
        let allowed = resolveRole(for: reply.data.user, chosen: loginChoice, announce: true)
      else {
        throw APIError(
          message: "This app is for learners and trainers. Your account has neither role.")
      }
      UserDefaults.standard.set(loginChoice, forKey: "loginRole")
      try Keychain.save(reply.data.token)
      mustChangePassword = reply.data.forcePasswordChange ?? false
      user = reply.data.user
      role = allowed
      demo = false
      loadLearningProgress()
      await refresh()
      await loadProfile()
      await updateNotificationStatus()
    } catch { self.error = error.localizedDescription }
  }
  /// Returns nil on success, or the message to show.
  func changePassword(current: String, new: String) async -> String? {
    if demo { return "Sample mode has no password to change." }
    do {
      let _: EmptyReply = try await API.shared.request(
        "mobile/password", method: "POST",
        body: ["currentPassword": current, "newPassword": new])
      mustChangePassword = false
      return nil
    } catch { return error.localizedDescription }
  }
  func loadProfile() async {
    if demo {
      profile = Sample.profile(role: role, theme: theme)
      return
    }
    do {
      let reply: Reply<Profile> = try await API.shared.request("mobile/profile")
      profile = reply.data
      theme = reply.data.theme
    } catch {
      // The profile is optional for browsing classes; Account shows a retry.
    }
  }
  /// Saves the given fields. Returns nil on success, or the message to show.
  func saveProfile(_ fields: [String: Any]) async -> String? {
    if demo {
      if var copy = profile {
        if let v = fields["fullName"] as? String { copy.fullName = v }
        if let v = fields["phone"] as? String { copy.phone = v }
        if let v = fields["company"] as? String { copy.company = v }
        if let v = fields["employmentStatus"] as? String { copy.employmentStatus = v }
        if let v = fields["linkedinURL"] as? String { copy.linkedinURL = v }
        if let v = fields["theme"] as? String { copy.theme = v }
        profile = copy
        if let current = user, current.fullName != copy.fullName {
          user = User(
            id: current.id, email: current.email, fullName: copy.fullName, role: current.role,
            roles: current.roles)
        }
      }
      if let v = fields["theme"] as? String { theme = v }
      return nil
    }
    do {
      let reply: Reply<Profile> = try await API.shared.request(
        "mobile/profile", method: "PATCH", body: fields)
      profile = reply.data
      theme = reply.data.theme
      if let current = user, current.fullName != reply.data.fullName {
        user = User(
          id: current.id, email: current.email, fullName: reply.data.fullName, role: current.role,
          roles: current.roles)
      }
      return nil
    } catch { return error.localizedDescription }
  }
  func restore() async {
    if let role = ProcessInfo.processInfo.environment["DEMO_ROLE"],
      ["learner", "trainer"].contains(role)
    {
      openDemo(role)
      return
    }
    guard Keychain.read() != nil else { return }
    busy = true
    defer { busy = false }
    do {
      struct Verify: Decodable {
        let data: DataValue
        struct DataValue: Decodable { let user: User }
      }
      let reply: Verify = try await API.shared.request("mobile/me")
      guard
        let allowed = resolveRole(
          for: reply.data.user, chosen: UserDefaults.standard.string(forKey: "loginRole"),
          announce: false)
      else {
        Keychain.clear()
        return
      }
      user = reply.data.user
      role = allowed
      loadLearningProgress()
      await refresh()
      await loadProfile()
      await updateNotificationStatus()
    } catch {
      Keychain.clear()
      self.error = "Please sign in again to access your classes."
    }
  }
  func refresh() async {
    if demo {
      dashboard = Sample.data(role: role)
      return
    }
    do {
      dashboard = try await API.shared.dashboard(role: role)
      error = nil
      await ClassAlerts.schedule(for: upcoming, enabled: notifications)
    } catch { self.error = error.localizedDescription }
  }
  func signOut() async {
    if !demo {
      do {
        try await Push.shared.unregister()
        let _: EmptyReply = try await API.shared.request("auth/logout", method: "POST")
      } catch {
        self.error = "Sign out could not be completed. Check your connection and try again."
        return
      }
    }
    clear()
  }
  func clear() {
    Keychain.clear()
    user = nil
    dashboard = Dashboard(courses: [], sessions: [])
    demo = false
    openedMaterials = []
    notifications = false
    selectedTab = 0
    profile = nil
    demoDetails = [:]
    demoSheets = [:]
    demoQuizAttempts = [:]
    mustChangePassword = false
    theme = "system"
    loginChoice = "learner"
    roleNotice = nil
    UserDefaults.standard.removeObject(forKey: "loginRole")
    UserDefaults.standard.removeObject(forKey: "viewRole")
    UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
  }
  func openDemo(_ role: String) {
    demo = true
    demoDetails = [:]
    demoSheets = [:]
    demoQuizAttempts = [:]
    self.role = role
    user = User(
      id: "demo", email: "sample@example.com",
      fullName: role == "trainer" ? "Alex Tan" : "Jamie Lim", role: role,
      roles: ["learner", "trainer"])
    dashboard = Sample.data(role: role)
    profile = Sample.profile(role: role, theme: theme)
    loadLearningProgress()
  }

  func materialKey(courseID: String, materialID: String) -> String {
    "\(courseID)::\(materialID)"
  }

  func markMaterialOpened(courseID: String, materialID: String) {
    openedMaterials.insert(materialKey(courseID: courseID, materialID: materialID))
    saveLearningProgress()
  }

  func hasOpened(courseID: String, materialID: String) -> Bool {
    openedMaterials.contains(materialKey(courseID: courseID, materialID: materialID))
  }

  func openedCount(for course: Course) -> Int {
    course.materials(for: role).filter {
      $0.isPublished && hasOpened(courseID: course.id, materialID: $0.id)
    }.count
  }

  func publishedCount(for course: Course) -> Int {
    course.materials(for: role).filter(\.isPublished).count
  }

  private var progressAccount: String { "learning-progress-\(user?.id ?? "signed-out")" }

  private func loadLearningProgress() {
    guard let value = Keychain.read(account: progressAccount),
      let data = value.data(using: .utf8),
      let keys = try? JSONDecoder().decode([String].self, from: data)
    else {
      openedMaterials = []
      return
    }
    openedMaterials = Set(keys)
  }

  private func saveLearningProgress() {
    guard let data = try? JSONEncoder().encode(Array(openedMaterials).sorted()),
      let value = String(data: data, encoding: .utf8)
    else { return }
    try? Keychain.save(value, account: progressAccount)
  }
  func updateNotificationStatus() async {
    let s = await UNUserNotificationCenter.current().notificationSettings()
    notifications = s.authorizationStatus == .authorized || s.authorizationStatus == .provisional
    if notifications && !demo { UIApplication.shared.registerForRemoteNotifications() }
    if !demo { await ClassAlerts.schedule(for: upcoming, enabled: notifications) }
  }
  func enableNotifications() async {
    do {
      let ok = try await UNUserNotificationCenter.current().requestAuthorization(options: [
        .alert, .sound, .badge,
      ])
      notifications = ok
      if ok && !demo {
        UIApplication.shared.registerForRemoteNotifications()
      } else if !ok {
        error =
          "Notifications are disabled. Enable them in iOS Settings to receive class reminders."
      }
    } catch { self.error = error.localizedDescription }
  }
  func deleteAccount() async {
    if demo {
      Keychain.clear(account: progressAccount)
      clear()
      return
    }
    do {
      let _: EmptyReply = try await API.shared.request(
        "mobile/delete-account", method: "POST", body: ["confirmation": "DELETE"])
      Keychain.clear(account: progressAccount)
      clear()
    } catch { self.error = error.localizedDescription }
  }
}
@MainActor final class Push: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
  static var shared = Push()
  var token: String?
  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    Push.shared = self
    token = Keychain.read(account: "apns")
    UNUserNotificationCenter.current().delegate = self
    return true
  }
  func application(
    _ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken data: Data
  ) {
    token = data.map { String(format: "%02x", $0) }.joined()
    if let token { try? Keychain.save(token, account: "apns") }
    Task {
      do { try await register() } catch {
        NotificationCenter.default.post(
          name: Notification.Name("pushError"), object: error.localizedDescription)
      }
    }
  }
  func application(
    _ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    NotificationCenter.default.post(
      name: Notification.Name("pushError"),
      object: "Push registration failed. Please try again on your device.")
  }
  func register() async throws {
    guard let token, Keychain.read() != nil else { return }
    #if DEBUG
      let environment = "sandbox"
    #else
      let environment = "production"
    #endif
    let _: EmptyReply = try await API.shared.request(
      "mobile/device", method: "POST",
      body: ["token": token, "environment": environment, "enabled": true])
  }
  func unregister() async throws {
    guard let token else { return }
    let _: EmptyReply = try await API.shared.request(
      "mobile/device", method: "DELETE", body: ["token": token])
  }
  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions { [.banner, .sound] }
  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
  ) async {
    await MainActor.run {
      NotificationCenter.default.post(
        name: .openClass,
        object: response.notification.request.content.userInfo["sessionID"] as? String)
    }
  }
}

/// On-device alerts for upcoming classes, in addition to the academy's push reminders:
/// one on the morning of each class (08:00 Singapore time, or an hour before an earlier start).
/// Rebuilt from the current class list each time, so cancelled or removed classes drop out.
enum ClassAlerts {
  static let prefix = "class-alert-"
  static func schedule(for sessions: [ClassSession], enabled: Bool) async {
    let center = UNUserNotificationCenter.current()
    let old = await center.pendingNotificationRequests().map(\.identifier).filter {
      $0.hasPrefix(prefix)
    }
    center.removePendingNotificationRequests(withIdentifiers: old)
    guard enabled else { return }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Singapore")!
    for session in sessions.prefix(30) {
      guard session.startTime != nil, let start = session.start,
        let fire = fireDate(for: start, calendar: calendar), fire > Date()
      else { continue }
      let content = UNMutableNotificationContent()
      content.title = "Class today: \(session.title)"
      content.body =
        "\(session.timeLabel)–\(session.endTimeLabel) SGT · "
        + (session.venue?.isEmpty == false ? session.venue! : (session.format ?? "See class details"))
      content.sound = .default
      content.userInfo = ["sessionID": session.id]
      let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
      var trigger = parts
      trigger.timeZone = calendar.timeZone
      try? await center.add(
        UNNotificationRequest(
          identifier: prefix + session.id, content: content,
          trigger: UNCalendarNotificationTrigger(dateMatching: trigger, repeats: false)))
    }
  }
  static func fireDate(for start: Date, calendar: Calendar) -> Date? {
    guard let eight = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: start) else {
      return nil
    }
    return start > eight.addingTimeInterval(1800) ? eight : start.addingTimeInterval(-3600)
  }
}
