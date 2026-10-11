import SwiftUI

/// One key on the virtual keyboard. Widths are in key units.
struct KeyDef {
    enum Kind {
        case char
        case mod(Mods, primary: Bool)
        case label(String)
        /// The tall ISO return key, drawn from the top row down into the next.
        case isoReturn
        case returnTail
        case arrows
    }

    let code: UInt16?
    let width: CGFloat
    let kind: Kind

    static func c(_ code: UInt16) -> KeyDef { KeyDef(code: code, width: 1, kind: .char) }
    static func l(_ code: UInt16?, _ label: String, _ width: CGFloat) -> KeyDef { KeyDef(code: code, width: width, kind: .label(label)) }
    static func m(_ code: UInt16, _ mod: Mods, _ width: CGFloat, primary: Bool = true) -> KeyDef {
        KeyDef(code: code, width: width, kind: .mod(mod, primary: primary))
    }
}

/// ISO MacBook keyboard (Swedish physical layout: § left of 1, < left of Z).
enum MacBookKeyboard {
    static let rows: [[KeyDef]] = [
        [0x0A, 0x12, 0x13, 0x14, 0x15, 0x17, 0x16, 0x1A, 0x1C, 0x19, 0x1D, 0x1B, 0x18].map(KeyDef.c) + [.l(0x33, "⌫", 2)],
        [.l(0x30, "⇥", 1.5)] + [0x0C, 0x0D, 0x0E, 0x0F, 0x11, 0x10, 0x20, 0x22, 0x1F, 0x23, 0x21, 0x1E].map(KeyDef.c)
            + [KeyDef(code: 0x24, width: 1.5, kind: .isoReturn)],
        [.l(0x39, "⇪", 1.75)] + [0x00, 0x01, 0x02, 0x03, 0x05, 0x04, 0x26, 0x28, 0x25, 0x29, 0x27, 0x2A].map(KeyDef.c)
            + [KeyDef(code: 0x24, width: 1.25, kind: .returnTail)],
        [.m(0x38, .shift, 1.25)] + [0x32, 0x06, 0x07, 0x08, 0x09, 0x0B, 0x2D, 0x2E, 0x2B, 0x2F, 0x2C].map(KeyDef.c)
            + [.m(0x3C, .shift, 2.75, primary: false)],
        [.m(0x3F, .fn, 1), .m(0x3B, .control, 1), .m(0x3A, .option, 1), .m(0x37, .command, 1.25), .l(0x31, "", 5.5),
         .m(0x36, .command, 1.25, primary: false), .m(0x3D, .option, 1, primary: false),
         KeyDef(code: nil, width: 3, kind: .arrows)],
    ]
}

enum StepColor {
    static let all: [Color] = [.accentColor, Color(red: 1.0, green: 0.58, blue: 0.24)]
    static func of(_ step: Int) -> Color { all[min(step, all.count - 1)] }
}

struct KeyboardView: View {
    @ObservedObject var model: HelperModel
    var unit: CGFloat = 44
    var gap: CGFloat = 6

    var body: some View {
        VStack(alignment: .leading, spacing: gap) {
            ForEach(MacBookKeyboard.rows.indices, id: \.self) { r in
                HStack(spacing: gap) {
                    ForEach(MacBookKeyboard.rows[r].indices, id: \.self) { i in
                        key(MacBookKeyboard.rows[r][i])
                    }
                }
                .zIndex(r == 1 ? 1 : 0) // let the tall return key overlap the row below
            }
        }
    }

    private func width(_ units: CGFloat) -> CGFloat { units * unit - gap }

    private var steps: [Stroke] { model.selected?.steps ?? [] }
    private var focusing: Bool { !steps.isEmpty }

    /// Which step (0 or 1) uses this key, if any.
    private func stepIndex(code: UInt16?, mod: Mods? = nil, primary: Bool = true) -> Int? {
        for (i, step) in steps.enumerated() {
            if let code, step.keyCode == code { return i }
            if let mod, primary, step.mods.contains(mod) { return i }
        }
        return nil
    }

    @ViewBuilder
    private func key(_ def: KeyDef) -> some View {
        let w = width(def.width)
        switch def.kind {
        case .char:
            let code = def.code!
            let out = model.layout.output(code, model.layer)
            let base = model.layout.output(code, [])
            let step = stepIndex(code: code)
            KeyCap(label: out?.text ?? "", sub: step != nil && !model.layer.isEmpty ? base?.text : nil,
                   width: w, height: unit, step: step, dimmed: focusing && step == nil,
                   dead: out?.dead ?? false, fontSize: 17)
                .onTapGesture { model.tapKey(code) }

        case let .mod(mod, primary):
            let step = stepIndex(code: nil, mod: mod, primary: primary)
            let pressed = model.heldMods.contains(mod) || (model.heldMods.isEmpty && model.manualLayer.contains(mod) && !focusing)
            KeyCap(label: mod.symbol, width: w, height: unit, step: step, pressed: pressed,
                   dimmed: focusing && step == nil, quiet: true, fontSize: mod == .fn ? 11 : 14)
                .onTapGesture { if Mods.typing.contains(mod) { model.toggleLayer(mod) } }

        case .label(let label):
            let step = stepIndex(code: def.code)
            KeyCap(label: label, width: w, height: unit, step: step, dimmed: focusing && step == nil, quiet: true, fontSize: 14)

        case .isoReturn:
            let step = stepIndex(code: def.code)
            KeyCap(label: "↩", width: w, height: unit, step: step, dimmed: focusing && step == nil, quiet: true,
                   fontSize: 14, isoReturn: (bottomWidth: width(1.25), totalHeight: unit * 2 + gap))

        case .returnTail:
            Color.clear.frame(width: w, height: unit)

        case .arrows:
            let half = (unit - gap / 2) / 2
            HStack(alignment: .bottom, spacing: gap) {
                arrow(0x7B, "←", half)
                VStack(spacing: gap / 2) {
                    arrow(0x7E, "↑", half)
                    arrow(0x7D, "↓", half)
                }
                arrow(0x7C, "→", half)
            }
            .frame(width: w, height: unit, alignment: .bottom)
        }
    }

    private func arrow(_ code: UInt16, _ label: String, _ h: CGFloat) -> some View {
        let step = stepIndex(code: code)
        return KeyCap(label: label, width: width(1), height: h, step: step, dimmed: focusing && step == nil,
                      quiet: true, fontSize: 10)
    }
}

/// The ISO return key: wide on top, narrower below, as one shape.
private struct ISOReturnShape: Shape {
    let topHeight: CGFloat
    let bottomWidth: CGFloat
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addRoundedRect(in: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: topHeight),
                         cornerSize: CGSize(width: radius, height: radius), style: .continuous)
        p.addRoundedRect(in: CGRect(x: rect.maxX - bottomWidth, y: rect.minY, width: bottomWidth, height: rect.height),
                         cornerSize: CGSize(width: radius, height: radius), style: .continuous)
        return p
    }
}

struct KeyCap: View {
    let label: String
    var sub: String? = nil
    let width: CGFloat
    let height: CGFloat
    var step: Int? = nil
    var pressed = false
    var dimmed = false
    var dead = false
    /// Modifier/system keys: lighter label.
    var quiet = false
    var fontSize: CGFloat = 15
    var isoReturn: (bottomWidth: CGFloat, totalHeight: CGFloat)? = nil

    @State private var hovered = false

    private var highlight: Color? { step.map(StepColor.of) }

    private var fill: Color {
        if let highlight { return highlight }
        if pressed { return Color.primary.opacity(0.22) }
        return Color.primary.opacity(hovered ? 0.13 : 0.075)
    }

    private var shape: AnyShape {
        if let iso = isoReturn {
            return AnyShape(ISOReturnShape(topHeight: height, bottomWidth: iso.bottomWidth, radius: 7))
        }
        return AnyShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    var body: some View {
        ZStack(alignment: .top) {
            shape
                .fill(fill)
                .shadow(color: highlight?.opacity(0.55) ?? .clear, radius: 9)
                .frame(width: width, height: isoReturn?.totalHeight ?? height)
            ZStack {
                Text(label)
                    .font(.system(size: fontSize, weight: highlight != nil ? .semibold : .regular, design: .rounded))
                    .foregroundStyle(highlight != nil ? AnyShapeStyle(.white) : quiet ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                    .minimumScaleFactor(0.6)
                if dead {
                    Circle()
                        .fill(highlight != nil ? Color.white.opacity(0.8) : StepColor.of(1))
                        .frame(width: 4, height: 4)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 5)
                }
                if let sub, !sub.isEmpty {
                    Text(sub)
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.leading, 5).padding(.top, 3)
                }
            }
            .frame(width: width, height: height)
        }
        .frame(width: width, height: height, alignment: .top)
        .opacity(dimmed ? 0.3 : 1)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: step)
        .animation(.easeOut(duration: 0.2), value: dimmed)
        .animation(.easeOut(duration: 0.1), value: hovered)
    }
}
