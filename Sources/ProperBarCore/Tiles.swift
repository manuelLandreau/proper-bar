import CoreGraphics
import Foundation

public struct WindowItem: Identifiable, Equatable, Sendable {
    public let id: CGWindowID
    public let pid: pid_t
    public var title: String
    public var isMinimized: Bool
    public var isFocused: Bool
    /// Cocoa coordinates (bottom-left origin of the primary screen).
    public var frame: CGRect

    public init(id: CGWindowID, pid: pid_t, title: String, isMinimized: Bool = false, isFocused: Bool = false, frame: CGRect = .zero) {
        self.id = id
        self.pid = pid
        self.title = title
        self.isMinimized = isMinimized
        self.isFocused = isFocused
        self.frame = frame
    }
}

public struct AppItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let pid: pid_t
    public let bundleURL: URL?
    public let name: String
    public let launchDate: Date?
    public var isActive: Bool
    public var isHidden: Bool
    public var isLaunching: Bool
    public var windows: [WindowItem]

    public init(id: String, pid: pid_t, bundleURL: URL? = nil, name: String, launchDate: Date? = nil,
                isActive: Bool = false, isHidden: Bool = false, isLaunching: Bool = false, windows: [WindowItem] = []) {
        self.id = id
        self.pid = pid
        self.bundleURL = bundleURL
        self.name = name
        self.launchDate = launchDate
        self.isActive = isActive
        self.isHidden = isHidden
        self.isLaunching = isLaunching
        self.windows = windows
    }
}

public struct PinnedApp: Codable, Equatable, Sendable {
    public let id: String
    public let path: String

    public init(id: String, path: String) {
        self.id = id
        self.path = path
    }

    public var name: String { appDisplayName(atPath: path) }
}

public func appDisplayName(atPath path: String) -> String {
    let name = FileManager.default.displayName(atPath: path)
    return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
}

public enum Grouping: String, CaseIterable, Codable, Sendable { case automatic, always, never }
public enum AppOrder: String, CaseIterable, Codable, Sendable { case manual, launch, alphabetical }

public struct Tile: Identifiable, Equatable, Sendable {
    public enum Kind: Sendable { case app, window }

    public let id: String
    public let kind: Kind
    public let appID: String
    public let pid: pid_t?
    public let bundleURL: URL?
    public let name: String
    public let windows: [WindowItem]
    public let isPinned: Bool
    public let isActive: Bool
    public let isHidden: Bool
    public let isLaunching: Bool

    public var isRunning: Bool { pid != nil }

    public var title: String {
        if kind == .window, let title = windows.first?.title, !title.isEmpty { return title }
        return name
    }
}

private struct Entry {
    let id: String
    let app: AppItem?
    let pinned: PinnedApp?
    let pinIndex: Int?
    let name: String
    let windows: [WindowItem]

    init(id: String, app: AppItem?, pinned: PinnedApp?, pinIndex: Int?) {
        self.id = id
        self.app = app
        self.pinned = pinned
        self.pinIndex = pinIndex
        name = app?.name ?? pinned?.name ?? id
        // AX returns windows in z-order, which reshuffles on every focus change; window ids grow with creation.
        windows = (app?.windows ?? []).sorted { $0.id < $1.id }
    }

    func grouped() -> [Tile] { [tile(.app, windows: windows, tileID: "a:\(id)")] }

    func ungrouped() -> [Tile] {
        windows.isEmpty ? grouped() : windows.map { tile(.window, windows: [$0], tileID: "w:\($0.id)") }
    }

    private func tile(_ kind: Tile.Kind, windows: [WindowItem], tileID: String) -> Tile {
        let appActive = app?.isActive ?? false
        return Tile(
            id: tileID, kind: kind, appID: id, pid: app?.pid,
            bundleURL: app?.bundleURL ?? pinned.map { URL(fileURLWithPath: $0.path) },
            name: name, windows: windows, isPinned: pinned != nil,
            isActive: kind == .window ? appActive && windows[0].isFocused : appActive,
            isHidden: app?.isHidden ?? false, isLaunching: app?.isLaunching ?? false
        )
    }
}

public func makeTiles(apps: [AppItem], pinned: [PinnedApp], grouping: Grouping, order: AppOrder,
                      manualOrder: [String], capacity: Int) -> [Tile] {
    var entries: [Entry] = []
    var index: [String: Int] = [:]
    for app in apps {
        if let i = index[app.id] {
            if var merged = entries[i].app {
                merged.windows += app.windows
                merged.isActive = merged.isActive || app.isActive
                entries[i] = Entry(id: app.id, app: merged, pinned: entries[i].pinned, pinIndex: entries[i].pinIndex)
            }
            continue
        }
        index[app.id] = entries.count
        let p = pinned.firstIndex { $0.id == app.id }
        entries.append(Entry(id: app.id, app: app, pinned: p.map { pinned[$0] }, pinIndex: p))
    }
    for (i, p) in pinned.enumerated() where index[p.id] == nil {
        index[p.id] = entries.count
        entries.append(Entry(id: p.id, app: nil, pinned: p, pinIndex: i))
    }

    entries = sort(entries, order: order, manualOrder: manualOrder)

    var grouped = Array(repeating: grouping == .always, count: entries.count)
    if grouping == .automatic {
        var total = entries.reduce(0) { $0 + max(1, $1.windows.count) }
        let candidates = entries.indices
            .filter { entries[$0].windows.count > 1 }
            .sorted { (entries[$0].windows.count, $1) > (entries[$1].windows.count, $0) }
        for i in candidates where total > capacity {
            grouped[i] = true
            total -= entries[i].windows.count - 1
        }
    }
    return entries.indices.flatMap { grouped[$0] ? entries[$0].grouped() : entries[$0].ungrouped() }
}

private func sort(_ entries: [Entry], order: AppOrder, manualOrder: [String]) -> [Entry] {
    let indexed = Array(entries.enumerated())
    func launchFirst(_ a: (offset: Int, element: Entry), _ b: (offset: Int, element: Entry)) -> Bool {
        switch (a.element.pinIndex, b.element.pinIndex) {
        case let (x?, y?): return x < y
        case (.some, nil): return true
        case (nil, .some): return false
        default:
            let da = a.element.app?.launchDate ?? .distantFuture
            let db = b.element.app?.launchDate ?? .distantFuture
            return da != db ? da < db : a.offset < b.offset
        }
    }
    let sorted: [(offset: Int, element: Entry)]
    switch order {
    case .launch:
        sorted = indexed.sorted(by: launchFirst)
    case .alphabetical:
        sorted = indexed.sorted {
            let c = $0.element.name.localizedStandardCompare($1.element.name)
            return c == .orderedSame ? $0.offset < $1.offset : c == .orderedAscending
        }
    case .manual:
        let rank = Dictionary(manualOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        sorted = indexed.sorted {
            let ra = rank[$0.element.id] ?? .max, rb = rank[$1.element.id] ?? .max
            return ra != rb ? ra < rb : launchFirst($0, $1)
        }
    }
    return sorted.map(\.element)
}

/// Drag-to-reorder semantics: the dragged item takes the target's slot and everything between shifts by one.
public func reordered(_ ids: [String], moving id: String, onto target: String) -> [String] {
    guard id != target, let from = ids.firstIndex(of: id), let to = ids.firstIndex(of: target) else { return ids }
    var result = ids
    result.remove(at: from)
    result.insert(id, at: to)
    return result
}
