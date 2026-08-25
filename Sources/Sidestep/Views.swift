import SwiftUI
import ServiceManagement

struct PopoverView: View {
    @EnvironmentObject var m: Monitor
    @State private var pasteCode = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            accounts
            if m.loginInProgress { loginPanel }
            if let b = m.banner { bannerView(b) }
            ResetTimeline()
            footer
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 12)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .background(FD.bg.opacity(0.42))   // kode-rust glass: hsla(220,16%,8%,.40) over under-window vibrancy
        .environment(\.colorScheme, .dark)
        .overlayPreferenceValue(TooltipKey.self) { TooltipLayer(info: $0) }
    }

    // MARK: header
    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("CLAUDE · USAGE").font(FD.sans(13, .semibold)).tracking(2).foregroundStyle(FD.ink2)
                HStack(spacing: 6) {
                    if let p = m.lastPoll {
                        Text("UPD").foregroundStyle(FD.ink3)
                        TimelineView(.periodic(from: .now, by: 15)) { ctx in
                            let s = max(0, Int(ctx.date.timeIntervalSince(p)))
                            Text(s < 60 ? "\(s)S" : s < 3600 ? "\(s / 60)M" : "\(s / 3600)H \((s % 3600) / 60)M").foregroundStyle(FD.ink2)
                        }
                        Text("AGO").foregroundStyle(FD.ink3)
                        Text("·").foregroundStyle(FD.ink3)
                    }
                    Text("EVERY").foregroundStyle(FD.ink3)
                    Picker("", selection: $m.pollInterval) {
                        ForEach(Monitor.intervalChoices, id: \.1) { Text($0.0.uppercased()).tag($0.1) }
                    }
                    .labelsHidden().controlSize(.mini).fixedSize()
                    Text("· \(m.requestCount) REQ SINCE LAUNCH").foregroundStyle(FD.ink3)
                }
                .font(FD.mono(10)).tracking(0.4)
            }
            Spacer()
            Button { Task { await m.poll() } } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(m.isPolling ? FD.accent : FD.ink2)
                    .rotationEffect(.degrees(m.isPolling ? 360 : 0))
                    .animation(m.isPolling ? .linear(duration: 1.2).repeatForever(autoreverses: false) : .default, value: m.isPolling)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(GlassButtonStyle(compact: true)).disabled(m.isPolling).help("Refresh now")
        }
        .padding(.bottom, 9)
        .overlay(alignment: .bottom) { Rectangle().fill(FD.line).frame(height: 1) }
    }

    // MARK: accounts + shifter
    private var accounts: some View {
        VStack(spacing: 0) {
            if m.accounts.isEmpty {
                Text("NO ACCOUNTS · ADD ONE BELOW OR SIGN IN TO THE PROXY").font(FD.mono(10)).foregroundStyle(FD.ink3).padding(.vertical, 20)
            }
            ForEach(Array(m.accounts.enumerated()), id: \.element.id) { i, a in
                AccountRow(index: i, account: a)
                    .overlay(alignment: .top) {
                        if i > 0 { Rectangle().fill(FD.divider).frame(height: 1).padding(.horizontal, 22) }
                    }
            }
        }
        .padding(.leading, 44)
        .coordinateSpace(name: "accounts")
        .overlayPreferenceValue(GateKey.self) { anchors in
            GeometryReader { geo in
                let gates = anchors.mapValues { geo[$0].y }
                Shifter(gates: gates).frame(width: 36, alignment: .leading)
            }
        }
    }

    // MARK: login / banner
    private var loginPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("WAITING FOR BROWSER SIGN-IN…").font(FD.mono(10, .medium)).foregroundStyle(FD.ink2)
            Text("Use a browser that's signed into the account you want to add (a private window is easiest). The token is filed under whichever account actually approves it.")
                .font(FD.sans(11)).foregroundStyle(FD.ink3).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Text("If localhost can't be reached:").font(FD.sans(11)).foregroundStyle(FD.ink3)
                Button("OPEN PASTE-MODE LINK") { m.openPasteModeLink() }.buttonStyle(GlassButtonStyle())
            }
            HStack {
                TextField("code#state", text: $pasteCode).textFieldStyle(.roundedBorder).font(FD.mono(10))
                Button("USE") { m.finishManualLogin(pasted: pasteCode); pasteCode = "" }.buttonStyle(GlassButtonStyle(tint: .ok)).disabled(pasteCode.isEmpty)
                Button("CANCEL") { m.cancelLogin() }.buttonStyle(GlassButtonStyle())
            }
        }
        .padding(10).background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.04)))
        .padding(.vertical, 6)
    }

    private func bannerView(_ b: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("▲").font(.system(size: 8)).foregroundStyle(FD.info)
            Text(b).font(FD.mono(10)).foregroundStyle(FD.info).textCase(.uppercase)
            Spacer()
            Button { m.banner = nil } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(FD.ink3) }.buttonStyle(.plain)
        }
        .padding(.vertical, 6)
    }

    // MARK: footer
    private var footer: some View {
        HStack(spacing: 10) {
            Button("+ ADD ACCOUNT") { m.beginLogin() }.buttonStyle(GlassButtonStyle(tint: .ok)).disabled(m.loginInProgress)
            Spacer()
            LaunchAtLoginToggle()
            Button("QUIT") { NSApp.terminate(nil) }.buttonStyle(GlassButtonStyle()).keyboardShortcut("q")
        }
        .padding(.top, 9)
        .overlay(alignment: .top) { Rectangle().fill(FD.line).frame(height: 1) }
        .padding(.top, 10)
    }
}

struct LaunchAtLoginToggle: View {
    @State private var on = SMAppService.mainApp.status == .enabled
    var body: some View {
        Button { on.toggle() } label: {
            HStack(spacing: 5) {
                ZStack {
                    RoundedRectangle(cornerRadius: 2).stroke(FD.ink3, lineWidth: 1).frame(width: 10, height: 10)
                    if on { Text("✓").font(.system(size: 8, weight: .bold)).foregroundStyle(FD.accent) }
                }
                Text("LOGIN ITEM").font(FD.mono(10, .medium)).tracking(1).foregroundStyle(FD.ink3)
            }
        }
        .buttonStyle(.plain)
        .onChange(of: on) { _, v in
            do { if v { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
            catch { on = SMAppService.mainApp.status == .enabled }
        }
    }
}

// MARK: - Account row

struct AccountRow: View {
    @EnvironmentObject var m: Monitor
    let index: Int
    let account: Account
    @State private var editing = false
    @State private var draft = ""
    @FocusState private var nameFocused: Bool

    private var status: AccountStatus { m.status[account.id] ?? .idle }
    private var isActive: Bool { account.id == m.activeEmail?.lowercased() }
    private var locked: Bool { m.isLocked(account) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            who.frame(width: 122, alignment: .leading)
            rows
        }
        .padding(.top, 12).padding(.bottom, 11)
        .opacity(locked ? 0.85 : 1)
    }

    private var tier: String {
        if let t = account.credentials.rateLimitTier { return t.replacingOccurrences(of: "default_claude_", with: "").replacingOccurrences(of: "_", with: " ").uppercased() }
        return (account.credentials.subscriptionType ?? "—").uppercased()
    }

    private var who: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                if editing {
                    TextField("", text: $draft)
                        .textFieldStyle(.plain).font(FD.sans(14, .semibold)).foregroundStyle(FD.ink)
                        .focused($nameFocused)
                        .onSubmit { commit() }
                        .onExitCommand { editing = false }
                        .onChange(of: nameFocused) { _, f in if !f && editing { commit() } }
                        .padding(.horizontal, 3).background(RoundedRectangle(cornerRadius: 4).fill(FD.info.opacity(0.1)))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(FD.info, lineWidth: 1))
                } else {
                    Text(m.displayName(account)).font(FD.sans(14, .semibold)).foregroundStyle(isActive ? FD.active : FD.ink).lineLimit(1)
                        .padding(.horizontal, 3).contentShape(Rectangle())
                        .onTapGesture { draft = m.nicknames[account.id] ?? m.displayName(account); editing = true; nameFocused = true }
                        .help("Click to rename")
                }
                if m.refreshing.contains(account.id) {
                    ProgressView().controlSize(.mini).scaleEffect(0.6).frame(width: 10, height: 10)
                }
            }
            .padding(.horizontal, -3)
            .anchorPreference(key: GateKey.self, value: .center) { [index: $0] }
            Text(account.email).font(FD.mono(9.5)).foregroundStyle(FD.ink4).lineLimit(1).truncationMode(.middle)
            Text(tier).font(FD.mono(10)).tracking(0.8).foregroundStyle(FD.ink3)
        }
    }

    private func commit() {
        m.setNickname(account, draft); editing = false
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 5) {
            switch status {
            case .ok(let s):
                ForEach(s.limits) { l in
                    LimitRow(limit: l, activity: (isActive && m.claudeRunning) || m.burning.contains(account.id))
                }
                if let note = m.notes[account.id] { Note(text: note, color: FD.warn) }
            case .needsLogin(let msg):
                LimitRow(limit: nil, label: "5H")
                LimitRow(limit: nil, label: "7D")
                HStack {
                    Note(text: msg, color: FD.warn)
                    Spacer()
                    Button { m.beginLogin() } label: { HStack(spacing: 6) { Text("SIGN IN"); Text("→").opacity(0.6) } }
                        .buttonStyle(GlassButtonStyle(tint: .warn))
                }
            case .error(let msg):
                LimitRow(limit: nil, label: "5H")
                LimitRow(limit: nil, label: "7D")
                Note(text: msg, color: FD.crit)
            case .idle, .loading:
                LimitRow(limit: nil, label: "5H")
                LimitRow(limit: nil, label: "7D")
                Text("LOADING…").font(FD.mono(10)).foregroundStyle(FD.ink3)
            }
        }
    }
}

struct Note: View {
    var text: String; var color: Color
    var body: some View {
        HStack(spacing: 6) {
            Text("▲").font(.system(size: 8))
            Text(text).textCase(.uppercase).lineLimit(1)
        }
        .font(FD.mono(10)).foregroundStyle(color)
    }
}

struct LimitRow: View {
    var limit: LimitBucket?
    var label: String = ""
    var activity: Bool = false

    var body: some View {
        let isModel = limit?.kind == "weekly_scoped"
        let lbl = limit.map { l -> String in
            switch l.kind { case "session": return "5H"; case "weekly_all": return "7D"; default: return (l.scopeName ?? "MODEL").uppercased() }
        } ?? label
        HStack(spacing: 8) {
            Text(lbl).font(FD.mono(10.5)).tracking(0.8).foregroundStyle(isModel ? FD.model : FD.ink2).frame(width: 44, alignment: .leading).lineLimit(1)
            if let l = limit {
                Ladder(percent: l.percent, color: isModel ? FD.model : FD.severity(l.percent), thin: isModel, activity: activity)
                Text("\(Int(l.percent))%").font(FD.mono(10.5, .semibold)).foregroundStyle(FD.pctInk).frame(width: 38, alignment: .trailing)
                    .contentTransition(.numericText())
                Group {
                    if let r = l.resetsAt {
                        Text(r.fdCountdown()).foregroundStyle(FD.ink2)
                            .fdTooltip(r.fdSpoken())
                            .contentShape(Rectangle())
                    } else { Text("—").foregroundStyle(FD.ink4) }
                }
                .font(FD.mono(10.5, .medium)).frame(width: 52, alignment: .trailing).lineLimit(1)
            } else {
                Ladder(percent: 0, color: FD.ok)
                Text("—").font(FD.mono(10.5)).foregroundStyle(FD.ink4).frame(width: 38, alignment: .trailing)
                Text("—").font(FD.mono(10.5)).foregroundStyle(FD.ink4).frame(width: 52, alignment: .trailing)
            }
        }
        .frame(height: 12)
    }
}
