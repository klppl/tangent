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
    enum Mode { case keyboard, cheatSheets }

    static let popular = ["@", "{", "}", "[", "]", "\\", "|", "~", "$", "€", "^", "`", "°"]

    @Published private(set) var layout = KeyboardLayout()
    @Published var tab: Tab = .popular
    @Published var query = ""
    @Published var selected: Entry?
    @Published var manualLayer: Mods = []
    @Published var heldMods: Mods = []
    @Published var toast: String?
    @Published var focusRequest = 0
    @Published var mode: Mode = .keyboard
    @Published private(set) var sheets: [CheatSheet] = []
    @Published var sheetID: String?
    /// The app that was in front when the helper opened, whose menu shortcuts form a sheet of their own.
    @Published private(set) var appName: String?
    @Published private(set) var appSheet: CheatSheet?
    @Published private(set) var appAccess = AppMenu.hasAccess
    private var appRead = 0

    private(set) var symbolEntries: [Entry] = []
    private(set) var shortcutEntries: [Entry] = []
    var onClose: (() -> Void)?

    init() { rebuild() }

    /// Re-reads the keyboard layout (the user may have switched input source), cheat sheets and the front app's menus.
    func reload(frontApp: NSRunningApplication? = nil) {
        sheets = CheatSheets.load()
        readMenus(of: frontApp)
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
            let resolve: (KeySpec) -> UInt16? = { spec in
                switch spec {
                case .code(let c): return c
                case .char(let c): return self.layout.keyCode(forBase: c)
                }
            }
            var fallback: String?
            if case .char(let c) = def.key { fallback = c.uppercased() }
            var steps: [Stroke] = []
            if let code = resolve(def.key) {
                steps = [Stroke(keyCode: code, mods: def.mods)]
                if let then = def.then, let next = resolve(then.key) {
                    steps.append(Stroke(keyCode: next, mods: then.mods))
                }
            }
            return Entry(id: "s:" + def.title, glyph: nil, title: def.title, aliases: def.aliases,
                         category: def.category, steps: steps, fallbackKey: fallback)
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

    // MARK: - Cheat sheets

    func toggleMode() {
        mode = mode == .keyboard ? .cheatSheets : .keyboard
    }

    static let appSheetID = "app"

    /// Sidebar order: the front app first, then the user's sheets.
    var sheetIDs: [String] { (appName != nil ? [Self.appSheetID] : []) + sheets.map(\.id) }

    /// The sheet shown when not searching. Falls back to the first one if the chosen sheet is gone.
    var currentSheetID: String? { sheetID.flatMap { sheetIDs.contains($0) ? $0 : nil } ?? sheetIDs.first }

    var currentSheet: CheatSheet? {
        currentSheetID == Self.appSheetID ? appSheet : sheets.first { $0.id == currentSheetID }
    }

    /// The current sheet, or search hits across all sheets.
    var sheetResults: [CheatSheet] {
        isSearching ? CheatSheets.search((appSheet.map { [$0] } ?? []) + sheets, query) : currentSheet.map { [$0] } ?? []
    }

    func showSheet(id: String) {
        sheetID = id
        query = ""
    }

    func requestAppAccess() {
        AppMenu.requestAccess()
    }

    private func readMenus(of app: NSRunningApplication?) {
        appAccess = AppMenu.hasAccess
        appName = app?.localizedName
        appSheet = nil
        appRead += 1
        guard appAccess, let app, let name = appName else { return }
        let read = appRead
        let pid = app.processIdentifier
        let id = Self.appSheetID
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let sheet = AppMenu.sheet(pid: pid, title: name, id: id)
            DispatchQueue.main.async {
                guard let self, self.appRead == read else { return }
                self.appSheet = sheet
            }
        }
    }

    func createExampleSheet() {
        guard let url = try? CheatSheets.createExample() else { return }
        sheets = CheatSheets.load()
        sheetID = url.path
    }

    func copy(_ row: CheatSheet.Row) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(row.keys, forType: .string)
        toast = "Kopierat"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.toast = nil }
    }

    /// ↑/↓ through the grid, or through the sheets in cheat sheet mode.
    func move(_ delta: Int) {
        if mode == .cheatSheets {
            let ids = sheetIDs
            guard !isSearching, !ids.isEmpty else { return }
            let index = currentSheetID.flatMap { ids.firstIndex(of: $0) } ?? 0
            sheetID = ids[min(max(index + delta, 0), ids.count - 1)]
            return
        }
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
        guard mode == .keyboard, let entry = selected ?? results.first, entry.glyph != nil else { return }
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
