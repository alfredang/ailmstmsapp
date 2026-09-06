import Foundation
import Security

struct APIError: LocalizedError {
  let message: String
  var errorDescription: String? { message }
}
struct EmptyReply: Decodable { let success: Bool? }
final class API {
  static let shared = API()
  let base = URL(string: "https://lms-tms.tertiaryinfotech.com")!
  var token: String? { Keychain.read() }
  func request<T: Decodable>(_ path: String, method: String = "GET", body: [String: Any]? = nil)
    async throws -> T
  {
    var request = URLRequest(url: base.appendingPathComponent("api/" + path))
    request.httpMethod = method
    request.timeoutInterval = 30
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
    if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let response = response as? HTTPURLResponse else {
      throw APIError(message: "No response from the learning portal.")
    }
    guard (200..<300).contains(response.statusCode) else {
      let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
      if response.statusCode == 401 && !path.hasPrefix("auth/") && path != "mobile/auth" {
        await MainActor.run { NotificationCenter.default.post(name: .sessionExpired, object: nil) }
      }
      throw APIError(
        message: json?["error"] as? String
          ?? "The portal could not complete this request (\(response.statusCode)). Please try again."
      )
    }
    return try JSONDecoder().decode(T.self, from: data)
  }
  func dashboard(role: String) async throws -> Dashboard {
    var components = URLComponents(
      url: base.appendingPathComponent("api/mobile/dashboard"), resolvingAgainstBaseURL: false)!
    components.queryItems = [URLQueryItem(name: "role", value: role)]
    var req = URLRequest(url: components.url!)
    req.timeoutInterval = 30
    if let token { req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
    let (data, response) = try await URLSession.shared.data(for: req)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    if status == 401 {
      await MainActor.run { NotificationCenter.default.post(name: .sessionExpired, object: nil) }
    }
    guard status == 200 else {
      throw APIError(message: "Your classes could not be loaded. Please try again. (\(status))")
    }
    return try JSONDecoder().decode(Dashboard.self, from: data)
  }
}
extension Notification.Name {
  static let sessionExpired = Notification.Name("sessionExpired")
  static let openClass = Notification.Name("openClass")
}
enum Keychain {
  static let query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: "com.tertiaryinfotech.ailmstms",
    kSecAttrAccount as String: "session",
  ]
  static func save(_ token: String, account: String = "session") throws {
    clear(account: account)
    var q = query
    q[kSecAttrAccount as String] = account
    q[kSecValueData as String] = Data(token.utf8)
    q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    guard SecItemAdd(q as CFDictionary, nil) == errSecSuccess else {
      throw APIError(message: "Unable to securely save your session.")
    }
  }
  static func read(account: String = "session") -> String? {
    var q = query
    q[kSecAttrAccount as String] = account
    q[kSecReturnData as String] = true
    var value: CFTypeRef?
    guard SecItemCopyMatching(q as CFDictionary, &value) == errSecSuccess, let data = value as? Data
    else { return nil }
    return String(data: data, encoding: .utf8)
  }
  static func clear(account: String = "session") {
    var q = query
    q[kSecAttrAccount as String] = account
    SecItemDelete(q as CFDictionary)
  }
}
