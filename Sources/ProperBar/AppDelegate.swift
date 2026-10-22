import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var bars: [BarController] = []
    private var barsKey = ""
    private var prefsObserver: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if Demo.isOn {
            UserDefaults.standard.removePersistentDomain(forName: Demo.suite)
            Demo.configure(Prefs.shared)
        }
        MenuTracking.install()
        WindowFitter.shared.areas = { [weak self] in self?.bars.map(\.reservedArea) ?? [] }
        AppState.shared.start()
        reconcileBars()
        _ = SystemControls.shared
        guard !Demo.isOn else {
            Demo.start()
            return
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.reconcileBars(force: true)
        }
        prefsObserver = Prefs.shared.objectWillChange
            .debounce(for: .milliseconds(30), scheduler: RunLoop.main)
            .sink { [weak self] in self?.reconcileBars() }
        DockHider.apply(Prefs.shared.hideSystemDock)
        if !Permissions.accessibility {
            Permissions.requestAccessibility()
            SettingsWindow.show()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Quitting with the Dock hidden would leave the user with no way to switch apps.
        DockHider.apply(false)
    }

    private func reconcileBars(force: Bool = false) {
        let prefs = Prefs.shared
        let screens: [NSScreen]
        switch prefs.screenMode {
        case .perScreen, .mirror:
            screens = NSScreen.screens
        case .single:
            screens = [NSScreen.screens.first { $0.localizedName == prefs.singleScreenName } ?? NSScreen.screens[0]]
        }
        let key = prefs.screenMode.rawValue + screens.map { "\($0.displayID)" }.joined(separator: ",")
        guard force || key != barsKey else {
            bars.forEach { $0.layout() }
            return
        }
        bars.forEach { $0.close() }
        bars = screens.map { BarController(screen: $0, showsAllWindows: prefs.screenMode != .perScreen) }
        barsKey = key
    }
}
