import AppKit
import ProperBarCore
import ScreenCaptureKit
import SwiftUI

final class PreviewController: ObservableObject {
    static let shared = PreviewController()
    static let card = CGSize(width: 224, height: 160)

    @Published private(set) var windowIDs: [CGWindowID] = []
    @Published private(set) var images: [CGWindowID: NSImage] = [:]

    private let panel: NSPanel
    private var anchor = CGRect.zero
    private var pending: DispatchWorkItem?
    private var overTile = false
    private var overPanel = false
    private var timer: Timer?
    private var generation = 0

    var isVisible: Bool { panel.isVisible && panel.alphaValue > 0 }

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        let host = NSHostingView(rootView: PreviewView(preview: self))
        host.sizingOptions = []
        panel.contentView = Chrome.wrap(host, cornerRadius: 16)
    }

    func hover(_ tile: Tile, rect: CGRect, inside: Bool) {
        overTile = inside
        guard inside else {
            scheduleHide()
            return
        }
        guard Prefs.shared.showPreviews, !tile.windows.isEmpty, !PanelPresenter.shared.isVisible else {
            scheduleHide()
            return
        }
        schedule(after: isVisible ? 0.05 : 0.4) { [weak self] in self?.show(tile, rect: rect) }
    }

    func panelHover(_ inside: Bool) {
        overPanel = inside
        if inside { pending?.cancel() } else { scheduleHide() }
    }

    func show(_ tile: Tile, rect: CGRect) {
        pending?.cancel()
        guard !tile.windows.isEmpty else { return }
        generation += 1
        let ids = tile.windows.map(\.id)
        if ids != windowIDs { images = images.filter { ids.contains($0.key) } }
        windowIDs = ids
        anchor = rect
        relayout(count: ids.count)
        panel.appearance = Prefs.shared.theme.appearance
        if !isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        }
        capture()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.capture() }
    }

    func hide() {
        pending?.cancel()
        timer?.invalidate()
        guard panel.isVisible else { return }
        let generation = generation
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, self.generation == generation else { return }
            self.panel.orderOut(nil)
            self.windowIDs = []
            self.images = [:]
        })
    }

    func relayout(count: Int) {
        guard count > 0 else { return }
        let columns = min(count, 4)
        let rows = (count + 3) / 4
        let size = CGSize(width: CGFloat(columns) * Self.card.width + CGFloat(columns - 1) * 8 + 20,
                          height: CGFloat(rows) * Self.card.height + CGFloat(rows - 1) * 8 + 20)
        panel.setFrame(popupFrame(size: size, anchor: anchor), display: true, animate: false)
    }

    private func schedule(after delay: TimeInterval, _ work: @escaping () -> Void) {
        pending?.cancel()
        let item = DispatchWorkItem(block: work)
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func scheduleHide() {
        schedule(after: 0.25) { [weak self] in
            guard let self, !self.overTile, !self.overPanel else { return }
            self.hide()
        }
    }

    private func capture() {
        let ids = windowIDs
        guard Permissions.screenRecording, !ids.isEmpty else { return }
        let maxSize = CGSize(width: Self.card.width * 2, height: (Self.card.height - 34) * 2)
        Task { [weak self] in
            let images = await WindowCapture.images(for: ids, maxSize: maxSize)
            await MainActor.run {
                guard let self, self.windowIDs == ids else { return }
                self.images.merge(images) { _, new in new }
            }
        }
    }
}

enum WindowCapture {
    static func images(for ids: [CGWindowID], maxSize: CGSize) async -> [CGWindowID: NSImage] {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false) else { return [:] }
        var result: [CGWindowID: NSImage] = [:]
        for window in content.windows where ids.contains(window.windowID) {
            let scale = min(maxSize.width / max(window.frame.width, 1), maxSize.height / max(window.frame.height, 1), 2)
            let config = SCStreamConfiguration()
            config.width = max(1, Int(window.frame.width * scale))
            config.height = max(1, Int(window.frame.height * scale))
            config.showsCursor = false
            config.ignoreShadowsSingleWindow = true
            let filter = SCContentFilter(desktopIndependentWindow: window)
            if let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) {
                result[window.windowID] = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
            }
        }
        return result
    }
}

struct PreviewView: View {
    @ObservedObject var preview: PreviewController
    @ObservedObject private var state = AppState.shared

    var body: some View {
        let all = Dictionary(state.apps.flatMap(\.windows).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let windows = preview.windowIDs.compactMap { all[$0] }
        let columns = Array(repeating: GridItem(.fixed(PreviewController.card.width), spacing: 8), count: max(1, min(windows.count, 4)))
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(windows) { PreviewCard(window: $0) }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(Motion.layout, value: windows.map(\.id))
        .onHover { PreviewController.shared.panelHover($0) }
        .onChange(of: windows.count) { _, count in
            if count == 0 { PreviewController.shared.hide() } else { PreviewController.shared.relayout(count: count) }
        }
    }
}

struct PreviewCard: View {
    let window: WindowItem
    @ObservedObject private var preview = PreviewController.shared
    @State private var hovering = false

    var body: some View {
        let icon = Icons.app(NSRunningApplication(processIdentifier: window.pid)?.bundleURL, pid: window.pid)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                Text(window.title.isEmpty ? (NSRunningApplication(processIdentifier: window.pid)?.localizedName ?? "") : window.title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button { AppState.shared.tracker.close(window) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Color.red.opacity(hovering ? 0.85 : 0)))
                        .foregroundStyle(hovering ? .white : .secondary)
                }
                .buttonStyle(.plain)
                .opacity(hovering ? 1 : 0)
            }
            ZStack {
                if let image = preview.images[window.id] {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
                } else {
                    Image(nsImage: icon).resizable().frame(width: 52, height: 52).opacity(window.isMinimized ? 0.5 : 0.85)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
        }
        .padding(8)
        .frame(width: PreviewController.card.width, height: PreviewController.card.height)
        .hoverHighlight(radius: 10)
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
        .animation(Motion.state, value: preview.images[window.id] != nil)
        .onTapGesture {
            AppState.shared.tracker.focus(window)
            PreviewController.shared.hide()
        }
    }
}
