import SwiftUI
import X3Kit

/// The X3 outline in a unit square, front at the top: flat-ish nose, wide front, slim waist, round rear.
struct MouseShape: Shape {
    enum Side { case top, bottom }
    var view: Side

    func path(in r: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height) }
        var path = Path()
        path.move(to: p(0.5, 0))
        path.addCurve(to: p(0.01, 0.25), control1: p(0.2, -0.005), control2: p(0.03, 0.07))
        path.addCurve(to: p(0.07, 0.6), control1: p(-0.01, 0.4), control2: p(0.07, 0.5))
        path.addCurve(to: p(0.5, 1), control1: p(0.05, 0.84), control2: p(0.2, 1))
        path.addCurve(to: p(0.93, 0.6), control1: p(0.8, 1), control2: p(0.95, 0.84))
        path.addCurve(to: p(0.99, 0.25), control1: p(0.93, 0.5), control2: p(1.01, 0.4))
        path.addCurve(to: p(0.5, 0), control1: p(0.97, 0.07), control2: p(0.8, -0.005))
        path.closeSubpath()
        return path
    }
}

/// Drawn artwork of the X3, or photos when the app bundle ships x3-top.png and x3-bottom.png.
struct MouseArt: View {
    let side: MouseShape.Side
    var accent: Color = .blue
    var glow = false

    private static let body = Color(red: 0.075, green: 0.078, blue: 0.09)
    static func photo(_ side: MouseShape.Side) -> NSImage? {
        Bundle.main.image(forResource: side == .top ? "x3-top" : "x3-bottom")
    }

    var body: some View {
        if let image = Self.photo(side) {
            Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                .shadow(color: glow ? accent.opacity(0.35) : .clear, radius: 18)
        } else {
            Canvas { ctx, size in draw(&ctx, CGRect(origin: .zero, size: size)) }
                .aspectRatio(0.62, contentMode: .fit)
                .shadow(color: glow ? accent.opacity(0.35) : .clear, radius: 18)
        }
    }

    private func draw(_ ctx: inout GraphicsContext, _ r: CGRect) {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height) }
        func rect(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) -> CGRect {
            CGRect(x: r.minX + x0 * r.width, y: r.minY + y0 * r.height, width: (x1 - x0) * r.width, height: (y1 - y0) * r.height)
        }
        let outline = MouseShape(view: side).path(in: r)
        ctx.fill(outline, with: .color(Self.body))
        ctx.fill(outline, with: .radialGradient(Gradient(colors: [.white.opacity(0.09), .clear]),
                                                 center: p(0.42, side == .top ? 0.55 : 0.5), startRadius: 0, endRadius: r.width * 0.75))
        ctx.stroke(outline, with: .color(.white.opacity(0.18)), lineWidth: 1)
        let seam = Color.black.opacity(0.85)
        let edge = Color.white.opacity(0.12)

        if side == .top {
            var split = Path()
            split.move(to: p(0.5, 0)); split.addLine(to: p(0.5, 0.1))
            split.move(to: p(0.5, 0.37)); split.addLine(to: p(0.5, 0.41))
            split.move(to: p(0.03, 0.41)); split.addQuadCurve(to: p(0.97, 0.41), control: p(0.5, 0.445))
            ctx.stroke(split, with: .color(seam), lineWidth: 2)
            ctx.stroke(split.offsetBy(dx: 0, dy: 1), with: .color(edge), lineWidth: 0.6)

            let wheelWell = Path(roundedRect: rect(0.41, 0.09, 0.59, 0.28), cornerRadius: r.width * 0.06)
            ctx.fill(wheelWell, with: .color(.black))
            let wheel = Path(roundedRect: rect(0.445, 0.105, 0.555, 0.265), cornerRadius: r.width * 0.05)
            ctx.fill(wheel, with: .linearGradient(Gradient(colors: [Color(white: 0.2), Color(white: 0.55), Color(white: 0.2)]),
                                                  startPoint: p(0.445, 0), endPoint: p(0.555, 0)))
            for i in 0..<9 {
                let y = 0.115 + CGFloat(i) * 0.017
                var rib = Path(); rib.move(to: p(0.45, y)); rib.addLine(to: p(0.55, y))
                ctx.stroke(rib, with: .color(.black.opacity(0.45)), lineWidth: 0.8)
            }
            let pill = Path(roundedRect: rect(0.43, 0.295, 0.57, 0.365), cornerRadius: r.width * 0.04)
            ctx.fill(pill, with: .color(Color(white: 0.06)))
            ctx.stroke(pill, with: .color(edge), lineWidth: 0.8)
            let led = Path(roundedRect: rect(0.488, 0.315, 0.512, 0.345), cornerRadius: r.width * 0.012)
            ctx.fill(led, with: .color(Color(red: 0.25, green: 0.7, blue: 1)))

            for (y0, y1) in [(0.3, 0.39), (0.41, 0.52)] {
                let b = Path(roundedRect: rect(-0.015, y0, 0.035, y1), cornerRadius: r.width * 0.02)
                ctx.fill(b, with: .color(Color(white: 0.1)))
                ctx.stroke(b, with: .color(edge), lineWidth: 0.8)
            }
        } else {
            let skate = Color(white: 0.2)
            var front = Path()
            front.move(to: p(0.12, 0.1)); front.addQuadCurve(to: p(0.88, 0.1), control: p(0.5, -0.02))
            ctx.stroke(front, with: .color(skate), style: StrokeStyle(lineWidth: r.width * 0.07, lineCap: .round))
            var rear = Path()
            rear.move(to: p(0.16, 0.86)); rear.addQuadCurve(to: p(0.84, 0.86), control: p(0.5, 1.0))
            ctx.stroke(rear, with: .color(skate), style: StrokeStyle(lineWidth: r.width * 0.07, lineCap: .round))
            for x in [0.1, 0.9] {
                var s = Path(); s.move(to: p(x, 0.48)); s.addLine(to: p(x, 0.58))
                ctx.stroke(s, with: .color(skate), style: StrokeStyle(lineWidth: r.width * 0.05, lineCap: .round))
            }
            let slot = Path(roundedRect: rect(0.36, 0.2, 0.64, 0.235), cornerRadius: r.width * 0.02)
            ctx.fill(slot, with: .color(.black))
            ctx.fill(Path(roundedRect: rect(0.47, 0.205, 0.53, 0.23), cornerRadius: r.width * 0.01), with: .color(Color(white: 0.45)))
            ctx.draw(Text("2.4G   OFF   BT").font(.system(size: max(5, r.width * 0.045), weight: .semibold)).foregroundStyle(Color(white: 0.5)),
                     at: p(0.5, 0.175))
            let sensorPad = Path(roundedRect: rect(0.4, 0.42, 0.6, 0.56), cornerRadius: r.width * 0.03)
            ctx.fill(sensorPad, with: .color(Color(white: 0.16)))
            ctx.fill(Path(ellipseIn: rect(0.46, 0.46, 0.54, 0.52)), with: .color(.black))
            let button = Path(roundedRect: rect(0.44, 0.61, 0.56, 0.665), cornerRadius: r.width * 0.02)
            ctx.fill(button, with: .color(Color(white: 0.12)))
            ctx.stroke(button, with: .color(accent), lineWidth: 1.2)
            ctx.fill(Path(ellipseIn: rect(0.27, 0.38, 0.33, 0.415)), with: .color(accent))
            ctx.fill(Path(ellipseIn: rect(0.67, 0.38, 0.73, 0.415)), with: .color(Color(red: 0.25, green: 0.7, blue: 1)))
            ctx.draw(Text("DPI").font(.system(size: max(5, r.width * 0.04))).foregroundStyle(Color(white: 0.45)), at: p(0.3, 0.44))
            ctx.draw(Text("MODE").font(.system(size: max(5, r.width * 0.04))).foregroundStyle(Color(white: 0.45)), at: p(0.7, 0.44))
        }
    }
}

private struct Callout: Identifiable {
    let id: String
    let title: String
    let action: String
    let target: CGPoint
    let leftSide: Bool
    let row: Int
    var fixed = false
    var slot: Int? = nil
}

/// A menu of the actions a slot can take, with the current one ticked.
struct ActionMenu<Label: View>: View {
    let slot: Int
    let current: UInt8?
    let assign: (Int, UInt8) -> Void
    @ViewBuilder var label: Label

    var body: some View {
        Menu {
            ForEach(ButtonMap.assignable, id: \.self) { a in
                Button {
                    if a != current { assign(slot, a) }
                } label: {
                    if a == current { SwiftUI.Label(ButtonSlot.names[a] ?? "", systemImage: "checkmark") } else { Text(ButtonSlot.names[a] ?? "") }
                }
                if a == 0x0a || a == 0x10 || a == 0x1c { Divider() }
            }
        } label: { label }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .help("Change what this button does")
    }
}

private struct MouseDiagram: View {
    let side: MouseShape.Side
    let callouts: [Callout]
    let accent: Color
    let current: (Int) -> UInt8?
    let assign: (Int, UInt8) -> Void

    private let size = CGSize(width: 440, height: 300)
    private let mouse = CGRect(x: 145, y: 25, width: 150, height: 242)

    var body: some View {
        ZStack(alignment: .topLeading) {
            MouseArt(side: side, accent: accent)
                .frame(width: mouse.width, height: mouse.height)
                .offset(x: mouse.minX, y: mouse.minY)
            Canvas { ctx, _ in
                for c in callouts {
                    let anchor = CGPoint(x: c.leftSide ? 132 : size.width - 132, y: labelY(c.row) + 18)
                    let target = CGPoint(x: mouse.minX + c.target.x * mouse.width, y: mouse.minY + c.target.y * mouse.height)
                    var line = Path()
                    line.move(to: anchor)
                    line.addLine(to: target)
                    ctx.stroke(line, with: .color(.white.opacity(0.2)), lineWidth: 0.75)
                    ctx.fill(Path(ellipseIn: CGRect(x: target.x - 2.5, y: target.y - 2.5, width: 5, height: 5)), with: .color(accent))
                }
            }
            ForEach(callouts) { c in
                label(c).frame(width: 128, alignment: c.leftSide ? .trailing : .leading)
                    .offset(x: c.leftSide ? 0 : size.width - 128, y: labelY(c.row))
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private func labelY(_ row: Int) -> CGFloat { 24 + CGFloat(row) * 62 }

    @ViewBuilder
    private func label(_ c: Callout) -> some View {
        if let slot = c.slot, !c.fixed {
            ActionMenu(slot: slot, current: current(slot), assign: assign) { box(c, editable: true) }
        } else {
            box(c, editable: false)
        }
    }

    private func box(_ c: Callout, editable: Bool) -> some View {
        VStack(alignment: c.leftSide ? .trailing : .leading, spacing: 2) {
            Text(c.title.uppercased()).font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Text(c.action).font(.callout.weight(.semibold)).foregroundStyle(c.fixed ? .secondary : .primary)
                    .lineLimit(2).multilineTextAlignment(c.leftSide ? .trailing : .leading)
                if editable { Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(accent) }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Palette.well, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(editable ? accent.opacity(0.35) : Palette.stroke))
        .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct MouseMapCard: View {
    let slots: [ButtonSlot]
    let accent: Color
    let assign: (Int, UInt8) -> Void

    private func code(_ slot: Int) -> UInt8? { slots.first { $0.slot == slot }?.action ?? 0x01 }

    private func action(_ slot: Int) -> String {
        slots.first { $0.slot == slot }?.actionName ?? "Not assigned"
    }

    private static let placed: Set<Int> = [1, 2, 3, 4, 5, 7, 8, 9]

    var body: some View {
        Card(title: "Buttons", icon: "computermouse", accessory: { Text("Click a button to change it") }) {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 4) {
                    Text("TOP").font(.caption2.weight(.bold)).tracking(1.2).foregroundStyle(.tertiary)
                    MouseDiagram(side: .top, callouts: [
                        Callout(id: "left", title: "Left button", action: action(1), target: CGPoint(x: 0.27, y: 0.2), leftSide: true, row: 0, slot: 1),
                        Callout(id: "fwd", title: "Side, front", action: action(7), target: CGPoint(x: 0.01, y: 0.345), leftSide: true, row: 1, slot: 7),
                        Callout(id: "back", title: "Side, rear", action: action(8), target: CGPoint(x: 0.01, y: 0.465), leftSide: true, row: 2, slot: 8),
                        Callout(id: "right", title: "Right button", action: action(2), target: CGPoint(x: 0.73, y: 0.2), leftSide: false, row: 0, slot: 2),
                        Callout(id: "wheel", title: "Wheel click", action: action(3), target: CGPoint(x: 0.56, y: 0.19), leftSide: false, row: 1, slot: 3),
                        Callout(id: "led", title: "Battery light", action: "Blinks when low or charging", target: CGPoint(x: 0.51, y: 0.33), leftSide: false, row: 2, fixed: true),
                    ], accent: accent, current: code, assign: assign)
                }
                VStack(spacing: 4) {
                    Text("UNDERSIDE").font(.caption2.weight(.bold)).tracking(1.2).foregroundStyle(.tertiary)
                    MouseDiagram(side: .bottom, callouts: [
                        Callout(id: "dpi", title: "DPI button", action: action(4), target: CGPoint(x: 0.44, y: 0.64), leftSide: true, row: 3, slot: 4),
                        Callout(id: "dpiled", title: "DPI light", action: "Shows the stage colour", target: CGPoint(x: 0.3, y: 0.4), leftSide: true, row: 1, fixed: true),
                        Callout(id: "mode", title: "Mode switch", action: "2.4G, off or Bluetooth", target: CGPoint(x: 0.62, y: 0.217), leftSide: false, row: 0, fixed: true),
                        Callout(id: "modeled", title: "Mode light", action: "Shows the connection", target: CGPoint(x: 0.7, y: 0.4), leftSide: false, row: 1, fixed: true),
                    ], accent: accent, current: code, assign: assign)
                }
            }
            .frame(maxWidth: .infinity)
            let others = slots.filter { !Self.placed.contains($0.slot) && $0.action != 0x3c }
            HStack(spacing: 10) {
                ForEach(others, id: \.slot) { s in
                    ActionMenu(slot: s.slot, current: s.action, assign: assign) {
                        HStack(spacing: 6) {
                            Text(otherTitle(s.slot)).foregroundStyle(.secondary)
                            Text(s.actionName).fontWeight(.semibold)
                            Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(accent)
                        }
                        .font(.callout)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Palette.well, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(accent.opacity(0.35)))
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .fixedSize()
                }
                Spacer()
            }
            Text("Every change is read back from the mouse. The mode key can't be changed, and one button always keeps left click.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func otherTitle(_ slot: Int) -> String {
        switch slot {
        case 17: return "Wheel down"
        case 18: return "Wheel up"
        default: return "Slot \(slot)"
        }
    }
}
