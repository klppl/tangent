import SwiftUI

/// Cheat sheet mode: the user's sheets on the left, the current sheet (or search hits) on the right.
struct CheatSheetView: View {
    @ObservedObject var model: HelperModel

    var body: some View {
        if model.sheetIDs.isEmpty {
            empty
        } else {
            HStack(alignment: .top, spacing: 20) {
                sidebar
                Divider().opacity(0.6)
                content
            }
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        let hits = model.isSearching ? Dictionary(uniqueKeysWithValues: model.sheetResults.map { ($0.id, $0.rowCount) }) : [:]
        let button = { (id: String, title: String) in
            SheetButton(title: title, count: model.isSearching ? hits[id] : nil,
                        selected: !model.isSearching && model.currentSheetID == id,
                        dimmed: model.isSearching && hits[id] == nil) {
                model.showSheet(id: id)
            }
        }
        return VStack(alignment: .leading, spacing: 2) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    if let app = model.appName {
                        button(HelperModel.appSheetID, app)
                        if !model.sheets.isEmpty { Divider().opacity(0.6).padding(.vertical, 4) }
                    }
                    ForEach(model.sheets) { sheet in button(sheet.id, sheet.title) }
                }
            }
            Spacer(minLength: 8)
            if model.sheets.isEmpty {
                Button(action: model.createExampleSheet) {
                    Label("Skapa exempel", systemImage: "plus")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            Button(action: CheatSheets.openDirectory) {
                Label("Öppna mappen", systemImage: "folder")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(CheatSheets.directory.path)
        }
        .frame(width: 150)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        let results = model.sheetResults
        if !model.isSearching, model.currentSheetID == HelperModel.appSheetID, model.appSheet == nil {
            appStatus
        } else if !model.isSearching, results.first?.sections.isEmpty == true {
            Text("Inga kortkommandon i menyerna")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if results.isEmpty {
            Text("Inga träffar")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(results) { sheet in
                        if model.isSearching {
                            Text(sheet.title)
                                .font(.system(size: 15, weight: .semibold))
                        }
                        ForEach(sheet.sections) { section in
                            VStack(alignment: .leading, spacing: 2) {
                                if !section.title.isEmpty {
                                    Text(section.title.uppercased())
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                        .padding(.bottom, 4)
                                }
                                ForEach(section.rows) { row in
                                    SheetRow(row: row) { model.copy(row) }
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .overlay(alignment: .bottomTrailing) {
                if let toast = model.toast {
                    Text(toast)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(.regularMaterial))
                }
            }
        }
    }

    /// The front app's sheet before it's ready: still reading, or no Accessibility permission yet.
    @ViewBuilder
    private var appStatus: some View {
        if model.appAccess {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.tertiary)
                Text("Visa kortkommandon för \(model.appName ?? "programmet")")
                    .font(.system(size: 15, weight: .semibold))
                Text("Tangent kan läsa menyerna i programmet du använder och visa alla kortkommandon. Det kräver behörighet under Integritet och säkerhet → Hjälpmedel. Öppna Tangent igen när du har gett behörighet.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Ge behörighet", action: model.requestAppAccess)
            }
            .frame(maxWidth: 380)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Empty state

    private var empty: some View {
        VStack(spacing: 14) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Inga fusklappar än")
                .font(.system(size: 15, weight: .semibold))
            Text("Lägg textfiler (.md eller .txt) i \(Self.displayPath).\n# Titel, ## Avsnitt, sedan en rad per kommando: tangenter, två mellanslag, beskrivning.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Skapa exempel", action: model.createExampleSheet)
                Button("Öppna mappen", action: CheatSheets.openDirectory)
            }
        }
        .frame(maxWidth: 440)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private static var displayPath: String {
        CheatSheets.directory.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
    }
}

private struct SheetButton: View {
    let title: String
    let count: Int?
    let selected: Bool
    let dimmed: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack {
            Text(title).lineLimit(1)
            Spacer(minLength: 4)
            if let count {
                Text("\(count)")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 12, weight: selected ? .semibold : .regular))
        .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(selected ? Color.accentColor : Color.primary.opacity(hovered ? 0.08 : 0))
        )
        .opacity(dimmed ? 0.4 : 1)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture(perform: action)
    }
}

private struct SheetRow: View {
    let row: CheatSheet.Row
    let onCopy: () -> Void
    @State private var hovered = false

    /// Splits leading modifiers off so they can be spaced apart: "⇧⌘N" → ["⇧", "⌘", "N"].
    static func parts(_ keys: String) -> [String] {
        let modifiers: Set<Character> = ["⌃", "⌥", "⇧", "⌘"]
        let mods = keys.prefix(while: modifiers.contains)
        let rest = keys.dropFirst(mods.count)
        return mods.map(String.init) + (rest.isEmpty ? [] : [String(rest)])
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            HStack(spacing: 3) {
                ForEach(Array(Self.parts(row.keys).enumerated()), id: \.offset) { _, part in Text(part) }
            }
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.primary.opacity(0.08)))
            .frame(width: 190, alignment: .leading)
            Text(row.text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(hovered ? 0.06 : 0))
        )
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture(count: 2, perform: onCopy)
        .help("Dubbelklicka för att kopiera")
    }
}
