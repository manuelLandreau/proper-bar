import AppKit
import AudioToolbox
import CoreAudio
import CoreWLAN
import IOKit.ps

struct AudioDevice: Identifiable, Equatable {
    let id: AudioDeviceID
    let name: String
}

struct Battery: Equatable {
    var percent: Int
    var charging: Bool
    var onAC: Bool

    var symbol: String {
        if charging || onAC { return "battery.100percent.bolt" }
        switch percent {
        case 88...: return "battery.100percent"
        case 63...: return "battery.75percent"
        case 38...: return "battery.50percent"
        case 13...: return "battery.25percent"
        default: return "battery.0percent"
        }
    }
}

final class SystemControls: ObservableObject {
    static let shared = SystemControls()

    @Published private(set) var wifiOn = false
    @Published private(set) var wifiName: String?
    @Published private(set) var bluetoothOn: Bool?
    @Published private(set) var darkMode = false
    @Published private(set) var volume: Float = 0
    @Published private(set) var muted = false
    @Published private(set) var brightness: Float?
    @Published private(set) var outputs: [AudioDevice] = []
    @Published private(set) var currentOutput: AudioDeviceID = 0
    @Published private(set) var battery: Battery?
    @Published private(set) var cycleCount: Int?
    @Published private(set) var ejectable: [URL] = []

    private var timer: Timer?
    private var bluetoothWanted = false

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.refresh() }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.refresh() }
        }
    }

    var volumeSymbol: String {
        if muted || volume == 0 { return "speaker.slash.fill" }
        if volume < 0.34 { return "speaker.wave.1.fill" }
        if volume < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    func refresh() {
        let wifi = CWWiFiClient.shared().interface()
        update(\.wifiOn, wifi?.powerOn() ?? false)
        update(\.wifiName, Demo.isOn ? nil : wifi?.ssid())
        readBluetooth()
        update(\.darkMode, UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark")
        update(\.volume, Audio.volume() ?? 0)
        update(\.muted, Audio.isMuted())
        update(\.brightness, Brightness.get())
        update(\.outputs, Audio.devices(input: false))
        update(\.currentOutput, Audio.defaultDevice(input: false))
        update(\.battery, Self.readBattery())
        update(\.ejectable, Self.ejectableVolumes())
        if battery != nil && cycleCount == nil { cycleCount = Self.readCycleCount() }
    }

    func setWiFi(_ on: Bool) {
        try? CWWiFiClient.shared().interface()?.setPower(on)
        wifiOn = on
        refreshSoon()
    }

    // The first Bluetooth call raises a TCC prompt and blocks until it is answered: never at launch, never on main.
    func enableBluetooth() {
        guard !Demo.isOn else {
            bluetoothOn = true
            return
        }
        bluetoothWanted = true
        readBluetooth()
    }

    private func readBluetooth() {
        guard bluetoothWanted else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let on = Bluetooth.isOn
            DispatchQueue.main.async { self?.update(\.bluetoothOn, on) }
        }
    }

    func setBluetooth(_ on: Bool) {
        DispatchQueue.global(qos: .userInitiated).async { Bluetooth.set(on) }
        bluetoothOn = on
        refreshSoon()
    }

    func toggleDarkMode() {
        darkMode.toggle()
        let target = darkMode
        DispatchQueue.global(qos: .userInitiated).async {
            let source = "tell application \"System Events\" to tell appearance preferences to set dark mode to \(target)"
            NSAppleScript(source: source)?.executeAndReturnError(nil)
        }
        refreshSoon()
    }

    func setVolume(_ value: Float) {
        volume = value
        Audio.setVolume(value)
        if muted, value > 0 {
            Audio.setMuted(false)
            muted = false
        }
    }

    func toggleMute() {
        muted.toggle()
        Audio.setMuted(muted)
    }

    func setBrightness(_ value: Float) {
        brightness = value
        Brightness.set(value)
    }

    func setOutput(_ id: AudioDeviceID) {
        Audio.setDefault(id, input: false)
        currentOutput = id
        refreshSoon()
    }

    func ejectAll() {
        for volume in ejectable {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                try? NSWorkspace.shared.unmountAndEjectDevice(at: volume)
                DispatchQueue.main.async { self?.refresh() }
            }
        }
    }

    private func refreshSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.refresh() }
    }

    private func update<T: Equatable>(_ key: ReferenceWritableKeyPath<SystemControls, T>, _ value: T) {
        if self[keyPath: key] != value { self[keyPath: key] = value }
    }

    private static func ejectableVolumes() -> [URL] {
        let keys: [URLResourceKey] = [.volumeIsEjectableKey, .volumeIsRemovableKey, .volumeIsInternalKey]
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return volumes.filter { url in
            guard url.path != "/", let values = try? url.resourceValues(forKeys: Set(keys)) else { return false }
            return values.volumeIsEjectable == true || values.volumeIsRemovable == true || values.volumeIsInternal == false
        }
    }

    private static func readBattery() -> Battery? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = description[kIOPSMaxCapacityKey] as? Int ?? 100
            return Battery(percent: max > 0 ? current * 100 / max : current,
                           charging: description[kIOPSIsChargingKey] as? Bool ?? false,
                           onAC: description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue)
        }
        return nil
    }

    private static func readCycleCount() -> Int? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        return IORegistryEntryCreateCFProperty(service, "CycleCount" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int
    }
}

enum Audio {
    private static let system = AudioObjectID(kAudioObjectSystemObject)

    private static func address(_ selector: AudioObjectPropertySelector,
                                _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func devices(input: Bool) -> [AudioDevice] {
        var addr = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        let scope = input ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput
        return ids.compactMap { id in
            var streams = address(kAudioDevicePropertyStreams, scope)
            var streamsSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &streamsSize) == noErr, streamsSize > 0 else { return nil }
            return AudioDevice(id: id, name: name(of: id))
        }
    }

    private static func name(of id: AudioDeviceID) -> String {
        var addr = address(kAudioObjectPropertyName)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &name) == noErr, let value = name?.takeRetainedValue() else {
            return "Périphérique \(id)"
        }
        return value as String
    }

    static func defaultDevice(input: Bool) -> AudioDeviceID {
        var addr = address(input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &id)
        return id
    }

    static func setDefault(_ id: AudioDeviceID, input: Bool) {
        var addr = address(input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice)
        var device = id
        AudioObjectSetPropertyData(system, &addr, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &device)
    }

    static func volume() -> Float? {
        var addr = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyScopeOutput)
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(defaultDevice(input: false), &addr, 0, nil, &size, &value) == noErr ? value : nil
    }

    static func setVolume(_ value: Float) {
        var addr = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyScopeOutput)
        var volume = Float32(min(max(value, 0), 1))
        AudioObjectSetPropertyData(defaultDevice(input: false), &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &volume)
    }

    static func isMuted() -> Bool {
        var addr = address(kAudioDevicePropertyMute, kAudioDevicePropertyScopeOutput)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(defaultDevice(input: false), &addr, 0, nil, &size, &value) == noErr && value == 1
    }

    static func setMuted(_ muted: Bool) {
        var addr = address(kAudioDevicePropertyMute, kAudioDevicePropertyScopeOutput)
        var value: UInt32 = muted ? 1 : 0
        AudioObjectSetPropertyData(defaultDevice(input: false), &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }
}

// No public API toggles Bluetooth power or reads the built-in display brightness; these private symbols are
// the ones blueutil and MonitorControl rely on, loaded lazily so a future macOS dropping them only hides the control.
enum Bluetooth {
    private typealias Get = @convention(c) () -> Int32
    private typealias Set = @convention(c) (Int32) -> Void
    private static let handle = dlopen("/System/Library/Frameworks/IOBluetooth.framework/IOBluetooth", RTLD_LAZY)
    private static let getter = dlsym(handle, "IOBluetoothPreferenceGetControllerPowerState").map { unsafeBitCast($0, to: Get.self) }
    private static let setter = dlsym(handle, "IOBluetoothPreferenceSetControllerPowerState").map { unsafeBitCast($0, to: Set.self) }

    static var isOn: Bool? { getter.map { $0() == 1 } }
    static func set(_ on: Bool) { setter?(on ? 1 : 0) }
}

enum Brightness {
    private typealias Get = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias Set = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private static let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
    private static let getter = dlsym(handle, "DisplayServicesGetBrightness").map { unsafeBitCast($0, to: Get.self) }
    private static let setter = dlsym(handle, "DisplayServicesSetBrightness").map { unsafeBitCast($0, to: Set.self) }

    private static var builtIn: CGDirectDisplayID? {
        NSScreen.screens.map(\.displayID).first { CGDisplayIsBuiltin($0) != 0 }
    }

    static func get() -> Float? {
        guard let display = builtIn, let getter else { return nil }
        var value: Float = 0
        return getter(display, &value) == 0 ? value : nil
    }

    static func set(_ value: Float) {
        guard let display = builtIn else { return }
        _ = setter?(display, min(max(value, 0), 1))
    }
}
