import SwiftUI
import AppKit
import Combine

@main
struct SidestepApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    init() { FD.loadFonts() }
    var body: some Scene { Settings { EmptyView() } }
}

/// Status item + a borderless panel we position ourselves, centred under the icon.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let monitor = Monitor()
    private var statusItem: NSStatusItem!
    private var panel: NSPanel!
    private var hosting: NSHostingController<AnyView>!
    private var subs = Set<AnyCancellable>()
    private var clickMonitors: [Any] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let b = statusItem.button {
            b.imagePosition = .imageLeading
            b.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
            b.target = self; b.action = #selector(toggle)
        }
        hosting = NSHostingController(rootView: AnyView(PopoverView().environmentObject(monitor)))
        hosting.sizingOptions = []          // we size the panel ourselves — auto-sizing loops layout in a borderless panel
        panel = KeyablePanel(contentRect: NSRect(x: 0, y: 0, width: 480, height: 400), styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: false)
        // Under-window vibrancy (same material kode-rust uses) with the SwiftUI tint layered on top.
        let fx = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 480, height: 400))
        fx.material = .underWindowBackground
        fx.blendingMode = .behindWindow
        fx.state = .active
        fx.wantsLayer = true
        fx.layer?.cornerRadius = 12
        fx.layer?.masksToBounds = true
        hosting.view.frame = fx.bounds
        hosting.view.autoresizingMask = [.width, .height]
        fx.addSubview(hosting.view)
        panel.contentView = fx
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]

        monitor.objectWillChange.receive(on: RunLoop.main).sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateTitle(); if self?.panel.isVisible == true { self?.syncSize() } }
        }.store(in: &subs)
        updateTitle()
    }

    private func updateTitle() {
        guard let b = statusItem.button else { return }
        b.title = " " + monitor.menuTitle
        b.image = NSImage(systemSymbolName: menuSymbol, accessibilityDescription: "Claude usage")
    }

    private var menuSymbol: String {
        guard let e = monitor.activeEmail, let s = monitor.status[e.lowercased()]?.snapshot, let w = s.worst else { return "gauge.with.dots.needle.0percent" }
        switch w.percent {
        case ..<34: return "gauge.with.dots.needle.33percent"
        case ..<67: return "gauge.with.dots.needle.50percent"
        case ..<90: return "gauge.with.dots.needle.67percent"
        default: return "gauge.with.dots.needle.100percent"
        }
    }

    @objc private func toggle() {
        if panel.isVisible { close() } else { show() }
    }

    private var contentSize = CGSize(width: 480, height: 400)
    private var adjusting = false

    /// Ask SwiftUI for the content's natural height at our fixed width and resize/re-centre the panel.
    private func syncSize() {
        guard !adjusting else { return }
        adjusting = true; defer { adjusting = false }
        let fit = hosting.sizeThatFits(in: NSSize(width: 480, height: 4000))
        let size = CGSize(width: 480, height: fit.height.rounded(.up))
        guard size.height > 0, size != contentSize else { return }
        contentSize = size
        position()
    }

    private func show() {
        syncSize()
        position()
        panel.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { self.syncSize() }   // second pass once fonts/images have laid out
        statusItem.button?.highlight(true)
        // close on any click outside the panel
        let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in self?.close() }
        let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] e in
            guard let self else { return e }
            if e.type == .keyDown, e.keyCode == 53 { self.close(); return nil }          // esc
            if e.window !== self.panel, e.window !== self.statusItem.button?.window { self.close() }
            return e
        }
        clickMonitors = [global as Any, local as Any]
    }

    private func close() {
        panel.orderOut(nil)
        statusItem.button?.highlight(false)
        for m in clickMonitors { NSEvent.removeMonitor(m) }
        clickMonitors = []
    }

    /// Centre the panel under the status item, clamped to the screen's visible frame.
    private func position() {
        guard let button = statusItem.button, let bw = button.window else { return }
        let br = bw.convertToScreen(button.convert(button.bounds, to: nil))
        let size = contentSize
        var x = br.midX - size.width / 2
        let y = br.minY - size.height - 6
        if let screen = bw.screen ?? NSScreen.main {
            let vis = screen.visibleFrame
            x = min(max(x, vis.minX + 8), vis.maxX - size.width - 8)
        }
        let frame = NSRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height)
        if panel.frame != frame { panel.setFrame(frame, display: panel.isVisible) }
    }
}

final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
