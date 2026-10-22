import ApplicationServices

// Private but stable since 10.x (used by AltTab, yabai, Rectangle): the only way to map an AX window to the CGWindowID ScreenCaptureKit needs.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

extension AXUIElement {
    private func raw(_ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(self, name as CFString, &value) == .success ? value : nil
    }

    func string(_ name: String) -> String? { raw(name) as? String }
    func bool(_ name: String) -> Bool? { raw(name) as? Bool }
    func url(_ name: String) -> URL? { raw(name) as? URL }
    func elements(_ name: String) -> [AXUIElement] { raw(name) as? [AXUIElement] ?? [] }

    func element(_ name: String) -> AXUIElement? {
        guard let value = raw(name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    func point(_ name: String) -> CGPoint? { axValue(name, .cgPoint, CGPoint.zero) }
    func size(_ name: String) -> CGSize? { axValue(name, .cgSize, CGSize.zero) }

    private func axValue<T>(_ name: String, _ type: AXValueType, _ initial: T) -> T? {
        guard let value = raw(name), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var out = initial
        return AXValueGetValue(value as! AXValue, type, &out) ? out : nil
    }

    var windowID: CGWindowID? {
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(self, &id) == .success && id != 0 ? id : nil
    }

    func set(_ name: String, _ value: Bool) {
        AXUIElementSetAttributeValue(self, name as CFString, value ? kCFBooleanTrue : kCFBooleanFalse)
    }

    func perform(_ action: String) {
        AXUIElementPerformAction(self, action as CFString)
    }
}
