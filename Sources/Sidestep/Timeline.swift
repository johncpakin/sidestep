import SwiftUI

/// Flight Deck reset Gantt: name column, dated day columns (−7d … +7d), NOW at centre,
/// each account's 7-day window filled to % used with a labelled end tick, a thin model bar,
/// and a ◆ at the 5 h reset.
struct ResetTimeline: View {
    @EnvironmentObject var m: Monitor
    private let span: TimeInterval = 7 * 86400
    private let nameW: CGFloat = 60, gapW: CGFloat = 8, laneH: CGFloat = 26, headH: CGFloat = 32

    var body: some View {
        if !m.accounts.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text("RESET WINDOWS · ±7 DAYS").font(FD.sans(10, .semibold)).tracking(1.6).foregroundStyle(FD.ink2)
                    Spacer()
                    HStack(spacing: 12) {
                        HStack(spacing: 4) { RoundedRectangle(cornerRadius: 1).fill(FD.ink2).frame(width: 14, height: 5); Text("7D WINDOW · FILL = USED") }
                        HStack(spacing: 4) { RoundedRectangle(cornerRadius: 1).fill(FD.model).frame(width: 14, height: 3); Text("MODEL") }
                        HStack(spacing: 4) { Rectangle().fill(FD.ink).frame(width: 5, height: 5).rotationEffect(.degrees(45)); Text("5H RESET") }
                    }
                    .font(FD.mono(8.5)).tracking(0.5).foregroundStyle(FD.ink3)
                }
                TimelineView(.periodic(from: .now, by: 60)) { ctx in
                    Canvas { g, size in draw(g, size, now: ctx.date) }
                        .frame(height: headH + CGFloat(m.accounts.count) * laneH)
                }
            }
            .padding(.top, 8)
            .overlay(alignment: .top) { Rectangle().fill(FD.line).frame(height: 1) }
            .padding(.top, 8)
        }
    }

    private func x(_ d: Date, now: Date, w: CGFloat) -> CGFloat {
        let f = (d.timeIntervalSince(now) + span) / (2 * span)
        return nameW + gapW + CGFloat(min(1, max(0, f))) * (w - nameW - gapW)
    }

    private func draw(_ g: GraphicsContext, _ size: CGSize, now: Date) {
        let x0 = nameW + gapW, x1 = size.width
        let colW = (x1 - x0) / 14
        let cal = Calendar.current
        let startDay = cal.startOfDay(for: now.addingTimeInterval(-span))
        // day columns
        var d = cal.date(byAdding: .day, value: 1, to: startDay) ?? startDay   // first midnight inside range
        let today = cal.startOfDay(for: now)
        while d < now.addingTimeInterval(span) {
            let px = x(d, now: now, w: size.width)
            var p = Path(); p.move(to: .init(x: px, y: 10)); p.addLine(to: .init(x: px, y: size.height))
            g.stroke(p, with: .color(FD.line2), lineWidth: 1)
            let isToday = d == today
            let wd = d.formatted(.dateTime.weekday(.abbreviated)).uppercased()
            let dn = d.formatted(.dateTime.day())
            g.draw(Text(wd).font(FD.mono(8)).foregroundColor(isToday ? FD.accent : FD.ink4), at: .init(x: px + 3, y: 11), anchor: .topLeading)
            g.draw(Text(dn).font(FD.mono(8, .medium)).foregroundColor(isToday ? FD.accent : FD.ink3), at: .init(x: px + 3, y: 20), anchor: .topLeading)
            d = cal.date(byAdding: .day, value: 1, to: d) ?? d.addingTimeInterval(86400)
        }
        // NOW
        let xn = x(now, now: now, w: size.width)
        var nl = Path(); nl.move(to: .init(x: xn, y: 10)); nl.addLine(to: .init(x: xn, y: size.height))
        g.stroke(nl, with: .color(FD.accent.opacity(0.9)), lineWidth: 1)
        g.draw(Text("NOW").font(FD.mono(8, .semibold)).foregroundColor(FD.accent), at: .init(x: xn, y: 0), anchor: .top)

        for (i, a) in m.accounts.enumerated() {
            let top = headH + CGFloat(i) * laneH
            var sep = Path(); sep.move(to: .init(x: 0, y: top)); sep.addLine(to: .init(x: size.width, y: top))
            g.stroke(sep, with: .color(FD.line2), lineWidth: 1)
            let active = a.id == m.activeEmail?.lowercased()
            let snap = m.status[a.id]?.snapshot
            g.draw(Text(m.displayName(a)).font(FD.mono(10.5, .medium)).foregroundColor(snap == nil ? FD.ink4 : active ? FD.active : FD.ink2),
                   at: .init(x: 0, y: top + laneH / 2), anchor: .leading)
            guard let s = snap else {
                g.draw(Text("NO DATA · SIGN IN").font(FD.mono(8.5)).foregroundColor(FD.ink4), at: .init(x: xn + 6, y: top + laneH / 2), anchor: .leading)
                continue
            }
            let barY = top + 9, barH: CGFloat = 7
            if let w = s.weekly, let r = w.resetsAt {
                let xa = x(r.addingTimeInterval(-span), now: now, w: size.width), xb = x(r, now: now, w: size.width)
                let c = FD.severity(w.percent)
                let track = CGRect(x: xa, y: barY, width: max(3, xb - xa), height: barH)
                g.fill(Path(roundedRect: track, cornerRadius: 1), with: .color(FD.track))
                g.fill(Path(roundedRect: CGRect(x: xa, y: barY, width: max(2, track.width * min(1, w.percent / 100)), height: barH), cornerRadius: 1), with: .color(c))
                g.fill(Path(CGRect(x: xb - 1, y: barY - 3, width: 2, height: barH + 6)), with: .color(c))
                let flip = xb + 70 > x1
                let lbl = Text("\(Int(w.percent))% ").font(FD.mono(8.5, .medium)).foregroundColor(FD.ink2) + Text(r.fdDayHour()).font(FD.mono(8.5)).foregroundColor(FD.ink3)
                g.draw(lbl, at: .init(x: flip ? xb - 5 : xb + 5, y: barY + barH / 2), anchor: flip ? .trailing : .leading)
            }
            if let sc = s.limits.first(where: { $0.kind == "weekly_scoped" }), let r = sc.resetsAt {
                let xa = x(r.addingTimeInterval(-span), now: now, w: size.width), xb = x(r, now: now, w: size.width)
                let y = barY + barH + 2
                g.fill(Path(roundedRect: CGRect(x: xa, y: y, width: max(3, xb - xa), height: 3), cornerRadius: 1), with: .color(FD.track))
                g.fill(Path(roundedRect: CGRect(x: xa, y: y, width: max(2, (xb - xa) * min(1, sc.percent / 100)), height: 3), cornerRadius: 1), with: .color(FD.model))
            }
            if let se = s.session, let r = se.resetsAt {
                let xs = x(r, now: now, w: size.width), y = top + 5
                var dm = Path()
                dm.move(to: .init(x: xs, y: y - 3)); dm.addLine(to: .init(x: xs + 3, y: y)); dm.addLine(to: .init(x: xs, y: y + 3)); dm.addLine(to: .init(x: xs - 3, y: y)); dm.closeSubpath()
                g.fill(dm, with: .color(FD.ink))
                g.draw(Text("5H \(r.fdClock())").font(FD.mono(8)).foregroundColor(FD.ink3), at: .init(x: xs + 6, y: y), anchor: .leading)
            }
        }
    }
}
