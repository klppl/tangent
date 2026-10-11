import Foundation

/// A character to explain. How to type it is computed from the live keyboard layout.
struct SymbolDef {
    let char: String
    let category: String
    let names: [String]
}

enum KeySpec {
    /// The key that types this character without modifiers (layout-aware, e.g. "c" or "+").
    case char(String)
    /// A fixed physical key (esc, arrows, space …).
    case code(UInt16)
}

struct ShortcutDef {
    let title: String
    let category: String
    let mods: Mods
    let key: KeySpec
    var aliases: [String] = []
    /// Optional second step, e.g. ⇧⌘4 then space.
    var then: (mods: Mods, key: KeySpec)? = nil
}

enum Catalog {
    static let symbolCategories = ["Programmering", "Valuta", "Bokstäver", "Matematik", "Typografi"]
    static let shortcutCategories = ["Skärmdumpar", "System", "Fönster & program", "Redigera text", "Flytta i text", "Finder"]

    private static func s(_ char: String, _ category: String, _ names: String...) -> SymbolDef {
        SymbolDef(char: char, category: category, names: names)
    }

    static let symbols: [SymbolDef] = [
        // Programmering
        s("@", "Programmering", "snabel-a", "at-tecken", "alfakrull", "at", "e-post krumelur", "at sign"),
        s("$", "Programmering", "dollartecken", "dollar sign"),
        s("(", "Programmering", "vänsterparentes", "parentes", "halvmåne", "round bracket"),
        s(")", "Programmering", "högerparentes", "parentes", "halvmåne", "round bracket"),
        s("[", "Programmering", "vänster hakparentes", "hakparentes", "square bracket", "box bracket"),
        s("]", "Programmering", "höger hakparentes", "hakparentes", "square bracket", "box bracket"),
        s("{", "Programmering", "vänster måsvinge", "måsvinge", "krullparentes", "curly brace", "curly bracket"),
        s("}", "Programmering", "höger måsvinge", "måsvinge", "krullparentes", "curly brace", "curly bracket"),
        s("/", "Programmering", "snedstreck", "slash"),
        s("\\", "Programmering", "bakåtsnedstreck", "backslash"),
        s("|", "Programmering", "lodstreck", "pipe", "vertical bar"),
        s("~", "Programmering", "tilde", "titulus", "vågen", "wave"),
        s("^", "Programmering", "cirkumflex", "caret", "hatt"),
        s("`", "Programmering", "grav accent", "backtick", "bakåtfnutt"),
        s("'", "Programmering", "apostrof", "enkelfnutt", "single quote"),
        s("\"", "Programmering", "citattecken", "dubbelfnutt", "double quote"),
        s("#", "Programmering", "brädgård", "hashtag", "nummertecken", "staket", "hash"),
        s("%", "Programmering", "procent", "percent"),
        s("&", "Programmering", "och-tecken", "et-tecken", "ampersand"),
        s("*", "Programmering", "asterisk", "stjärna"),
        s("=", "Programmering", "likhetstecken", "lika med", "equals"),
        s("+", "Programmering", "plus"),
        s("_", "Programmering", "understreck", "underscore"),
        s(";", "Programmering", "semikolon"),
        s(":", "Programmering", "kolon"),
        s("?", "Programmering", "frågetecken", "question mark"),
        s("!", "Programmering", "utropstecken", "exclamation mark"),

        // Valuta
        s("€", "Valuta", "euro", "eurotecken", "euro symbol"),
        s("£", "Valuta", "pund", "brittiskt pund", "pound sterling"),
        s("¥", "Valuta", "yen"),
        s("¢", "Valuta", "cent"),

        // Bokstäver
        s("ø", "Bokstäver", "norskt ö", "danskt ö", "o med snedstreck"),
        s("Ø", "Bokstäver", "norskt Ö", "danskt Ö", "stort ø"),
        s("æ", "Bokstäver", "norskt ä", "danskt ä", "ae"),
        s("Æ", "Bokstäver", "norskt Ä", "danskt Ä", "stort æ"),
        s("ü", "Bokstäver", "tyskt y", "u med trema", "umlaut"),
        s("Ü", "Bokstäver", "stort ü", "umlaut"),
        s("ß", "Bokstäver", "dubbel-s", "skarpt s", "eszett", "tyskt s"),
        s("é", "Bokstäver", "e med accent", "akut accent", "café"),
        s("è", "Bokstäver", "e med grav accent"),
        s("ê", "Bokstäver", "e med cirkumflex"),
        s("á", "Bokstäver", "a med accent"),
        s("à", "Bokstäver", "a med grav accent"),
        s("ñ", "Bokstäver", "spanskt n", "n med tilde"),
        s("ç", "Bokstäver", "c med cedilj", "franskt c"),

        // Matematik
        s("√", "Matematik", "roten ur", "kvadratrot", "square root"),
        s("÷", "Matematik", "division", "delat med", "divided by"),
        s("±", "Matematik", "plus minus"),
        s("≈", "Matematik", "ungefär lika med", "approximately"),
        s("≠", "Matematik", "inte lika med", "not equal"),
        s("≤", "Matematik", "mindre än eller lika med"),
        s("≥", "Matematik", "större än eller lika med"),
        s("∞", "Matematik", "oändligheten", "infinity"),
        s("π", "Matematik", "pi"),
        s("°", "Matematik", "grader", "gradtecken", "degree"),
        s("µ", "Matematik", "my", "mikro", "micro"),
        s("∑", "Matematik", "summa", "sigma"),
        s("∆", "Matematik", "delta", "triangel"),
        s("∫", "Matematik", "integral"),
        s("‰", "Matematik", "promille", "per mille"),

        // Typografi
        s("–", "Typografi", "tankstreck", "kort tankstreck", "en dash"),
        s("—", "Typografi", "långt tankstreck", "em dash"),
        s("…", "Typografi", "tre punkter", "ellips", "ellipsis"),
        s("«", "Typografi", "gåsögon", "vinkelcitat", "guillemet"),
        s("»", "Typografi", "gåsögon", "vinkelcitat", "guillemet"),
        s("”", "Typografi", "svenskt citattecken", "typografiskt citattecken", "smart quote"),
        s("’", "Typografi", "typografisk apostrof", "smart apostrophe"),
        s("“", "Typografi", "engelskt citattecken", "curly quote", "smart quote"),
        s("‘", "Typografi", "engelskt enkelcitat", "curly single quote"),
        s("\u{F8FF}", "Typografi", "äpple", "apple-logga", "äppellogga", "apple logo"),
        s("•", "Typografi", "punkt", "bullet", "punktlista"),
        s("§", "Typografi", "paragraf", "paragraftecken", "section sign"),
        s("¶", "Typografi", "stycketecken", "pilcrow"),
        s("©", "Typografi", "copyright", "upphovsrätt"),
        s("®", "Typografi", "registrerat varumärke", "registered"),
        s("™", "Typografi", "varumärke", "trademark"),
        s("†", "Typografi", "kors", "dagger", "död"),
        s("¿", "Typografi", "upp-och-ned frågetecken", "spanskt frågetecken"),
        s("¡", "Typografi", "upp-och-ned utropstecken", "spanskt utropstecken"),
    ]

    static let shortcuts: [ShortcutDef] = [
        // Skärmdumpar
        .init(title: "Skärmdump av hela skärmen", category: "Skärmdumpar", mods: [.shift, .command], key: .char("3"), aliases: ["screenshot", "printscreen"]),
        .init(title: "Skärmdump av markerat område", category: "Skärmdumpar", mods: [.shift, .command], key: .char("4"), aliases: ["screenshot", "klippverktyg", "snipping tool"]),
        .init(title: "Skärmdumpverktyg & skärminspelning", category: "Skärmdumpar", mods: [.shift, .command], key: .char("5"), aliases: ["screenshot", "spela in skärmen", "screen recording"]),
        .init(title: "Skärmdump av ett fönster", category: "Skärmdumpar", mods: [.shift, .command], key: .char("4"), aliases: ["screenshot", "fönster", "window"], then: ([], .code(0x31))),
        .init(title: "Skärmdump av område till urklipp", category: "Skärmdumpar", mods: [.control, .shift, .command], key: .char("4"), aliases: ["screenshot", "kopiera"]),

        // System
        .init(title: "Tvångsavsluta program", category: "System", mods: [.option, .command], key: .code(0x35), aliases: ["force quit", "ctrl alt delete", "aktivitetshanteraren", "task manager", "hängt sig"]),
        .init(title: "Lås skärmen", category: "System", mods: [.control, .command], key: .char("q"), aliases: ["lock screen", "windows l"]),
        .init(title: "Spotlight-sökning", category: "System", mods: [.command], key: .code(0x31), aliases: ["sök", "search"]),
        .init(title: "Emoji och symboler", category: "System", mods: [.control, .command], key: .code(0x31), aliases: ["emoji", "smiley", "tecken", "globe"]),
        .init(title: "Emoji (fn/🌐-tangenten)", category: "System", mods: [.fn], key: .char("e"), aliases: ["emoji", "smiley", "globe"]),
        .init(title: "Diktering (tala in text)", category: "System", mods: [], key: .code(0x3F), aliases: ["dictation", "röst", "prata"], then: ([], .code(0x3F))),
        .init(title: "Byt tangentbordsspråk", category: "System", mods: [.control], key: .code(0x31), aliases: ["input source", "layout", "språk", "engelskt tangentbord"]),
        .init(title: "Logga ut", category: "System", mods: [.shift, .command], key: .char("q"), aliases: ["log out"]),
        .init(title: "Växla mellan program", category: "System", mods: [.command], key: .code(0x30), aliases: ["alt tab", "byt program", "app switcher"]),
        .init(title: "Växla mellan fönster i programmet", category: "System", mods: [.command], key: .code(0x32), aliases: ["byt fönster"]),
        .init(title: "Mission Control", category: "System", mods: [.control], key: .code(0x7E), aliases: ["alla fönster", "skrivbord"]),
        .init(title: "Programmets alla fönster", category: "System", mods: [.control], key: .code(0x7D), aliases: ["app exposé"]),

        // Fönster & program
        .init(title: "Avsluta program", category: "Fönster & program", mods: [.command], key: .char("q"), aliases: ["quit", "stäng program", "alt f4"]),
        .init(title: "Stäng fönster / flik", category: "Fönster & program", mods: [.command], key: .char("w"), aliases: ["close"]),
        .init(title: "Stäng alla fönster", category: "Fönster & program", mods: [.option, .command], key: .char("w"), aliases: ["close all"]),
        .init(title: "Minimera fönster", category: "Fönster & program", mods: [.command], key: .char("m"), aliases: ["minimize"]),
        .init(title: "Göm program", category: "Fönster & program", mods: [.command], key: .char("h"), aliases: ["hide", "dölj"]),
        .init(title: "Göm alla andra program", category: "Fönster & program", mods: [.option, .command], key: .char("h"), aliases: ["hide others"]),
        .init(title: "Helskärm", category: "Fönster & program", mods: [.control, .command], key: .char("f"), aliases: ["fullscreen", "fullskärm"]),
        .init(title: "Inställningar", category: "Fönster & program", mods: [.command], key: .char(","), aliases: ["settings", "preferences"]),
        .init(title: "Ny flik", category: "Fönster & program", mods: [.command], key: .char("t"), aliases: ["new tab"]),
        .init(title: "Nästa flik", category: "Fönster & program", mods: [.control], key: .code(0x30), aliases: ["next tab", "byt flik"]),
        .init(title: "Föregående flik", category: "Fönster & program", mods: [.control, .shift], key: .code(0x30), aliases: ["previous tab", "byt flik"]),
        .init(title: "Gå till adressfältet", category: "Fönster & program", mods: [.command], key: .char("l"), aliases: ["address bar", "url", "webbadress"]),
        .init(title: "Öppna stängd flik igen", category: "Fönster & program", mods: [.shift, .command], key: .char("t"), aliases: ["reopen tab", "ångra stängd flik"]),
        .init(title: "Ladda om sidan", category: "Fönster & program", mods: [.command], key: .char("r"), aliases: ["refresh", "uppdatera", "f5"]),
        .init(title: "Zooma in", category: "Fönster & program", mods: [.command], key: .char("+"), aliases: ["förstora", "zoom"]),
        .init(title: "Zooma ut", category: "Fönster & program", mods: [.command], key: .char("-"), aliases: ["förminska", "zoom"]),
        .init(title: "Återställ zoom", category: "Fönster & program", mods: [.command], key: .char("0"), aliases: ["zoom"]),

        // Redigera text
        .init(title: "Kopiera", category: "Redigera text", mods: [.command], key: .char("c"), aliases: ["copy", "ctrl c"]),
        .init(title: "Klipp ut", category: "Redigera text", mods: [.command], key: .char("x"), aliases: ["cut", "ctrl x"]),
        .init(title: "Klistra in", category: "Redigera text", mods: [.command], key: .char("v"), aliases: ["paste", "ctrl v"]),
        .init(title: "Klistra in utan formatering", category: "Redigera text", mods: [.option, .shift, .command], key: .char("v"), aliases: ["paste plain text", "ren text"]),
        .init(title: "Ångra", category: "Redigera text", mods: [.command], key: .char("z"), aliases: ["undo", "ctrl z"]),
        .init(title: "Gör om", category: "Redigera text", mods: [.shift, .command], key: .char("z"), aliases: ["redo", "ctrl y"]),
        .init(title: "Markera allt", category: "Redigera text", mods: [.command], key: .char("a"), aliases: ["select all"]),
        .init(title: "Sök", category: "Redigera text", mods: [.command], key: .char("f"), aliases: ["find", "hitta"]),
        .init(title: "Hitta nästa", category: "Redigera text", mods: [.command], key: .char("g"), aliases: ["find next", "sök igen"]),
        .init(title: "Spara", category: "Redigera text", mods: [.command], key: .char("s"), aliases: ["save"]),
        .init(title: "Skriv ut", category: "Redigera text", mods: [.command], key: .char("p"), aliases: ["print"]),

        // Flytta i text
        .init(title: "Radera framåt (Delete)", category: "Flytta i text", mods: [.fn], key: .code(0x33), aliases: ["delete", "del"]),
        .init(title: "Radera helt ord", category: "Flytta i text", mods: [.option], key: .code(0x33), aliases: ["ctrl backspace"]),
        .init(title: "Radera hela raden bakåt", category: "Flytta i text", mods: [.command], key: .code(0x33), aliases: ["delete line"]),
        .init(title: "Markera ett ord i taget", category: "Flytta i text", mods: [.option, .shift], key: .code(0x7C), aliases: ["select word", "ctrl shift pil"]),
        .init(title: "Hoppa ett ord bakåt", category: "Flytta i text", mods: [.option], key: .code(0x7B), aliases: ["ctrl vänsterpil"]),
        .init(title: "Hoppa ett ord framåt", category: "Flytta i text", mods: [.option], key: .code(0x7C), aliases: ["ctrl högerpil"]),
        .init(title: "Början av raden", category: "Flytta i text", mods: [.command], key: .code(0x7B), aliases: ["home", "radstart"]),
        .init(title: "Slutet av raden", category: "Flytta i text", mods: [.command], key: .code(0x7C), aliases: ["end", "radslut"]),
        .init(title: "Home (överst på sidan)", category: "Flytta i text", mods: [.fn], key: .code(0x7B), aliases: ["home", "toppen"]),
        .init(title: "End (längst ner på sidan)", category: "Flytta i text", mods: [.fn], key: .code(0x7C), aliases: ["end", "botten"]),
        .init(title: "Början av dokumentet", category: "Flytta i text", mods: [.command], key: .code(0x7E), aliases: ["ctrl home"]),
        .init(title: "Slutet av dokumentet", category: "Flytta i text", mods: [.command], key: .code(0x7D), aliases: ["ctrl end"]),
        .init(title: "Page Up", category: "Flytta i text", mods: [.fn], key: .code(0x7E), aliases: ["sida upp"]),
        .init(title: "Page Down", category: "Flytta i text", mods: [.fn], key: .code(0x7D), aliases: ["sida ner"]),

        // Finder
        .init(title: "Visa/dölj dolda filer", category: "Finder", mods: [.shift, .command], key: .char("."), aliases: ["hidden files", "gömda filer"]),
        .init(title: "Flytta till papperskorgen", category: "Finder", mods: [.command], key: .code(0x33), aliases: ["ta bort fil", "delete file"]),
        .init(title: "Radera direkt (utan papperskorg)", category: "Finder", mods: [.option, .command], key: .code(0x33), aliases: ["shift delete", "permanent"]),
        .init(title: "Snabbtitt", category: "Finder", mods: [], key: .code(0x31), aliases: ["quick look", "förhandsvisa"]),
        .init(title: "Byt namn", category: "Finder", mods: [], key: .code(0x24), aliases: ["rename", "f2"]),
        .init(title: "Flytta fil (efter ⌘C)", category: "Finder", mods: [.option, .command], key: .char("v"), aliases: ["klipp ut fil", "cut file", "move"]),
        .init(title: "Duplicera", category: "Finder", mods: [.command], key: .char("d"), aliases: ["duplicate", "kopia"]),
        .init(title: "Sök bland filer", category: "Finder", mods: [.option, .command], key: .code(0x31), aliases: ["finder search", "hitta fil"]),
        .init(title: "Gå till mapp", category: "Finder", mods: [.shift, .command], key: .char("g"), aliases: ["go to folder", "sökväg"]),
        .init(title: "Ny mapp", category: "Finder", mods: [.shift, .command], key: .char("n"), aliases: ["new folder"]),
        .init(title: "Visa info", category: "Finder", mods: [.command], key: .char("i"), aliases: ["egenskaper", "properties", "get info"]),
    ]
}
