import AppKit
import ProperBarCore
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

enum Permissions {
    static var accessibility: Bool { AXIsProcessTrusted() }
    static var screenRecording: Bool { CGPreflightScreenCaptureAccess() }

    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func requestScreenRecording() { CGRequestScreenCaptureAccess() }

    static func openPane(_ anchor: String) {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!)
    }
}

enum DockHider {
    private static let dock = "com.apple.dock" as CFString
    private static let backupKey = "dockBackup"

    // The backup doubles as the "ProperBar has hidden the Dock" flag, so repeated calls are no-ops.
    static func apply(_ hide: Bool) {
        let backup = UserDefaults.standard.dictionary(forKey: backupKey)
        if hide, backup == nil {
            var saved: [String: Any] = ["autohide": value("autohide") as? Bool ?? false]
            if let delay = value("autohide-delay") { saved["delay"] = delay }
            UserDefaults.standard.set(saved, forKey: backupKey)
            set("autohide", true)
            set("autohide-delay", 1000.0)
            restartDock()
        } else if !hide, let backup {
            set("autohide", backup["autohide"] ?? false)
            set("autohide-delay", backup["delay"])
            UserDefaults.standard.removeObject(forKey: backupKey)
            restartDock()
        }
    }

    private static func value(_ key: String) -> Any? {
        CFPreferencesCopyAppValue(key as CFString, dock)
    }

    private static func set(_ key: String, _ value: Any?) {
        CFPreferencesSetAppValue(key as CFString, value.map { $0 as AnyObject }, dock)
        CFPreferencesAppSynchronize(dock)
    }

    private static func restartDock() {
        // launchd respawns the Dock, which then reloads its preferences.
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock") {
            if !app.terminate() { app.forceTerminate() }
        }
    }
}

enum SettingsWindow {
    private static var window: NSWindow?

    static func show() {
        PanelPresenter.shared.dismiss(restoreFocus: false)
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            window.title = "Réglages de ProperBar"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject private var prefs = Prefs.shared
    @State private var accessibility = Permissions.accessibility
    @State private var screenRecording = Permissions.screenRecording
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section("Autorisations") {
                permission("Accessibilité", detail: "Lister et piloter les fenêtres", granted: accessibility) {
                    Permissions.requestAccessibility()
                    Permissions.openPane("Privacy_Accessibility")
                }
                permission("Enregistrement de l'écran", detail: "Aperçus des fenêtres", granted: screenRecording) {
                    Permissions.requestScreenRecording()
                    Permissions.openPane("Privacy_ScreenCapture")
                }
            }

            Section("Barre") {
                picker("Mode", $prefs.mode, BarMode.allCases, \.label)
                picker("Position", $prefs.position, BarPosition.allCases, \.label)
                picker("Hauteur de la barre", $prefs.size, BarSize.allCases, \.label)
                Toggle("Masquer automatiquement", isOn: $prefs.autoHide)
            }

            Section("Tuiles") {
                Picker("Style", selection: Binding(get: { prefs.tileStyle }, set: { prefs.tileStyle = $0 })) {
                    ForEach(TileStyle.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                slider("Taille des icônes", $prefs.iconSize, 14...48)
                slider("Marge autour des icônes", $prefs.tilePadding, 0...20)
                slider("Espacement entre les tuiles", $prefs.tileSpacing, 0...16)
                if prefs.mode == .taskbar {
                    slider("Largeur maximale des tuiles", $prefs.maxTileWidth, 132...360)
                }
                Toggle("Surligner au survol", isOn: $prefs.hoverHighlight)
                Toggle("Agrandir l'icône au survol", isOn: $prefs.hoverZoom)
                    .disabled(prefs.mode != .dock)
                DisclosureGroup("Indicateur et forme") {
                    picker("Indicateur", $prefs.indicatorStyle, IndicatorStyle.allCases, \.label)
                    if prefs.indicatorStyle != .none {
                        slider("Épaisseur", $prefs.indicatorThickness, 1...8)
                        if prefs.indicatorStyle != .dot {
                            slider("Longueur", $prefs.indicatorLength, 0.1...1, unit: "%", scale: 100, step: 0.05)
                        }
                        Toggle("Côté bord de l'écran", isOn: $prefs.indicatorAtEdge)
                    }
                    slider("Arrondi des tuiles", $prefs.tileRadius, 0...14)
                }
            }

            Section("Lanceur") {
                Picker("Icône", selection: $prefs.launcherSymbol) {
                    ForEach(Prefs.launcherSymbols, id: \.symbol) { item in
                        Label(item.name, systemImage: item.symbol).tag(item.symbol)
                    }
                }
                .disabled(!prefs.launcherImagePath.isEmpty)
                LabeledContent("Image personnalisée") {
                    HStack {
                        if !prefs.launcherImagePath.isEmpty {
                            Text(URL(fileURLWithPath: prefs.launcherImagePath).lastPathComponent)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Button("Retirer") { prefs.launcherImagePath = "" }
                        }
                        Button("Choisir…", action: chooseLauncherImage)
                    }
                }
                Toggle("Suivre la taille des icônes", isOn: $prefs.launcherFollowsIconSize)
            }

            Section("Fenêtres") {
                picker("Regroupement", $prefs.grouping, Grouping.allCases, \.label).disabled(prefs.mode == .dock)
                picker("Ordre des apps", $prefs.order, AppOrder.allCases, \.label)
                Toggle("Garder les fenêtres agrandies au-dessus de la barre", isOn: $prefs.keepWindowsClear)
                    .disabled(prefs.autoHide)
                Toggle("Aperçus au survol", isOn: $prefs.showPreviews)
                Toggle("Badges de notification", isOn: $prefs.showBadges)
            }

            Section("Écrans") {
                picker("Affichage", $prefs.screenMode, ScreenMode.allCases, \.label)
                if prefs.screenMode == .single {
                    Picker("Écran", selection: $prefs.singleScreenName) {
                        ForEach(NSScreen.screens.map(\.localizedName), id: \.self) { Text($0).tag($0) }
                    }
                }
            }

            Section("Éléments") {
                Toggle("Favoris (déposez fichiers et dossiers sur le lanceur)", isOn: $prefs.showFavorites)
                Toggle("Icônes système", isOn: $prefs.showTray)
                Toggle("Date et heure", isOn: $prefs.showClock)
                Toggle("Coin « Afficher le bureau » au bout de la barre", isOn: $prefs.showDesktopEdge)
            }

            Section("Apparence") {
                picker("Thème", $prefs.theme, Theme.allCases, \.label)
            }

            Section("Système") {
                Toggle("Masquer le Dock de macOS", isOn: $prefs.hideSystemDock)
                Toggle("Ouvrir ProperBar à l'ouverture de session", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        _ = try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
            }

            Section {
                Text("Maintenez ⌃ pour afficher le CPU et la mémoire de chaque app. Glissez une tuile sur une autre pour réordonner, un fichier sur une tuile pour l'ouvrir avec cette app.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Quitter ProperBar") { NSApp.terminate(nil) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 680)
        .onReceive(ticker) { _ in
            accessibility = Permissions.accessibility
            screenRecording = Permissions.screenRecording
        }
    }

    private func picker<T: Hashable>(_ title: String, _ selection: Binding<T>, _ cases: [T], _ label: KeyPath<T, String>) -> some View {
        Picker(title, selection: selection) {
            ForEach(cases, id: \.self) { Text($0[keyPath: label]).tag($0) }
        }
    }

    private func chooseLauncherImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        prefs.launcherImagePath = url.path
    }

    private func slider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>,
                        unit: String = "pt", scale: Double = 1, step: Double = 1) -> some View {
        LabeledContent(title) {
            HStack {
                Slider(value: value, in: range, step: step).frame(width: 160)
                Text("\(Int((value.wrappedValue * scale).rounded())) \(unit)")
                    .monospacedDigit().foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
            }
        }
    }

    private func permission(_ title: String, detail: String, granted: Bool, request: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(granted ? .green : .orange)
            VStack(alignment: .leading) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted { Button("Autoriser…", action: request) }
        }
    }
}
