import SwiftUI
import X3Kit

@main
struct X3ConfigApp: App {
    var body: some Scene {
        WindowGroup("X3 Config") {
            ContentView()
                .frame(minWidth: 900, minHeight: 640)
                .preferredColorScheme(.dark)
        }
        // macOS saves the frame itself, so the window reopens at whatever size it was left.
        .defaultSize(width: 1060, height: 880)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
    }
}

enum Palette {
    static let page = Color(red: 0.055, green: 0.06, blue: 0.075)
    static let card = Color(red: 0.09, green: 0.1, blue: 0.12)
    static let well = Color(red: 0.13, green: 0.14, blue: 0.17)
    static let stroke = Color.white.opacity(0.08)
    static let ok = Color(red: 0.25, green: 0.85, blue: 0.45)
    static let fallbackAccent = Color(red: 0.45, green: 0.55, blue: 1)

    /// LED colours are stored as raw RGB; pure blue or red reads poorly on black, so lift them a little.
    static func led(_ rgb: RGB) -> Color {
        let lift = 0.22
        func c(_ v: UInt8) -> Double { lift + (1 - lift) * Double(v) / 255 }
        return rgb == RGB(r: 0, g: 0, b: 0) ? fallbackAccent : Color(red: c(rgb.r), green: c(rgb.g), blue: c(rgb.b))
    }
}

struct Card<Content: View, Accessory: View>: View {
    let title: String
    let icon: String
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: icon).foregroundStyle(.secondary)
                Text(title.uppercased()).font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(.secondary)
                Spacer()
                accessory.font(.caption).foregroundStyle(.secondary)
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.stroke))
    }
}

extension Card where Accessory == EmptyView {
    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.init(title: title, icon: icon, accessory: { EmptyView() }, content: content)
    }
}

struct ContentView: View {
    @StateObject private var model = MouseModel()

    private var accent: Color {
        guard let d = model.snapshot.dpi, d.activeStage >= 1 else { return Palette.fallbackAccent }
        return Palette.led(d.color(d.activeStage - 1))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 16) {
                    if let dpi = model.snapshot.dpi {
                        HeroCard(dpi: dpi, model: model, accent: accent)
                        HStack(alignment: .top, spacing: 16) {
                            performance
                            sensor(dpi)
                            power
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        MouseMapCard(slots: model.snapshot.buttons, accent: accent)
                    } else if !model.busy {
                        emptyState
                    }
                }
                .padding(20)
                .disabled(model.busy)
            }
            statusBar
        }
        .background(Palette.page)
        .tint(accent)
        .animation(.easeOut(duration: 0.25), value: model.snapshot.dpi?.activeStage)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Spacer().frame(width: 64)
            Text("ATTACK SHARK X3").font(.system(size: 15, weight: .heavy)).tracking(2.4)
            connectionBadge
            if !model.snapshot.firmware.isEmpty {
                Text("FW \(model.snapshot.firmware)").font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            BatteryMeter(level: model.snapshot.batteryLevel, charging: model.snapshot.isCable, text: model.snapshot.battery)
            Button { model.refresh() } label: {
                Label("Read", systemImage: "arrow.clockwise").labelStyle(.iconOnly).frame(width: 18, height: 18)
            }
            .help("Read from mouse (⌘R)")
            .keyboardShortcut("r")
            .disabled(model.busy)
        }
        .padding(.horizontal, 20)
        .frame(height: 52)
        .background(Palette.card)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.stroke).frame(height: 1) }
    }

    private var connected: Bool { model.snapshot.dpi != nil }

    private var connectionBadge: some View {
        let color = connected ? Palette.ok : Color.secondary
        return HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7).shadow(color: color, radius: connected ? 4 : 0)
            Text(connected ? model.snapshot.connection.uppercased() : "OFFLINE")
                .font(.caption2.weight(.bold)).tracking(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(color.opacity(0.12), in: Capsule())
    }

    private var performance: some View {
        Card(title: "Performance", icon: "gauge.with.dots.needle.67percent") {
            Text("Polling rate").font(.callout).foregroundStyle(.secondary)
            Picker("Polling rate", selection: Binding(
                get: { model.snapshot.polling ?? .hz1000 },
                set: { model.setPolling($0) })) {
                ForEach(PollingRate.allCases) { Text(verbatim: "\($0.rawValue)").tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text(verbatim: "\(model.snapshot.polling?.rawValue ?? 1000) Hz")
                .font(.system(size: 28, weight: .bold, design: .rounded)).monospacedDigit()
            if let prefs = model.snapshot.prefs {
                Divider()
                MenuRow(title: "Button debounce", selection: Binding(
                    get: { prefs.debounceMs }, set: { model.setDebounce($0) }),
                    values: Preferences.debounceRange) { "\($0) ms" }
            }
        }
    }

    private func sensor(_ d: DPISettings) -> some View {
        Card(title: "Sensor", icon: "scope") {
            Text("Lift-off distance").font(.callout).foregroundStyle(.secondary)
            Picker("Lift-off distance", selection: Binding(
                get: { d.liftOff },
                set: { v in model.applyDPI { $0.setting(liftOff: v) } })) {
                ForEach([UInt8(0x02), 0x00, 0x01], id: \.self) { Text(DPISettings.liftOffNames[$0]!).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            SwitchRow(title: "Angle snapping", hint: "Straightens small wobbles", isOn: d.angleSnap) { v in
                model.applyDPI { $0.setting(angleSnap: v) }
            }
            SwitchRow(title: "Motion sync", hint: "Aligns sensor reads with polling", isOn: d.motionSync) { v in
                model.applyDPI { $0.setting(motionSync: v) }
            }
            SwitchRow(title: "Ripple control", hint: "Smooths jitter at high DPI", isOn: d.rippleControl) { v in
                model.applyDPI { $0.setting(rippleControl: v) }
            }
        }
    }

    private var power: some View {
        Card(title: "Power", icon: "moon.zzz") {
            if let prefs = model.snapshot.prefs {
                MenuRow(title: "Sleep after", selection: Binding(
                    get: { prefs.sleepMinutes }, set: { model.setSleep($0) }),
                    values: Set([0.5, 1, 2, 3, 5, 10, 15, 20, 30, prefs.sleepMinutes]).sorted()) { minutes($0) }
                MenuRow(title: "Deep sleep after", selection: Binding(
                    get: { prefs.deepSleepMinutes }, set: { model.setDeepSleep($0) }),
                    values: Set([1, 5, 10, 15, 20, 30, 45, 60, prefs.deepSleepMinutes]).sorted()) { minutes(Double($0)) }
                Text("A sleeping mouse wakes when you move it. Longer timers keep it ready for longer but use more battery.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Not read yet").foregroundStyle(.secondary)
            }
        }
    }

    private func minutes(_ m: Double) -> String {
        m < 1 ? "30 sec" : m == 1 ? "1 min" : m == m.rounded() ? "\(Int(m)) min" : "\(m) min"
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            MouseShape(view: .top).stroke(Color.secondary.opacity(0.5), lineWidth: 2).frame(width: 70, height: 110)
            Text("No X3 found").font(.title3.bold())
            Text("Plug in the 2.4 GHz receiver or the USB cable. The app connects by itself.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 90)
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            if model.busy { ProgressView().controlSize(.small) }
            if let error = model.error {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(error).lineLimit(2)
            } else {
                Text(model.status).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .font(.callout)
        .padding(.horizontal, 20).padding(.vertical, 9)
        .background(Palette.card)
        .overlay(alignment: .top) { Rectangle().fill(Palette.stroke).frame(height: 1) }
    }
}

struct MenuRow<V: Hashable>: View {
    let title: String
    let selection: Binding<V>
    let values: [V]
    let label: (V) -> String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Picker(title, selection: selection) {
                ForEach(values, id: \.self) { Text(label($0)).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
        }
    }
}

struct SwitchRow: View {
    let title: String
    let hint: String
    let isOn: Bool
    let set: (Bool) -> Void

    var body: some View {
        VStack(spacing: 12) {
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(hint).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle(title, isOn: Binding(get: { isOn }, set: set))
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
        }
    }
}

/// Ten segments, because the X3 reports its battery in tenths.
struct BatteryMeter: View {
    let level: Int?
    let charging: Bool
    let text: String?

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                ForEach(0..<10, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(i < (level ?? 0) ? color : Color.white.opacity(0.1))
                        .frame(width: 5, height: 12)
                }
            }
            .padding(3)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.white.opacity(0.25)))
            if charging { Image(systemName: "bolt.fill").font(.caption).foregroundStyle(Palette.ok) }
            Text(level.map { "\($0 * 10)%" } ?? "—").font(.callout.weight(.semibold)).monospacedDigit()
        }
        .help(text ?? "Waiting for a battery report")
    }

    private var color: Color {
        guard let level else { return .secondary }
        return level <= 2 ? .red : level <= 4 ? .orange : Palette.ok
    }
}

struct HeroCard: View {
    let dpi: DPISettings
    @ObservedObject var model: MouseModel
    let accent: Color
    @State private var draft = ""
    @FocusState private var editing: Bool

    var body: some View {
        HStack(spacing: 28) {
            ZStack {
                Circle().fill(accent.opacity(0.16)).frame(width: 170, height: 170).blur(radius: 28)
                MouseShape(view: .top).fill(Palette.well).frame(width: 96, height: 150)
                MouseShape(view: .top).stroke(accent.opacity(0.9), lineWidth: 2).frame(width: 96, height: 150)
                MouseShape.details(width: 96, height: 150).stroke(Color.white.opacity(0.25), lineWidth: 1)
                    .frame(width: 96, height: 150)
            }
            .frame(width: 180, height: 180)

            VStack(alignment: .leading, spacing: 14) {
                Text("ACTIVE DPI · STAGE \(dpi.activeStage)").font(.caption.weight(.bold)).tracking(1.4).foregroundStyle(.secondary)
                Text(dpi.stageDPI(dpi.activeStage - 1).map { $0.formatted() } ?? "—")
                    .font(.system(size: 64, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(accent)
                    .shadow(color: accent.opacity(0.45), radius: 16)
                    .contentTransition(.numericText())
                HStack(spacing: 10) {
                    ForEach(0..<dpi.stageCount, id: \.self) { i in chip(i) }
                }
                HStack(spacing: 10) {
                    TextField("DPI", text: $draft)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                        .monospacedDigit()
                        .focused($editing)
                        .onSubmit(commit)
                    Button("Set stage \(dpi.activeStage)", action: commit)
                        .disabled(Int(draft) == nil || Int(draft) == dpi.stageDPI(dpi.activeStage - 1))
                    Text("50–10,000, steps of 50").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Stepper(value: Binding(
                        get: { dpi.stageCount },
                        set: { n in model.applyDPI { $0.setting(activeStage: min($0.activeStage, n), stageCount: n) } }), in: 1...8) {
                        Text("\(dpi.stageCount) stages").font(.callout).foregroundStyle(.secondary)
                    }
                    .fixedSize()
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(accent.opacity(0.35)))
        .onAppear(perform: syncDraft)
        .onChange(of: dpi.raw) { _, _ in syncDraft() }
    }

    private func syncDraft() {
        guard !editing else { return }
        draft = dpi.stageDPI(dpi.activeStage - 1).map(String.init) ?? ""
    }

    private func commit() {
        guard let value = Int(draft) else { return }
        editing = false
        model.setStageDPI(stage: dpi.activeStage, dpi: value)
    }

    private func chip(_ i: Int) -> some View {
        let active = dpi.activeStage == i + 1
        let led = Palette.led(dpi.color(i))
        let value = dpi.stageDPI(i)
        return Button {
            if !active { model.applyDPI { $0.setting(activeStage: i + 1) } }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle().fill(led).frame(width: 8, height: 8).shadow(color: led, radius: active ? 5 : 0)
                    Text("\(i + 1)").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                }
                Text(value.map { $0.formatted() } ?? "—").font(.system(size: 17, weight: .bold, design: .rounded)).monospacedDigit()
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(minWidth: 78, alignment: .leading)
            .background(active ? led.opacity(0.16) : Palette.well, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(active ? led : Palette.stroke, lineWidth: active ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .help(active ? "Active stage" : "Make stage \(i + 1) active")
        .accessibilityLabel("Stage \(i + 1), \(value.map { "\($0) DPI" } ?? "unknown DPI")\(active ? ", active" : "")")
    }
}
