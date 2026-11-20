import SwiftUI
import X3Kit

/// The X3 outline in a unit square, front at the top.
struct MouseShape: Shape {
    enum Side { case top, bottom }
    var view: Side

    func path(in r: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height) }
        var path = Path()
        path.move(to: p(0.5, 0))
        path.addCurve(to: p(0.02, 0.42), control1: p(0.16, 0), control2: p(0.02, 0.16))
        path.addCurve(to: p(0.5, 1), control1: p(0.02, 0.8), control2: p(0.18, 1))
        path.addCurve(to: p(0.98, 0.42), control1: p(0.82, 1), control2: p(0.98, 0.8))
        path.addCurve(to: p(0.5, 0), control1: p(0.98, 0.16), control2: p(0.84, 0))
        path.closeSubpath()
        return path
    }

    /// Button split, wheel and battery light on top.
    static func details(width w: CGFloat, height h: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: w * 0.5, y: 0))
        path.addLine(to: CGPoint(x: w * 0.5, y: h * 0.1))
        path.move(to: CGPoint(x: w * 0.5, y: h * 0.3))
        path.addLine(to: CGPoint(x: w * 0.5, y: h * 0.38))
        path.move(to: CGPoint(x: w * 0.03, y: h * 0.38))
        path.addQuadCurve(to: CGPoint(x: w * 0.97, y: h * 0.38), control: CGPoint(x: w * 0.5, y: h * 0.44))
        path.addRoundedRect(in: CGRect(x: w * 0.43, y: h * 0.1, width: w * 0.14, height: h * 0.2), cornerSize: CGSize(width: w * 0.07, height: w * 0.07))
        path.addEllipse(in: CGRect(x: w * 0.47, y: h * 0.47, width: w * 0.06, height: w * 0.06))
        return path
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
}

private struct MouseDiagram: View {
    let side: MouseShape.Side
    let callouts: [Callout]
    let accent: Color

    private let size = CGSize(width: 440, height: 300)
    private let mouse = CGRect(x: 160, y: 30, width: 120, height: 240)

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { ctx, _ in
                let outline = MouseShape(view: side).path(in: mouse)
                ctx.fill(outline, with: .color(Palette.well))
                ctx.stroke(outline, with: .color(.white.opacity(0.35)), lineWidth: 1.5)
                if side == .top {
                    ctx.stroke(MouseShape.details(width: mouse.width, height: mouse.height).offsetBy(dx: mouse.minX, dy: mouse.minY),
                               with: .color(.white.opacity(0.25)), lineWidth: 1)
                    for y in [0.47, 0.6] {
                        let side = Path(roundedRect: CGRect(x: mouse.minX - 3, y: mouse.minY + mouse.height * y, width: 6, height: mouse.height * 0.1), cornerRadius: 3)
                        ctx.fill(side, with: .color(Palette.card))
                        ctx.stroke(side, with: .color(accent.opacity(0.8)), lineWidth: 1.2)
                    }
                } else {
                    let sensor = Path(ellipseIn: CGRect(x: mouse.midX - 14, y: mouse.minY + mouse.height * 0.42, width: 28, height: 28))
                    ctx.stroke(sensor, with: .color(.white.opacity(0.3)), lineWidth: 1)
                    let button = Path(roundedRect: CGRect(x: mouse.midX - 14, y: mouse.minY + mouse.height * 0.7, width: 22, height: 14), cornerRadius: 4)
                    ctx.stroke(button, with: .color(accent), lineWidth: 1.5)
                    let led = Path(ellipseIn: CGRect(x: mouse.midX + 12, y: mouse.minY + mouse.height * 0.7 + 3, width: 8, height: 8))
                    ctx.fill(led, with: .color(accent))
                    let mode = Path(roundedRect: CGRect(x: mouse.midX - 18, y: mouse.minY + mouse.height * 0.85, width: 36, height: 10), cornerRadius: 5)
                    ctx.stroke(mode, with: .color(.white.opacity(0.35)), lineWidth: 1)
                }
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

    private func label(_ c: Callout) -> some View {
        VStack(alignment: c.leftSide ? .trailing : .leading, spacing: 2) {
            Text(c.title.uppercased()).font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(.secondary)
            Text(c.action).font(.callout.weight(.semibold)).foregroundStyle(c.fixed ? .secondary : .primary)
                .lineLimit(2).multilineTextAlignment(c.leftSide ? .trailing : .leading)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Palette.well, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.stroke))
    }
}

struct MouseMapCard: View {
    let slots: [ButtonSlot]
    let accent: Color

    private func action(_ slot: Int) -> String {
        slots.first { $0.slot == slot }?.actionName ?? "Not assigned"
    }

    private static let placed: Set<Int> = [1, 2, 3, 4, 5, 7, 8, 9, 17, 18]

    var body: some View {
        Card(title: "Buttons", icon: "computermouse", accessory: { Text("Read-only for now") }) {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 4) {
                    Text("TOP").font(.caption2.weight(.bold)).tracking(1.2).foregroundStyle(.tertiary)
                    MouseDiagram(side: .top, callouts: [
                        Callout(id: "left", title: "Left button", action: action(1), target: CGPoint(x: 0.28, y: 0.16), leftSide: true, row: 0),
                        Callout(id: "fwd", title: "Side, front", action: action(7), target: CGPoint(x: 0.0, y: 0.52), leftSide: true, row: 2),
                        Callout(id: "back", title: "Side, rear", action: action(8), target: CGPoint(x: 0.0, y: 0.65), leftSide: true, row: 3),
                        Callout(id: "right", title: "Right button", action: action(2), target: CGPoint(x: 0.72, y: 0.16), leftSide: false, row: 0),
                        Callout(id: "wheel", title: "Wheel", action: "\(action(3)), scroll", target: CGPoint(x: 0.57, y: 0.22), leftSide: false, row: 1),
                        Callout(id: "led", title: "Battery light", action: "Blinks when low or charging", target: CGPoint(x: 0.53, y: 0.49), leftSide: false, row: 2, fixed: true),
                    ], accent: accent)
                }
                VStack(spacing: 4) {
                    Text("UNDERSIDE").font(.caption2.weight(.bold)).tracking(1.2).foregroundStyle(.tertiary)
                    MouseDiagram(side: .bottom, callouts: [
                        Callout(id: "dpi", title: "DPI button", action: action(4), target: CGPoint(x: 0.4, y: 0.73), leftSide: true, row: 2),
                        Callout(id: "dpiled", title: "DPI light", action: "Shows the stage colour", target: CGPoint(x: 0.66, y: 0.73), leftSide: false, row: 2, fixed: true),
                        Callout(id: "mode", title: "Mode switch", action: "Connection mode (fixed)", target: CGPoint(x: 0.5, y: 0.87), leftSide: false, row: 3, fixed: true),
                    ], accent: accent)
                }
            }
            .frame(maxWidth: .infinity)
            let others = slots.filter { !Self.placed.contains($0.slot) }
            if !others.isEmpty {
                Text("Also stored on the mouse: " + others.map { "slot \($0.slot) · \($0.actionName)" }.joined(separator: ", "))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
