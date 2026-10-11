import SwiftUI

struct HelperView: View {
    @ObservedObject var model: HelperModel
    @FocusState private var searchFocused: Bool

    static let width: CGFloat = 710

    var body: some View {
        VStack(spacing: 0) {
            search
            Divider().opacity(0.6)
            // Cheat sheets cover the keyboard view, which stays in place to keep the panel's size.
            VStack(spacing: 24) {
                KeyboardView(model: model)
                resultLine
                browser
            }
            .opacity(cheatSheets ? 0 : 1)
            .allowsHitTesting(!cheatSheets)
            .accessibilityHidden(cheatSheets)
            .overlay {
                if cheatSheets { CheatSheetView(model: model) }
            }
            .padding(.horizontal, 28)
            .padding(.top, 28)
            .padding(.bottom, 22)
        }
        .frame(width: Self.width)
        // Tint over the frosted glass so it stays readable over busy backgrounds.
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.6))
        .onReceive(model.$focusRequest) { _ in searchFocused = true }
        .onChange(of: model.query) { _ in
            guard !cheatSheets else { return }
            model.select(model.isSearching ? model.results.first : nil)
        }
    }

    private var cheatSheets: Bool { model.mode == .cheatSheets }

    // MARK: Search

    private var search: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.secondary)
            TextField(cheatSheets ? "Sök i fusklappar" : "Sök tecken eller kortkommando", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 20, weight: .regular))
                .focused($searchFocused)
                .onSubmit { model.submit() }
            if !model.query.isEmpty {
                Button { model.query = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 15))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
            }
            Picker("", selection: $model.mode) {
                Image(systemName: "keyboard").tag(HelperModel.Mode.keyboard)
                Image(systemName: "list.bullet.rectangle").tag(HelperModel.Mode.cheatSheets)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("Tangentbord eller fusklappar (⇥)")
        }
        .padding(.horizontal, 22)
        .frame(height: 58)
    }

    // MARK: Result

    private var resultLine: some View {
        HStack(spacing: 16) {
            if let entry = model.selected {
                if let glyph = entry.glyph {
                    Text(glyph)
                        .font(.system(size: 30))
                        .frame(width: 54, height: 54)
                        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color.primary.opacity(0.07)))
                        .onTapGesture { model.copy(entry) }
                        .help("Klicka för att kopiera")
                }
                VStack(alignment: .leading, spacing: 6) {
                    recipe(entry)
                        .onTapGesture { if model.returnToSheets { model.playDemo(entry.steps) } }
                        .help(model.returnToSheets ? "Klicka för att spela upp igen" : "")
                    Text(model.toast ?? subtitle(entry))
                        .font(.system(size: 12))
                        .foregroundStyle(model.toast != nil ? AnyShapeStyle(Color.green) : AnyShapeStyle(.secondary))
                        .lineLimit(1)
                }
            } else {
                Text("Håll in ⌥ eller ⇧ för att utforska")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .animation(.easeOut(duration: 0.15), value: model.selected)
    }

    private func subtitle(_ entry: Entry) -> String {
        if model.returnToSheets { return entry.title + " · esc tillbaka till fusklappar" }
        if entry.isShortcut { return entry.title }
        return entry.aliases.prefix(3).joined(separator: " · ")
    }

    @ViewBuilder
    private func recipe(_ entry: Entry) -> some View {
        if entry.steps.isEmpty {
            if entry.isShortcut, let key = entry.fallbackKey {
                Cap(text: key, color: nil)
            } else {
                Text("Finns inte på din layout – klicka för att kopiera")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
        } else {
            HStack(spacing: 5) {
                ForEach(entry.steps.indices, id: \.self) { i in
                    if i > 0 {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 4)
                    }
                    let color = entry.steps.count > 1 ? StepColor.of(i) : nil
                    ForEach(Array(model.caps(for: entry.steps[i], uppercase: entry.isShortcut).enumerated()), id: \.offset) { _, cap in
                        Cap(text: cap, color: color)
                    }
                }
            }
        }
    }

    // MARK: Browser

    private var browser: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 20) {
                if model.isSearching {
                    Text(model.results.isEmpty ? "Inga träffar" : "\(model.results.count) träffar")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(HelperModel.Tab.allCases, id: \.self) { tab in
                        Button { model.tab = tab } label: {
                            Text(tab.rawValue)
                                .font(.system(size: 12, weight: model.tab == tab ? .semibold : .regular))
                                .foregroundStyle(model.tab == tab ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Spacer()
            }
            ScrollView(showsIndicators: false) {
                let results = model.results
                let chars = results.filter { !$0.isShortcut }
                let shortcuts = results.filter(\.isShortcut)
                VStack(alignment: .leading, spacing: 10) {
                    if !chars.isEmpty {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 42, maximum: 42), spacing: 6)], alignment: .leading, spacing: 6) {
                            ForEach(chars) { entry in
                                CharChip(entry: entry, selected: model.selected == entry,
                                         onSelect: { model.select(entry) }, onCopy: { model.copy(entry) })
                            }
                        }
                    }
                    if !shortcuts.isEmpty {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 4) {
                            ForEach(shortcuts) { entry in
                                ShortcutRow(title: entry.title, combo: model.compactCombo(entry),
                                            selected: model.selected == entry, onSelect: { model.select(entry) })
                            }
                        }
                    }
                }
            }
            .frame(height: 96)
        }
    }
}

/// A key cap in the result line.
private struct Cap: View {
    let text: String
    let color: Color?

    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(color.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.primary))
            .padding(.horizontal, 9)
            .frame(minWidth: 28, minHeight: 26)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(color?.opacity(0.16) ?? Color.primary.opacity(0.08))
            )
    }
}

private struct CharChip: View {
    let entry: Entry
    let selected: Bool
    let onSelect: () -> Void
    let onCopy: () -> Void
    @State private var hovered = false

    var body: some View {
        Text(entry.glyph ?? "")
            .font(.system(size: 18))
            .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .frame(width: 42, height: 42)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? Color.accentColor : Color.primary.opacity(hovered ? 0.1 : 0.05))
            )
            .opacity(entry.steps.isEmpty ? 0.4 : 1)
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
            .onTapGesture(count: 2, perform: onCopy)
            .onTapGesture(perform: onSelect)
            .help(entry.title)
    }
}

private struct ShortcutRow: View {
    let title: String
    let combo: String
    let selected: Bool
    let onSelect: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack {
            Text(title).lineLimit(1)
            Spacer(minLength: 8)
            Text(combo)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(selected ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary))
        }
        .font(.system(size: 12))
        .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(selected ? Color.accentColor : Color.primary.opacity(hovered ? 0.08 : 0.0))
        )
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture(perform: onSelect)
    }
}
