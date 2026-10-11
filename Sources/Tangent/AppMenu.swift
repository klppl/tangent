import AppKit
import Carbon

/// Reads another app's menu bar through the Accessibility API and turns its keyboard shortcuts into a cheat sheet.
enum AppMenu {
    static var hasAccess: Bool { AXIsProcessTrusted() }

    /// Shows the system dialog that leads to Privacy & Security → Accessibility.
    static func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// One section per top-level menu, skipping the Apple menu. Slow for big apps, so call off the main thread.
    static func sheet(pid: pid_t, title: String, id: String) -> CheatSheet? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1)
        var bar: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &bar) == .success,
              let bar, CFGetTypeID(bar) == AXUIElementGetTypeID() else { return nil }

        var sections: [CheatSheet.Section] = []
        var rowID = 0
        for item in Item.read(children(bar as! AXUIElement)).dropFirst() {
            var rows: [CheatSheet.Row] = []
            var seen = Set<String>()
            for menu in item.children { collect(menu, path: [], into: &rows, seen: &seen, id: &rowID) }
            if !rows.isEmpty { sections.append(.init(id: sections.count, title: item.title, rows: rows)) }
        }
        return CheatSheet(id: id, title: title, sections: sections)
    }

    private static func collect(_ menu: AXUIElement, path: [String], into rows: inout [CheatSheet.Row],
                                seen: inout Set<String>, id: inout Int) {
        for item in Item.read(children(menu)) where !item.title.isEmpty {
            if let submenu = item.children.first {
                collect(submenu, path: path + [item.title], into: &rows, seen: &seen, id: &id)
                continue
            }
            guard let keys = item.shortcut else { continue }
            let text = (path + [item.title]).joined(separator: " › ")
            guard seen.insert(keys + text).inserted else { continue }
            rows.append(.init(id: id, keys: keys, text: text))
            id += 1
        }
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    /// The attributes of one menu item, fetched in a single round trip.
    private struct Item {
        static let attributes = [kAXTitleAttribute, kAXMenuItemCmdCharAttribute, kAXMenuItemCmdModifiersAttribute,
                                 kAXMenuItemCmdGlyphAttribute, kAXChildrenAttribute]

        let title: String
        let char: String?
        let modifiers: Int
        let glyph: Int?
        let children: [AXUIElement]

        static func read(_ elements: [AXUIElement]) -> [Item] {
            elements.compactMap { element in
                var values: CFArray?
                guard AXUIElementCopyMultipleAttributeValues(element, attributes as CFArray, [], &values) == .success,
                      let list = values as? [Any], list.count == attributes.count else { return nil }
                return Item(title: list[0] as? String ?? "", char: list[1] as? String, modifiers: list[2] as? Int ?? 0,
                            glyph: list[3] as? Int, children: list[4] as? [AXUIElement] ?? [])
            }
        }

        /// E.g. "⇧⌘S", or nil if the item has no shortcut.
        var shortcut: String? {
            let key: String
            if let glyph, let name = AppMenu.glyphs[glyph] {
                key = name
            } else if let char, let scalar = char.unicodeScalars.first, scalar.value > 0x20, scalar.value != 0x7F {
                key = char.uppercased()
            } else {
                return nil
            }
            // kAXMenuItemModifier* bits: ⌘ is implied unless "no command" is set.
            var mods = ""
            if modifiers & (1 << 2) != 0 { mods += "⌃" }
            if modifiers & (1 << 1) != 0 { mods += "⌥" }
            if modifiers & (1 << 0) != 0 { mods += "⇧" }
            if modifiers & (1 << 3) == 0 { mods += "⌘" }
            return mods + key
        }
    }

    /// Menu glyphs for keys without a printable character.
    static let glyphs: [Int: String] = {
        var g: [Int: String] = [
            kMenuTabRightGlyph: "⇥", kMenuTabLeftGlyph: "⇤", kMenuEnterGlyph: "⌅", kMenuSpaceGlyph: "␣",
            kMenuDeleteRightGlyph: "⌦", kMenuReturnGlyph: "↩", kMenuNonmarkingReturnGlyph: "↩", kMenuDeleteLeftGlyph: "⌫",
            kMenuEscapeGlyph: "esc", kMenuClearGlyph: "⌧", kMenuPageUpGlyph: "⇞", kMenuPageDownGlyph: "⇟",
            kMenuLeftArrowGlyph: "←", kMenuRightArrowGlyph: "→", kMenuUpArrowGlyph: "↑", kMenuDownArrowGlyph: "↓",
            kMenuNorthwestArrowGlyph: "↖", kMenuSoutheastArrowGlyph: "↘", kMenuHelpGlyph: "?⃝", kMenuEjectGlyph: "⏏",
        ]
        let fKeys = [kMenuF1Glyph, kMenuF2Glyph, kMenuF3Glyph, kMenuF4Glyph, kMenuF5Glyph, kMenuF6Glyph, kMenuF7Glyph,
                     kMenuF8Glyph, kMenuF9Glyph, kMenuF10Glyph, kMenuF11Glyph, kMenuF12Glyph, kMenuF13Glyph,
                     kMenuF14Glyph, kMenuF15Glyph]
        for (i, glyph) in fKeys.enumerated() { g[glyph] = "F\(i + 1)" }
        return g
    }()
}
