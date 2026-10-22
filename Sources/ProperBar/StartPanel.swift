import AppKit
import SwiftUI

struct CatalogApp: Identifiable, Hashable {
    let url: URL
    let name: String
    var id: String { url.path }
}

enum AppCatalog {
    static func load() -> [CatalogApp] {
        let fm = FileManager.default
        let dirs = Demo.isOn ? ["/System/Applications"] : [
            "/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities",
            NSHomeDirectory() + "/Applications",
        ]
        var seen = Set<String>()
        var apps: [CatalogApp] = []
        for dir in dirs {
            let urls = (try? fm.contentsOfDirectory(at: URL(fileURLWithPath: dir), includingPropertiesForKeys: nil,
                                                    options: [.skipsHiddenFiles])) ?? []
            for url in urls where url.pathExtension == "app" {
                var name = fm.displayName(atPath: url.path)
                if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
                if seen.insert(name).inserted { apps.append(CatalogApp(url: url, name: name)) }
            }
        }
        return apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

enum Power {
    static func lock() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_LAZY),
              let symbol = dlsym(handle, "SACLockScreenImmediate") else { return }
        typealias Lock = @convention(c) () -> Int32
        _ = unsafeBitCast(symbol, to: Lock.self)()
    }

    static func sleep() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["sleepnow"]
        try? process.run()
    }

    // loginwindow's own confirmation dialogs (restart / shut down / log out), same as the Apple menu.
    static func restart() { loginwindow("rrst") }
    static func shutDown() { loginwindow("rsdn") }
    static func logOut() { loginwindow("logo") }

    private static func loginwindow(_ code: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            NSAppleScript(source: "tell application \"loginwindow\" to «event aevt\(code)»")?.executeAndReturnError(nil)
        }
    }
}

struct StartView: View {
    @ObservedObject private var prefs = Prefs.shared
    @State private var query = ""
    @State private var apps = AppCatalog.load()
    @FocusState private var searchFocused: Bool

    private var results: [CatalogApp] {
        guard !query.isEmpty else { return apps }
        let matches = apps.filter { $0.name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        let prefix = matches.filter { $0.name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil }
        return prefix + matches.filter { !prefix.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Rechercher une app", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($searchFocused)
                    .onSubmit { if let first = results.first { launch(first) } }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.07)))

            Text(query.isEmpty ? "Toutes les apps" : "\(results.count) résultat\(results.count > 1 ? "s" : "")")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 6), spacing: 6) {
                    ForEach(Array(results.enumerated()), id: \.element) { index, app in
                        AppCell(app: app, highlighted: !query.isEmpty && index == 0) { launch(app) }
                    }
                }
                .animation(Motion.layout, value: query)
            }
            .scrollIndicators(.never)
            .frame(height: 312)

            if query.isEmpty { folders }

            Divider()
            footer
        }
        .padding(16)
        .frame(width: 540)
        .onAppear { DispatchQueue.main.async { searchFocused = true } }
        .onExitCommand { PanelPresenter.shared.dismiss() }
    }

    private var folders: some View {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let standard = [("Documents", "doc.fill"), ("Downloads", "arrow.down.circle.fill"), ("Desktop", "menubar.dock.rectangle")]
            .map { (home.appendingPathComponent($0.0), $0.1) }
        let custom = prefs.startFolders.map { (URL(fileURLWithPath: $0), "folder.fill") }
        return ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(standard + custom, id: \.0) { url, symbol in
                    FolderChip(url: url, symbol: symbol, removable: prefs.startFolders.contains(url.path))
                }
                Button {
                    addFolder()
                } label: {
                    Image(systemName: "plus").font(.system(size: 11, weight: .semibold)).frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .hoverHighlight(radius: 13)
                .help("Ajouter un dossier")
            }
        }
        .scrollIndicators(.never)
    }

    private var footer: some View {
        HStack(spacing: 4) {
            Image(systemName: "person.crop.circle.fill").font(.system(size: 22)).foregroundStyle(.secondary)
            Text(Demo.isOn ? Demo.userName : NSFullUserName()).font(.system(size: 12, weight: .medium))
            Spacer()
            PowerButton(symbol: "gearshape.fill", label: "Réglages de ProperBar") { SettingsWindow.show() }
            Divider().frame(height: 18).padding(.horizontal, 4)
            PowerButton(symbol: "lock.fill", label: "Verrouiller", action: Power.lock)
            PowerButton(symbol: "moon.zzz.fill", label: "Suspendre", action: Power.sleep)
            PowerButton(symbol: "rectangle.portrait.and.arrow.right", label: "Fermer la session…", action: Power.logOut)
            PowerButton(symbol: "arrow.clockwise", label: "Redémarrer…", action: Power.restart)
            PowerButton(symbol: "power", label: "Éteindre…", action: Power.shutDown)
        }
    }

    private func launch(_ app: CatalogApp) {
        PanelPresenter.shared.dismiss(restoreFocus: false)
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: app.url, configuration: config)
    }

    private func addFolder() {
        PanelPresenter.shared.dismiss(restoreFocus: false)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        NSApp.activate()
        guard panel.runModal() == .OK else { return }
        let prefs = Prefs.shared
        prefs.startFolders += panel.urls.map(\.path).filter { !prefs.startFolders.contains($0) }
    }
}

private struct AppCell: View {
    let app: CatalogApp
    let highlighted: Bool
    let action: () -> Void

    var body: some View {
        VStack(spacing: 5) {
            Image(nsImage: Icons.file(app.url.path)).resizable().interpolation(.high).frame(width: 40, height: 40)
            Text(app.name)
                .font(.system(size: 11))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: 28, alignment: .top)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity)
        .hoverHighlight(active: highlighted, radius: 10)
        .onTapGesture(perform: action)
        .contextMenu {
            Button("Ouvrir", action: action)
            Button(Prefs.shared.pinned.contains { $0.path == app.url.path } ? "Déjà dans la barre" : "Garder dans la barre") {
                Prefs.shared.pin(appAt: app.url)
            }
            Button("Afficher dans le Finder") { NSWorkspace.shared.activateFileViewerSelecting([app.url]) }
        }
    }
}

private struct FolderChip: View {
    let url: URL
    let symbol: String
    let removable: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(Color.accentColor)
            Text(FileManager.default.displayName(atPath: url.path)).font(.system(size: 12))
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
        .hoverHighlight(radius: 13)
        .onTapGesture { FolderMenu(folder: url).popUpAtMouse() }
        .contextMenu {
            Button("Ouvrir dans le Finder") { NSWorkspace.shared.open(url) }
            if removable {
                Button("Retirer") { Prefs.shared.startFolders.removeAll { $0 == url.path } }
            }
        }
    }
}

private struct PowerButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .medium))
            .frame(width: 30, height: 30)
            .hoverHighlight(radius: 15)
            .onTapGesture {
                PanelPresenter.shared.dismiss(restoreFocus: false)
                action()
            }
            .help(label)
    }
}
