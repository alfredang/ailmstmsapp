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
  @Published var selectedTab = 0
  @Published var selectedDate = Date()
  var roles: [String] { user?.roles.filter { ["learner", "trainer"].contains($0) } ?? [] }
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
        let allowed = reply.data.user.roles.first(where: { ["learner", "trainer"].contains($0) })
      else {
        throw APIError(
          message: "This app is for learners and trainers. Your account has neither role.")
      }
      try Keychain.save(reply.data.token)
      user = reply.data.user
      role = allowed
      demo = false
      await refresh()
      await updateNotificationStatus()
    } catch { self.error = error.localizedDescription }
  }
  func restore() async {
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
        let allowed = reply.data.user.roles.first(where: { ["learner", "trainer"].contains($0) })
      else {
        Keychain.clear()
        return
      }
      user = reply.data.user
      role = allowed
      await refresh()
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
    notifications = false
    selectedTab = 0
    UNUserNotificationCenter.current().removeAllDeliveredNotifications()
  }
  func openDemo(_ role: String) {
    demo = true
    self.role = role
    user = User(
      id: "demo", email: "sample@example.com",
      fullName: role == "trainer" ? "Alex Tan" : "Jamie Lim", role: role,
      roles: ["learner", "trainer"])
    dashboard = Sample.data(role: role)
  }
  func updateNotificationStatus() async {
    let s = await UNUserNotificationCenter.current().notificationSettings()
    notifications = s.authorizationStatus == .authorized || s.authorizationStatus == .provisional
    if notifications && !demo { UIApplication.shared.registerForRemoteNotifications() }
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
      clear()
      return
    }
    do {
      let _: EmptyReply = try await API.shared.request(
        "mobile/delete-account", method: "POST", body: ["confirmation": "DELETE"])
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
