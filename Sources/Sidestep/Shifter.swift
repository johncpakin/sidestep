import SwiftUI

/// Reports the vertical centre of each account's name line, in the accounts container's space.
struct GateKey: PreferenceKey {
    static var defaultValue: [Int: Anchor<CGPoint>] = [:]
    static func reduce(value: inout [Int: Anchor<CGPoint>], nextValue: () -> [Int: Anchor<CGPoint>]) { value.merge(nextValue()) { $1 } }
}

/// The gear shifter: slot, one gate per account, a metallic knob parked in the active gear.
struct Shifter: View {
    @EnvironmentObject var m: Monitor
    let gates: [Int: CGFloat]              // index → y
    @State private var knobIndex: Int?     // where the knob is while animating
    @State private var dragY: CGFloat?     // while dragging
    @State private var shake: CGFloat = 0
    @State private var animating = false

    private var ys: [CGFloat] { (0..<m.accounts.count).compactMap { gates[$0] } }
    private var restIndex: Int { knobIndex ?? m.activeIndex ?? 0 }

    var body: some View {
        let ys = ys
        ZStack(alignment: .topLeading) {
            if let first = ys.first, let last = ys.last {
                // slot
                RoundedRectangle(cornerRadius: 3).fill(Color.black.opacity(0.45))
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(0.05), lineWidth: 1).offset(y: 1))
                    .shadow(color: .black.opacity(0.9), radius: 1.5, y: 1)
                    .frame(width: 6, height: last - first + 28)
                    .position(x: 19, y: (first + last) / 2)
                // gates
                ForEach(Array(ys.enumerated()), id: \.offset) { i, y in
                    let a = m.accounts[i]
                    let locked = m.isLocked(a)
                    let lit = highlightIndex == i
                    ZStack {
                        if locked {
                            HStack(spacing: 2) { ForEach(0..<4, id: \.self) { _ in Rectangle().fill(FD.warn).frame(width: 2, height: 2) } }
                        } else {
                            RoundedRectangle(cornerRadius: 1).fill(lit ? FD.active : Color.white.opacity(0.25))
                                .frame(width: lit ? 16 : 12, height: 2)
                                .shadow(color: lit ? FD.active.opacity(0.8) : .clear, radius: 3)
                        }
                        Text("\(i + 1)").font(FD.mono(8, .medium)).foregroundStyle(FD.ink4).offset(x: -16)
                    }
                    .frame(width: 22, height: 22).contentShape(Rectangle())
                    .position(x: 19, y: y)
                    .onTapGesture { shift(to: i) }
                    .help(locked ? "Sign in first" : "Switch to \(m.displayName(a))")
                }
                // knob
                knob
                    .position(x: 19, y: dragY ?? ys[min(restIndex, ys.count - 1)])
                    .offset(x: shake)
                    .gesture(drag(ys: ys))
            }
        }
    }

    private var highlightIndex: Int {
        if let d = dragY { return nearest(d, ys) }
        return restIndex
    }

    private var knob: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [Color(hex: 0xe9edf2), Color(hex: 0xaeb7c3), Color(hex: 0x5d6773), Color(hex: 0x3a424c)],
                                         center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 16))
                .overlay(Circle().stroke(Color.black.opacity(0.6), lineWidth: 1))
                .shadow(color: .black.opacity(0.6), radius: 3, y: 3)
            Circle().fill(RadialGradient(colors: [Color(hsl: 25, 95, 70), Color(hsl: 25, 85, 42)], center: UnitPoint(x: 0.4, y: 0.35), startRadius: 0, endRadius: 6))
                .frame(width: 10, height: 10)
                .shadow(color: FD.active.opacity(0.55), radius: 4)
        }
        .frame(width: 28, height: 28)
        .scaleEffect(dragY != nil ? 1.06 : 1)
    }

    private func nearest(_ y: CGFloat, _ ys: [CGFloat]) -> Int {
        var n = 0
        for (i, g) in ys.enumerated() where abs(g - y) < abs(ys[n] - y) { n = i }
        return n
    }

    private func drag(ys: [CGFloat]) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { v in
                guard !animating, let lo = ys.first, let hi = ys.last else { return }
                dragY = min(hi, max(lo, v.location.y))
            }
            .onEnded { v in
                guard let d = dragY else { return }
                let n = nearest(d, ys)
                dragY = nil
                if n == m.activeIndex { return }
                if m.isLocked(m.accounts[n]) { doShake(); return }
                withAnimation(.spring(response: 0.18, dampingFraction: 0.6)) { knobIndex = n }
                Task { await commit(n) }
            }
    }

    private func shift(to target: Int) {
        guard !animating, target != m.activeIndex, target < m.accounts.count else { return }
        if m.isLocked(m.accounts[target]) { doShake(); return }
        animating = true
        let start = m.activeIndex ?? 0
        Task {
            let dir = target > start ? 1 : -1
            var i = start
            while i != target {
                i += dir
                withAnimation(.spring(response: 0.18, dampingFraction: 0.6)) { knobIndex = i }
                try? await Task.sleep(nanoseconds: 170_000_000)
            }
            await commit(target)
            animating = false
        }
    }

    private func commit(_ i: Int) async {
        await m.activate(m.accounts[i])
        knobIndex = nil
    }

    private func doShake() {
        Task {
            for dx in [-3.0, 3.0, -2.0, 2.0, 0.0] {
                withAnimation(.linear(duration: 0.06)) { shake = dx }
                try? await Task.sleep(nanoseconds: 60_000_000)
            }
        }
    }
}
