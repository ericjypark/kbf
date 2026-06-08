import AppKit

// Headless validation mode: `kbf --debug-dump [AppName]`.
if let i = CommandLine.arguments.firstIndex(of: "--debug-dump") {
    let name = i + 1 < CommandLine.arguments.count ? CommandLine.arguments[i + 1] : nil
    DebugDump.run(appName: name)
    exit(0)
}

// Click-path diagnostics: `kbf --debug-click <App> <index>`.
if let i = CommandLine.arguments.firstIndex(of: "--debug-click") {
    let name = i + 1 < CommandLine.arguments.count ? CommandLine.arguments[i + 1] : nil
    let idx = i + 2 < CommandLine.arguments.count ? Int(CommandLine.arguments[i + 2]) ?? 0 : 0
    DebugClick.run(appName: name, index: idx)
    exit(0)
}

// Preferences design demo: `kbf --demo-prefs`.
if CommandLine.arguments.contains("--demo-prefs") {
    DemoPrefs.run()
    exit(0)
}

// Search-bar design demo: `kbf --demo-search`.
if CommandLine.arguments.contains("--demo-search") {
    DemoSearch.run()
    exit(0)
}

// Pure-logic self-test: `kbf --self-test`.
if CommandLine.arguments.contains("--self-test") {
    exit(SelfTest.run())
}

// Visual overlay demo: `kbf --demo [AppName]` (shows hints for 3s, then exits).
if let i = CommandLine.arguments.firstIndex(of: "--demo") {
    let name = i + 1 < CommandLine.arguments.count ? CommandLine.arguments[i + 1] : nil
    DemoOverlay.run(appName: name)
    exit(0)
}

// Agent app: no Dock icon, lives in the menu bar. Entry point is plain
// top-level code in main.swift (no @main needed).
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
