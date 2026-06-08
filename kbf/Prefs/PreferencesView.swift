import SwiftUI

struct PreferencesView: View {
    @ObservedObject private var settings = AppSettings.shared
    private let accent = Color(red: 0.388, green: 0.400, blue: 0.945)

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            header
            section("SHORTCUTS") {
                shortcutRow("Click mode", "Label every clickable element", $settings.clickHotkey)
                divider
                shortcutRow("Scroll mode", "Pick a scroll area, then i/k/j/l", $settings.scrollHotkey)
                divider
                shortcutRow("Search mode", "Find an element by its text", $settings.searchHotkey)
            }
            section("GENERAL") {
                HStack {
                    label("Launch at login", "Start kbf automatically")
                    Spacer()
                    Toggle("", isOn: $settings.launchAtLogin).toggleStyle(.switch).tint(accent).labelsHidden()
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
            }
            Spacer(minLength: 0)
            Text("kbf · open-source keyboard-first control")
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.25))
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(28)
        .frame(width: 520, height: 384)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 13) {
            Image(systemName: "keyboard.fill").font(.system(size: 24)).foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 1) {
                Text("Preferences").font(.system(size: 20, weight: .semibold))
                Text("⌥Space click · ⌥⇧Space scroll · ⌥/ search")
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
