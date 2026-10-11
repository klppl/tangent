import AppKit

/// Detects a double-tap of a lone modifier key (e.g. ⌘ ⌘), and "double-tap and hold".
///
/// Uses flagsChanged monitors, which need no Accessibility permission. Typing (⌘C, ⌘V…)
/// is told apart from a clean tap with the system-wide key/mouse counters, so we never
/// see which keys were pressed.
final class ModifierTapDetector {
    /// The modifier to watch; nil disables detection.
    var modifier: Mods?
    /// Second press of a double-tap.
    var onDoubleTap: (() -> Void)?
    /// The second press was held and then released without doing anything else ("peek").
    var onHoldReleased: (() -> Void)?

    private static let maxTap: TimeInterval = 0.3
    private static let maxGap: TimeInterval = 0.35
    private static let minHold: TimeInterval = 0.4

    private var monitors: [Any] = []
    private var isDown = false
    private var downAt = Date.distantPast
    private var downCounter: UInt32 = 0
    private var lastCleanTapUp: Date?
    private var inSecondPress = false

    init() {
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] in self?.handle($0) }) {
            monitors.append(m)
        }
        // Global monitors don't see our own app's events (when the helper is focused).
        if let m = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] in
            self?.handle($0)
            return $0
        }) {
            monitors.append(m)
        }
    }

    /// Key presses and clicks anywhere since boot.
    private var activityCounter: UInt32 {
        CGEventSource.counterForEventType(.combinedSessionState, eventType: .keyDown)
            &+ CGEventSource.counterForEventType(.combinedSessionState, eventType: .leftMouseDown)
            &+ CGEventSource.counterForEventType(.combinedSessionState, eventType: .rightMouseDown)
    }

    private func handle(_ event: NSEvent) {
        guard let modifier else { return }
        let mods = Mods(event.modifierFlags).subtracting(.fn)
        let nowDown = mods == modifier
        let now = Date()

        if nowDown && !isDown {
            isDown = true
            downAt = now
            downCounter = activityCounter
            if let up = lastCleanTapUp, now.timeIntervalSince(up) < Self.maxGap {
                lastCleanTapUp = nil
                inSecondPress = true
                onDoubleTap?()
            }
        } else if !nowDown && isDown {
            isDown = false
            let held = now.timeIntervalSince(downAt)
            let untouched = activityCounter == downCounter && mods.isEmpty
            if inSecondPress {
                inSecondPress = false
                if held >= Self.minHold && untouched { onHoldReleased?() }
            } else {
                lastCleanTapUp = untouched && held < Self.maxTap ? now : nil
            }
        } else if !nowDown && !mods.isEmpty {
            // Some other modifier joined in: not a clean tap.
            lastCleanTapUp = nil
        }
    }
}
