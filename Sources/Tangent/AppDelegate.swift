import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let helper = HelperPanelController()
    private let settings = SettingsModel()
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = Self.statusIcon()

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        HotKeyCenter.shared.onPress = { [weak self] in self?.helper.toggle() }
        settings.onShowHelper = { [weak self] in
            self?.settingsWindow?.close()
            self?.helper.show()
        }
        settings.tapDetector.onDoubleTap = { [weak self] in self?.helper.toggle() }
        settings.tapDetector.onHoldReleased = { [weak self] in self?.helper.hide(reactivatePrevious: true) }
        settings.applyTrigger()

        if !UserDefaults.standard.bool(forKey: "hasLaunched") {
            UserDefaults.standard.set(true, forKey: "hasLaunched")
            openSettings()
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let layout = KeyboardLayout(followSettings: false)

        let show = NSMenuItem(title: "Visa teckenhjälp", action: #selector(showHelper), keyEquivalent: "")
        show.target = self
        let hotKey = settings.hotKey
        if settings.trigger == .combo, let char = layout.output(hotKey.keyCode, [])?.text, char.count == 1, !hotKey.mods.contains(.fn) {
            show.keyEquivalent = char.lowercased()
            var mask: NSEvent.ModifierFlags = []
            if hotKey.mods.contains(.command) { mask.insert(.command) }
            if hotKey.mods.contains(.option) { mask.insert(.option) }
            if hotKey.mods.contains(.control) { mask.insert(.control) }
            if hotKey.mods.contains(.shift) { mask.insert(.shift) }
            show.keyEquivalentModifierMask = mask
        }
        menu.addItem(show)

        menu.addItem(.separator())
        let change = NSMenuItem(title: "Ändra kortkommando (\(settings.triggerDisplay))…", action: #selector(openSettings), keyEquivalent: ",")
        change.target = self
        menu.addItem(change)

        let login = NSMenuItem(title: "Starta vid inloggning", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = settings.launchAtLogin ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Avsluta Tangent", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    /// A single keycap with ⌥ on it: thicker bottom edge for the key's "lip".
    static func statusIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 16), flipped: false) { _ in
            let outer = NSRect(x: 1, y: 1, width: 18, height: 14)
            let inner = NSRect(x: outer.minX + 1.4, y: outer.minY + 2.8, width: outer.width - 2.8, height: outer.height - 4.2)
            let cap = NSBezierPath(roundedRect: outer, xRadius: 4, yRadius: 4)
            cap.append(NSBezierPath(roundedRect: inner, xRadius: 2.8, yRadius: 2.8))
            cap.windingRule = .evenOdd
            NSColor.black.setFill()
            cap.fill()

            let glyph = NSAttributedString(string: "⌥", attributes: [
                .font: NSFont.systemFont(ofSize: 9.5, weight: .bold),
                .foregroundColor: NSColor.black,
            ])
            let size = glyph.size()
            glyph.draw(at: NSPoint(x: inner.midX - size.width / 2, y: inner.midY - size.height / 2))
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Tangent"
        return image
    }

    @objc private func showHelper() { helper.show() }

    @objc private func toggleLogin() { settings.setLaunchAtLogin(!settings.launchAtLogin) }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Tangent – Inställningar"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(model: settings))
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
