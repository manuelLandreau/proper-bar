import CoreGraphics
import Testing
@testable import ProperBarCore

private let visible = CGRect(x: 0, y: 0, width: 1512, height: 950)

@Test func zoomedWindowStopsJustAboveABottomBar() {
    let bar = CGRect(x: 0, y: 0, width: 1512, height: 42)
    #expect(fittedFrame(visible, visible: visible, bar: bar, edge: .bottom) == CGRect(x: 0, y: 42, width: 1512, height: 908))
}

@Test func leftHalfTiledWindowIsShortenedToo() {
    let bar = CGRect(x: 0, y: 0, width: 1512, height: 42)
    let half = CGRect(x: 0, y: 0, width: 756, height: 950)
    #expect(fittedFrame(half, visible: visible, bar: bar, edge: .bottom) == CGRect(x: 0, y: 42, width: 756, height: 908))
}

@Test func windowDraggedOverTheBarByHandIsLeftAlone() {
    let bar = CGRect(x: 0, y: 0, width: 1512, height: 42)
    #expect(fittedFrame(CGRect(x: 200, y: 20, width: 800, height: 600), visible: visible, bar: bar, edge: .bottom) == nil)
}

@Test func windowAlreadyClearOfTheBarIsLeftAlone() {
    let bar = CGRect(x: 0, y: 0, width: 1512, height: 42)
    #expect(fittedFrame(CGRect(x: 0, y: 42, width: 1512, height: 908), visible: visible, bar: bar, edge: .bottom) == nil)
}

@Test func zoomedWindowStopsJustBelowATopBar() {
    let bar = CGRect(x: 0, y: 908, width: 1512, height: 42)
    #expect(fittedFrame(visible, visible: visible, bar: bar, edge: .top) == CGRect(x: 0, y: 0, width: 1512, height: 908))
}

@Test func zoomedWindowStartsJustRightOfALeftBar() {
    let bar = CGRect(x: 0, y: 0, width: 210, height: 950)
    #expect(fittedFrame(visible, visible: visible, bar: bar, edge: .left) == CGRect(x: 210, y: 0, width: 1302, height: 950))
}
