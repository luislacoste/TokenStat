import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Sends a Telegram message via the Bot API when Claude Code turns ready.
// Bot token + chat id are stored in Config (~/.config/tokenstat/config.json),
// same as the other optional settings — this is a single-user tray app,
// not a shared secret.
enum TelegramNotifier {
    static var enabled: Bool {
        get { Config.shared.telegramEnabled }
        set { Config.shared.telegramEnabled = newValue }
    }

    static var botToken: String {
        get { Config.shared.telegramBotToken }
        set { Config.shared.telegramBotToken = newValue }
    }

    static var chatID: String {
        get { Config.shared.telegramChatID }
        set { Config.shared.telegramChatID = newValue }
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
    // Called back on whatever thread URLSession uses — callers touching GTK
    // widgets from it must marshal through scheduleGtkUpdate themselves.
    static func send(text: String, botToken: String, chatID: String,
                      completion: ((String?) -> Void)? = nil) {
        guard let url = URL(string: "https://api.telegram.org/bot\(botToken)/sendMessage") else {
            completion?("Invalid bot token")
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["chat_id": chatID, "text": text])

        URLSession.shared.dataTask(with: req) { data, response, error in
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
        }.resume()
    }
}
