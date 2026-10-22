import SwiftUI

struct TrayView: View {
    @ObservedObject private var sys = SystemControls.shared
    @ObservedObject private var prefs = Prefs.shared
    @EnvironmentObject private var bar: BarContext
    @State private var frame = CGRect.zero

    var body: some View {
        let horizontal = prefs.position.isHorizontal
        let stack = horizontal ? AnyLayout(HStackLayout(spacing: 11)) : AnyLayout(VStackLayout(spacing: 10))
        stack {
            if !sys.ejectable.isEmpty { Image(systemName: "eject.fill") }
            Image(systemName: sys.wifiOn ? "wifi" : "wifi.slash")
            Image(systemName: sys.volumeSymbol).frame(width: 18)
            if let battery = sys.battery {
                HStack(spacing: 3) {
                    Image(systemName: battery.symbol)
                    if horizontal { Text("\(battery.percent) %").font(.system(size: 11)).monospacedDigit() }
                }
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, horizontal ? 10 : 0)
        .padding(.vertical, horizontal ? 0 : 10)
        .frame(maxWidth: horizontal ? nil : .infinity, maxHeight: horizontal ? .infinity : nil)
        .hoverHighlight()
        .globalFrame($frame)
        .onTapGesture(perform: open)
        .onReceive(NotificationCenter.default.publisher(for: .demoPanel)) { note in
            if bar.isPrimary, note.object as? String == "control" { open() }
        }
    }

    private func open() {
        PanelPresenter.shared.toggle("control", anchor: bar.screenRect(frame)) { ControlCenterView() }
    }
}

struct ControlCenterView: View {
    @ObservedObject private var sys = SystemControls.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                QuickToggle(symbol: sys.wifiOn ? "wifi" : "wifi.slash", title: "Wi-Fi",
                            subtitle: sys.wifiOn ? (sys.wifiName ?? "Activé") : "Désactivé", isOn: sys.wifiOn) {
                    sys.setWiFi(!sys.wifiOn)
                }
                if let bluetooth = sys.bluetoothOn {
                    QuickToggle(symbol: "antenna.radiowaves.left.and.right", title: "Bluetooth",
                                subtitle: bluetooth ? "Activé" : "Désactivé", isOn: bluetooth) {
                        sys.setBluetooth(!bluetooth)
                    }
                }
                QuickToggle(symbol: "circle.lefthalf.filled", title: "Mode sombre",
                            subtitle: sys.darkMode ? "Activé" : "Désactivé", isOn: sys.darkMode) {
                    sys.toggleDarkMode()
                }
            }

            VStack(spacing: 10) {
                SliderRow(symbol: sys.volumeSymbol, value: Binding(get: { sys.muted ? 0 : sys.volume }, set: { sys.setVolume($0) }),
                          onSymbolTap: { sys.toggleMute() })
                if let brightness = sys.brightness {
                    SliderRow(symbol: "sun.max.fill", value: Binding(get: { brightness }, set: { sys.setBrightness($0) }))
                }
            }

            Menu {
                ForEach(sys.outputs) { device in
                    Button {
                        sys.setOutput(device.id)
                    } label: {
                        if device.id == sys.currentOutput {
                            Label(device.name, systemImage: "checkmark")
                        } else {
                            Text(device.name)
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "hifispeaker.fill").foregroundStyle(.secondary)
                    Text(sys.outputs.first { $0.id == sys.currentOutput }?.name ?? "Sortie audio").lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 9)).foregroundStyle(.secondary)
                }
                .font(.system(size: 12))
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.06)))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)

            HStack(spacing: 10) {
                if let battery = sys.battery {
                    Image(systemName: battery.symbol).foregroundStyle(battery.percent <= 15 && !battery.onAC ? .red : .primary)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(battery.percent) %").font(.system(size: 12, weight: .medium)).monospacedDigit()
                        Text(batteryDetail(battery)).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if !sys.ejectable.isEmpty {
                    PillButton(symbol: "eject.fill", title: sys.ejectable.count > 1 ? "Éjecter \(sys.ejectable.count) disques" : "Éjecter") {
                        sys.ejectAll()
                    }
                }
                PillButton(symbol: "gearshape.fill", title: nil) {
                    PanelPresenter.shared.dismiss(restoreFocus: false)
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
                }
                .help("Réglages Système")
            }
        }
        .padding(16)
        .frame(width: 360)
        .onAppear { sys.enableBluetooth() }
        .animation(Motion.state, value: sys.wifiOn)
        .animation(Motion.state, value: sys.bluetoothOn)
        .animation(Motion.state, value: sys.darkMode)
    }

    private func batteryDetail(_ battery: Battery) -> String {
        let state = battery.charging ? "En charge" : battery.onAC ? "Sur secteur" : "Sur batterie"
        guard let cycles = sys.cycleCount else { return state }
        return "\(state) · \(cycles) cycles"
    }
}

private struct QuickToggle: View {
    let symbol: String
    let title: String
    let subtitle: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isOn ? .white : .primary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(isOn ? Color.accentColor : Color.primary.opacity(0.1)))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.06)))
        .hoverHighlight(radius: 12)
        .onTapGesture(perform: action)
    }
}

private struct SliderRow: View {
    let symbol: String
    @Binding var value: Float
    var onSymbolTap: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .frame(width: 26, height: 26)
                .hoverHighlight(radius: 13)
                .onTapGesture { onSymbolTap?() }
            Slider(value: $value, in: 0...1)
                .controlSize(.small)
        }
    }
}

private struct PillButton: View {
    let symbol: String
    let title: String?
    let action: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 11))
            if let title { Text(title).font(.system(size: 11, weight: .medium)) }
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(Capsule().fill(Color.primary.opacity(0.07)))
        .hoverHighlight(radius: 13)
        .onTapGesture(perform: action)
    }
}
