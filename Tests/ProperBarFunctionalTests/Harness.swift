import AppKit
import ApplicationServices
import Testing

let appBinary = ProcessInfo.processInfo.environment["PROPERBAR_BINARY"]

struct AXElement {
    let ref: AXUIElement

    func value(_ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(ref, name as CFString, &value) == .success ? value : nil
    }

    var children: [AXElement] { (value(kAXChildrenAttribute) as? [AXUIElement] ?? []).map(AXElement.init) }
    var role: String? { value(kAXRoleAttribute) as? String }
    var identifier: String? { value(kAXIdentifierAttribute) as? String }
    var title: String? { value(kAXTitleAttribute) as? String }
    var label: String? { value(kAXDescriptionAttribute) as? String }
    var number: Double? { (value(kAXValueAttribute) as? NSNumber)?.doubleValue }

    /// Global coordinates with a top-left origin, the same space as CGEvent and CGDisplayBounds.
    var frame: CGRect {
        var origin = CGPoint.zero
        var size = CGSize.zero
        if let position = value(kAXPositionAttribute) { AXValueGetValue(position as! AXValue, .cgPoint, &origin) }
        if let extent = value(kAXSizeAttribute) { AXValueGetValue(extent as! AXValue, .cgSize, &size) }
        return CGRect(origin: origin, size: size)
    }

    func perform(_ action: String) {
        AXUIElementPerformAction(ref, action as CFString)
    }

    func all(where match: (AXElement) -> Bool) -> [AXElement] {
        (match(self) ? [self] : []) + children.flatMap { $0.all(where: match) }
    }
}

final class DemoApp {
    private let process = Process()
    let pid: pid_t
    let root: AXElement

    init(_ arguments: [String] = [], idle: Bool = false) async throws {
        try #require(AXIsProcessTrusted(), "grant Accessibility to this terminal in System Settings > Privacy & Security")
        process.executableURL = URL(fileURLWithPath: try #require(appBinary))
        process.arguments = (idle ? ["--demo-idle"] : ["--demo"]) + arguments
        try process.run()
        pid = process.processIdentifier
        root = AXElement(ref: AXUIElementCreateApplication(pid))
        if idle {
            // macOS refuses focus to a process launched in the background, whether it asks or AX does; a real click works.
            let window = try #require(await waitFor { self.window(titled: "idle") }, "the idle window never showed up")
            await click(at: window.frame.center)
            try #require(await eventually { self.isFrontmost }, "the idle app never became frontmost")
        } else {
            try #require(await eventually { self.element("start-button") != nil }, "the bar never showed up")
        }
    }

    deinit {
        process.terminate()
        // waitUntilExit() spins the current run loop, which never sees the exit off the main thread: it can hang forever.
        for _ in 0..<50 where process.isRunning { usleep(100_000) }
    }

    var windows: [AXElement] { (root.value(kAXWindowsAttribute) as? [AXUIElement] ?? []).map(AXElement.init) }

    /// Bars exist on every screen: keep the one on the main display so frames compare against a known screen.
    func element(_ identifier: String) -> AXElement? {
        windows.flatMap { $0.all { $0.identifier == identifier } }.first { mainScreen.contains($0.frame.center) }
    }

    func labeled(_ label: String) -> AXElement? {
        windows.lazy.compactMap { $0.all { $0.label == label }.first }.first
    }

    func window(titled title: String) -> AXElement? {
        windows.first { $0.title == title }
    }

    var hasSearchField: Bool {
        windows.contains { !$0.all { $0.role == kAXTextFieldRole }.isEmpty }
    }

    /// Whether a real click at this point would land in one of our windows rather than another app's.
    func owns(_ point: CGPoint) -> Bool { owner(at: point) == pid }

    /// A point on the window's title bar that a real click would reach. Other apps' windows can sit over it (another
    /// app under development, a maximised Finder), so the window is moved around the main screen until one is free.
    func reachableTitleBar(of window: AXElement) async -> CGPoint? {
        func free() -> CGPoint? {
            let frame = window.frame
            return stride(from: frame.minX + 80, to: frame.maxX - 80, by: 40).lazy
                .map { CGPoint(x: $0, y: frame.minY + 12) }
                .first { self.owns($0) }
        }
        if let point = free() { return point }
        for y in stride(from: mainScreen.minY + 40, to: mainScreen.maxY - 200, by: 80) {
            for x in stride(from: mainScreen.minX, to: mainScreen.maxX - 300, by: 120) {
                var origin = CGPoint(x: x, y: y)
                guard let value = AXValueCreate(.cgPoint, &origin) else { continue }
                AXUIElementSetAttributeValue(window.ref, kAXPositionAttribute as CFString, value)
                try? await Task.sleep(for: .milliseconds(50))
                if let point = free() { return point }
            }
        }
        return nil
    }

    var isFrontmost: Bool { root.value(kAXFrontmostAttribute) as? Bool == true }
}

let mainScreen = CGDisplayBounds(CGMainDisplayID())

func owner(at point: CGPoint) -> pid_t? {
    var hit: AXUIElement?
    var owner: pid_t = 0
    guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &hit) == .success,
          let hit, AXUIElementGetPid(hit, &owner) == .success else { return nil }
    return owner
}

func eventually(timeout: Duration = .seconds(5), _ condition: () -> Bool) async -> Bool {
    await waitFor(timeout: timeout) { condition() ? true : nil } ?? false
}

func waitFor<T>(timeout: Duration = .seconds(5), _ find: () -> T?) async -> T? {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if let found = find() { return found }
        try? await Task.sleep(for: .milliseconds(100))
    }
    return find()
}

/// A real click, for code paths that only react to mouse events (NSEvent monitors) and not to AXPress.
func click(at point: CGPoint) async {
    for type in [CGEventType.leftMouseDown, .leftMouseUp] {
        CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
        try? await Task.sleep(for: .milliseconds(50))
    }
}

extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}
