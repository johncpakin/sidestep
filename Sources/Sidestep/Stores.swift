import Foundation

// MARK: - Proxy-format JSON files (the same layout CLIProxyAPI writes)

/// Reads/writes the JSON layout used by CLIProxyAPI in ~/.cli-proxy-api/claude-<email>.json.
/// We reuse the format verbatim so the proxy and this app share one source of truth.
struct ProxyAuthFile: Codable {
    var access_token: String
    var refresh_token: String
    var expired: String            // ISO-8601 with offset, e.g. 2026-08-21T16:33:49-07:00
    var last_refresh: String?
    var email: String
    var type: String               // "claude"
    var disabled: Bool?
    var id_token: String?
    // Extra fields this app adds (harmless to the proxy; it ignores unknown keys).
    var scopes: [String]?
    var subscription_type: String?
    var rate_limit_tier: String?
    var account_uuid: String?
    var organization_uuid: String?
    var organization_name: String?
    var organization_type: String?
    var display_name: String?

    static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    static let fracFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func parseDate(_ s: String) -> Date? {
        isoFormatter.date(from: s) ?? fracFormatter.date(from: s)
    }
    static func formatDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssxxx"
        return f.string(from: d)
    }
}

final class FileStore {
    static let proxyDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cli-proxy-api")
    static let appDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Sidestep/accounts")
    }()

    /// Directory new accounts get written to: the proxy dir if it exists (so the proxy picks them up), else our own.
    static var writeDir: URL {
        if FileManager.default.fileExists(atPath: proxyDir.path) { return proxyDir }
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir
    }

    static func loadAll() -> [Account] {
        var out: [Account] = []
        for (dir, source) in [(proxyDir, CredentialSource.proxyFile), (appDir, CredentialSource.appStore)] {
            guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for url in files where url.lastPathComponent.hasPrefix("claude-") && url.pathExtension == "json" {
                if let acct = load(url: url, source: source) { out.append(acct) }
            }
        }
        return out
    }

    static func load(url: URL, source: CredentialSource) -> Account? {
        guard let data = try? Data(contentsOf: url),
              let f = try? JSONDecoder().decode(ProxyAuthFile.self, from: data),
              f.type == "claude" else { return nil }
        let creds = Credentials(
            accessToken: f.access_token,
            refreshToken: f.refresh_token,
            expiresAt: ProxyAuthFile.parseDate(f.expired) ?? .distantPast,
            scopes: f.scopes ?? OAuth.defaultScopes,
            subscriptionType: f.subscription_type,
            rateLimitTier: f.rate_limit_tier)
        return Account(email: f.email, displayName: f.display_name, accountUUID: f.account_uuid,
                       organizationUUID: f.organization_uuid, organizationName: f.organization_name,
                       organizationType: f.organization_type, credentials: creds, source: source,
                       filePath: url, disabled: f.disabled ?? false)
    }

    /// Persist an account. Keeps any keys already in the file we don't model (by merging JSON), so the
    /// proxy's own fields survive.
    static func save(_ account: Account) throws -> URL {
        let url = account.filePath ?? writeDir.appendingPathComponent("claude-\(account.email).json")
        var dict: [String: Any] = [:]
        if let data = try? Data(contentsOf: url),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            dict = existing
        }
        let c = account.credentials
        dict["type"] = "claude"
        dict["email"] = account.email
        dict["access_token"] = c.accessToken
        dict["refresh_token"] = c.refreshToken
        dict["expired"] = ProxyAuthFile.formatDate(c.expiresAt)
        dict["last_refresh"] = ProxyAuthFile.formatDate(Date())
        if dict["disabled"] == nil { dict["disabled"] = false }
        if dict["id_token"] == nil { dict["id_token"] = "" }
        dict["scopes"] = c.scopes
        dict["subscription_type"] = c.subscriptionType
        dict["rate_limit_tier"] = c.rateLimitTier
        dict["account_uuid"] = account.accountUUID
        dict["organization_uuid"] = account.organizationUUID
        dict["organization_name"] = account.organizationName
        dict["organization_type"] = account.organizationType
        dict["display_name"] = account.displayName
        let clean = dict.compactMapValues { $0 is NSNull ? nil : $0 }
        let data = try JSONSerialization.data(withJSONObject: clean, options: [.sortedKeys])
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return url
    }
}

// MARK: - Claude Code keychain item

/// The item Claude Code itself reads: service "Claude Code-credentials", value is
/// {"claudeAiOauth":{accessToken,refreshToken,expiresAt(ms),scopes,subscriptionType,rateLimitTier}}.
/// We go through /usr/bin/security (same tool Claude Code uses) so the item ACL stays consistent.
enum ClaudeKeychain {
    static let service = "Claude Code-credentials"

    struct Blob: Codable {
        struct OAuth: Codable {
            var accessToken: String
            var refreshToken: String
            var expiresAt: Double
            var scopes: [String]
            var subscriptionType: String?
            var rateLimitTier: String?
            var refreshTokenExpiresAt: Double?
        }
        var claudeAiOauth: OAuth
    }

    @discardableResult
    static func run(_ args: [String]) -> (status: Int32, out: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = args
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
        do { try p.run() } catch { return (-1, "") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    static func read() -> Credentials? {
        let r = run(["find-generic-password", "-s", service, "-w"])
        guard r.status == 0, let data = r.out.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
              let blob = try? JSONDecoder().decode(Blob.self, from: data) else { return nil }
        let o = blob.claudeAiOauth
        return Credentials(accessToken: o.accessToken, refreshToken: o.refreshToken,
                           expiresAt: Date(timeIntervalSince1970: o.expiresAt / 1000),
                           scopes: o.scopes, subscriptionType: o.subscriptionType, rateLimitTier: o.rateLimitTier)
    }

    static func write(_ c: Credentials) throws {
        let blob = Blob(claudeAiOauth: .init(
            accessToken: c.accessToken, refreshToken: c.refreshToken,
            expiresAt: (c.expiresAt.timeIntervalSince1970 * 1000).rounded(),
            scopes: c.scopes, subscriptionType: c.subscriptionType ?? "max",
            rateLimitTier: c.rateLimitTier, refreshTokenExpiresAt: nil))
        let data = try JSONEncoder().encode(blob)
        let json = String(data: data, encoding: .utf8)!
        let r = run(["add-generic-password", "-U", "-a", NSUserName(), "-s", service, "-w", json])
        if r.status != 0 { throw SidestepError("security add-generic-password failed (\(r.status))") }
    }
}

// MARK: - ~/.claude.json oauthAccount (what /status and the UI show)

enum ClaudeConfig {
    static let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json")

    static func currentEmail() -> String? {
        guard let data = try? Data(contentsOf: url),
              let d = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let o = d["oauthAccount"] as? [String: Any] else { return nil }
        return o["emailAddress"] as? String
    }

    static func setActive(_ a: Account) throws {
        guard let data = try? Data(contentsOf: url),
              var d = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        var o = (d["oauthAccount"] as? [String: Any]) ?? [:]
        o["emailAddress"] = a.email
        o["accountUuid"] = a.accountUUID ?? o["accountUuid"]
        o["organizationUuid"] = a.organizationUUID ?? o["organizationUuid"]
        o["organizationName"] = a.organizationName ?? o["organizationName"]
        o["organizationType"] = a.organizationType ?? o["organizationType"]
        o["organizationRateLimitTier"] = a.credentials.rateLimitTier ?? o["organizationRateLimitTier"]
        o["displayName"] = a.displayName ?? o["displayName"]
        o["fullName"] = a.displayName ?? o["fullName"]
        o["profileFetchedAt"] = Int(Date().timeIntervalSince1970 * 1000)
        d["oauthAccount"] = o
        // Keep a backup of the previous file — cheap insurance.
        try? FileManager.default.copyItem(at: url, to: url.appendingPathExtension("sidestep-bak"))
        try? FileManager.default.removeItem(at: url.appendingPathExtension("sidestep-bak"))
        try FileManager.default.copyItem(at: url, to: url.appendingPathExtension("sidestep-bak"))
        let out = try JSONSerialization.data(withJSONObject: d, options: [.prettyPrinted, .sortedKeys])
        try out.write(to: url, options: .atomic)
    }
}

struct SidestepError: LocalizedError {
    var message: String
    init(_ m: String) { message = m }
    var errorDescription: String? { message }
}
