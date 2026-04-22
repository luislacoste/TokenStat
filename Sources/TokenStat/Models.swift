import Foundation
import AppKit

// MARK: - API response

struct OAuthUsageResponse: Decodable {
    let fiveHour: UsagePeriod?
    let sevenDay: UsagePeriod?
    let sevenDaySonnet: UsagePeriod?

    enum CodingKeys: String, CodingKey {
        case fiveHour     = "five_hour"
        case sevenDay     = "seven_day"
        case sevenDaySonnet = "seven_day_sonnet"
    }

    struct UsagePeriod: Decodable {
        let utilization: Double   // 0–100
        let resetsAt: String

        enum CodingKeys: String, CodingKey {
            case utilization
            case resetsAt = "resets_at"
        }

        var resetsAtDate: Date? {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = f.date(from: resetsAt) { return d }
            f.formatOptions = [.withInternetDateTime]
            return f.date(from: resetsAt)
        }
    }
}

// MARK: - App snapshot

struct UsageSnapshot {
    let fiveHourUtilization: Int      // 0–100
    let sevenDayUtilization: Int
    let sevenDaySonnetUtilization: Int?
    let fiveHourResetIn: String?      // e.g. "2h 30m"
    let sevenDayResetIn: String?
    let lastUpdated: Date

    static var empty: UsageSnapshot {
        UsageSnapshot(fiveHourUtilization: 0, sevenDayUtilization: 0,
                      sevenDaySonnetUtilization: nil,
                      fiveHourResetIn: nil, sevenDayResetIn: nil,
                      lastUpdated: .distantPast)
    }
}

// MARK: - Time helper

func formatTimeRemaining(until date: Date, from now: Date = Date()) -> String {
    let interval = date.timeIntervalSince(now)
    if interval <= 0 { return "now" }
    let days    = Int(interval) / 86_400
    let hours   = (Int(interval) % 86_400) / 3_600
    let minutes = (Int(interval) % 3_600)  / 60
    if days  > 0 { return "\(days)d \(hours)h" }
    if hours > 0 { return "\(hours)h \(minutes)m" }
    return "\(minutes)m"
}
