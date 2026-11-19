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
  func request<T: Decodable>(
    _ path: String, method: String = "GET", query: [String: String] = [:],
    body: [String: Any]? = nil
  ) async throws -> T {
    var components = URLComponents(
      url: base.appendingPathComponent("api/" + path), resolvingAgainstBaseURL: false)!
    if !query.isEmpty {
      components.queryItems = query.sorted { $0.key < $1.key }.map {
        URLQueryItem(name: $0.key, value: $0.value)
      }
    }
    var request = URLRequest(url: components.url!)
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
      if response.statusCode == 401 && !path.hasPrefix("auth/")
        && !["mobile/auth", "mobile/login", "mobile/password"].contains(path)
      {
        await MainActor.run { NotificationCenter.default.post(name: .sessionExpired, object: nil) }
      }
      throw APIError(
        message: json?["error"] as? String
          ?? "The portal could not complete this request (\(response.statusCode)). Please try again."
      )
    }
    return try JSONDecoder().decode(T.self, from: data)
  }
  /// Uploads one file to the academy's Google Drive assessment folder and returns its link.
  func upload(file: URL, studentName: String, runCode: String) async throws -> (
    url: String, folder: String?
  ) {
    var components = URLComponents(
      url: base.appendingPathComponent("api/upload/google-drive"), resolvingAgainstBaseURL: false)!
    components.queryItems = [
      URLQueryItem(name: "studentName", value: studentName),
      URLQueryItem(name: "courseRunId", value: runCode),
    ]
    let boundary = "tia-" + UUID().uuidString
    var request = URLRequest(url: components.url!)
    request.httpMethod = "POST"
    request.timeoutInterval = 300
    request.setValue(
      "multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
    let name = file.lastPathComponent.replacingOccurrences(of: "\"", with: "")
    var body = Data()
    body.append(Data("--\(boundary)\r\n".utf8))
    body.append(
      Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(name)\"\r\n".utf8))
    body.append(Data("Content-Type: application/octet-stream\r\n\r\n".utf8))
    body.append(try Data(contentsOf: file))
    body.append(Data("\r\n--\(boundary)--\r\n".utf8))
    let (data, response) = try await URLSession.shared.upload(for: request, from: body)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    if status == 401 {
      await MainActor.run { NotificationCenter.default.post(name: .sessionExpired, object: nil) }
    }
    guard (200..<300).contains(status), let info = json?["data"] as? [String: Any],
      let link = info["fileUrl"] as? String
    else {
      throw APIError(
        message: json?["error"] as? String
          ?? "The file could not be uploaded (\(status)). Please try again.")
    }
    return (link, info["studentFolderId"] as? String)
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
