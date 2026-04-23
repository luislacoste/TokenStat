import Foundation

// Polls the Anthropic OAuth usage API every N minutes.
// On Linux, credentials are read via `secret-tool` (libsecret) with a
// file-path fallback for systems where the Secret Service is unavailable.

final class ClaudeService {
    static let shared = ClaudeService()
    private init() {}

    private(set) var snapshot: UsageSnapshot = .empty
    private(set) var lastError: String?
    // Invoked on GTK's main thread (via g_idle_add) after each fetch.
    var onUpdate: (() -> Void)?

    private var cachedToken: String?
    private var pollTask: Task<Void, Never>?

    var refreshInterval: Int {
        get { Config.shared.refreshInterval }
        set { Config.shared.refreshInterval = newValue }
    }

    private var normalNs:  UInt64 { UInt64(refreshInterval) * 60 * 1_000_000_000 }
    private let backoffNs: UInt64 = 15 * 60 * 1_000_000_000

    // MARK: - Lifecycle

    func start() {
        pollTask?.cancel()
        pollTask = Task.detached { [weak self] in await self?.fetchLoop() }
    }

    func stop() { pollTask?.cancel() }

    func refresh() { Task.detached { [weak self] in await self?.fetch() } }

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

    @discardableResult
    private func fetch() async -> Bool {
        do {
            let token    = try accessToken()
            let response = try await fetchOAuthUsage(token: token)

            snapshot = UsageSnapshot(
                fiveHourUtilization:       Int(response.fiveHour?.utilization      ?? 0),
                sevenDayUtilization:       Int(response.sevenDay?.utilization      ?? 0),
                sevenDaySonnetUtilization: response.sevenDaySonnet.map { Int($0.utilization) },
                fiveHourResetIn: response.fiveHour?.resetsAtDate.map  { formatTimeRemaining(until: $0) },
                sevenDayResetIn: response.sevenDay?.resetsAtDate.map  { formatTimeRemaining(until: $0) },
                lastUpdated: Date()
            )
            lastError = nil
            notifyUpdate()
            return false

        } catch {
            if (error as NSError).code == 429 {
                cachedToken = nil
                lastError = "Rate limited — retrying in 15 min"
                notifyUpdate()
                return true
            }
            lastError = error.localizedDescription
            notifyUpdate()
            return false
        }
    }

    // Schedules onUpdate on GTK's main thread via g_idle_add (see GtkHelpers.swift).
    private func notifyUpdate() {
        let cb = onUpdate
        scheduleGtkUpdate { cb?() }
    }

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
        return try JSONDecoder().decode(OAuthUsageResponse.self, from: data)
    }
}

// MARK: - Credential reading (Linux)

private struct KeychainCredentials: Decodable {
    let claudeAiOauth: OAuthData
    struct OAuthData: Decodable { let accessToken: String }
}

private func readOAuthAccessToken() throws -> String {
    // 1. Try secret-tool (GNOME keyring / libsecret)
    if let token = try? readViaSecretTool() { return token }
    // 2. Try known file paths (some Claude Code builds on Linux use a file)
    if let token = try? readFromFile() { return token }

    throw NSError(domain: "Credentials", code: 1, userInfo: [
        NSLocalizedDescriptionKey:
            "Claude Code credentials not found.\n" +
            "Make sure Claude Code is installed and you are logged in.\n" +
            "Tried: secret-tool lookup and common config file paths."
    ])
}

// Reads the credential the same way keytar stores it in the Secret Service.
private func readViaSecretTool() throws -> String {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/secret-tool")
    // keytar stores with attributes: service=<name>, account=""
    proc.arguments = ["lookup", "service", "Claude Code-credentials", "account", ""]
    let outPipe = Pipe()
    let errPipe = Pipe()   // suppress stderr
    proc.standardOutput = outPipe
    proc.standardError  = errPipe

    try proc.run()
    proc.waitUntilExit()
    guard proc.terminationStatus == 0 else { throw CocoaError(.fileNoSuchFile) }

    let raw = outPipe.fileHandleForReading.readDataToEndOfFile()
    let json = String(data: raw, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !json.isEmpty else { throw CocoaError(.fileNoSuchFile) }

    let creds = try JSONDecoder().decode(KeychainCredentials.self, from: Data(json.utf8))
    return creds.claudeAiOauth.accessToken
}

// Fallback: some distributions / Claude Code versions write a plain JSON file.
private func readFromFile() throws -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let candidates = [
        "\(home)/.config/claude/credentials",
        "\(home)/.config/claude/credentials.json",
        "\(home)/.config/@anthropic-ai/claude/credentials",
        "\(home)/.local/share/claude/credentials",
    ]
    for path in candidates {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { continue }
        if let creds = try? JSONDecoder().decode(KeychainCredentials.self, from: data) {
            return creds.claudeAiOauth.accessToken
        }
    }
    throw CocoaError(.fileNoSuchFile)
}
