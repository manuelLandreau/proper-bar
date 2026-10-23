import SwiftUI

struct FavoritesView: View {
    @ObservedObject private var prefs = Prefs.shared
    @State private var targeted = false

    var body: some View {
        let stack = prefs.position.stack(spacing: CGFloat(prefs.tileSpacing))
        stack {
            ForEach(prefs.favorites, id: \.self) { FavoriteItem(path: $0) }
        }
        .frame(minWidth: 6, minHeight: 6)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.accentColor.opacity(targeted ? 0.3 : 0)))
        .animation(Motion.state, value: targeted)
        .animation(Motion.layout, value: prefs.favorites)
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            loadFileURLs(providers) { prefs.favorites.appendUnique(contentsOf: $0.map(\.path)) }
            return true
        }
    }
}

struct FavoriteItem: View {
    let path: String
    @ObservedObject private var prefs = Prefs.shared

    var body: some View {
        let side = prefs.squareSide(icon: prefs.iconSide)
        Image(nsImage: Icons.file(path))
            .resizable()
            .interpolation(.high)
            .frame(width: prefs.iconSide, height: prefs.iconSide)
            .frame(width: side, height: side)
            .hoverHighlight(radius: CGFloat(prefs.tileRadius), enabled: prefs.hoverHighlight)
            .onTapGesture(perform: open)
            .contextMenu {
                Button("Ouvrir") { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
                Button("Afficher dans le Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
                Divider()
                Button("Retirer des favoris") { prefs.favorites.removeAll { $0 == path } }
            }
            .help(FileManager.default.displayName(atPath: path))
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }

    private func open() {
        let url = URL(fileURLWithPath: path)
        if FolderMenu.isBrowsableFolder(url) {
            FolderMenu(folder: url).popUpAtMouse()
        } else {
            NSWorkspace.shared.open(url)
        }
    }
}

final class FolderMenu: NSMenu, NSMenuDelegate {
    let folder: URL

    init(folder: URL) {
        self.folder = folder
        super.init(title: folder.lastPathComponent)
        delegate = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    static func isBrowsableFolder(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        return values?.isDirectory == true && values?.isPackage != true
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        removeAllItems()
        let folder = self.folder
        addItem(ClosureMenuItem("Ouvrir dans le Finder", image: Icons.menu(folder.path)) { NSWorkspace.shared.open(folder) })
        addItem(.separator())
        let items = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey], options: [.skipsHiddenFiles]
        )) ?? []
        let sorted = items.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        for url in sorted.prefix(300) {
            let item = ClosureMenuItem(FileManager.default.displayName(atPath: url.path), image: Icons.menu(url.path)) {
                NSWorkspace.shared.open(url)
            }
            if Self.isBrowsableFolder(url) { item.submenu = FolderMenu(folder: url) }
            addItem(item)
        }
        if items.isEmpty {
            let empty = NSMenuItem(title: "Dossier vide", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            addItem(empty)
        }
    }
}
