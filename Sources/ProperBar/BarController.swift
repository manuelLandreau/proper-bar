import AppKit
import SwiftUI

final class BarPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class BarContext: ObservableObject {
    weak var panel: NSPanel?
    let isPrimary: Bool

    init(panel: NSPanel, isPrimary: Bool) {
        self.panel = panel
        self.isPrimary = isPrimary
    }

    func screenRect(_ global: CGRect) -> CGRect {
        guard let frame = panel?.frame else { return .zero }
        return CGRect(x: frame.minX + global.minX, y: frame.maxY - global.maxY, width: global.width, height: global.height)
    }
}

final class BarController {
    let screen: NSScreen
    private let panel: BarPanel
    private var shown = true
    private var lastInside = Date()
    private var timer: Timer?

    init(screen: NSScreen, showsAllWindows: Bool) {
        self.screen = screen
        panel = BarPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .bar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false

        let root = BarView(screenID: screen.displayID, showsAllWindows: showsAllWindows)
            .environmentObject(BarContext(panel: panel, isPrimary: screen == NSScreen.screens.first))
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        panel.contentView = Chrome.wrap(host, cornerRadius: 0)
        layout()
        panel.orderFrontRegardless()
    }

    func layout() {
        panel.setFrame(targetFrame(), display: true)
        guard Prefs.shared.autoHide else {
            timer?.invalidate()
            timer = nil
            setShown(true)
            return
        }
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func close() {
        timer?.invalidate()
        panel.orderOut(nil)
    }

    var reservedArea: WindowFitter.Area {
        WindowFitter.Area(visible: screen.visibleFrame, bar: targetFrame())
    }

    private func targetFrame() -> CGRect {
        let prefs = Prefs.shared
        let full = screen.frame, visible = screen.visibleFrame
        let thickness = prefs.barThickness
        switch prefs.position {
        case .bottom: return CGRect(x: full.minX, y: visible.minY, width: full.width, height: thickness)
        case .top: return CGRect(x: full.minX, y: visible.maxY - thickness, width: full.width, height: thickness)
        case .left: return CGRect(x: visible.minX, y: visible.minY, width: thickness, height: visible.height)
        case .right: return CGRect(x: visible.maxX - thickness, y: visible.minY, width: thickness, height: visible.height)
        }
    }

    private func tick() {
        let mouse = NSEvent.mouseLocation
        let inside = panel.frame.insetBy(dx: -4, dy: -4).contains(mouse)
            || PreviewController.shared.isVisible || PanelPresenter.shared.isVisible || MenuTracking.isOpen
        if inside { lastInside = Date() }
        if !shown, touchesEdge(mouse) {
            setShown(true)
        } else if shown, !inside, Date().timeIntervalSince(lastInside) > 0.7 {
            setShown(false)
        }
    }

    private func touchesEdge(_ mouse: CGPoint) -> Bool {
        let frame = screen.frame
        guard frame.insetBy(dx: -1, dy: -1).contains(mouse) else { return false }
        switch Prefs.shared.position {
        case .bottom: return mouse.y <= frame.minY + 2
        case .top: return mouse.y >= frame.maxY - 2
        case .left: return mouse.x <= frame.minX + 2
        case .right: return mouse.x >= frame.maxX - 2
        }
    }

    private func setShown(_ value: Bool) {
        guard value != shown else { return }
        shown = value
        panel.ignoresMouseEvents = !value
        panel.fade(to: value ? 1 : 0, duration: 0.18)
    }
}
