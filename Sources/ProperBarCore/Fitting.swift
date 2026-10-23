import CoreGraphics

public enum BarPosition: String, Codable, CaseIterable, Sendable {
    case bottom, top, left, right
    public var isHorizontal: Bool { self == .bottom || self == .top }
}

/// Only a window snapped to the screen edge under the bar is moved; one the user dragged there by hand is left alone.
public func fittedFrame(_ frame: CGRect, visible: CGRect, bar: CGRect, edge: BarPosition) -> CGRect? {
    let tolerance: CGFloat = 4
    guard frame.intersects(bar) else { return nil }
    var target = frame
    switch edge {
    case .bottom:
        guard abs(frame.minY - visible.minY) <= tolerance else { return nil }
        target.origin.y = bar.maxY
        target.size.height = frame.maxY - bar.maxY
    case .top:
        guard abs(frame.maxY - visible.maxY) <= tolerance else { return nil }
        target.size.height = bar.minY - frame.minY
    case .left:
        guard abs(frame.minX - visible.minX) <= tolerance else { return nil }
        target.origin.x = bar.maxX
        target.size.width = frame.maxX - bar.maxX
    case .right:
        guard abs(frame.maxX - visible.maxX) <= tolerance else { return nil }
        target.size.width = bar.minX - frame.minX
    }
    return target.width >= 120 && target.height >= 80 ? target.integral : nil
}
