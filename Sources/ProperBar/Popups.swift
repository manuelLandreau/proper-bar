import AppKit
import SwiftUI

final class PopupPanel: NSPanel {
    var acceptsKey = false
    override var canBecomeKey: Bool { acceptsKey }
}

final class PanelPresenter {
    static let shared = PanelPresenter()

    private(set) var current: String?
    private var panel: PopupPanel?
    private var anchor = CGRect.zero
    private var monitors: [Any] = []
    private var previousApp: NSRunningApplication?

    var isVisible: Bool { panel != nil }

    /// `key: true` activates ProperBar so a text field can take typing; the previous app is re-activated on dismiss.
    func toggle<Content: View>(_ id: String, anchor: CGRect, key: Bool = false, @ViewBuilder content: () -> Content) {
        if current == id {
            dismiss()
            return
        }
        dismiss(animated: false)
        PreviewController.shared.hide()

        let host = NSHostingView(rootView: content())
        let size = host.fittingSize
        let panel = Chrome.floatingPanel(PopupPanel.self, behavior: [.moveToActiveSpace, .ignoresCycle])
        panel.contentView = Chrome.wrap(host, cornerRadius: 16)
        panel.acceptsKey = key

        let target = popupFrame(size: size, anchor: anchor)
        panel.setFrame(target.offsetBy(dx: slide.dx, dy: slide.dy), display: false)
        panel.alphaValue = 0
        if key {
            previousApp = NSWorkspace.shared.frontmostApplication
            NSApp.activate()
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(target, display: true)
        }
        self.panel = panel
        self.anchor = anchor
        current = id

        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            self?.dismiss()
        }) { monitors.append(global) }
        // A click on the popup's own bar button is left to that button, which toggles. A click in another ProperBar
        // window (Settings) must keep ProperBar active, or re-activating the previous app would bury the window just clicked.
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] event in
            guard let self, let window = event.window, window !== self.panel else { return event }
            if !(window is BarPanel) {
                self.dismiss(restoreFocus: false)
            } else if !self.anchor.contains(NSEvent.mouseLocation) {
                self.dismiss()
            }
            return event
        }) { monitors.append(local) }
    }

    func dismiss(animated: Bool = true, restoreFocus: Bool = true) {
        guard let panel else { return }
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        self.panel = nil
        current = nil
        let previous = previousApp
        previousApp = nil
        if animated {
            panel.fade(to: 0, duration: 0.12) { panel.orderOut(nil) }
        } else {
            panel.orderOut(nil)
        }
        if restoreFocus, panel.acceptsKey { previous?.activate() }
    }

    private var slide: CGVector {
        switch Prefs.shared.position {
        case .bottom: CGVector(dx: 0, dy: -10)
        case .top: CGVector(dx: 0, dy: 10)
        case .left: CGVector(dx: -10, dy: 0)
        case .right: CGVector(dx: 10, dy: 0)
        }
    }
}
