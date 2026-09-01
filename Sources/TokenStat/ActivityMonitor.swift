import Foundation

// Watches ~/.claude/projects/**/*.jsonl — Claude Code appends to the active
// session file while it works, so the newest mtime tells us what it's doing:
//   working: written within the last 15 s
//   done:    last write between 15 s and 5 min ago
//   idle:    nothing written for 5 min (or no sessions at all)

enum ClaudeActivity {
    case idle      // red
    case working   // yellow
    case done      // green
}

@MainActor
final class ActivityMonitor {
    static let shared = ActivityMonitor()
    private init() {}

    private(set) var state: ClaudeActivity = .idle
    var onChange: (() -> Void)?

    private var timer: Timer?
    private nonisolated static let workingWindow: TimeInterval = 15
    private nonisolated static let doneWindow:    TimeInterval = 5 * 60

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

    private nonisolated static func currentState() -> ClaudeActivity {
        let projects = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
        guard let latest = newestSessionWrite(in: projects) else { return .idle }
        let age = Date().timeIntervalSince(latest)
        if age <= workingWindow { return .working }
        if age <= doneWindow    { return .done }
        return .idle
    }

    private nonisolated static func newestSessionWrite(in dir: URL) -> Date? {
        guard let en = FileManager.default.enumerator(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var newest: Date?
        for case let url as URL in en where url.pathExtension == "jsonl" {
            let d = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate
            if let d, newest.map({ d > $0 }) ?? true { newest = d }
        }
        return newest
    }
}
