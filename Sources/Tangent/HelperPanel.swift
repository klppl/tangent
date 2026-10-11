import AppKit
import SwiftUI

private final class HelperPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Floating window with the keyboard helper. Toggled by the global hotkey.
final class HelperPanelController: NSObject, NSWindowDelegate {
    let model = HelperModel()
    private var panel: HelperPanel?
    private var monitors: [Any] = []
    private var previousApp: NSRunningApplication?
    private var isShowing = false

    func toggle() {
        isShowing ? hide(reactivatePrevious: true) : show()
    }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel

        let front = NSWorkspace.shared.frontmostApplication
        if front != NSRunningApplication.current { previousApp = front }
        model.reload(frontApp: previousApp)

        // Center on the screen that has the mouse.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            let size = panel.frame.size
            // Slightly above center, like Spotlight.
            panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2,
                                         y: visible.midY - size.height / 2 + visible.height * 0.06))
        }

        isShowing = true
        NSApp.activate(ignoringOtherApps: true)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.14
            panel.animator().alphaValue = 1
        }
        model.focusRequest += 1
        installMonitors()
    }

    func hide(reactivatePrevious: Bool) {
        guard isShowing else { return }
        isShowing = false
        removeMonitors()
        model.heldMods = []
        panel?.orderOut(nil)
        if reactivatePrevious { previousApp?.activate() }
    }

    private func makePanel() -> HelperPanel {
        let hosting = NSHostingView(rootView: HelperView(model: model))
        let size = hosting.fittingSize

        // Frosted, rounded, borderless – like Spotlight.
        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.maskImage = Self.roundedMask(radius: 22)
        hosting.frame = effect.bounds
        hosting.autoresizingMask = [.width, .height]
        effect.addSubview(hosting)

        let panel = HelperPanel(contentRect: NSRect(origin: .zero, size: size),
                                styleMask: [.borderless], backing: .buffered, defer: false)
        panel.contentView = effect
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        model.onClose = { [weak self] in self?.hide(reactivatePrevious: true) }
        return panel
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    private func installMonitors() {
        removeMonitors()
        if let m = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] event in
            self?.model.heldMods = Mods(event.modifierFlags)
            return event
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            switch event.keyCode {
            case 0x35: // esc: clear search, then close
                if !self.model.escape() { self.hide(reactivatePrevious: true) }
                return nil
            case 0x30 where Mods(event.modifierFlags).subtracting(.fn).isEmpty: // ⇥: switch mode
                self.model.toggleMode()
                return nil
            case 0x7E: self.model.move(-1); return nil // ↑
            case 0x7D: self.model.move(1); return nil  // ↓
            default: return event
            }
        }) { monitors.append(m) }
    }

    private func removeMonitors() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }

    // MARK: NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        // Clicked somewhere else: get out of the way, without stealing focus back.
        hide(reactivatePrevious: false)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide(reactivatePrevious: true)
        return false
    }
}
