import AppKit

/// A user-written cheat sheet, read from a text file in ~/.config/tangent.
///
/// Format:
///
///     # Vim                    ← sheet title (defaults to the file name)
///     ## Rörelse               ← section
///     gg       Början av filen ← keys, two or more spaces (or a tab), description
struct CheatSheet: Identifiable, Equatable {
    struct Row: Identifiable, Equatable {
        let id: Int
        let keys: String
        let text: String
    }

    struct Section: Identifiable, Equatable {
        let id: Int
        let title: String
        var rows: [Row]
    }

    /// File path.
    let id: String
    let title: String
    var sections: [Section]

    var rowCount: Int { sections.reduce(0) { $0 + $1.rows.count } }
}

enum CheatSheets {
    static let extensions: Set<String> = ["md", "txt"]

    static var directory: URL {
        let config = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config")
        return config.appendingPathComponent("tangent", isDirectory: true)
    }

    /// Every sheet in the config directory, sorted by title.
    static func load() -> [CheatSheet] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { extensions.contains($0.pathExtension.lowercased()) }
            .compactMap { url in
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                return parse(text, id: url.path, fallbackTitle: url.deletingPathExtension().lastPathComponent)
            }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    static func parse(_ text: String, id: String, fallbackTitle: String) -> CheatSheet {
        var title: String?
        var sections: [CheatSheet.Section] = []
        var rowID = 0

        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("## ") {
                sections.append(.init(id: sections.count, title: String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces), rows: []))
                continue
            }
            if line.hasPrefix("# ") {
                if title == nil { title = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces) }
                continue
            }
            // Keys and description are separated by a tab or at least two spaces.
            let keys: String
            let description: String
            if let range = line.range(of: #"\t|\s{2,}"#, options: .regularExpression) {
                keys = String(line[..<range.lowerBound])
                description = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            } else {
                keys = line
                description = ""
            }
            if sections.isEmpty { sections.append(.init(id: 0, title: "", rows: [])) }
            sections[sections.count - 1].rows.append(.init(id: rowID, keys: keys, text: description))
            rowID += 1
        }
        return CheatSheet(id: id, title: title ?? fallbackTitle, sections: sections.filter { !$0.rows.isEmpty })
    }

    /// Rows where every word of the query appears in the sheet title, section, keys or description.
    static func search(_ sheets: [CheatSheet], _ query: String) -> [CheatSheet] {
        let fold: (String) -> String = { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
        let words = fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return sheets }
        return sheets.compactMap { sheet in
            var hit = sheet
            hit.sections = sheet.sections.compactMap { section in
                var s = section
                s.rows = section.rows.filter { row in
                    let haystack = fold("\(sheet.title) \(section.title) \(row.keys) \(row.text)")
                    return words.allSatisfy(haystack.contains)
                }
                return s.rows.isEmpty ? nil : s
            }
            return hit.sections.isEmpty ? nil : hit
        }
    }

    /// Writes an example sheet so there's something to start from. Returns its path.
    @discardableResult
    static func createExample() throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("vim.md")
        if !FileManager.default.fileExists(atPath: url.path) {
            try example.write(to: url, atomically: true, encoding: .utf8)
        }
        return url
    }

    static func openDirectory() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }

    private static let example = """
        # Vim

        ## Rörelse
        h j k l      Vänster, ner, upp, höger
        w / b        Nästa / föregående ord
        0 / $        Början / slutet av raden
        gg / G       Början / slutet av filen

        ## Redigera
        i            Skriv före markören
        a            Skriv efter markören
        dd           Klipp ut raden
        yy           Kopiera raden
        p            Klistra in
        u            Ångra
        ⌃r           Gör om

        ## Arkiv
        :w           Spara
        :q           Avsluta
        :q!          Avsluta utan att spara

        """
}
