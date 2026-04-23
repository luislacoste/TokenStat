import Foundation
import Security

// Reads Claude usage from the Anthropic OAuth API:
//   GET https://api.anthropic.com/api/oauth/usage
// The OAuth token is retrieved from the macOS Keychain where Claude Code stores it.
// Polls every 5 minutes; backs off to 15 minutes after HTTP 429.

@MainActor
final class ClaudeService {
    static let shared = ClaudeService()
    private init() {}

    private(set) var snapshot: UsageSnapshot = .empty
    private(set) var lastError: String?
    var onUpdate: (() -> Void)?

    private var cachedToken: String?
    private var pollTask: Task<Void, Never>?

    // User-configurable refresh interval (minutes), clamped 1–60, default 5
    var refreshInterval: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: "refresh_interval")
            return v > 0 ? v : 5
        }
        set { UserDefaults.standard.set(max(1, min(60, newValue)), forKey: "refresh_interval") }
    }

    private var normalNs:  UInt64 { UInt64(refreshInterval) * 60 * 1_000_000_000 }
    private let backoffNs: UInt64 = 15 * 60 * 1_000_000_000

    // MARK: - Lifecycle

    func start() {
        pollTask?.cancel()
        pollTask = Task { await self.fetchLoop() }
    }

    func stop() { pollTask?.cancel() }

    func refresh() { Task { await self.fetch() } }

    // MARK: - Poll loop

    private func fetchLoop() async {
        var delay: UInt64 = 0
        while !Task.isCancelled {
            if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
            if Task.isCancelled { break }
            let rateLimited = await fetch()
            delay = rateLimited ? backoffNs : normalNs
        }
    }

    // Returns true when the server rate-limited us (back off).
    @discardableResult
    private func fetch() async -> Bool {
        do {
            let token    = try accessToken()
            let response = try await fetchOAuthUsage(token: token)

            snapshot = UsageSnapshot(
                fiveHourUtilization:      Int(response.fiveHour?.utilization     ?? 0),
                sevenDayUtilization:      Int(response.sevenDay?.utilization     ?? 0),
                sevenDaySonnetUtilization: response.sevenDaySonnet.map { Int($0.utilization) },
                fiveHourResetIn:  response.fiveHour?.resetsAtDate.map  { formatTimeRemaining(until: $0) },
                sevenDayResetIn:  response.sevenDay?.resetsAtDate.map  { formatTimeRemaining(until: $0) },
                lastUpdated: Date()
            )
            lastError = nil
            onUpdate?()
            return false

        } catch let err as NSError {
            if err.code == 429 {
                cachedToken = nil   // re-read keychain next time in case token refreshed
                lastError = "Rate limited — retrying in 15 min"
                onUpdate?()
                return true
            }
            lastError = err.localizedDescription
            onUpdate?()
            return false
        }
    }

    // MARK: - Keychain

    private func accessToken() throws -> String {
        if let t = cachedToken { return t }
        let t = try readOAuthAccessToken()
        cachedToken = t
        return t
    }

    // MARK: - API

    private func fetchOAuthUsage(token: String) async throws -> OAuthUsageResponse {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        req.setValue("Bearer \(token)",  forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "OAuthUsage", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(body)"])
        }
        do {
            return try JSONDecoder().decode(OAuthUsageResponse.self, from: data)
        } catch {
            let rawBody = String(data: data, encoding: .utf8) ?? "<unreadable>"
            throw NSError(domain: "OAuthUsage", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "JSON decode error: \(error)\nResponse: \(rawBody)"
            ])
        }
    }
}

// MARK: - Keychain helper

private struct KeychainCredentials: Decodable {
    let claudeAiOauth: OAuthData
    struct OAuthData: Decodable { let accessToken: String }
}

private func readOAuthAccessToken() throws -> String {
    var item: AnyObject?
    let query: [String: Any] = [
        kSecClass       as String: kSecClassGenericPassword,
        kSecAttrService as String: "Claude Code-credentials",
        kSecReturnData  as String: true,
        kSecMatchLimit  as String: kSecMatchLimitOne
    ]
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess, let data = item as? Data else {
        throw NSError(domain: "Keychain", code: Int(status), userInfo: [
            NSLocalizedDescriptionKey:
                "Claude Code credentials not found in Keychain (OSStatus \(status)). " +
                "Make sure Claude Code is installed and you are logged in."
        ])
    }
    let creds = try JSONDecoder().decode(KeychainCredentials.self, from: data)
    return creds.claudeAiOauth.accessToken
}
