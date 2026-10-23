import AppKit
import ProperBarCore

final class WindowTracker {
    var onChange: (([AppItem]) -> Void)?

    private static let appNotifications = [
        kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification,
        kAXApplicationHiddenNotification, kAXApplicationShownNotification,
    ]
    private static let windowNotifications = [
        kAXUIElementDestroyedNotification, kAXTitleChangedNotification, kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification, kAXWindowMovedNotification, kAXWindowResizedNotification,
    ]

    private let queue = DispatchQueue(label: "properbar.ax", qos: .userInitiated)
    private let ownPID = ProcessInfo.processInfo.processIdentifier
    private var observers: [pid_t: AXObserver] = [:]
    private var observedWindows: Set<CGWindowID> = []
    private var elements: [CGWindowID: AXUIElement] = [:]
    private var refreshPending = false
    private var trusted = AXIsProcessTrusted()

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        let names = [
            NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didActivateApplicationNotification, NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification,
        ]
        for name in names {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.scheduleRefresh() }
        }
        // AX notifications miss some changes (apps that never post them, windows moved across Spaces).
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.scheduleRefresh() }.tolerance = 0.5
        scheduleRefresh()
    }

    func scheduleRefresh(after delay: TimeInterval = 0.03) {
        guard !refreshPending else { return }
        refreshPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.refresh() }
    }

    func focus(_ window: WindowItem) {
        if let app = NSRunningApplication(processIdentifier: window.pid), app.isHidden { app.unhide() }
        withElement(window.id) { element in
            if element.bool(kAXMinimizedAttribute) == true { element.set(kAXMinimizedAttribute, false) }
            AXUIElementCreateApplication(window.pid).set(kAXFrontmostAttribute, true)
            element.perform(kAXRaiseAction)
            element.set(kAXMainAttribute, true)
        }
    }

    func minimize(_ window: WindowItem) {
        withElement(window.id) { $0.set(kAXMinimizedAttribute, true) }
    }

    func setFrame(_ id: CGWindowID, _ frame: CGRect) {
        let flipped = frame.flippedY(primaryHeight: primaryHeight)
        withElement(id) { element in
            var origin = flipped.origin
            var size = flipped.size
            guard let position = AXValueCreate(.cgPoint, &origin), let extent = AXValueCreate(.cgSize, &size) else { return }
            // Size, move, size again: macOS clamps a resize that would push the window off screen at its old position.
            AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, extent)
            AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, position)
            AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, extent)
        }
    }

    func close(_ window: WindowItem) {
        withElement(window.id) { $0.element(kAXCloseButtonAttribute)?.perform(kAXPressAction) }
    }

    private func withElement(_ id: CGWindowID, _ body: @escaping (AXUIElement) -> Void) {
        queue.async { [weak self] in
            if let element = self?.elements[id] { body(element) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { self?.scheduleRefresh() }
        }
    }

    private func refresh() {
        refreshPending = false
        let nowTrusted = AXIsProcessTrusted()
        if nowTrusted != trusted {
            trusted = nowTrusted
            observers.keys.forEach(unobserve)
            observedWindows = []
        }
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != ownPID
        }
        let live = Set(running.map(\.processIdentifier))
        observers.keys.filter { !live.contains($0) }.forEach(unobserve)
        if trusted { running.forEach(observe) }

        let apps = running.map {
            AppItem(id: $0.bundleIdentifier ?? "pid:\($0.processIdentifier)", pid: $0.processIdentifier, bundleURL: $0.bundleURL,
                    name: $0.localizedName ?? "?", launchDate: $0.launchDate, isActive: $0.isActive,
                    isHidden: $0.isHidden, isLaunching: !$0.isFinishedLaunching)
        }
        let primaryHeight = primaryHeight
        queue.async { [weak self] in
            guard let self else { return }
            let (apps, found) = self.snapshot(apps, primaryHeight: primaryHeight)
            DispatchQueue.main.async {
                self.watch(found)
                self.onChange?(apps)
            }
        }
    }

    private func snapshot(_ apps: [AppItem], primaryHeight: CGFloat) -> ([AppItem], [(CGWindowID, pid_t, AXUIElement)]) {
        var elements: [CGWindowID: AXUIElement] = [:]
        var found: [(CGWindowID, pid_t, AXUIElement)] = []
        let apps = apps.map { app -> AppItem in
            var app = app
            let appElement = AXUIElementCreateApplication(app.pid)
            // A hung app would otherwise block the whole refresh for the default 6 s.
            AXUIElementSetMessagingTimeout(appElement, 0.25)
            let focused = appElement.element(kAXFocusedWindowAttribute)?.windowID
            var windows: [WindowItem] = []
            for window in appElement.elements(kAXWindowsAttribute) {
                guard window.string(kAXSubroleAttribute) == kAXStandardWindowSubrole, let id = window.windowID else { continue }
                let origin = window.point(kAXPositionAttribute) ?? .zero
                let size = window.size(kAXSizeAttribute) ?? .zero
                elements[id] = window
                found.append((id, app.pid, window))
                windows.append(WindowItem(
                    id: id, pid: app.pid, title: window.string(kAXTitleAttribute) ?? "",
                    isMinimized: window.bool(kAXMinimizedAttribute) ?? false, isFocused: id == focused,
                    frame: CGRect(origin: origin, size: size).flippedY(primaryHeight: primaryHeight)
                ))
            }
            app.windows = windows
            return app
        }
        self.elements = elements
        return (apps, found)
    }

    private func observe(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard observers[pid] == nil else { return }
        var created: AXObserver?
        let callback: AXObserverCallback = { _, _, notification, refcon in
            guard let refcon else { return }
            // A drag or a live resize posts these continuously: a full refresh per event would rebuild every bar ~30×/s.
            let continuous = [kAXWindowMovedNotification, kAXWindowResizedNotification].contains(notification as String)
            Unmanaged<WindowTracker>.fromOpaque(refcon).takeUnretainedValue().scheduleRefresh(after: continuous ? 0.25 : 0.03)
        }
        guard AXObserverCreate(pid, callback, &created) == .success, let observer = created else { return }
        let element = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let registered = Self.appNotifications.filter {
            AXObserverAddNotification(observer, element, $0 as CFString, refcon) == .success
        }
        // Apps still launching refuse registration; leave them unobserved so the next refresh retries.
        guard !registered.isEmpty else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        observers[pid] = observer
    }

    private func unobserve(_ pid: pid_t) {
        guard let observer = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }

    private var primaryHeight: CGFloat { NSScreen.screens.first?.frame.maxY ?? 0 }

    private func watch(_ found: [(CGWindowID, pid_t, AXUIElement)]) {
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for (id, pid, element) in found where !observedWindows.contains(id) {
            guard let observer = observers[pid] else { continue }
            observedWindows.insert(id)
            for name in Self.windowNotifications {
                AXObserverAddNotification(observer, element, name as CFString, refcon)
            }
        }
        observedWindows.formIntersection(found.map(\.0))
    }
}
