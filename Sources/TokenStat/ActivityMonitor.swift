import Foundation

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

    private var timer: Timer?
    private nonisolated static let workingWindow: TimeInterval = 20
    private nonisolated static let staleWindow:   TimeInterval = 30 * 60

    func start() {
        timer?.invalidate()
        let t = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)   // keep ticking while the menu is open
        timer = t
        tick()
    }

    func stop() { timer?.invalidate() }

    private func tick() {
        let new = Self.currentState()
        if new != state {
            state = new
            onChange?()
        }
    }

    // MARK: - State detection

    private nonisolated static func currentState() -> ClaudeActivity {
        let projects = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
        guard let (url, mtime) = newestSession(in: projects) else { return .ready }

        let age = Date().timeIntervalSince(mtime)
        if age > staleWindow  { return .ready }        // long-abandoned session
        if age <= workingWindow { return .working }    // actively streaming

        // Quiet for a while — inspect the last entry to see why.
        switch lastEntry(of: url) {
        case .pendingToolUse:  return .blocked   // tool call sent, no result → permission prompt
        case .pendingToolResult: return .working // result arrived, Claude is composing the next step
        case .turnComplete, .unknown: return .ready
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
        case pendingToolUse     // assistant message ending in tool_use, unanswered
        case pendingToolResult  // user message carrying a tool_result
        case turnComplete       // assistant message with plain text only
        case unknown
    }

    private nonisolated static func lastEntry(of url: URL) -> SessionTail {
        guard let line = lastNonEmptyLine(of: url),
              let data = line.data(using: .utf8),
              let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return .unknown }

        let type    = obj["type"] as? String
        let message = obj["message"] as? [String: Any]
        let content = message?["content"] as? [[String: Any]] ?? []
        let kinds   = Set(content.compactMap { $0["type"] as? String })

        if type == "assistant" {
            return kinds.contains("tool_use") ? .pendingToolUse : .turnComplete
        }
        if type == "user" && kinds.contains("tool_result") {
            return .pendingToolResult
        }
        return .unknown
    }

    /// Reads the tail of the file (up to 256 KB) and returns its last non-empty line.
    private nonisolated static func lastNonEmptyLine(of url: URL) -> String? {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }

        let size = (try? fh.seekToEnd()) ?? 0
        let chunk: UInt64 = 256 * 1024
        let offset = size > chunk ? size - chunk : 0
        try? fh.seek(toOffset: offset)
        guard let data = try? fh.readToEnd(),
              let text = String(data: data, encoding: .utf8) else { return nil }

        return text.split(separator: "\n", omittingEmptySubsequences: true)
            .last.map(String.init)
    }
}
