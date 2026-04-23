import Foundation

// Persists settings to ~/.config/tokenstat/config.json
// Replaces UserDefaults (which is unreliable on Linux).

final class Config {
    static let shared = Config()

    private let path: URL
    private var data: [String: Any] = [:]

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir  = home.appendingPathComponent(".config/tokenstat")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        path = dir.appendingPathComponent("config.json")
        load()
    }

    var refreshInterval: Int {
        get { (data["refresh_interval"] as? Int).map { max(1, min(60, $0)) } ?? 5 }
        set { data["refresh_interval"] = max(1, min(60, newValue)); save() }
    }

    private func load() {
        guard let raw  = try? Data(contentsOf: path),
              let json = try? JSONSerialization.jsonObject(with: raw) as? [String: Any]
        else { return }
        data = json
    }

    private func save() {
        guard let raw = try? JSONSerialization.data(withJSONObject: data, options: .prettyPrinted)
        else { return }
        try? raw.write(to: path)
    }
}
