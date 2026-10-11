import AppKit
import Carbon

/// Modifier keys, in Apple's display order (fn ⌃ ⌥ ⇧ ⌘).
struct Mods: OptionSet, Hashable, Codable {
    let rawValue: Int

    static let shift = Mods(rawValue: 1 << 0)
    static let option = Mods(rawValue: 1 << 1)
    static let control = Mods(rawValue: 1 << 2)
    static let command = Mods(rawValue: 1 << 3)
    static let fn = Mods(rawValue: 1 << 4)

    static let typing: Mods = [.shift, .option]

    init(rawValue: Int) { self.rawValue = rawValue }

    init(_ flags: NSEvent.ModifierFlags) {
        var m: Mods = []
        if flags.contains(.shift) { m.insert(.shift) }
        if flags.contains(.option) { m.insert(.option) }
        if flags.contains(.control) { m.insert(.control) }
        if flags.contains(.command) { m.insert(.command) }
        if flags.contains(.function) { m.insert(.fn) }
        self = m
    }

    /// Individual modifiers in display order.
    var parts: [Mods] {
        [Mods.fn, .control, .option, .shift, .command].filter { contains($0) }
    }

    var symbol: String {
        switch self {
        case .fn: return "fn"
        case .control: return "⌃"
        case .option: return "⌥"
        case .shift: return "⇧"
        case .command: return "⌘"
        default: return parts.map(\.symbol).joined()
        }
    }

    /// Symbol plus name, for keycaps in the detail view.
    var capLabel: String {
        switch self {
        case .fn: return "fn"
        case .control: return "⌃ control"
        case .option: return "⌥ option"
        case .shift: return "⇧ shift"
        case .command: return "⌘ command"
        default: return symbol
        }
    }

    var carbon: UInt32 {
        var c = 0
        if contains(.shift) { c |= shiftKey }
        if contains(.option) { c |= optionKey }
        if contains(.control) { c |= controlKey }
        if contains(.command) { c |= cmdKey }
        return UInt32(c)
    }

    var count: Int { parts.count }
}

/// One key press: a physical key plus held modifiers.
struct Stroke: Hashable {
    let keyCode: UInt16
    let mods: Mods
}

/// What a key produces in a given layer.
struct KeyOutput {
    let text: String
    /// Dead key: produces nothing by itself, modifies the next key (e.g. ¨ ^ ~ ´ `).
    let dead: Bool
}

/// Reads the user's current keyboard layout and works out which keys produce which characters.
final class KeyboardLayout {
    /// Every key that types a character, in physical order (ISO MacBook keyboard).
    static let typingKeys: [UInt16] = [
        0x0A, 0x12, 0x13, 0x14, 0x15, 0x17, 0x16, 0x1A, 0x1C, 0x19, 0x1D, 0x1B, 0x18,
        0x0C, 0x0D, 0x0E, 0x0F, 0x11, 0x10, 0x20, 0x22, 0x1F, 0x23, 0x21, 0x1E,
        0x00, 0x01, 0x02, 0x03, 0x05, 0x04, 0x26, 0x28, 0x25, 0x29, 0x27, 0x2A,
        0x32, 0x06, 0x07, 0x08, 0x09, 0x0B, 0x2D, 0x2E, 0x2B, 0x2F, 0x2C,
        0x31,
    ]
    static let layers: [Mods] = [[], [.shift], [.option], [.shift, .option]]

    let name: String
    private let data: Data?
    private var outputs: [Stroke: KeyOutput] = [:]
    /// Cheapest way to type each character.
    private(set) var recipes: [String: [Stroke]] = [:]
    private var baseKeys: [String: UInt16] = [:]

    init() {
        var source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue()
        if source.flatMap({ TISGetInputSourceProperty($0, kTISPropertyUnicodeKeyLayoutData) }) == nil {
            source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue()
        }
        if let source, let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) {
            data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        } else {
            data = nil
        }
        if let source, let ptr = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) {
            name = Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
        } else {
            name = "Okänd"
        }
        build()
    }

    func output(_ keyCode: UInt16, _ layer: Mods) -> KeyOutput? {
        outputs[Stroke(keyCode: keyCode, mods: layer.intersection(.typing))]
    }

    /// The key that types `char` without modifiers (used to place letter shortcuts like ⌘C).
    func keyCode(forBase char: String) -> UInt16? {
        baseKeys[char.lowercased()]
    }

    /// Human-readable key name for keycaps and hints.
    func keyName(_ keyCode: UInt16, uppercase: Bool = false, compact: Bool = false) -> String {
        if let special = Self.specialNames[keyCode] {
            return compact && keyCode == 0x31 ? "␣" : special
        }
        let text = output(keyCode, [])?.text ?? "?"
        return uppercase ? text.uppercased() : text
    }

    static let specialNames: [UInt16: String] = [
        0x31: "mellanslag", 0x24: "↩", 0x30: "⇥", 0x33: "⌫", 0x35: "esc", 0x39: "⇪",
        0x7B: "←", 0x7C: "→", 0x7D: "↓", 0x7E: "↑",
        0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4", 0x60: "F5", 0x61: "F6",
        0x62: "F7", 0x64: "F8", 0x65: "F9", 0x6D: "F10", 0x67: "F11", 0x6F: "F12",
    ]

    // MARK: - Layout analysis

    private func translate(_ keyCode: UInt16, _ mods: Mods, _ deadState: inout UInt32, noDeadKeys: Bool = false) -> String {
        guard let data else { return "" }
        return data.withUnsafeBytes { raw -> String in
            guard let base = raw.baseAddress else { return "" }
            let layout = base.assumingMemoryBound(to: UCKeyboardLayout.self)
            var chars = [UniChar](repeating: 0, count: 8)
            var length = 0
            let status = UCKeyTranslate(
                layout, keyCode, UInt16(kUCKeyActionDown), (mods.carbon >> 8) & 0xFF,
                UInt32(LMGetKbdType()), noDeadKeys ? OptionBits(kUCKeyTranslateNoDeadKeysMask) : 0,
                &deadState, chars.count, &length, &chars)
            guard status == noErr else { return "" }
            return String(utf16CodeUnits: chars, count: length)
        }
    }

    private func build() {
        for layer in Self.layers {
            for code in Self.typingKeys {
                let stroke = Stroke(keyCode: code, mods: layer)
                var state: UInt32 = 0
                let text = translate(code, layer, &state)
                if state != 0 {
                    var ignored: UInt32 = 0
                    outputs[stroke] = KeyOutput(text: translate(code, layer, &ignored, noDeadKeys: true), dead: true)
                    // Dead key: try every follow-up key to find what it composes.
                    for followLayer in [Mods(), .shift] {
                        // Space first, so "dead key + space" wins ties (the usual way to type ~ ^ ´).
                        for follow in [0x31] + Self.typingKeys.filter({ $0 != 0x31 }) {
                            var s = state
                            // Don't check `s` afterwards: macOS leaves leftover bits in it after composing.
                            let composed = translate(follow, followLayer, &s)
                            consider(composed, [stroke, Stroke(keyCode: follow, mods: followLayer)])
                        }
                    }
                } else {
                    outputs[stroke] = KeyOutput(text: text, dead: false)
                    consider(text, [stroke])
                    if layer.isEmpty, !text.isEmpty, baseKeys[text] == nil { baseKeys[text] = code }
                }
            }
        }
    }

    private func consider(_ text: String, _ strokes: [Stroke]) {
        guard text.count == 1, let scalar = text.unicodeScalars.first,
              scalar.value >= 0x20, scalar.value != 0x7F else { return }
        func cost(_ s: [Stroke]) -> Int { s.count * 10 + s.reduce(0) { $0 + $1.mods.count } }
        if let existing = recipes[text], cost(existing) <= cost(strokes) { return }
        recipes[text] = strokes
    }
}
