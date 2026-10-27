import AppKit

// NSWorkspace hands our environment to every app we launch: started from a Claude Code shell, we would mark the
// relaunched terminal, and every claude run in it, as a child session with transcript saving off.
for name in ProcessInfo.processInfo.environment.keys where name.hasPrefix("CLAUDE") { unsetenv(name) }

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
