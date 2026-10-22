import ProperBarCore
import SwiftUI
import UniformTypeIdentifiers

struct BarView: View {
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var prefs = Prefs.shared
    let screenID: CGDirectDisplayID
    let isPrimary: Bool
    let showsAllWindows: Bool

    var body: some View {
        let horizontal = prefs.position.isHorizontal
        let spacing = CGFloat(prefs.tileSpacing)
        let stack = horizontal ? AnyLayout(HStackLayout(spacing: spacing)) : AnyLayout(VStackLayout(spacing: spacing))
        stack {
            StartButton()
            if prefs.showFavorites && !prefs.favorites.isEmpty { FavoritesView() }
            TilesView(apps: visibleApps)
            if prefs.showTray { TrayView() }
            if prefs.showClock { ClockView() }
        }
        .padding(.horizontal, horizontal ? 6 : 4)
        .padding(.vertical, horizontal ? 4 : 6)
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
            guard !app.windows.isEmpty else { return isPrimary || pinned.contains(app.id) ? app : nil }
            var local = app
            local.windows = app.windows.filter(isHere)
            return local.windows.isEmpty && !pinned.contains(app.id) ? nil : local
        }
    }
}

struct StartButton: View {
    @ObservedObject private var prefs = Prefs.shared
    @EnvironmentObject private var bar: BarContext
    @State private var frame = CGRect.zero

    var body: some View {
        let side = min(prefs.size.thickness - 8, prefs.launcherIconSide + CGFloat(prefs.tilePadding))
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
        .frame(width: side, height: prefs.size.thickness - 8)
        .hoverHighlight()
        .globalFrame($frame)
        .onTapGesture(perform: open)
        .onReceive(NotificationCenter.default.publisher(for: .demoPanel)) { note in
            if bar.isPrimary, note.object as? String == "start" { open() }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            loadFileURLs(providers) { urls in
                prefs.favorites += urls.map(\.path).filter { !prefs.favorites.contains($0) }
            }
            return true
        }
        .help("Applications — déposez un fichier ou un dossier ici pour l'ajouter aux favoris")
    }

    private func open() {
        PanelPresenter.shared.toggle("start", anchor: bar.screenRect(frame), key: true) { StartView() }
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
            let dockLength = min(cross, prefs.iconSide + CGFloat(prefs.tilePadding))
            let minLength = horizontal ? (taskbar ? 132 : dockLength) : (taskbar ? prefs.size.thickness - 8 : dockLength)
            let capacity = max(1, Int((length + spacing) / (minLength + spacing)))
            let tiles = makeTiles(apps: apps, pinned: prefs.pinned, grouping: taskbar ? prefs.grouping : .always,
                                  order: prefs.order, manualOrder: prefs.manualOrder, capacity: capacity)
            let fitted = horizontal && taskbar
                ? min(232, max(minLength, (length + spacing) / CGFloat(max(tiles.count, 1)) - spacing))
                : minLength
            let stack = horizontal ? AnyLayout(HStackLayout(spacing: spacing)) : AnyLayout(VStackLayout(spacing: spacing))
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
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(fill))
            .overlay(alignment: indicatorAlignment) { indicator }
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

    private var fontSize: CGFloat { prefs.size == .small ? 11 : 12 }

    private var icon: some View {
        Image(nsImage: Icons.app(tile.bundleURL, pid: tile.pid))
            .resizable()
            .interpolation(.high)
            .frame(width: prefs.iconSide, height: prefs.iconSide)
            .scaleEffect(hovering && prefs.mode == .dock ? 1.1 : 1)
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
        if tile.isActive { return Color.primary.opacity(hovering ? 0.18 : 0.13) }
        return Color.primary.opacity(hovering ? 0.08 : 0)
    }

    private var indicatorAlignment: Alignment {
        switch prefs.position {
        case .bottom: .bottom
        case .top: .top
        case .left: .leading
        case .right: .trailing
        }
    }

    @ViewBuilder private var indicator: some View {
        if tile.isRunning {
            let horizontal = prefs.position.isHorizontal
            let long: CGFloat = tile.isActive ? 16 : 5
            Capsule()
                .fill(tile.isActive ? Color.accentColor : Color.primary.opacity(0.4))
                .frame(width: horizontal ? long : 3, height: horizontal ? 3 : long)
                .padding(1)
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
        PanelPresenter.shared.dismiss()
        if tile.windows.count > 1 {
            PreviewController.shared.show(tile, rect: rect)
            return
        }
        PreviewController.shared.hide()
        if let window = tile.windows.first {
            toggle(window, in: tile)
        } else {
            open(tile)
        }
    }

    static func toggle(_ window: WindowItem, in tile: Tile) {
        let tracker = AppState.shared.tracker
        if tile.isActive && window.isFocused && !window.isMinimized && !tile.isHidden {
            tracker.minimize(window)
        } else {
            tracker.focus(window)
        }
    }

    static func open(_ tile: Tile) {
        if let url = tile.bundleURL {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config)
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
            DispatchQueue.main.async { move(id, before: tile.appID, siblings: siblings) }
        }
        return true
    }

    static func move(_ id: String, before target: String, siblings: [Tile]) {
        guard id != target else { return }
        var ids: [String] = []
        for tile in siblings where !ids.contains(tile.appID) { ids.append(tile.appID) }
        ids.removeAll { $0 == id }
        ids.insert(id, at: ids.firstIndex(of: target) ?? ids.endIndex)
        let prefs = Prefs.shared
        prefs.manualOrder = ids + prefs.manualOrder.filter { !ids.contains($0) }
        prefs.order = .manual
    }
}
