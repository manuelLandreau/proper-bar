import AppKit
import ProperBarCore

struct Activity: Equatable {
    var cpu: Double?
    var memory: UInt64

    var text: String {
        let memory = ByteCountFormatter.string(fromByteCount: Int64(memory), countStyle: .memory)
        guard let cpu else { return memory }
        return String(format: "%.0f %% · %@", cpu, memory)
    }
}

final class AppState: ObservableObject {
    static let shared = AppState()

    @Published private(set) var apps: [AppItem] = []
    @Published private(set) var badges: [String: String] = [:]
    @Published private(set) var activity: [pid_t: Activity] = [:]
    @Published private(set) var showActivity = false

    let tracker = WindowTracker()
    private let sampler = ActivitySampler()
    private let background = DispatchQueue(label: "properbar.background", qos: .utility)
    private var timers: [Timer] = []
    private var lastSample = Date.distantPast

    func start() {
        if Demo.isOn {
            apps = Demo.apps
            badges = Demo.badges
            return
        }
        tracker.onChange = { [weak self] apps in
            guard let self, self.apps != apps else { return }
            self.apps = apps
            WindowFitter.shared.fit(apps)
        }
        tracker.start()
        timers.append(.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refreshBadges() })
        // Polling the modifier state needs no Input Monitoring permission, unlike a global key monitor.
        timers.append(.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in self?.pollControlKey() })
        refreshBadges()
    }

    private func refreshBadges() {
        guard Prefs.shared.showBadges else {
            if !badges.isEmpty { badges = [:] }
            return
        }
        background.async { [weak self] in
            let badges = DockBadges.read()
            DispatchQueue.main.async {
                guard let self, self.badges != badges else { return }
                self.badges = badges
            }
        }
    }

    private func pollControlKey() {
        let down = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask) == .control
        if down != showActivity {
            showActivity = down
            sampler.reset()
            if down { lastSample = .distantPast }
        }
        guard down, Date().timeIntervalSince(lastSample) >= 0.5 else { return }
        lastSample = Date()
        activity = sampler.sample(apps.map(\.pid))
    }
}

final class ActivitySampler {
    private var last: [pid_t: (cpu: UInt64, at: UInt64)] = [:]

    func reset() { last = [:] }

    func sample(_ pids: [pid_t]) -> [pid_t: Activity] {
        let now = mach_absolute_time()
        var result: [pid_t: Activity] = [:]
        for pid in Set(pids) {
            var info = rusage_info_v4()
            let status = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
            }
            guard status == 0 else { continue }
            // ri_*_time is in mach ticks on Apple Silicon, so dividing by elapsed mach ticks needs no timebase conversion.
            let cpu = info.ri_user_time + info.ri_system_time
            var percent: Double?
            if let previous = last[pid], now > previous.at, cpu >= previous.cpu {
                percent = Double(cpu - previous.cpu) / Double(now - previous.at) * 100
            }
            last[pid] = (cpu, now)
            result[pid] = Activity(cpu: percent, memory: info.ri_phys_footprint)
        }
        return result
    }
}

enum DockBadges {
    static func read() -> [String: String] {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return [:] }
        let element = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.5)
        guard let list = element.elements(kAXChildrenAttribute).first(where: { $0.string(kAXRoleAttribute) == kAXListRole }) else {
            return [:]
        }
        var badges: [String: String] = [:]
        for item in list.elements(kAXChildrenAttribute) {
            guard let label = item.string("AXStatusLabel"), !label.isEmpty, let url = item.url(kAXURLAttribute) else { continue }
            badges[url.standardizedFileURL.path] = label
        }
        return badges
    }
}
