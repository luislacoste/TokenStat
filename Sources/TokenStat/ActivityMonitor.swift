import Foundation
import UserNotifications

// Watches ~/.claude/projects/**/*.jsonl — Claude Code appends to the active
// session file while it works. State is derived from the newest file:
//   working: written within the last 20 s, or waiting on a running tool
//   blocked: last entry is an assistant tool call with no result following,
//            i.e. Claude is sitting on a permission prompt
//   ready:   last turn completed — Claude is waiting for a new prompt

enum ClaudeActivity {
    case ready     // green  — not doing anything, ready to prompt
    case working   // yellow — thinking / generating
    case blocked   // red    — asking for permission / waiting on approval
}

@MainActor
final class ActivityMonitor {
    static let shared = ActivityMonitor()
    private init() {}

    private(set) var state: ClaudeActivity = .ready
    var onChange: (() -> Void)?

    // Optional: post a macOS notification each time Claude Code turns ready (green).
    var notifyOnReady: Bool {
        get { UserDefaults.standard.bool(forKey: "notify_on_ready") }
        set { UserDefaults.standard.set(newValue, forKey: "notify_on_ready") }
    }

    private var timer: Timer?
    // Tail classification cache — only re-read the file when it changed.
    private var cachedTail: (url: URL, mtime: Date, tail: SessionTail)?
    private nonisolated static let workingWindow: TimeInterval = 20
    private nonisolated static let promptWindow:  TimeInterval = 2 * 60
    private nonisolated static let staleWindow:   TimeInterval = 30 * 60

    func start() {
        timer?.invalidate()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)   // keep ticking while the menu is open
        timer = t
        tick()
    }

    func stop() { timer?.invalidate() }

    private func tick() {
        let new = currentState()
        if new != state {
            let previous = state
            state = new
            onChange?()
            if new == .ready, previous != .ready {
                if notifyOnReady { notifyReady() }
                TelegramNotifier.sendReadyMessage()
            }
        }
    }

    private func notifyReady() {
        let content = UNMutableNotificationContent()
        content.title = "Claude Code"
        content.body  = "Ready for your next prompt"
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "tokenstat.ready.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - State detection

    private func currentState() -> ClaudeActivity {
        // Marker written by a Claude Code Notification hook the moment a
        // permission prompt appears (and removed by PreToolUse/UserPromptSubmit/
        // Stop hooks when it's resolved). Instant and unambiguous → red.
        let marker = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.tokenstat-blocked")
        if let m = (try? marker.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate,
           Date().timeIntervalSince(m) < Self.staleWindow {
            return .blocked
        }

        let projects = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
        guard let (url, mtime) = Self.newestSession(in: projects) else { return .ready }

        let age = Date().timeIntervalSince(mtime)
        if age > Self.staleWindow { return .ready }    // long-abandoned session

        let tail: SessionTail
        if let c = cachedTail, c.url == url, c.mtime == mtime {
            tail = c.tail
        } else {
            tail = Self.lastEntry(of: url)
            cachedTail = (url, mtime, tail)
        }

        switch tail {
        case .turnComplete:      return .ready    // final text written → green immediately
        case .pendingToolResult: return .working  // Claude is composing the next step
        case .thinking:          return .working  // mid-turn reasoning
        case .pendingToolUse:
            // Recent → the tool is just executing; quiet too long → permission prompt.
            return age <= Self.workingWindow ? .working : .blocked
        case .userPrompt:
            // Prompt sent, first response not written yet. Long silence → interrupted.
            return age <= Self.promptWindow ? .working : .ready
        case .unknown:
            return age <= Self.workingWindow ? .working : .ready
        }
    }

    private nonisolated static func newestSession(in dir: URL) -> (URL, Date)? {
        guard let en = FileManager.default.enumerator(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var newest: (URL, Date)?
        for case let url as URL in en where url.pathExtension == "jsonl" {
            let d = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate
            if let d, newest.map({ d > $0.1 }) ?? true { newest = (url, d) }
        }
        return newest
    }

    // MARK: - Last JSONL entry classification

    private enum SessionTail {
        case pendingToolUse     // assistant tool call, unanswered
        case pendingToolResult  // tool result arrived, next message pending
        case thinking           // assistant thinking block, turn still going
        case turnComplete       // assistant message with final text
        case userPrompt         // user just sent a prompt, no response yet
        case unknown
    }

    // Walks the file tail backwards, skipping bookkeeping entries (attachment,
    // system, file-history-snapshot, ai-title, mode, …) until it finds a real
    // assistant/user message to classify.
    private nonisolated static func lastEntry(of url: URL) -> SessionTail {
        for line in tailLines(of: url).reversed() {
            guard let data = line.data(using: .utf8),
                  let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = obj["type"] as? String
            else { continue }

            let message = obj["message"] as? [String: Any]
            let content = message?["content"]
            let kinds: Set<String>
            if let items = content as? [[String: Any]] {
                kinds = Set(items.compactMap { $0["type"] as? String })
            } else if content is String {
                kinds = ["text"]
            } else {
                kinds = []
            }

            switch type {
            case "assistant":
                if kinds.contains("tool_use")  { return .pendingToolUse }
                if kinds.contains("text")      { return .turnComplete }
                if kinds.contains("thinking")  { return .thinking }
                return .unknown
            case "user":
                if kinds.contains("tool_result") { return .pendingToolResult }
                if kinds.contains("text")        { return .userPrompt }
                return .unknown
            default:
                continue   // bookkeeping entry — keep walking back
            }
        }
        return .unknown
    }

    /// Reads the tail of the file (up to 256 KB) and returns its non-empty lines.
    private nonisolated static func tailLines(of url: URL) -> [String] {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? fh.close() }

        let size = (try? fh.seekToEnd()) ?? 0
        let chunk: UInt64 = 256 * 1024
        let offset = size > chunk ? size - chunk : 0
        try? fh.seek(toOffset: offset)
        guard let data = try? fh.readToEnd(),
              let text = String(data: data, encoding: .utf8) else { return [] }

        return text.split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
    }
}
