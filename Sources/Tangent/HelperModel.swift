import AppKit
import SwiftUI

/// A row in the helper: either a character or a shortcut, with the key strokes to show.
struct Entry: Identifiable, Equatable {
    let id: String
    let glyph: String?
    let title: String
    let aliases: [String]
    let category: String
    let steps: [Stroke]
    /// Shown when the key couldn't be found in the current layout.
    var fallbackKey: String?
    var isShortcut: Bool { glyph == nil }

    static func == (a: Entry, b: Entry) -> Bool { a.id == b.id }
}

final class HelperModel: ObservableObject {
    enum Tab: String, CaseIterable { case popular = "Populära", characters = "Alla tecken", shortcuts = "Kortkommandon" }

    static let popular = ["@", "{", "}", "[", "]", "\\", "|", "~", "$", "€", "<", ">", "^"]

    @Published private(set) var layout = KeyboardLayout()
    @Published var tab: Tab = .popular
    @Published var query = ""
    @Published var selected: Entry?
    @Published var manualLayer: Mods = []
    @Published var heldMods: Mods = []
    @Published var toast: String?
    @Published var focusRequest = 0

    private(set) var symbolEntries: [Entry] = []
    private(set) var shortcutEntries: [Entry] = []
    var onClose: (() -> Void)?

    init() { rebuild() }

    /// Re-reads the keyboard layout (the user may have switched input source).
    func reload() {
        layout = KeyboardLayout()
        rebuild()
        if let id = selected?.id { selected = (symbolEntries + shortcutEntries).first { $0.id == id } }
    }

    private func rebuild() {
        symbolEntries = Catalog.symbols.map { def in
            Entry(id: "c:" + def.char, glyph: def.char, title: def.names.first ?? "", aliases: def.names,
                  category: def.category, steps: layout.recipes[def.char] ?? [])
        }
        shortcutEntries = Catalog.shortcuts.map { def in
            let code: UInt16?
            var fallback: String?
            switch def.key {
            case .code(let c): code = c
            case .char(let c): code = layout.keyCode(forBase: c); fallback = c.uppercased()
            }
            return Entry(id: "s:" + def.title, glyph: nil, title: def.title, aliases: def.aliases,
                         category: def.category, steps: code.map { [Stroke(keyCode: $0, mods: def.mods)] } ?? [],
                         fallbackKey: fallback)
        }
    }

    /// The modifier layer the keyboard shows: held keys win, otherwise the selected/toggled layer.
    var layer: Mods {
        let held = heldMods.intersection(.typing)
        return held.isEmpty ? manualLayer : held
    }

    var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    /// What the grid shows: the current tab, or search hits across characters and shortcuts.
    var results: [Entry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else {
            switch tab {
            case .popular: return Self.popular.compactMap { c in symbolEntries.first { $0.glyph == c } }
            case .characters: return symbolEntries
            case .shortcuts: return shortcutEntries
            }
        }
        let fold: (String) -> String = { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
        let needle = fold(q)
        let matches: (Entry) -> Bool = { e in ([e.title] + e.aliases).contains { fold($0).contains(needle) } }
        let exact = symbolEntries.filter { $0.glyph == q }
        return exact + symbolEntries.filter { $0.glyph != q && matches($0) } + shortcutEntries.filter(matches)
    }

    func select(_ entry: Entry?) {
        selected = entry
        // Shortcuts show the plain key labels (⇧⌘4 highlights "4", not "€").
        manualLayer = entry.flatMap { $0.isShortcut ? nil : $0.steps.first?.mods.intersection(.typing) } ?? []
    }

    /// ↑/↓ through the grid.
    func move(_ delta: Int) {
        let list = results
        guard !list.isEmpty else { return }
        let index = selected.flatMap { s in list.firstIndex(of: s) }
        let next = index.map { min(max($0 + delta, 0), list.count - 1) } ?? 0
        select(list[next])
    }

    func toggleLayer(_ mod: Mods) {
        selected = nil
        manualLayer.formSymmetricDifference(mod)
    }

    /// Clicking a key on the virtual keyboard shows the character it types in the current layer.
    func tapKey(_ code: UInt16) {
        guard let out = layout.output(code, layer), !out.text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let currentLayer = layer
        if let entry = symbolEntries.first(where: { $0.glyph == out.text }) {
            selected = entry
        } else {
            let steps = layout.recipes[out.text] ?? [Stroke(keyCode: code, mods: currentLayer)]
            selected = Entry(id: "k:" + out.text, glyph: out.text, title: out.dead ? "dödtangent" : "",
                             aliases: out.dead ? ["dödtangent – tryck sedan en annan tangent"] : [],
                             category: "", steps: steps)
        }
        manualLayer = currentLayer
    }

    func copy(_ entry: Entry) {
        guard let glyph = entry.glyph else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(glyph, forType: .string)
        toast = "Kopierat"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.toast = nil }
    }

    /// ↩ in the search field: copy the selected (or first) character and close.
    func submit() {
        guard let entry = selected ?? results.first, entry.glyph != nil else { return }
        copy(entry)
        onClose?()
    }

    /// esc: clear the search first, close on the second press. Returns true if handled.
    func escape() -> Bool {
        guard query.isEmpty else { query = ""; return true }
        return false
    }

    // MARK: - Text for keycaps

    func caps(for stroke: Stroke, uppercase: Bool) -> [String] {
        stroke.mods.parts.map(\.symbol) + [layout.keyName(stroke.keyCode, uppercase: uppercase)]
    }

    func compactCombo(_ entry: Entry) -> String {
        if entry.steps.isEmpty { return entry.fallbackKey ?? "–" }
        return entry.steps.map { s in
            s.mods.parts.map(\.symbol).joined() + layout.keyName(s.keyCode, uppercase: entry.isShortcut, compact: true)
        }.joined(separator: " → ")
    }
}
