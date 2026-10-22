import AppKit
import ProperBarCore

enum BarMode: String, Codable, CaseIterable {
    case taskbar, dock
    var label: String { self == .taskbar ? "Barre des tâches" : "Dock" }
}

enum BarPosition: String, Codable, CaseIterable {
    case bottom, top, left, right
    var isHorizontal: Bool { self == .bottom || self == .top }
    var label: String {
        switch self {
        case .bottom: "En bas"
        case .top: "En haut"
        case .left: "À gauche"
        case .right: "À droite"
        }
    }
}

enum BarSize: String, Codable, CaseIterable {
    case small, medium, large, xlarge
    var thickness: CGFloat {
        switch self {
        case .small: 34
        case .medium: 42
        case .large: 52
        case .xlarge: 64
        }
    }
    var icon: CGFloat {
        switch self {
        case .small: 18
        case .medium: 22
        case .large: 30
        case .xlarge: 40
        }
    }
    var label: String {
        switch self {
        case .small: "Petite"
        case .medium: "Moyenne"
        case .large: "Grande"
        case .xlarge: "Très grande"
        }
    }
}

enum ScreenMode: String, Codable, CaseIterable {
    case perScreen, mirror, single
    var label: String {
        switch self {
        case .perScreen: "Une barre par écran, ses fenêtres"
        case .mirror: "Miroir sur tous les écrans"
        case .single: "Un seul écran"
        }
    }
}

enum Theme: String, Codable, CaseIterable {
    case system, light, dark
    var appearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
    var label: String {
        switch self {
        case .system: "Système"
        case .light: "Clair"
        case .dark: "Sombre"
        }
    }
}

extension Grouping {
    var label: String {
        switch self {
        case .automatic: "Automatique"
        case .always: "Toujours"
        case .never: "Jamais"
        }
    }
}

extension AppOrder {
    var label: String {
        switch self {
        case .manual: "Manuel (glisser-déposer)"
        case .launch: "Ordre de lancement"
        case .alphabetical: "Alphabétique"
        }
    }
}

final class Prefs: ObservableObject {
    static let shared = Prefs()

    @Published var mode = load("mode", BarMode.taskbar) { didSet { store("mode", mode) } }
    @Published var position = load("position", BarPosition.bottom) { didSet { store("position", position) } }
    @Published var size = load("size", BarSize.medium) { didSet { store("size", size) } }
    @Published var grouping = load("grouping", Grouping.automatic) { didSet { store("grouping", grouping) } }
    @Published var order = load("order", AppOrder.manual) { didSet { store("order", order) } }
    @Published var iconSize = load("iconSize", 22.0) { didSet { store("iconSize", iconSize) } }
    @Published var tilePadding = load("tilePadding", 8.0) { didSet { store("tilePadding", tilePadding) } }
    @Published var tileSpacing = load("tileSpacing", 2.0) { didSet { store("tileSpacing", tileSpacing) } }
    @Published var launcherSymbol = load("launcherSymbol", "apple.logo") { didSet { store("launcherSymbol", launcherSymbol) } }
    @Published var launcherImagePath = load("launcherImagePath", "") { didSet { store("launcherImagePath", launcherImagePath) } }
    @Published var launcherFollowsIconSize = load("launcherFollowsIconSize", true) {
        didSet { store("launcherFollowsIconSize", launcherFollowsIconSize) }
    }
    @Published var autoHide = load("autoHide", false) { didSet { store("autoHide", autoHide) } }
    @Published var keepWindowsClear = load("keepWindowsClear", true) { didSet { store("keepWindowsClear", keepWindowsClear) } }
    @Published var screenMode = load("screenMode", ScreenMode.perScreen) { didSet { store("screenMode", screenMode) } }
    @Published var singleScreenName = load("singleScreenName", "") { didSet { store("singleScreenName", singleScreenName) } }
    @Published var theme = load("theme", Theme.system) { didSet { store("theme", theme) } }
    @Published var showPreviews = load("showPreviews", true) { didSet { store("showPreviews", showPreviews) } }
    @Published var showBadges = load("showBadges", true) { didSet { store("showBadges", showBadges) } }
    @Published var showFavorites = load("showFavorites", true) { didSet { store("showFavorites", showFavorites) } }
    @Published var showTray = load("showTray", true) { didSet { store("showTray", showTray) } }
    @Published var showClock = load("showClock", true) { didSet { store("showClock", showClock) } }
    @Published var hideSystemDock = load("hideSystemDock", false) {
        didSet {
            store("hideSystemDock", hideSystemDock)
            DockHider.apply(hideSystemDock)
        }
    }
    @Published var pinned = load("pinned", [PinnedApp]()) { didSet { store("pinned", pinned) } }
    @Published var manualOrder = load("manualOrder", [String]()) { didSet { store("manualOrder", manualOrder) } }
    @Published var favorites = load("favorites", [String]()) { didSet { store("favorites", favorites) } }
    @Published var startFolders = load("startFolders", [String]()) { didSet { store("startFolders", startFolders) } }

    var iconSide: CGFloat { min(CGFloat(iconSize), size.thickness - 8) }
    var launcherIconSide: CGFloat { launcherFollowsIconSize ? iconSide : size.icon }

    static let launcherSymbols: [(name: String, symbol: String)] = [
        ("Pomme", "apple.logo"),
        ("Grille", "square.grid.2x2.fill"),
        ("Points", "circle.grid.3x3.fill"),
        ("Commande", "command"),
        ("Étincelles", "sparkles"),
        ("Maison", "house.fill"),
        ("Pile", "square.stack.3d.up.fill"),
        ("Fusée", "paperplane.fill"),
    ]

    var barThickness: CGFloat {
        if position.isHorizontal { return size.thickness }
        return mode == .taskbar ? 150 + size.thickness * 1.5 : size.thickness + 8
    }

    func togglePin(id: String, url: URL) {
        if let i = pinned.firstIndex(where: { $0.id == id }) {
            pinned.remove(at: i)
            return
        }
        pinned.append(PinnedApp(id: id, path: url.path))
        if !manualOrder.contains(id) { manualOrder.append(id) }
    }

    func pin(appAt url: URL) {
        guard let id = Bundle(url: url)?.bundleIdentifier, !pinned.contains(where: { $0.id == id }) else { return }
        togglePin(id: id, url: url)
    }
}

private func load<T: Codable>(_ key: String, _ fallback: T) -> T {
    guard let data = defaults.data(forKey: key),
          let value = try? JSONDecoder().decode(T.self, from: data) else { return fallback }
    return value
}

private func store<T: Codable>(_ key: String, _ value: T) {
    defaults.set(try? JSONEncoder().encode(value), forKey: key)
}

private let defaults = Demo.isOn ? UserDefaults(suiteName: Demo.suite)! : UserDefaults.standard
