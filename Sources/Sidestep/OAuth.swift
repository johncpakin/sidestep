import Foundation
import CryptoKit
import Network
import AppKit

/// Anthropic consumer OAuth, exactly as Claude Code / CLIProxyAPI use it.
enum OAuth {
    static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    static let tokenURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
    static let authorizeURL = URL(string: "https://claude.ai/oauth/authorize")!
    static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    static let profileURL = URL(string: "https://api.anthropic.com/api/oauth/profile")!
    static let callbackPort: UInt16 = 54545
    static let redirectURI = "http://localhost:54545/callback"
    static let defaultScopes = ["user:file_upload", "user:inference", "user:mcp_servers", "user:profile", "user:sessions:claude_code"]
    static let loginScopes = "org:create_api_key user:profile user:inference user:mcp_servers user:sessions:claude_code user:file_upload"
    static let userAgent = "claude-cli/2.1.0 (external, cli)"

    static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 20
        c.httpAdditionalHeaders = ["User-Agent": userAgent]
        return URLSession(configuration: c)
    }()

    struct TokenResponse: Decodable {
        var access_token: String
        var refresh_token: String?
        var expires_in: Double
        var scope: String?
    }

    struct APIError: LocalizedError {
        enum Kind { case invalidGrant, authExpired, rateLimited, other }
        var kind: Kind; var message: String
        var errorDescription: String? { message }
    }

    private static func classify(_ data: Data, status: Int) -> APIError {
        let text = String(data: data, encoding: .utf8) ?? ""
        if text.contains("invalid_grant") { return APIError(kind: .invalidGrant, message: "Refresh token expired — sign in again") }
        if text.contains("rate_limit_error") || status == 429 { return APIError(kind: .rateLimited, message: "Rate limited by Anthropic edge") }
        if text.contains("authentication_error") || status == 401 { return APIError(kind: .authExpired, message: "Access token rejected") }
        // Try to pull a message field out.
        if let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let e = j["error"] as? [String: Any], let m = e["message"] as? String { return APIError(kind: .other, message: m) }
            if let m = j["error_description"] as? String { return APIError(kind: .other, message: m) }
        }
        return APIError(kind: .other, message: "HTTP \(status)")
    }

    // MARK: Refresh

    static func refresh(_ c: Credentials) async throws -> Credentials {
        var req = URLRequest(url: tokenURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token", "refresh_token": c.refreshToken, "client_id": clientID])
        let (data, resp) = try await session.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200, let t = try? JSONDecoder().decode(TokenResponse.self, from: data) else {
            throw classify(data, status: status)
        }
        var n = c
        n.accessToken = t.access_token
        n.refreshToken = t.refresh_token ?? c.refreshToken
        n.expiresAt = Date().addingTimeInterval(t.expires_in)
        if let s = t.scope { n.scopes = s.split(separator: " ").map(String.init) }
        return n
    }

    // MARK: Usage / profile

    private static func get(_ url: URL, token: String) async throws -> [String: Any] {
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, resp) = try await session.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200, let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any], j["error"] == nil else {
            throw classify(data, status: status)
        }
        return j
    }

    static func usage(token: String) async throws -> UsageSnapshot {
        let j = try await get(usageURL, token: token)
        var limits: [LimitBucket] = []
        for raw in (j["limits"] as? [[String: Any]]) ?? [] {
            var scopeName: String? = nil
            if let scope = raw["scope"] as? [String: Any] {
                if let m = scope["model"] as? [String: Any] { scopeName = m["display_name"] as? String }
                if scopeName == nil, let s = scope["surface"] as? String { scopeName = s }
            }
            limits.append(LimitBucket(
                kind: raw["kind"] as? String ?? "?",
                group: raw["group"] as? String ?? "",
                percent: (raw["percent"] as? Double) ?? 0,
                severity: raw["severity"] as? String ?? "normal",
                resetsAt: (raw["resets_at"] as? String).flatMap(ProxyAuthFile.parseDate),
                scopeName: scopeName,
                isActive: raw["is_active"] as? Bool ?? false))
        }
        // Older payload shape fallback.
        if limits.isEmpty {
            for (key, kind) in [("five_hour", "session"), ("seven_day", "weekly_all"), ("seven_day_opus", "weekly_scoped"), ("seven_day_sonnet", "weekly_scoped")] {
                if let b = j[key] as? [String: Any], let u = b["utilization"] as? Double {
                    limits.append(LimitBucket(kind: kind, group: kind == "session" ? "session" : "weekly", percent: u, severity: "normal",
                                              resetsAt: (b["resets_at"] as? String).flatMap(ProxyAuthFile.parseDate),
                                              scopeName: key.hasSuffix("opus") ? "Opus" : key.hasSuffix("sonnet") ? "Sonnet" : nil, isActive: false))
                }
            }
        }
        let extra = ((j["extra_usage"] as? [String: Any])?["is_enabled"] as? Bool) ?? false
        return UsageSnapshot(fetchedAt: Date(), limits: limits, extraUsageEnabled: extra)
    }

    struct Profile {
        var email: String; var displayName: String?; var accountUUID: String?
        var orgUUID: String?; var orgName: String?; var orgType: String?; var rateLimitTier: String?
        var subscriptionType: String {
            switch orgType {
            case "claude_max": return "max"
            case "claude_pro": return "pro"
            case "claude_team": return "team"
            case "claude_enterprise": return "enterprise"
            default: return "max"
            }
        }
    }

    static func profile(token: String) async throws -> Profile {
        let j = try await get(profileURL, token: token)
        let a = j["account"] as? [String: Any] ?? [:]
        let o = j["organization"] as? [String: Any] ?? [:]
        guard let email = a["email"] as? String else { throw APIError(kind: .other, message: "profile had no email") }
        return Profile(email: email, displayName: a["display_name"] as? String, accountUUID: a["uuid"] as? String,
                       orgUUID: o["uuid"] as? String, orgName: o["name"] as? String, orgType: o["organization_type"] as? String,
                       rateLimitTier: o["rate_limit_tier"] as? String)
    }

    // MARK: Login (PKCE, local callback listener with manual-paste fallback)

    final class LoginFlow {
        let verifier: String
        let state: String
        private var listener: NWListener?
        private var continuation: CheckedContinuation<(code: String, state: String), Error>?

        init() {
            verifier = LoginFlow.random(32)
            state = LoginFlow.random(32)
        }

        static func random(_ n: Int) -> String {
            var bytes = [UInt8](repeating: 0, count: n)
            _ = SecRandomCopyBytes(kSecRandomDefault, n, &bytes)
            return Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }

        var challenge: String {
            let digest = SHA256.hash(data: Data(verifier.utf8))
            return Data(digest).base64EncodedString().replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }

        func authorizeURL(manual: Bool) -> URL {
            var c = URLComponents(url: OAuth.authorizeURL, resolvingAgainstBaseURL: false)!
            c.queryItems = [
                .init(name: "code", value: "true"),
                .init(name: "client_id", value: OAuth.clientID),
                .init(name: "response_type", value: "code"),
                .init(name: "redirect_uri", value: manual ? "https://console.anthropic.com/oauth/code/callback" : OAuth.redirectURI),
                .init(name: "scope", value: OAuth.loginScopes),
                .init(name: "code_challenge", value: challenge),
                .init(name: "code_challenge_method", value: "S256"),
                .init(name: "state", value: state),
            ]
            return c.url!
        }

        /// Opens the browser and waits for the callback on localhost:54545.
        func runBrowserFlow() async throws -> Credentials {
            let (code, st) = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<(code: String, state: String), Error>) in
                self.continuation = cont
                do { try self.startListener() } catch { cont.resume(throwing: error); self.continuation = nil; return }
                NSWorkspace.shared.open(self.authorizeURL(manual: false))
            }
            guard st == state else { throw APIError(kind: .other, message: "OAuth state mismatch") }
            return try await exchange(code: code, state: st, redirect: OAuth.redirectURI)
        }

        /// For the paste fallback: user pastes "code#state" from console.anthropic.com.
        func runManual(pasted: String) async throws -> Credentials {
            let parts = pasted.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "#", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { throw APIError(kind: .other, message: "Expected code#state") }
            return try await exchange(code: parts[0], state: parts[1], redirect: "https://console.anthropic.com/oauth/code/callback")
        }

        func cancel() {
            listener?.cancel(); listener = nil
            continuation?.resume(throwing: CancellationError()); continuation = nil
        }

        private func exchange(code: String, state: String, redirect: String) async throws -> Credentials {
            var req = URLRequest(url: OAuth.tokenURL)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: [
                "grant_type": "authorization_code", "code": code, "state": state,
                "redirect_uri": redirect, "client_id": OAuth.clientID, "code_verifier": verifier])
            let (data, resp) = try await OAuth.session.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200, let t = try? JSONDecoder().decode(TokenResponse.self, from: data) else {
                throw OAuth.classify(data, status: status)
            }
            return Credentials(accessToken: t.access_token, refreshToken: t.refresh_token ?? "",
                               expiresAt: Date().addingTimeInterval(t.expires_in),
                               scopes: t.scope?.split(separator: " ").map(String.init) ?? OAuth.defaultScopes,
                               subscriptionType: nil, rateLimitTier: nil)
        }

        static func page(title: String, detail: String, ok: Bool) -> String {
            """
            <!doctype html><html><head><meta charset="utf-8"><title>Sidestep</title>
            <meta name="viewport" content="width=device-width,initial-scale=1">
            <style>
              :root{color-scheme:light dark}
              body{margin:0;min-height:100vh;display:grid;place-items:center;font-family:-apple-system,BlinkMacSystemFont,"SF Pro Text",Helvetica,sans-serif;background:#f5f5f7;color:#1d1d1f}
              @media(prefers-color-scheme:dark){body{background:#1c1c1e;color:#f5f5f7}.card{background:#2c2c2e;box-shadow:0 10px 30px rgba(0,0,0,.5)}}
              .card{background:#fff;border-radius:18px;padding:36px 44px;text-align:center;box-shadow:0 10px 30px rgba(0,0,0,.08);max-width:380px}
              .badge{width:56px;height:56px;border-radius:50%;display:grid;place-items:center;margin:0 auto 18px;font-size:28px;color:#fff;background:\(ok ? "#34c759" : "#ff3b30")}
              h1{font-size:20px;margin:0 0 8px;font-weight:600}
              p{margin:0;font-size:14px;opacity:.7;line-height:1.45}
              .app{margin-top:22px;font-size:12px;opacity:.45;letter-spacing:.04em;text-transform:uppercase}
            </style></head><body>
            <div class="card"><div class="badge">\(ok ? "✓" : "✕")</div><h1>\(title)</h1><p>\(detail)</p><div class="app">Sidestep</div></div>
            </body></html>
            """
        }

        private func startListener() throws {
            let l = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: OAuth.callbackPort)!)
            listener = l
            l.newConnectionHandler = { [weak self] conn in
                conn.start(queue: .main)
                conn.receive(minimumIncompleteLength: 1, maximumLength: 16384) { data, _, _, _ in
                    guard let self, let data, let text = String(data: data, encoding: .utf8) else { return }
                    let firstLine = text.split(separator: "\r\n").first.map(String.init) ?? ""
                    let path = firstLine.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
                    var body = LoginFlow.page(title: "Signed in", detail: "Sidestep has this account now — you can close this tab.", ok: true)
                    var handled = false
                    if let comps = URLComponents(string: "http://localhost" + path), comps.path == "/callback" {
                        let q = comps.queryItems ?? []
                        if let code = q.first(where: { $0.name == "code" })?.value, let st = q.first(where: { $0.name == "state" })?.value {
                            handled = true
                            self.continuation?.resume(returning: (code, st)); self.continuation = nil
                        } else if let err = q.first(where: { $0.name == "error" })?.value {
                            body = LoginFlow.page(title: "Sign-in failed", detail: err, ok: false)
                            self.continuation?.resume(throwing: APIError(kind: .other, message: err)); self.continuation = nil
                        }
                    }
                    let resp = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n" + body
                    conn.send(content: resp.data(using: .utf8), completion: .contentProcessed { _ in
                        conn.cancel()
                        if handled { self.listener?.cancel(); self.listener = nil }
                    })
                }
            }
            l.start(queue: .main)
        }
    }
}
