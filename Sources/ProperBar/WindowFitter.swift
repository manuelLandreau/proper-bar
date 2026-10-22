import AppKit
import ProperBarCore

// macOS has no public API to reserve screen space: zoom, Fill and edge tiling size windows to the screen's
// visibleFrame, which only knows about the menu bar and the Dock. We shrink those windows back off the bar.
final class WindowFitter {
    struct Area {
        let visible: CGRect
        let bar: CGRect
        let position: BarPosition
    }

    static let shared = WindowFitter()

    var areas: () -> [Area] = { [] }
    private var attempts: [CGWindowID: CGRect] = [:]

    func fit(_ apps: [AppItem]) {
        let prefs = Prefs.shared
        guard prefs.keepWindowsClear, !prefs.autoHide else { return }
        let areas = areas()
        var live = Set<CGWindowID>()
        for window in apps.flatMap(\.windows) where !window.isMinimized {
            live.insert(window.id)
            let target = areas.lazy
                .compactMap { fittedFrame(window.frame, visible: $0.visible, bar: $0.bar, edge: $0.position.edge) }
                .first
            guard let target else {
                attempts[window.id] = nil
                continue
            }
            // An app that refuses the new size would otherwise be retried on every refresh.
            guard attempts[window.id] != target else { continue }
            attempts[window.id] = target
            AppState.shared.tracker.setFrame(window.id, target)
        }
        attempts = attempts.filter { live.contains($0.key) }
    }
}

extension BarPosition {
    var edge: ScreenEdge {
        switch self {
        case .bottom: .bottom
        case .top: .top
        case .left: .left
        case .right: .right
        }
    }
}
