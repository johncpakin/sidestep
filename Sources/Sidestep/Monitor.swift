import Foundation
import Combine
import SwiftUI
import AppKit
import CryptoKit

@MainActor
final class Monitor: ObservableObject {
    @Published var accounts: [Account] = []
    @Published var status: [String: AccountStatus] = [:]     // keyed by Account.id
    @Published var activeEmail: String?                       // owner of the Keychain token (what Claude Code is using)
    @Published var lastPoll: Date?
    @Published var banner: String?
    @Published var loginInProgress = false
    @Published var refreshing: Set<String> = []
    @Published var isPolling = false
    @Published var notes: [String: String] = [:]
    @Published var nicknames: [String: String] = (UserDefaults.standard.dictionary(forKey: "nicknames") as? [String: String]) ?? [:]
    @Published var requestCount = 0

    @Published var pollInterval: TimeInterval = UserDefaults.standard.object(forKey: "pollInterval") as? TimeInterval ?? 300 {
        didSet { UserDefaults.standard.set(pollInterval, forKey: "pollInterval"); schedule() }
    }
    static let intervalChoices: [(String, TimeInterval)] = [("1 min", 60), ("2 min", 120), ("5 min", 300), ("15 min", 900), ("30 min", 1800)]
    private var timer: Timer?
    private var polling = false

    private var alerts = UsageAlerts()

    /// Activity signals — no chat files are ever read.
    @Published var claudeRunning = false          // a `claude` CLI process exists (process table only)
    @Published var burning: Set<String> = []      // session %% rose since the previous poll
    private var lastSession: [String: Double] = [:]
    private var procTimer: Timer?

    init() {
        Notifier.bootstrap()
        schedule()
        procTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkProcesses() }
        }
        checkProcesses()
        Task { await poll() }
    }

    /// `pgrep` for the Claude Code CLI — reads the process table, never files.
    private func checkProcesses() {
        Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
            p.arguments = ["-f", "(^|/)claude( |$)"]
            let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
            guard (try? p.run()) != nil else { return }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            let running = !(String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            await MainActor.run { [running] in
                if self.claudeRunning != running { self.claudeRunning = running }
            }
        }
    }

    private func schedule() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { await self?.poll() }
        }
    }

    // MARK: Nicknames / helpers

    func displayName(_ a: Account) -> String {
        if let n = nicknames[a.id], !n.isEmpty { return n }
        return a.email.split(separator: "@").first.map(String.init) ?? a.email
    }
    func setNickname(_ a: Account, _ name: String) {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { nicknames[a.id] = nil } else { nicknames[a.id] = t }
        UserDefaults.standard.set(nicknames, forKey: "nicknames")
    }
    var activeIndex: Int? { accounts.firstIndex { $0.id == activeEmail?.lowercased() } }
    func isLocked(_ a: Account) -> Bool { if case .needsLogin = status[a.id] ?? .idle { return true }; return false }

    // MARK: Token ownership (fix 1 + 4)
    //
    // Every access token is mapped to the email that owns it, via /api/oauth/profile, cached by fingerprint.
    // The active account is whoever owns the Keychain token — never what ~/.claude.json claims.

    private var owners: [String: String] = (UserDefaults.standard.dictionary(forKey: "tokenOwners") as? [String: String]) ?? [:]

    private func fingerprint(_ token: String) -> String {
        SHA256.hash(data: Data(token.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    /// Email that owns `creds.accessToken`, or nil if it can't be determined right now.
    private func owner(of creds: Credentials) async -> String? {
        let fp = fingerprint(creds.accessToken)
        if let e = owners[fp] { return e }
        requestCount += 1
        guard let p = try? await OAuth.profile(token: creds.accessToken) else { return nil }
        owners[fp] = p.email.lowercased()
        if owners.count > 64 { owners = Dictionary(uniqueKeysWithValues: Array(owners.suffix(48))) }
        UserDefaults.standard.set(owners, forKey: "tokenOwners")
        return p.email.lowercased()
    }

    private func remember(_ creds: Credentials, owner email: String) {
        owners[fingerprint(creds.accessToken)] = email.lowercased()
        UserDefaults.standard.set(owners, forKey: "tokenOwners")
    }

    /// The only path that writes a credential file. Refuses if the token doesn't belong to the file's account.
    @discardableResult
    private func persist(_ a: Account) async -> Bool {
        guard let who = await owner(of: a.credentials) else {
            notes[a.id] = "COULDN'T VERIFY TOKEN OWNER · NOT SAVED"; return false
        }
        guard who == a.id else {
            notes[a.id] = "REFUSED WRITE · TOKEN BELONGS TO \(who)"; return false
        }
        do { _ = try FileStore.save(a); return true }
        catch { notes[a.id] = "SAVE FAILED · \(error.localizedDescription)"; return false }
    }

    // MARK: Discovery

    /// Re-read every credential source and merge by email.
    func reload() async {
        var merged: [String: Account] = [:]
        for a in FileStore.loadAll() where !a.disabled { merged[a.id] = a }

        // Active account = owner of the Keychain token.
        if let kc = ClaudeKeychain.read() {
            if let who = await owner(of: kc) {
                activeEmail = who
                if var existing = merged[who] {
                    // Claude Code keeps this token alive; its copy is authoritative. Mirror it to the file
                    // (ownership already verified) so the proxy's copy never goes stale.
                    if kc != existing.credentials {
                        existing.credentials = kc
                        merged[who] = existing
                        if existing.filePath != nil { await persist(existing) }
                    }
                } else {
                    merged[who] = Account(email: who, credentials: kc, source: .keychain)
                }
            } else if kc.isExpired {
                // Can't ask the API whose token it is; fall back to the config file's claim, read-only.
                activeEmail = ClaudeConfig.currentEmail()?.lowercased()
            }
        } else {
            activeEmail = nil
        }

        // File accounts whose token belongs to someone else are quarantined, never used.
        for (id, a) in merged where a.source != .keychain {
            if let who = await owner(of: a.credentials), who != id {
                status[id] = .needsLogin("TOKEN BELONGS TO \(who) · SIGN IN AGAIN")
            } else if case .needsLogin(let msg) = status[id] ?? .idle, msg.hasPrefix("TOKEN BELONGS") {
                status[id] = .idle
            }
        }

        accounts = merged.values.sorted { $0.email.lowercased() < $1.email.lowercased() }
        for a in accounts where status[a.id] == nil { status[a.id] = .idle }
    }

    // MARK: Polling

    func poll() async {
        guard !polling else { return }
        polling = true; isPolling = true; defer { polling = false; isPolling = false }
        await reload()
        for a in accounts {
            await refreshUsage(for: a)
            try? await Task.sleep(nanoseconds: 1_500_000_000)
        }
        lastPoll = Date()
    }

    func refreshUsage(for account: Account) async {
        var a = account
        if case .needsLogin(let msg) = status[a.id] ?? .idle, msg.hasPrefix("TOKEN BELONGS") { return }   // quarantined
        refreshing.insert(a.id); defer { refreshing.remove(a.id) }
        if status[a.id]?.snapshot == nil, case .idle = status[a.id] ?? .idle { status[a.id] = .loading }
        do {
            if a.credentials.isExpired { a = try await freshCredentials(a) }
            requestCount += 1
            var snap = try await OAuth.usage(token: a.credentials.accessToken)
            if a.accountUUID == nil || a.credentials.rateLimitTier == nil {
                requestCount += 1
                if let p = try? await OAuth.profile(token: a.credentials.accessToken) {
                    a.displayName = p.displayName; a.accountUUID = p.accountUUID
                    a.organizationUUID = p.orgUUID; a.organizationName = p.orgName; a.organizationType = p.orgType
                    a.credentials.rateLimitTier = p.rateLimitTier; a.credentials.subscriptionType = p.subscriptionType
                    remember(a.credentials, owner: p.email)
                    if a.filePath != nil { await persist(a) }
                }
            }
            snap.limits.sort { rank($0) < rank($1) }
            if let sess = snap.session?.percent {
                if let prev = lastSession[a.id], sess > prev { burning.insert(a.id) } else if (lastSession[a.id] ?? 0) >= (snap.session?.percent ?? 0) { burning.remove(a.id) }
                lastSession[a.id] = sess
            }
            notifyThresholds(a, snap)
            withAnimation(.easeInOut(duration: 0.4)) { status[a.id] = .ok(snap) }
            notes[a.id] = nil
            update(a)
        } catch let e as OAuth.APIError {
            switch e.kind {
            case .invalidGrant: status[a.id] = .needsLogin(e.message)
            case .authExpired:
                a.credentials.expiresAt = .distantPast; update(a)
                softFail(a.id, e.message)
            default: softFail(a.id, e.message)
            }
        } catch {
            softFail(a.id, error.localizedDescription)
        }
    }

    /// One notification per threshold (80/90/95) per bucket per reset window; a big jump fires only the highest.
    private func notifyThresholds(_ a: Account, _ snap: UsageSnapshot) {
        for l in snap.limits {
            guard let t = alerts.crossed(a.id, l) else { continue }
            let bucket: String
            switch l.kind {
            case "session": bucket = "5-hour"
            case "weekly_all": bucket = "weekly"
            default: bucket = "\(l.scopeName ?? "model") weekly"
            }
            let reset = l.resetsAt.map { " · resets \($0.fdSpoken())" } ?? ""
            Notifier.post(title: "\(displayName(a)) at \(Int(l.percent))%",
                          body: "\(Int(t))% threshold crossed on the \(bucket) limit\(reset)")
        }
    }

    private func softFail(_ id: String, _ msg: String) {
        if status[id]?.snapshot != nil { notes[id] = msg } else { status[id] = .error(msg) }
    }

    private func rank(_ l: LimitBucket) -> Int {
        switch l.kind { case "session": return 0; case "weekly_all": return 1; default: return 2 }
    }

    /// Returns credentials that are safe to use for `account` (fix 2 + 3).
    /// - Active (Keychain) account: never refreshed by us — re-read the Keychain and wait for Claude Code.
    /// - File account: re-read the file first (the proxy may have rotated it); refresh only if still expired.
    private func freshCredentials(_ account: Account) async throws -> Account {
        var a = account
        if a.id == activeEmail {
            if let kc = ClaudeKeychain.read() {
                if let who = await owner(of: kc), who == a.id, !kc.isExpired {
                    a.credentials = kc; update(a)
                    if a.filePath != nil { await persist(a) }
                    return a
                }
            }
            throw OAuth.APIError(kind: .other, message: "WAITING FOR CLAUDE CODE TO REFRESH")
        }
        if let url = a.filePath, let fresh = FileStore.load(url: url, source: a.source), !fresh.credentials.isExpired,
           await owner(of: fresh.credentials) == a.id {
            a.credentials = fresh.credentials; update(a); return a
        }
        requestCount += 1
        let refreshed = try await OAuth.refresh(a.credentials)
        guard await owner(of: refreshed) == a.id else {
            throw OAuth.APIError(kind: .other, message: "REFRESHED TOKEN BELONGS TO ANOTHER ACCOUNT · NOT SAVED")
        }
        a.credentials = refreshed
        update(a)
        await persist(a)
        return a
    }

    private func update(_ a: Account) {
        if let i = accounts.firstIndex(where: { $0.id == a.id }) { accounts[i] = a }
    }

    // MARK: Switching

    /// Make `account` the one Claude Code uses. The current Keychain token is mirrored to its owner's file
    /// first (ownership verified), then the target's verified credentials go into the Keychain + ~/.claude.json.
    func activate(_ account: Account) async {
        do {
            if let kc = ClaudeKeychain.read(), let who = await owner(of: kc), who != account.id {
                var snap = accounts.first { $0.id == who } ?? Account(email: who, credentials: kc, source: .proxyFile)
                snap.credentials = kc
                snap.source = .proxyFile
                if snap.filePath == nil { snap.filePath = FileStore.writeDir.appendingPathComponent("claude-\(snap.email).json") }
                await persist(snap)
            }
            var target = account
            if target.credentials.isExpired { target = try await freshCredentials(target) }
            guard await owner(of: target.credentials) == target.id else {
                banner = "REFUSED · \(displayName(target).uppercased())'S FILE HOLDS SOMEONE ELSE'S TOKEN — SIGN IN AGAIN"
                status[target.id] = .needsLogin("TOKEN BELONGS TO ANOTHER ACCOUNT · SIGN IN AGAIN")
                return
            }
            if target.credentials.rateLimitTier == nil {
                requestCount += 1
                let p = try await OAuth.profile(token: target.credentials.accessToken)
                target.credentials.rateLimitTier = p.rateLimitTier; target.credentials.subscriptionType = p.subscriptionType
                target.accountUUID = p.accountUUID; target.organizationUUID = p.orgUUID
                target.organizationName = p.orgName; target.organizationType = p.orgType; target.displayName = p.displayName
            }
            try ClaudeKeychain.write(target.credentials)
            try ClaudeConfig.setActive(target)
            activeEmail = target.id
            update(target)
            banner = "CLAUDE CODE → \(displayName(target).uppercased()) · RUNNING SESSIONS FOLLOW WITHIN ~30S"
        } catch {
            banner = "SWITCH FAILED · \(error.localizedDescription)"
        }
        await reload()
    }

    // MARK: Login

    private var loginFlow: OAuth.LoginFlow?

    func beginLogin() {
        loginInProgress = true
        let flow = OAuth.LoginFlow()
        loginFlow = flow
        Task {
            do {
                let creds = try await flow.runBrowserFlow()
                try await finishLogin(creds)
            } catch is CancellationError {
            } catch {
                banner = "LOGIN FAILED · \(error.localizedDescription)"
            }
            loginInProgress = false
            loginFlow = nil
        }
    }

    func cancelLogin() { loginFlow?.cancel(); loginInProgress = false }

    /// Opens the same PKCE flow with Anthropic's "display the code" redirect, for the paste fallback.
    func openPasteModeLink() {
        guard let flow = loginFlow else { return }
        NSWorkspace.shared.open(flow.authorizeURL(manual: true))
    }

    func finishManualLogin(pasted: String) {
        guard let flow = loginFlow else { return }
        Task {
            do { try await finishLogin(try await flow.runManual(pasted: pasted)) }
            catch { banner = "LOGIN FAILED · \(error.localizedDescription)" }
            flow.cancel(); loginInProgress = false; loginFlow = nil
        }
    }

    private func finishLogin(_ creds: Credentials) async throws {
        requestCount += 1
        let p = try await OAuth.profile(token: creds.accessToken)
        remember(creds, owner: p.email)
        var c = creds
        c.rateLimitTier = p.rateLimitTier; c.subscriptionType = p.subscriptionType
        var a = Account(email: p.email, displayName: p.displayName, accountUUID: p.accountUUID,
                        organizationUUID: p.orgUUID, organizationName: p.orgName, organizationType: p.orgType,
                        credentials: c, source: .proxyFile)
        a.filePath = accounts.first { $0.id == a.id }?.filePath
        await persist(a)
        status[a.id] = .idle
        banner = "ADDED \(p.email.uppercased())"
        await reload()
        await refreshUsage(for: accounts.first { $0.id == a.id } ?? a)
    }

    func remove(_ a: Account) {
        if let url = a.filePath { try? FileManager.default.removeItem(at: url) }
        status[a.id] = nil
        Task { await reload() }
    }

    // MARK: Menu bar summary

    var menuTitle: String {
        guard let email = activeEmail, let a = accounts.first(where: { $0.id == email.lowercased() }) else {
            return accounts.isEmpty ? "—" : "…"
        }
        let name = displayName(a)
        let live = claudeRunning || !burning.isEmpty
        guard let snap = status[a.id]?.snapshot else { return name + (live ? " ▸" : "") }
        let s = snap.session.map { Int($0.percent) } ?? 0
        let w = snap.weekly.map { Int($0.percent) } ?? 0
        return "\(name) \(live ? "▸" : "·") \(s)% · \(w)%"
    }
}
