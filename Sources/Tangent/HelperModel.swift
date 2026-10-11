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
    @Published var mode: Mode = .keyboard {
        didSet {
            stopDemo()
            if mode == .cheatSheets, returnToSheets {
                returnToSheets = false
                select(nil)
            }
        }
    }
    /// The keyboard is showing a shortcut picked from a cheat sheet; esc goes back.
    @Published private(set) var returnToSheets = false
    /// Keys held down in the shortcut animation.
    @Published private(set) var demoMods: Mods = []
    @Published private(set) var demoKey: UInt16?
    private var demoRun = 0
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
        if returnToSheets { mode = .cheatSheets }
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

    /// Shows a cheat sheet row on the keyboard and animates pressing it. Returns false if the keys can't be typed.
    @discardableResult
    func showOnKeyboard(_ row: CheatSheet.Row) -> Bool {
        guard let steps = strokes(for: row.keys) else { return false }
        let entry = Entry(id: "r:" + row.keys, glyph: nil, title: row.text, aliases: [], category: "", steps: steps)
        mode = .keyboard
        returnToSheets = true
        select(entry)
        playDemo(steps)
        return true
    }

    /// Presses each step's modifiers one at a time, then its key, and lets go. Plays twice.
    func playDemo(_ steps: [Stroke]) {
        stopDemo()
        let run = demoRun
        var time = 0.35
        var actions: [(TimeInterval, (HelperModel) -> Void)] = []
        for _ in 0..<2 {
            for step in steps {
                var held: Mods = []
                for mod in step.mods.parts {
                    held.insert(mod)
                    let mods = held
                    actions.append((time, { $0.demoMods = mods }))
                    time += 0.2
                }
                actions.append((time, { $0.demoKey = step.keyCode }))
                time += 0.45
                actions.append((time, { $0.demoKey = nil; $0.demoMods = [] }))
                time += 0.3
            }
            time += 0.5
        }
        for (delay, action) in actions {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.demoRun == run else { return }
                action(self)
            }
        }
    }

    func stopDemo() {
        demoRun += 1
        demoMods = []
        demoKey = nil
    }

    /// Keys that cheat sheets name instead of typing, with any modifier a MacBook needs for them.
    private static let namedKeys: [String: (UInt16, Mods)] = {
        var keys: [String: (UInt16, Mods)] = [:]
        for (code, name) in KeyboardLayout.specialNames { keys[name.lowercased()] = (code, []) }
        let extra: [String: (UInt16, Mods)] = [
            "␣": (0x31, []), "space": (0x31, []), "tab": (0x30, []), "return": (0x24, []), "enter": (0x24, []),
            "delete": (0x33, []), "backspace": (0x33, []), "escape": (0x35, []),
            "left": (0x7B, []), "right": (0x7C, []), "down": (0x7D, []), "up": (0x7E, []),
            "⌦": (0x33, .fn), "⇞": (0x7E, .fn), "⇟": (0x7D, .fn), "↖": (0x7B, .fn), "↘": (0x7C, .fn),
        ]
        keys.merge(extra) { _, new in new }
        return keys
    }()

    /// Turns cheat sheet keys like "⇧⌘N", "⌃r", "esc", "gg" or ":wq" into strokes on the current layout.
    func strokes(for keys: String) -> [Stroke]? {
        let symbols: [Character: Mods] = ["⌃": .control, "⌥": .option, "⇧": .shift, "⌘": .command]
        var mods: Mods = []
        var rest = Substring(keys.trimmingCharacters(in: .whitespaces))
        while let first = rest.first, let mod = symbols[first] {
            mods.insert(mod)
            rest = rest.dropFirst()
        }
        guard !rest.isEmpty else { return nil }
        if let (code, extra) = Self.namedKeys[rest.lowercased()] {
            return [Stroke(keyCode: code, mods: mods.union(extra))]
        }
        // With modifiers, a single key (menus show letters uppercase). Without, a short sequence like "gg" or ":wq".
        let chars = rest.map(String.init)
        guard mods.isEmpty ? chars.count <= 6 : chars.count == 1, !chars.contains(" ") else { return nil }
        var result: [Stroke] = []
        for char in chars {
            let isCapital = mods.isEmpty && char != char.lowercased()
            if let code = layout.keyCode(forBase: char) {
                result.append(Stroke(keyCode: code, mods: isCapital ? [.shift] : []))
            } else if let recipe = layout.recipes[char], recipe.count == 1 {
                result.append(recipe[0])
            } else {
                return nil
            }
        }
        result[0] = Stroke(keyCode: result[0].keyCode, mods: result[0].mods.union(mods))
        return result
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
        if returnToSheets {
            mode = .cheatSheets
            return true
        }
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
