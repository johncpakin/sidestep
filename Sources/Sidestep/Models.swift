import Foundation

/// Where an account's credentials were found.
enum CredentialSource: String, Codable {
    case proxyFile    // ~/.cli-proxy-api/claude-<email>.json
    case keychain     // "Claude Code-credentials" (the account Claude Code is currently logged into)
    case appStore     // ~/Library/Application Support/Sidestep/accounts/
}

/// OAuth credential set, normalised from either the proxy JSON or the Claude Code keychain blob.
struct Credentials: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var scopes: [String]
    var subscriptionType: String?
    var rateLimitTier: String?

    var isExpired: Bool { expiresAt.timeIntervalSinceNow < 60 }
}

/// A single Claude account.
struct Account: Identifiable, Equatable {
    var id: String { email.lowercased() }
    var email: String
    var displayName: String?
    var accountUUID: String?
    var organizationUUID: String?
    var organizationName: String?
    var organizationType: String?
    var credentials: Credentials
    var source: CredentialSource
    /// Path of the proxy / app-store JSON file this account was loaded from (nil for keychain).
    var filePath: URL?
    var disabled: Bool = false
}

/// One limit bucket as returned by /api/oauth/usage.
struct LimitBucket: Identifiable, Equatable {
    var id: String { kind + (scopeName ?? "") }
    var kind: String        // session, weekly_all, weekly_scoped …
    var group: String       // session, weekly
    var percent: Double
    var severity: String
    var resetsAt: Date?
    var scopeName: String?  // e.g. "Fable" / "Opus"
    var isActive: Bool

    var title: String {
        switch kind {
        case "session": return "Session (5h)"
        case "weekly_all": return "Weekly"
        case "weekly_scoped": return "Weekly · \(scopeName ?? "model")"
        default: return kind.replacingOccurrences(of: "_", with: " ").capitalized + (scopeName.map { " · \($0)" } ?? "")
        }
    }
}

struct UsageSnapshot: Equatable {
    var fetchedAt: Date
    var limits: [LimitBucket]
    var extraUsageEnabled: Bool

    var session: LimitBucket? { limits.first { $0.kind == "session" } }
    var weekly: LimitBucket? { limits.first { $0.kind == "weekly_all" } }
    /// Highest utilisation across all buckets — what will bite first.
    var worst: LimitBucket? { limits.max { $0.percent < $1.percent } }
}

enum AccountStatus: Equatable {
    case idle
    case loading
    case ok(UsageSnapshot)
    case needsLogin(String)   // refresh token dead
    case error(String)

    var snapshot: UsageSnapshot? { if case .ok(let s) = self { return s }; return nil }
}
