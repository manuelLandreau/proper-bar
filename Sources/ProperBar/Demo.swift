import AppKit
import ProperBarCore

// `--demo` swaps live windows for fixed sample data so screenshots never leak real window titles.
enum Demo {
    private static let arguments = ProcessInfo.processInfo.arguments
    static let isOn = arguments.contains("--demo")
    // For the functional tests: another app to click into focus, whose one small window covers nothing they look at.
    static let isIdle = arguments.contains("--demo-idle")
    static let suite = "fr.manuellandreau.properbar.demo"

    static func value(_ flag: String) -> String? {
        guard let i = arguments.firstIndex(of: flag), arguments.indices.contains(i + 1) else { return nil }
        return arguments[i + 1]
    }

    static let userName = "Alex Martin"

    static let badges: [String: String] = [
        "/System/Applications/Mail.app": "3",
        "/System/Applications/Messages.app": "12",
    ]

    static var apps: [AppItem] {
        let frame = CGRect(x: 120, y: 160, width: 900, height: 600)
        func app(_ id: String, _ path: String, _ name: String, pid: pid_t, active: Bool = false, _ titles: [String]) -> AppItem {
            let windows = titles.enumerated().map { i, title in
                WindowItem(id: CGWindowID(pid * 10 + Int32(i)), pid: pid, title: title, isFocused: active && i == 0, frame: frame)
            }
            return AppItem(id: id, pid: pid, bundleURL: URL(fileURLWithPath: path), name: name,
                           launchDate: Date(timeIntervalSince1970: TimeInterval(pid)), isActive: active, windows: windows)
        }
        return [
            app("com.apple.finder", "/System/Library/CoreServices/Finder.app", "Finder", pid: 101, ["Téléchargements"]),
            app("com.apple.Safari", "/Applications/Safari.app", "Safari", pid: 102, active: true,
                ["ProperBar — GitHub", "Apple (France)"]),
            app("com.apple.mail", "/System/Applications/Mail.app", "Mail", pid: 103, ["Boîte de réception"]),
            app("com.apple.Notes", "/System/Applications/Notes.app", "Notes", pid: 104, ["Idées de vacances"]),
            app("com.apple.Terminal", "/System/Applications/Utilities/Terminal.app", "Terminal", pid: 105,
                ["~/dev/proper-bar — zsh"]),
            app("com.apple.Music", "/System/Applications/Music.app", "Musique", pid: 106, ["Musique"]),
            app("com.apple.MobileSMS", "/System/Applications/Messages.app", "Messages", pid: 107, []),
        ]
    }

    static func configure(_ prefs: Prefs) {
        prefs.pinned = [
            PinnedApp(id: "com.apple.finder", path: "/System/Library/CoreServices/Finder.app"),
            PinnedApp(id: "com.apple.Safari", path: "/Applications/Safari.app"),
            PinnedApp(id: "com.apple.iCal", path: "/System/Applications/Calendar.app"),
        ]
        prefs.manualOrder = prefs.pinned.map(\.id)
        prefs.favorites = ["/Applications", NSHomeDirectory() + "/Documents"]
        if let mode = value("--demo-mode").flatMap(BarMode.init(rawValue:)) { prefs.mode = mode }
        if let style = value("--demo-style").flatMap(TileStyle.init(rawValue:)) { prefs.tileStyle = style }
    }

    private static var backdrop: NSWindow?
    private static var idleWindow: NSWindow?

    static func startIdle() {
        NSApp.setActivationPolicy(.regular)
        guard let screen = NSScreen.screens.first else { return }
        let window = NSWindow(contentRect: CGRect(x: screen.visibleFrame.minX, y: screen.visibleFrame.maxY - 80, width: 120, height: 80),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "idle"
        window.orderFrontRegardless()
        idleWindow = window
    }

    static func start() {
        guard let screen = NSScreen.screens.first else { return }
        let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = NSWindow.Level(rawValue: NSWindow.Level.bar.rawValue - 1)
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        let gradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.36, green: 0.27, blue: 0.80, alpha: 1),
            NSColor(calibratedRed: 0.13, green: 0.55, blue: 0.85, alpha: 1),
            NSColor(calibratedRed: 0.95, green: 0.55, blue: 0.45, alpha: 1),
        ])!
        let image = NSImage(size: screen.frame.size, flipped: false) { rect in
            gradient.draw(in: rect, angle: 35)
            return true
        }
        let view = NSImageView(image: image)
        view.imageScaling = .scaleAxesIndependently
        window.contentView = view
        window.orderFrontRegardless()
        backdrop = window

        if let panel = value("--demo-panel") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                NotificationCenter.default.post(name: .demoPanel, object: panel)
            }
        }
    }
}

extension Notification.Name {
    static let demoPanel = Notification.Name("properbar.demoPanel")
}
