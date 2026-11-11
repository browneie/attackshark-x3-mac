import SwiftUI
import X3Kit

@main
struct X3ConfigApp: App {
    var body: some Scene {
        WindowGroup("X3 Config") {
            ContentView()
                .frame(minWidth: 860, minHeight: 600)
        }
        // macOS saves the frame itself, so the window reopens at whatever size it was left.
        .defaultSize(width: 1000, height: 850)
        .windowResizability(.contentMinSize)
    }
}

private enum Palette {
    static let card = Color(nsColor: .controlBackgroundColor)
    static let well = Color(nsColor: .windowBackgroundColor)
    static let stroke = Color.primary.opacity(0.1)
    static let ok = Color(red: 0.19, green: 0.82, blue: 0.35)
}

struct Card<Content: View, Accessory: View>: View {
    let title: String
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                Spacer()
                accessory.font(.caption).foregroundStyle(.secondary)
            }
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.stroke))
    }
}

extension Card where Accessory == EmptyView {
    init(title: String, @ViewBuilder content: () -> Content) {
        self.init(title: title, accessory: { EmptyView() }, content: content)
    }
}

struct ContentView: View {
    @StateObject private var model = MouseModel()

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    header
                    if let dpi = model.snapshot.dpi {
                        StagesCard(dpi: dpi, model: model)
                        HStack(alignment: .top, spacing: 20) { performance; sensor(dpi) }
                            .fixedSize(horizontal: false, vertical: true)
                        buttons
                    } else if !model.busy {
                        emptyState
                    }
                }
                .padding(24)
                .disabled(model.busy)
            }
            statusBar
        }
        .background(Palette.well)
    }

    private var header: some View {
        HStack(spacing: 16) {
            Image(systemName: "computermouse")
                .font(.system(size: 22, weight: .medium))
                .frame(width: 52, height: 52)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.stroke))
            VStack(alignment: .leading, spacing: 4) {
                Text("Attack Shark X3").font(.title2.bold())
                HStack(spacing: 8) {
                    connectionBadge
                    if !model.snapshot.firmware.isEmpty {
                        Text("Firmware \(model.snapshot.firmware)")
                    }
                    if let p = model.snapshot.dpi?.profile { Text("Profile \(p)") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            batteryPill
            Button("Read from mouse") { model.refresh() }
                .keyboardShortcut("r")
                .disabled(model.busy)
        }
    }

    private var connected: Bool { model.snapshot.dpi != nil }

    private var connectionBadge: some View {
        let color = connected ? Palette.ok : Color.secondary
        return HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(connected ? "Connected · \(model.snapshot.connection)" : "Not connected")
                .fontWeight(.semibold)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 9).padding(.vertical, 3)
        .background(color.opacity(0.14), in: Capsule())
    }

    private var batteryPill: some View {
        let s = model.snapshot
        let title = s.isCable ? "Charging" : (s.battery ?? "Battery")
        let detail = s.isCable ? (s.battery ?? "on USB power") : (s.battery == nil ? "waiting for a report" : "last report")
        return HStack(spacing: 10) {
            Image(systemName: s.isCable ? "battery.100.bolt" : batterySymbol(s.batteryLevel))
                .symbolRenderingMode(.hierarchical)
                .font(.title3)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout.weight(.semibold))
                Text(detail).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.stroke))
    }

    private func batterySymbol(_ level: Int?) -> String {
        guard let level else { return "battery.0" }
        return "battery.\([0, 25, 50, 75, 100][min(4, (level * 4 + 5) / 10)])"
    }

    private var performance: some View {
        Card(title: "Performance") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Polling rate").font(.callout).foregroundStyle(.secondary)
                Picker("Polling rate", selection: Binding(
                    get: { model.snapshot.polling ?? .hz1000 },
                    set: { model.setPolling($0) })) {
                    ForEach(PollingRate.allCases) { Text("\($0.rawValue) Hz").tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            if let prefs = model.snapshot.prefs {
                Divider()
                HStack {
                    Text("Button debounce")
                    Spacer()
                    Picker("Button debounce", selection: Binding(
                        get: { prefs.debounceMs },
                        set: { model.setDebounce($0) })) {
                        ForEach(Preferences.debounceRange, id: \.self) { Text("\($0) ms").tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                HStack {
                    Text("Sleep after")
                    Spacer()
                    Picker("Sleep after", selection: Binding(
                        get: { prefs.sleepMinutes },
                        set: { model.setSleep($0) })) {
                        ForEach(Set([0.5, 1, 2, 3, 5, 10, 15, 20, 30, prefs.sleepMinutes]).sorted(), id: \.self) { Text(minutes($0)).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                HStack {
                    Text("Deep sleep after")
                    Spacer()
                    Picker("Deep sleep after", selection: Binding(
                        get: { prefs.deepSleepMinutes },
                        set: { model.setDeepSleep($0) })) {
                        ForEach(Set([1, 5, 10, 15, 20, 30, 45, 60, prefs.deepSleepMinutes]).sorted(), id: \.self) { Text(minutes(Double($0))).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                Text("A sleeping mouse wakes when you move it. Longer timers keep it ready for longer but use more battery.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func minutes(_ m: Double) -> String {
        m < 1 ? "30 seconds" : m == 1 ? "1 minute" : m == m.rounded() ? "\(Int(m)) minutes" : "\(m) minutes"
    }

    private func sensor(_ d: DPISettings) -> some View {
        Card(title: "Sensor") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Lift-off distance").font(.callout).foregroundStyle(.secondary)
                Picker("Lift-off distance", selection: Binding(
                    get: { d.liftOff },
                    set: { v in model.applyDPI { $0.setting(liftOff: v) } })) {
                    ForEach([UInt8(0x02), 0x00, 0x01], id: \.self) { Text(DPISettings.liftOffNames[$0]!).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
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

    private var buttons: some View {
        Card(title: "Buttons", accessory: { Text("Read-only for now") }) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 8)], spacing: 8) {
                ForEach(model.snapshot.buttons, id: \.slot) { s in
                    HStack {
                        Text("Slot \(s.slot)").foregroundStyle(.secondary)
                        Spacer()
                        Text(s.actionName).fontWeight(.medium)
                    }
                    .font(.callout)
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(Palette.well, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.stroke))
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "computermouse").font(.system(size: 36)).foregroundStyle(.secondary)
            Text("No X3 found").font(.headline)
            Text("Plug in the 2.4 GHz receiver or the USB cable, then press Read from mouse.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
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
        .padding(.horizontal, 24).padding(.vertical, 10)
        .background(.bar)
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

struct StagesCard: View {
    let dpi: DPISettings
    @ObservedObject var model: MouseModel
    @State private var draft = ""
    @FocusState private var editing: Bool

    var body: some View {
        Card(title: "DPI stages", accessory: { Text("Click a stage to make it active") }) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                ForEach(0..<dpi.stageCount, id: \.self) { i in tile(i) }
            }
            HStack(spacing: 12) {
                Text("Stage \(dpi.activeStage) DPI").foregroundStyle(.secondary)
                TextField("DPI", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                    .monospacedDigit()
                    .focused($editing)
                    .onSubmit(commit)
                Button("Set", action: commit).disabled(Int(draft) == nil || Int(draft) == dpi.stageDPI(dpi.activeStage - 1))
                Text("50–10,000 in steps of 50").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Stepper(value: Binding(
                    get: { dpi.stageCount },
                    set: { n in model.applyDPI { $0.setting(activeStage: min($0.activeStage, n), stageCount: n) } }), in: 1...8) {
                    Text("Enabled stages: \(dpi.stageCount)").font(.callout).foregroundStyle(.secondary)
                }
                .fixedSize()
            }
        }
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

    private func tile(_ i: Int) -> some View {
        let active = dpi.activeStage == i + 1
        let rgb = dpi.color(i)
        let led = Color(red: Double(rgb.r) / 255, green: Double(rgb.g) / 255, blue: Double(rgb.b) / 255)
        let value = dpi.stageDPI(i)
        return Button {
            if !active { model.applyDPI { $0.setting(activeStage: i + 1) } }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("STAGE \(i + 1)").font(.caption2.weight(.semibold)).tracking(0.6).foregroundStyle(.secondary)
                    Spacer()
                    Circle().fill(led).frame(width: 10, height: 10).shadow(color: led.opacity(0.8), radius: 4)
                }
                Text(value.map { $0.formatted() } ?? "—")
                    .font(.system(size: 26, weight: .bold))
                    .monospacedDigit()
                Text(value == nil ? "Unreadable code" : active ? "Active" : "DPI")
                    .font(.caption)
                    .foregroundStyle(active ? Color.accentColor : .secondary)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            .background(active ? Color.accentColor.opacity(0.14) : Palette.well, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(active ? Color.accentColor : Palette.stroke, lineWidth: active ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Stage \(i + 1), \(value.map { "\($0) DPI" } ?? "unknown DPI")\(active ? ", active" : "")")
    }
}
