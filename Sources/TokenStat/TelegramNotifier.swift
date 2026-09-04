import Foundation

// Sends a Telegram message via the Bot API when Claude Code turns ready.
// Bot token + chat id are stored in UserDefaults, same as the other
// optional settings — this is a single-user menu bar app, not a shared secret.
enum TelegramNotifier {
    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: "telegram_notify_on_ready") }
        set { UserDefaults.standard.set(newValue, forKey: "telegram_notify_on_ready") }
    }

    static var botToken: String {
        get { UserDefaults.standard.string(forKey: "telegram_bot_token") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "telegram_bot_token") }
    }

    static var chatID: String {
        get { UserDefaults.standard.string(forKey: "telegram_chat_id") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "telegram_chat_id") }
    }

    static var isConfigured: Bool {
        !botToken.trimmingCharacters(in: .whitespaces).isEmpty &&
        !chatID.trimmingCharacters(in: .whitespaces).isEmpty
    }

    static func sendReadyMessage() {
        guard enabled, isConfigured else { return }
        send(text: "✅ Claude Code is ready for your next prompt", botToken: botToken, chatID: chatID)
    }

    // completion receives nil on success, or an error message on failure.
    static func send(text: String, botToken: String, chatID: String,
                      completion: (@MainActor @Sendable (String?) -> Void)? = nil) {
        guard let url = URL(string: "https://api.telegram.org/bot\(botToken)/sendMessage") else {
            Task { @MainActor in completion?("Invalid bot token") }
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["chat_id": chatID, "text": text])

        URLSession.shared.dataTask(with: req) { data, response, error in
            Task { @MainActor in
                if let error {
                    completion?(error.localizedDescription)
                    return
                }
                guard let http = response as? HTTPURLResponse else {
                    completion?("No response from Telegram")
                    return
                }
                guard http.statusCode == 200 else {
                    let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                    completion?("HTTP \(http.statusCode): \(body)")
                    return
                }
                completion?(nil)
            }
        }.resume()
    }
}
