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

/// Physical key arrangement of the keyboard.
enum PhysicalLayout: String, CaseIterable {
    /// Tall return key and an extra key between left shift and Z (most of Europe).
    case iso
    /// Wide return key with \ above it and a long left shift (US and others).
    case ansi

    var label: String { self == .iso ? "ISO" : "ANSI" }

    private static let defaultsKey = "physicalLayout"

    /// The user's choice; nil means detect it.
    static var preference: PhysicalLayout? {
        get { UserDefaults.standard.string(forKey: defaultsKey).flatMap(PhysicalLayout.init) }
        set { UserDefaults.standard.set(newValue?.rawValue, forKey: defaultsKey) }
    }

    /// The keyboard last typed on. JIS is shown as ISO, the closer shape.
    static var detected: PhysicalLayout {
        KBGetLayoutType(Int16(LMGetKbdType())) == UInt32(kKeyboardANSI) ? .ansi : .iso
    }

    static var current: PhysicalLayout { preference ?? detected }

    /// Keyboard type for UCKeyTranslate. When the user overrides detection, translate as that
    /// kind of keyboard so keys that only exist on it get the right characters.
    var kbdType: UInt32 {
        let actual = UInt32(LMGetKbdType())
        guard self != Self.detected else { return actual }
        let wanted = UInt32(self == .ansi ? kKeyboardANSI : kKeyboardISO)
        return (0...255).first { KBGetLayoutType(Int16($0)) == wanted }.map(UInt32.init) ?? actual
    }
}

/// Which keyboard layout (input source) to show: the active one, or one the user picked in settings.
enum CharacterLayout {
    struct Choice: Hashable, Identifiable {
        let id: String
        let name: String
    }

    private static let defaultsKey = "characterLayout"

    /// Input source ID, e.g. "com.apple.keylayout.German"; nil follows the active layout.
    static var preference: String? {
        get { UserDefaults.standard.string(forKey: defaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }

    /// Layouts the user has added in System Settings, or every layout installed on the Mac.
    static func choices(all: Bool) -> [Choice] {
        sources(all: all)
            .compactMap { source in
                guard TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) != nil,
                      let id = string(source, kTISPropertyInputSourceID),
                      let name = string(source, kTISPropertyLocalizedName) else { return nil }
                return Choice(id: id, name: name)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The layout to read: the chosen one if it still exists, otherwise the active one.
    static func source(followSettings: Bool) -> TISInputSource? {
        if followSettings, let id = preference,
           let chosen = sources(all: true).first(where: { string($0, kTISPropertyInputSourceID) == id }) {
            return chosen
        }
        let current = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue()
        if current.flatMap({ TISGetInputSourceProperty($0, kTISPropertyUnicodeKeyLayoutData) }) != nil { return current }
        return TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue()
    }

    static func string(_ source: TISInputSource, _ key: CFString) -> String? {
        TISGetInputSourceProperty(source, key).map { Unmanaged<CFString>.fromOpaque($0).takeUnretainedValue() as String }
    }

    private static func sources(all: Bool) -> [TISInputSource] {
        let filter = [kTISPropertyInputSourceType as String: kTISTypeKeyboardLayout as String] as CFDictionary
        return TISCreateInputSourceList(filter, all)?.takeRetainedValue() as? [TISInputSource] ?? []
    }
}

/// Reads the user's current keyboard layout and works out which keys produce which characters.
final class KeyboardLayout {
    static let layers: [Mods] = [[], [.shift], [.option], [.shift, .option]]

    let name: String
    let physical: PhysicalLayout
    /// Every key that types a character, in physical order.
    let typingKeys: [UInt16]
    private let kbdType: UInt32
    private let data: Data?
    private var outputs: [Stroke: KeyOutput] = [:]
    /// Cheapest way to type each character.
    private(set) var recipes: [String: [Stroke]] = [:]
    private var baseKeys: [String: UInt16] = [:]

    /// True when showing a layout picked in settings rather than the active one.
    let isOverride: Bool

    /// `followSettings: false` reads the active layout, for matching what the user's keys actually type.
    init(followSettings: Bool = true) {
        physical = .current
        kbdType = physical.kbdType
        typingKeys = MacBookKeyboard.typingKeys(physical)
        let source = CharacterLayout.source(followSettings: followSettings)
        if let source, let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) {
            data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        } else {
            data = nil
        }
        name = source.flatMap { CharacterLayout.string($0, kTISPropertyLocalizedName) } ?? "Okänd"
        let id = source.flatMap { CharacterLayout.string($0, kTISPropertyInputSourceID) }
        let current = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue()
        isOverride = id != nil && id != current.flatMap { CharacterLayout.string($0, kTISPropertyInputSourceID) }
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
        0x31: "mellanslag", 0x24: "↩", 0x30: "⇥", 0x33: "⌫", 0x35: "esc", 0x39: "⇪", 0x3F: "fn",
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
                kbdType, noDeadKeys ? OptionBits(kUCKeyTranslateNoDeadKeysMask) : 0,
                &deadState, chars.count, &length, &chars)
            guard status == noErr else { return "" }
            return String(utf16CodeUnits: chars, count: length)
        }
    }

    private func build() {
        for layer in Self.layers {
            for code in typingKeys {
                let stroke = Stroke(keyCode: code, mods: layer)
                var state: UInt32 = 0
                let text = translate(code, layer, &state)
                if state != 0 {
                    var ignored: UInt32 = 0
                    outputs[stroke] = KeyOutput(text: translate(code, layer, &ignored, noDeadKeys: true), dead: true)
                    // Dead key: try every follow-up key to find what it composes.
                    for followLayer in [Mods(), .shift] {
                        // Space first, so "dead key + space" wins ties (the usual way to type ~ ^ ´).
                        for follow in [0x31] + typingKeys.filter({ $0 != 0x31 }) {
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
