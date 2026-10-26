import ProperBarCore
import SwiftUI
import UniformTypeIdentifiers

struct BarView: View {
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var prefs = Prefs.shared
    @EnvironmentObject private var bar: BarContext
    let screenID: CGDirectDisplayID
    let showsAllWindows: Bool

    var body: some View {
        let horizontal = prefs.position.isHorizontal
        let edge = prefs.position.stack(spacing: 0)
        let items = prefs.position.stack(spacing: CGFloat(prefs.tileSpacing))
        edge {
            items {
                StartButton()
                if prefs.showFavorites && !prefs.favorites.isEmpty { FavoritesView() }
                TilesView(apps: visibleApps)
                if prefs.showTray { TrayView() }
                if prefs.showClock { ClockView() }
            }
            .padding(horizontal ? .vertical : .horizontal, Prefs.crossInset)
            .padding(horizontal ? .horizontal : .vertical, 6)
            if prefs.showDesktopEdge { ShowDesktopEdge() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var visibleApps: [AppItem] {
        guard !showsAllWindows, NSScreen.screens.count > 1 else { return state.apps }
        let screens = NSScreen.screens.map { ($0.displayID, $0.frame) }
        let pinned = Set(prefs.pinned.map(\.id))
        func isHere(_ window: WindowItem) -> Bool {
            screens.max { $0.1.intersection(window.frame).area < $1.1.intersection(window.frame).area }?.0 == screenID
        }
        return state.apps.compactMap { app in
            guard !app.windows.isEmpty else { return bar.isPrimary || pinned.contains(app.id) ? app : nil }
            var local = app
            local.windows = app.windows.filter(isHere)
            return local.windows.isEmpty && !pinned.contains(app.id) ? nil : local
        }
    }
}

struct StartButton: View {
    @ObservedObject private var prefs = Prefs.shared

    var body: some View {
        let icon = prefs.launcherIconSide
        Group {
            if let image = Icons.image(prefs.launcherImagePath) {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit).frame(width: icon, height: icon)
            } else {
                Image(systemName: prefs.launcherSymbol)
                    .font(.system(size: icon * 0.8, weight: .semibold))
                    .foregroundStyle(Color.accentColor.gradient)
            }
        }
        .frame(width: prefs.squareSide(icon: icon), height: prefs.tileCross)
        .barPopup("start", key: true) { StartView() }
        .accessibilityIdentifier("start-button")
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            loadFileURLs(providers) { prefs.favorites.appendUnique(contentsOf: $0.map(\.path)) }
            return true
        }
        .help("Applications — déposez un fichier ou un dossier ici pour l'ajouter aux favoris")
    }
}

struct TilesView: View {
    @ObservedObject private var prefs = Prefs.shared
    let apps: [AppItem]

    var body: some View {
        GeometryReader { geo in
            let horizontal = prefs.position.isHorizontal
            let taskbar = prefs.mode == .taskbar
            let spacing = CGFloat(prefs.tileSpacing)
            let length = horizontal ? geo.size.width : geo.size.height
            let cross = horizontal ? geo.size.height : geo.size.width
            let dockLength = prefs.iconSide + CGFloat(prefs.tilePadding)
            let minLength = !taskbar ? dockLength : horizontal ? Prefs.minTaskbarTileWidth : prefs.tileCross
            let capacity = max(1, Int((length + spacing) / (minLength + spacing)))
            let tiles = makeTiles(apps: apps, pinned: prefs.pinned, grouping: taskbar ? prefs.grouping : .always,
                                  order: prefs.order, manualOrder: prefs.manualOrder, capacity: capacity)
            let fitted = horizontal && taskbar
                ? min(max(CGFloat(prefs.maxTileWidth), minLength), max(minLength, (length + spacing) / CGFloat(max(tiles.count, 1)) - spacing))
                : minLength
            let stack = prefs.position.stack(spacing: spacing)
            ScrollView(horizontal ? .horizontal : .vertical) {
                stack {
                    ForEach(tiles) { tile in
                        TileView(tile: tile, siblings: tiles)
                            .frame(width: horizontal ? fitted : cross, height: horizontal ? cross : fitted)
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                }
                .animation(Motion.layout, value: tiles.map(\.id))
                .animation(Motion.layout, value: fitted)
            }
            .scrollIndicators(.never)
            .frame(width: geo.size.width, height: geo.size.height, alignment: horizontal ? .leading : .top)
        }
    }
}

struct TileView: View {
    let tile: Tile
    let siblings: [Tile]
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var prefs = Prefs.shared
    @EnvironmentObject private var bar: BarContext
    @State private var hovering = false
    @State private var dropping = false
    @State private var frame = CGRect.zero

    private var dimmed: Bool { tile.isHidden || (tile.kind == .window && tile.windows.first?.isMinimized == true) }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: prefs.mode == .taskbar ? .leading : .center)
            .background(RoundedRectangle(cornerRadius: CGFloat(prefs.tileRadius), style: .continuous).fill(fill))
            .overlay {
                if tile.isRunning && prefs.indicatorStyle != .none {
                    TileIndicator(isActive: tile.isActive, hovering: hovering)
                }
            }
            .contentShape(Rectangle())
            .opacity(tile.isLaunching ? 0.5 : 1)
            .animation(Motion.hover, value: hovering)
            .animation(Motion.state, value: tile.isActive)
            .animation(Motion.state, value: dropping)
            .globalFrame($frame)
            .onHover { inside in
                hovering = inside
                PreviewController.shared.hover(tile, rect: bar.screenRect(frame), inside: inside)
            }
            .onTapGesture { TileActions.click(tile, rect: bar.screenRect(frame)) }
            .contextMenu { TileMenu(tile: tile) }
            .onDrag { NSItemProvider(object: (TileActions.dragPrefix + tile.appID) as NSString) }
            .onDrop(of: [.fileURL, .utf8PlainText], isTargeted: $dropping) { TileActions.drop($0, on: tile, siblings: siblings) }
            .help(tile.windows.isEmpty || !prefs.showPreviews ? tile.title : "")
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("tile")
    }

    @ViewBuilder private var content: some View {
        if prefs.mode == .taskbar {
            HStack(spacing: 7) {
                icon
                VStack(alignment: .leading, spacing: 0) {
                    Text(tile.title)
                        .font(.system(size: fontSize, weight: tile.isActive ? .medium : .regular))
                        .lineLimit(1)
                    if let activity {
                        Text(activity).font(.system(size: fontSize - 2)).monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .foregroundStyle(dimmed ? .secondary : .primary)
                Spacer(minLength: 0)
                if tile.kind == .app && tile.windows.count > 1 {
                    Text("\(tile.windows.count)")
                        .font(.system(size: 10, weight: .semibold))
                        .monospacedDigit()
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.primary.opacity(0.12)))
                }
            }
            .padding(.horizontal, CGFloat(prefs.tilePadding))
        } else {
            icon.overlay(alignment: .bottom) {
                if let activity {
                    Text(activity).font(.system(size: 8)).monospacedDigit().padding(.horizontal, 3)
                        .background(.ultraThinMaterial, in: Capsule()).fixedSize().offset(y: 6)
                }
            }
        }
    }

    private var fontSize: CGFloat { prefs.isCompact ? 11 : 12 }

    private var icon: some View {
        Image(nsImage: Icons.app(tile.bundleURL, pid: tile.pid))
            .resizable()
            .interpolation(.high)
            .frame(width: prefs.iconSide, height: prefs.iconSide)
            .scaleEffect(hovering && prefs.mode == .dock && prefs.hoverZoom ? 1.1 : 1)
            .overlay(alignment: .topTrailing) {
                if let badge { BadgeView(text: badge).offset(x: 7, y: -5) }
            }
            .opacity(dimmed ? 0.6 : 1)
    }

    private var badge: String? {
        guard prefs.showBadges, let url = tile.bundleURL else { return nil }
        return state.badges[url.standardizedFileURL.path]
    }

    private var activity: String? {
        guard state.showActivity, let pid = tile.pid else { return nil }
        return state.activity[pid]?.text
    }

    private var fill: Color {
        if dropping { return Color.accentColor.opacity(0.35) }
        let hover = hovering && prefs.hoverHighlight
        if tile.isActive { return Color.primary.opacity(hover ? 0.18 : 0.13) }
        return Color.primary.opacity(hover ? 0.08 : 0)
    }
}

struct TileIndicator: View {
    let isActive: Bool
    let hovering: Bool
    @ObservedObject private var prefs = Prefs.shared

    var body: some View {
        GeometryReader { geo in
            let horizontal = prefs.position.isHorizontal
            let cell = horizontal ? geo.size.width : geo.size.height
            let thickness = CGFloat(prefs.indicatorThickness)
            let along = length(cell: cell, thickness: thickness)
            let across = prefs.indicatorStyle == .dot ? along : thickness
            shape
                .fill(color)
                .frame(width: horizontal ? along : across, height: horizontal ? across : along)
                .padding(prefs.indicatorStyle == .line ? 0 : 1)
                .frame(width: geo.size.width, height: geo.size.height, alignment: alignment)
        }
        .allowsHitTesting(false)
        .animation(Motion.state, value: isActive)
    }

    private func length(cell: CGFloat, thickness: CGFloat) -> CGFloat {
        let fraction = CGFloat(prefs.indicatorLength)
        switch prefs.indicatorStyle {
        case .pill: return isActive ? max(thickness * 2, cell * fraction) : max(thickness * 1.7, cell * fraction * 0.3)
        case .line: return cell * fraction
        case .dot: return thickness * 1.6
        case .none: return 0
        }
    }

    private var shape: AnyShape {
        prefs.indicatorStyle == .line ? AnyShape(Rectangle()) : AnyShape(Capsule())
    }

    private var color: Color {
        if isActive { return .accentColor }
        if prefs.indicatorStyle == .line { return Color.primary.opacity(hovering ? 0.55 : 0.3) }
        return Color.primary.opacity(0.4)
    }

    private var alignment: Alignment {
        let edge = prefs.indicatorAtEdge
        switch prefs.position {
        case .bottom: return edge ? .bottom : .top
        case .top: return edge ? .top : .bottom
        case .left: return edge ? .leading : .trailing
        case .right: return edge ? .trailing : .leading
        }
    }
}

struct BadgeView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 4)
            .frame(minWidth: 15, minHeight: 15)
            .background(Capsule().fill(Color.red))
            .fixedSize()
    }
}

struct TileMenu: View {
    let tile: Tile

    var body: some View {
        let tracker = AppState.shared.tracker
        if tile.kind == .window, let window = tile.windows.first {
            Button(window.isMinimized ? "Restaurer" : "Réduire") {
                window.isMinimized ? tracker.focus(window) : tracker.minimize(window)
            }
            Button("Fermer la fenêtre") { tracker.close(window) }
            Divider()
        } else if tile.windows.count > 1 {
            ForEach(tile.windows) { window in
                Button(window.title.isEmpty ? tile.name : window.title) { tracker.focus(window) }
            }
            Divider()
            Button("Fermer toutes les fenêtres") { tile.windows.forEach(tracker.close) }
            Divider()
        }
        if let url = tile.bundleURL {
            Button(tile.isPinned ? "Retirer de la barre" : "Garder dans la barre") {
                Prefs.shared.togglePin(id: tile.appID, url: url)
            }
            Button("Afficher dans le Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
        if let pid = tile.pid, let app = NSRunningApplication(processIdentifier: pid) {
            Button(app.isHidden ? "Afficher" : "Masquer") { _ = app.isHidden ? app.unhide() : app.hide() }
            Divider()
            Button("Quitter") { app.terminate() }
            Button("Forcer à quitter") { app.forceTerminate() }
        } else {
            Button("Ouvrir") { TileActions.open(tile) }
        }
    }
}

enum TileActions {
    static let dragPrefix = "properbar-tile:"

    static func click(_ tile: Tile, rect: CGRect) {
        let grouped = tile.windows.count > 1
        let mode = Prefs.shared.groupClick
        if grouped && mode == .windows {
            PreviewController.shared.show(tile, rect: rect)
            return
        }
        PreviewController.shared.hide()
        if grouped {
            // A Dock click is a reopen: the app comes forward and restores a window if all are minimized.
            mode == .plasma ? cycle(tile) : open(tile)
        } else if let window = tile.windows.first {
            toggle(window, active: tile.isActive, hidden: tile.isHidden)
        } else {
            open(tile)
        }
    }

    static func cycle(_ tile: Tile) {
        let focused = tile.windows.first { $0.isFocused && !$0.isMinimized }
        let next = tile.isActive && !tile.isHidden ? tile.window(cycling: 1, from: focused?.id) : tile.recentWindow
        if let next { AppState.shared.tracker.focus(next) }
    }

    static func toggle(_ window: WindowItem, active: Bool, hidden: Bool) {
        let tracker = AppState.shared.tracker
        if active && window.isFocused && !window.isMinimized && !hidden && tracker.isInPlace(window) {
            tracker.minimize(window)
        } else {
            tracker.focus(window)
        }
    }

    static func open(_ tile: Tile) {
        if let url = tile.bundleURL {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        } else if let pid = tile.pid {
            NSRunningApplication(processIdentifier: pid)?.activate()
        }
    }

    static func drop(_ providers: [NSItemProvider], on tile: Tile, siblings: [Tile]) -> Bool {
        if providers.contains(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) {
            guard let app = tile.bundleURL else { return false }
            loadFileURLs(providers) { urls in
                NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
            }
            return true
        }
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let text = object as? String, text.hasPrefix(dragPrefix) else { return }
            let id = String(text.dropFirst(dragPrefix.count))
            DispatchQueue.main.async { move(id, onto: tile.appID, siblings: siblings) }
        }
        return true
    }

    static func move(_ id: String, onto target: String, siblings: [Tile]) {
        var ids: [String] = []
        for tile in siblings where !ids.contains(tile.appID) { ids.append(tile.appID) }
        let order = reordered(ids, moving: id, onto: target)
        guard order != ids else { return }
        let prefs = Prefs.shared
        prefs.manualOrder = order + prefs.manualOrder.filter { !order.contains($0) }
        prefs.pinned.sort { (order.firstIndex(of: $0.id) ?? .max) < (order.firstIndex(of: $1.id) ?? .max) }
        prefs.order = .manual
    }
}

// Sits outside the bar padding so it reaches the screen corner, like the Windows "show desktop" sliver.
struct ShowDesktopEdge: View {
    @ObservedObject private var prefs = Prefs.shared

    var body: some View {
        let horizontal = prefs.position.isHorizontal
        // A tap gesture, not a Button: the bar panel never becomes key, like the tiles that also use onTapGesture.
        Color.clear
            .frame(width: horizontal ? 8 : nil, height: horizontal ? nil : 8)
            .hoverHighlight(radius: 0)
            .onTapGesture(perform: Desktop.toggle)
            .help("Afficher le bureau")
            .accessibilityElement()
            .accessibilityLabel("Afficher le bureau")
            .accessibilityIdentifier("show-desktop")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { Desktop.toggle() }
    }
}

// Private Dock call: NSRunningApplication.hide() is refused on the frontmost app when another process asks.
enum Desktop {
    private typealias SendNotification = @convention(c) (CFString, Int32) -> Void
    private static let send: SendNotification? = {
        let handle = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_LAZY)
        return dlsym(handle, "CoreDockSendNotification").map { unsafeBitCast($0, to: SendNotification.self) }
    }()

    static func toggle() {
        PreviewController.shared.hide()
        send?("com.apple.showdesktop.awake" as CFString, 0)
    }
}
