import CoreGraphics
import Foundation
import Testing
@testable import ProperBarCore

private func app(_ id: String, pid: pid_t, launched: TimeInterval, windows: [CGWindowID] = [], active: Bool = false, focused: CGWindowID? = nil) -> AppItem {
    AppItem(id: id, pid: pid, name: id.capitalized, launchDate: Date(timeIntervalSince1970: launched), isActive: active,
            windows: windows.map { WindowItem(id: $0, pid: pid, title: "\(id)-\($0)", isFocused: $0 == focused) })
}

private func make(_ apps: [AppItem], pinned: [PinnedApp] = [], grouping: Grouping = .never, order: AppOrder = .launch,
                  manual: [String] = [], capacity: Int = 100) -> [Tile] {
    makeTiles(apps: apps, pinned: pinned, grouping: grouping, order: order, manualOrder: manual, capacity: capacity)
}

private func tiles(_ apps: [AppItem], pinned: [PinnedApp] = [], grouping: Grouping = .never, order: AppOrder = .launch,
                   manual: [String] = [], capacity: Int = 100) -> [String] {
    make(apps, pinned: pinned, grouping: grouping, order: order, manual: manual, capacity: capacity).map(\.id)
}

@Test func neverGroupingGivesOneTilePerWindowAndOneForWindowlessApps() {
    let apps = [app("safari", pid: 1, launched: 1, windows: [12, 10]), app("music", pid: 2, launched: 2)]
    #expect(tiles(apps) == ["w:10", "w:12", "a:music"])
}

@Test func alwaysGroupingGivesOneTilePerApp() {
    let apps = [app("safari", pid: 1, launched: 1, windows: [10, 12]), app("music", pid: 2, launched: 2)]
    let result = make(apps, grouping: .always)
    #expect(result.map(\.id) == ["a:safari", "a:music"])
    #expect(result[0].windows.map(\.id) == [10, 12])
}

@Test func automaticGroupingFoldsBiggestAppsUntilItFits() {
    let apps = [
        app("a", pid: 1, launched: 1, windows: [1, 2]),
        app("b", pid: 2, launched: 2, windows: [3, 4, 5]),
        app("c", pid: 3, launched: 3, windows: [6]),
    ]
    #expect(tiles(apps, grouping: .automatic, capacity: 6) == ["w:1", "w:2", "w:3", "w:4", "w:5", "w:6"])
    #expect(tiles(apps, grouping: .automatic, capacity: 5) == ["w:1", "w:2", "a:b", "w:6"])
    #expect(tiles(apps, grouping: .automatic, capacity: 3) == ["a:a", "a:b", "w:6"])
    #expect(tiles(apps, grouping: .automatic, capacity: 1) == ["a:a", "a:b", "w:6"])
}

@Test func launchOrderPutsPinnedFirstThenRunningByLaunchDate() {
    let apps = [app("late", pid: 1, launched: 9), app("early", pid: 2, launched: 1), app("pinned", pid: 3, launched: 5)]
    let pinned = [PinnedApp(id: "pinned", path: "/Applications/Pinned.app"), PinnedApp(id: "idle", path: "/Applications/Idle.app")]
    #expect(tiles(apps, pinned: pinned) == ["a:pinned", "a:idle", "a:early", "a:late"])
}

@Test func pinnedAppThatIsNotRunningHasNoPid() {
    let result = make([], pinned: [PinnedApp(id: "x", path: "/Applications/Xcode.app")])
    #expect(result.count == 1)
    #expect(result[0].isRunning == false)
    #expect(result[0].isPinned)
    #expect(result[0].name == "Xcode")
}

@Test func alphabeticalOrderIgnoresPinning() {
    let apps = [app("zed", pid: 1, launched: 1), app("arc", pid: 2, launched: 2)]
    let pinned = [PinnedApp(id: "mail", path: "/System/Applications/Mail.app")]
    #expect(tiles(apps, pinned: pinned, order: .alphabetical) == ["a:arc", "a:mail", "a:zed"])
}

@Test func manualOrderFollowsListThenFallsBackToLaunchOrder() {
    let apps = [app("a", pid: 1, launched: 1), app("b", pid: 2, launched: 2), app("c", pid: 3, launched: 3)]
    #expect(tiles(apps, order: .manual, manual: ["c", "a"]) == ["a:c", "a:a", "a:b"])
}

@Test func activeFlagFollowsFocusedWindowOfActiveApp() {
    let apps = [app("a", pid: 1, launched: 1, windows: [1, 2], active: true, focused: 2)]
    let result = make(apps)
    #expect(result.map(\.isActive) == [false, true])
}

@Test func multipleInstancesOfSameAppAreMerged() {
    let apps = [app("term", pid: 1, launched: 1, windows: [5]), app("term", pid: 2, launched: 2, windows: [3])]
    #expect(tiles(apps, grouping: .always) == ["a:term"])
    #expect(tiles(apps) == ["w:3", "w:5"])
}

@Test func draggingRightTakesTheTargetSlot() {
    #expect(reordered(["a", "b", "c", "d"], moving: "a", onto: "c") == ["b", "c", "a", "d"])
}

@Test func draggingLeftTakesTheTargetSlot() {
    #expect(reordered(["a", "b", "c", "d"], moving: "d", onto: "b") == ["a", "d", "b", "c"])
}

@Test func reorderingOntoItselfOrAnUnknownIdChangesNothing() {
    #expect(reordered(["a", "b"], moving: "a", onto: "a") == ["a", "b"])
    #expect(reordered(["a", "b"], moving: "z", onto: "a") == ["a", "b"])
}
