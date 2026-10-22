import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension NSScreen {
    var displayID: CGDirectDisplayID {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
    }
}

extension NSWindow.Level {
    static let bar = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)))
    // Above the bar, below .popUpMenu: context menus opened over a preview or a popup must stay on top of it.
    static let aboveBar = NSWindow.Level(rawValue: bar.rawValue + 1)
}

extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }
}

extension NSMenu {
    func popUpAtMouse() {
        popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}

final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, image: NSImage? = nil, _ handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
        self.image = image
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func fire() { handler() }
}

enum MenuTracking {
    private(set) static var isOpen = false

    static func install() {
        let center = NotificationCenter.default
        center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { _ in isOpen = true }
        center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { _ in isOpen = false }
    }
}

enum Icons {
    private static var cache: [String: NSImage] = [:]

    static func file(_ path: String) -> NSImage {
        if let icon = cache[path] { return icon }
        let icon = NSWorkspace.shared.icon(forFile: path)
        cache[path] = icon
        return icon
    }

    static func app(_ url: URL?, pid: pid_t? = nil) -> NSImage {
        if let url { return file(url.path) }
        if let pid, let icon = NSRunningApplication(processIdentifier: pid)?.icon { return icon }
        return NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage()
    }

    static func image(_ path: String) -> NSImage? {
        guard !path.isEmpty else { return nil }
        let key = "image:" + path
        if let image = cache[key] { return image }
        guard let image = NSImage(contentsOfFile: path) else { return nil }
        cache[key] = image
        return image
    }

    static func menu(_ path: String) -> NSImage {
        let key = "menu:" + path
        if let icon = cache[key] { return icon }
        let icon = file(path).copy() as! NSImage
        icon.size = NSSize(width: 16, height: 16)
        cache[key] = icon
        return icon
    }
}

enum Chrome {
    static func wrap(_ content: NSView, cornerRadius: CGFloat) -> NSView {
        content.autoresizingMask = [.width, .height]
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = cornerRadius
            glass.contentView = content
            return glass
        }
        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = cornerRadius
        effect.layer?.masksToBounds = true
        content.frame = effect.bounds
        effect.addSubview(content)
        return effect
    }
}

enum Motion {
    static let hover = Animation.easeOut(duration: 0.12)
    static let state = Animation.easeOut(duration: 0.16)
    static let layout = Animation.easeOut(duration: 0.18)
}

struct GlobalFrameReader: ViewModifier {
    @Binding var frame: CGRect

    func body(content: Content) -> some View {
        content.background(GeometryReader { geo in
            Color.clear
                .onAppear { frame = geo.frame(in: .global) }
                .onChange(of: geo.frame(in: .global)) { _, new in frame = new }
        })
    }
}

struct HoverHighlight: ViewModifier {
    var active = false
    var radius: CGFloat = 7
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color.primary.opacity(active ? 0.14 : hovering ? 0.08 : 0)))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .animation(Motion.hover, value: hovering)
            .animation(Motion.state, value: active)
    }
}

extension View {
    func globalFrame(_ frame: Binding<CGRect>) -> some View { modifier(GlobalFrameReader(frame: frame)) }
    func hoverHighlight(active: Bool = false, radius: CGFloat = 7) -> some View { modifier(HoverHighlight(active: active, radius: radius)) }
}

func popupFrame(size: CGSize, anchor: CGRect, gap: CGFloat = 8) -> CGRect {
    let screen = (NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main ?? NSScreen.screens[0]).visibleFrame
    var origin: CGPoint
    switch Prefs.shared.position {
    case .bottom: origin = CGPoint(x: anchor.midX - size.width / 2, y: anchor.maxY + gap)
    case .top: origin = CGPoint(x: anchor.midX - size.width / 2, y: anchor.minY - gap - size.height)
    case .left: origin = CGPoint(x: anchor.maxX + gap, y: anchor.midY - size.height / 2)
    case .right: origin = CGPoint(x: anchor.minX - gap - size.width, y: anchor.midY - size.height / 2)
    }
    origin.x = min(max(origin.x, screen.minX + gap), screen.maxX - size.width - gap)
    origin.y = min(max(origin.y, screen.minY + gap), screen.maxY - size.height - gap)
    return CGRect(origin: origin, size: size)
}

func loadFileURLs(_ providers: [NSItemProvider], _ done: @escaping ([URL]) -> Void) {
    let group = DispatchGroup()
    let lock = NSLock()
    var urls: [URL] = []
    for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
        group.enter()
        _ = provider.loadObject(ofClass: NSURL.self) { object, _ in
            if let url = object as? URL {
                lock.lock()
                urls.append(url)
                lock.unlock()
            }
            group.leave()
        }
    }
    group.notify(queue: .main) {
        if !urls.isEmpty { done(urls) }
    }
}
