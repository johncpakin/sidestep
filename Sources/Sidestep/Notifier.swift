import Foundation
import UserNotifications
import AppKit

/// Usage-threshold notifications. UNUserNotificationCenter when available (we run from a bundle),
/// osascript `display notification` as fallback.
@MainActor
enum Notifier {
    private static var authorized = false
    private static var requested = false

    static func bootstrap() {
        guard Bundle.main.bundleIdentifier != nil, !requested else { return }
        requested = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { ok, _ in
            Task { @MainActor in authorized = ok }
        }
    }

    static func post(title: String, body: String) {
        if Bundle.main.bundleIdentifier != nil, authorized {
            let c = UNMutableNotificationContent()
            c.title = title; c.body = body; c.sound = .default
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil)) { err in
                if err != nil { Task { @MainActor in fallback(title: title, body: body) } }
            }
        } else {
            fallback(title: title, body: body)
        }
    }

    private static func fallback(title: String, body: String) {
        let esc = { (s: String) in s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", "display notification \"\(esc(body))\" with title \"\(esc(title))\""]
        try? p.run()
    }
}

/// Tracks which thresholds have fired, keyed per account+bucket+reset-window, persisted across relaunches.
@MainActor
struct UsageAlerts {
    static let thresholds: [Double] = [80, 90, 95]
    private var fired: [String: Double] = (UserDefaults.standard.dictionary(forKey: "usageAlerts") as? [String: Double]) ?? [:]

    private func key(_ accountID: String, _ l: LimitBucket) -> String {
        "\(accountID)|\(l.id)|\(Int(l.resetsAt?.timeIntervalSince1970 ?? 0))"
    }

    /// Returns the threshold to announce for this bucket, or nil. Marks it fired.
    mutating func crossed(_ accountID: String, _ l: LimitBucket) -> Double? {
        guard let t = Self.thresholds.last(where: { l.percent >= $0 }) else { return nil }
        let k = key(accountID, l)
        if let done = fired[k], done >= t { return nil }
        fired[k] = t
        if fired.count > 128 {   // prune stale windows
            let now = Date().timeIntervalSince1970
            fired = fired.filter { Double($0.key.split(separator: "|").last.map(String.init) ?? "0") ?? 0 > now - 8 * 86400 }
        }
        UserDefaults.standard.set(fired, forKey: "usageAlerts")
        return t
    }
}
