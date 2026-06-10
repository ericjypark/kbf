import AppKit
import SwiftUI

struct PreferencesView: View {
    @ObservedObject private var settings = AppSettings.shared
    private let accent = Color(red: 0.388, green: 0.400, blue: 0.945)

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    section("SHORTCUTS") {
                        shortcutRow("Click mode", "Label every clickable element", $settings.clickHotkey)
                        divider
                        shortcutRow("Scroll mode", "i/k/j/l · ⇧ dash · Tab/1–9 switch area", $settings.scrollHotkey)
                        divider
                        shortcutRow("Search mode", "Find an element by its text", $settings.searchHotkey)
                    }
                    section("CLICKING") {
                        HStack {
                            label("Hint characters", "Letters used to build labels, in order")
                            Spacer()
                            TextField("", text: $settings.alphabet)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12, design: .monospaced))
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(.white.opacity(0.85))
                                .frame(width: 190)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        divider
                        pickerRow("Label theme", "Hint pill appearance") {
                            Picker("", selection: $settings.labelTheme) {
                                ForEach(LabelTheme.allCases, id: \.self) { Text($0.displayName).tag($0) }
                            }
                        }
                        divider
                        pickerRow("Label size", "Hint text size") {
                            Picker("", selection: $settings.hintScale) {
                                ForEach(HintScale.allCases, id: \.self) { Text($0.displayName).tag($0) }
                            }
                        }
                        divider
                        toggleRow("Click sound", "Audible tick on every click", $settings.clickSound)
                    }
                    section("SCROLLING") {
                        sliderRow("Scroll speed", "Pixels per key press", $settings.scrollStep, range: 30...240)
                        divider
                        sliderRow("Dash speed", "Pixels per ⇧-dash press", $settings.scrollDash, range: 120...900)
                    }
                    section("EXCLUDED APPS") {
                        if settings.excludedApps.isEmpty {
                            Text("kbf is active everywhere. Add apps to disable it in them.")
                                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.35))
                                .padding(.horizontal, 14).padding(.vertical, 10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        ForEach(settings.excludedApps, id: \.self) { id in
                            HStack {
                                label(appName(for: id), id)
                                Spacer()
                                Button {
                                    settings.excludedApps.removeAll { $0 == id }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.white.opacity(0.4))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            divider
                        }
                        addExcludedAppMenu
                    }
                    section("GENERAL") {
                        toggleRow("Launch at login", "Start kbf automatically", $settings.launchAtLogin)
                    }
                    Text("kbf · open-source keyboard-first control")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.25))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 2)
                }
            }
        }
        .padding(28)
        .frame(width: 520, height: 640)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 13) {
            Image(systemName: "keyboard.fill").font(.system(size: 24)).foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 1) {
                Text("Preferences").font(.system(size: 20, weight: .semibold))
                Text("\(settings.clickHotkey.display) click · \(settings.scrollHotkey.display) scroll · \(settings.searchHotkey.display) search")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.35)).tracking(0.6)
            VStack(spacing: 0) { content() }
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.07)))
        }
    }

    private func shortcutRow(_ title: String, _ subtitle: String, _ binding: Binding<Hotkey>) -> some View {
        HStack {
            label(title, subtitle)
            Spacer()
            HotkeyRecorder(hotkey: binding).frame(width: 124, height: 28)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private func toggleRow(_ title: String, _ subtitle: String, _ binding: Binding<Bool>) -> some View {
        HStack {
            label(title, subtitle)
            Spacer()
            Toggle("", isOn: binding).toggleStyle(.switch).tint(accent).labelsHidden()
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    private func pickerRow<P: View>(_ title: String, _ subtitle: String, @ViewBuilder _ picker: () -> P) -> some View {
        HStack {
            label(title, subtitle)
            Spacer()
            picker()
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 190)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private func sliderRow(_ title: String, _ subtitle: String, _ binding: Binding<Double>,
                           range: ClosedRange<Double>) -> some View {
        HStack {
            label(title, subtitle)
            Spacer()
            Slider(value: binding, in: range).tint(accent).frame(width: 140)
            Text("\(Int(binding.wrappedValue))px")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 48, alignment: .trailing)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var addExcludedAppMenu: some View {
        Menu {
            ForEach(runningApps(), id: \.processIdentifier) { app in
                Button(app.localizedName ?? app.bundleIdentifier ?? "?") {
                    guard let id = app.bundleIdentifier,
                          !AppSettings.matchesExclusion(id, in: settings.excludedApps) else { return }
                    settings.excludedApps.append(id)
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "plus.circle.fill")
                Text("Add Running App")
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(0.6))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private func runningApps() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    private func appName(for bundleID: String) -> String {
        if let live = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
           let name = live.localizedName { return name }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path)
                .replacingOccurrences(of: ".app", with: "")
        }
        return bundleID
    }

    private func label(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.9))
            Text(subtitle).font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
        }
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1).padding(.leading, 14)
    }
}
