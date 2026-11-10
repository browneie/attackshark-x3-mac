import Foundation
import X3Kit

/// HID callbacks are scheduled on the run loop of the thread that opened the device,
/// so one long-lived thread owns the mouse and runs every request.
final class MouseWorker: Thread {
    private let lock = NSCondition()
    private var jobs: [() -> Void] = []

    override init() {
        super.init()
        name = "X3 HID"
        start()
    }

    func submit(_ job: @escaping () -> Void) {
        lock.lock(); jobs.append(job); lock.signal(); lock.unlock()
    }

    override func main() {
        while true {
            lock.lock()
            while jobs.isEmpty { lock.wait() }
            let job = jobs.removeFirst()
            lock.unlock()
            job()
        }
    }
}

struct Snapshot {
    var connection = ""
    var isCable = false
    var firmware = ""
    var battery: String?
    var polling: PollingRate?
    var dpi: DPISettings?
    var prefs: Preferences?
    var buttons: [ButtonSlot] = []
}

@MainActor
final class MouseModel: ObservableObject {
    @Published var snapshot = Snapshot()
    @Published var busy = false
    @Published var status = "Not connected"
    @Published var error: String?

    private let worker = MouseWorker()
    nonisolated(unsafe) private var mouse: X3Mouse?
    private var watcher: DeviceWatcher?
    private var reconnectWork: DispatchWorkItem?
    private var reconnectPending = false

    /// Plugging or unplugging the cable or receiver fires a burst of events, and a new device needs a moment
    /// before it answers, so reconnection waits for things to settle.
    init() {
        watcher = DeviceWatcher { [weak self] in
            guard let self else { return }
            self.reconnectWork?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.reconnect() }
            self.reconnectWork = work
            self.status = "Looking for the mouse…"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
        }
    }

    private func reconnect() {
        guard !busy else { reconnectPending = true; return }
        run("Connecting…", fresh: true) { _ in }
    }

    func refresh() { run("Reading settings…") { _ in } }

    func setPolling(_ rate: PollingRate) {
        run("Setting polling rate…") { try $0.setPolling(rate) }
    }

    func applyDPI(_ edit: @escaping (DPISettings) -> DPISettings) {
        run("Updating DPI settings…") { try $0.apply(edit(try $0.readDPI())) }
    }

    func setStageDPI(stage: Int, dpi: Int) {
        run("Setting stage \(stage) to \(dpi) DPI…") { try $0.setStageDPI(stage: stage, dpi: dpi) }
    }

    func setDebounce(_ ms: Int) {
        run("Setting debounce…") { try $0.setDebounce(ms: ms) }
    }

    private static func readAll(_ m: X3Mouse) throws -> Snapshot {
        m.listen(0.3)
        var s = Snapshot()
        s.connection = m.hid.mode.rawValue
        s.isCable = m.hid.mode == .cable
        s.firmware = String(format: "%x.%02x", m.hid.firmwareVersion >> 8, m.hid.firmwareVersion & 0xff)
        s.polling = try m.readPolling().rate
        s.dpi = try m.readDPI()
        s.prefs = try m.readPreferences()
        s.buttons = try m.readButtons().used
        s.battery = m.battery?.description
        return s
    }

    /// Every write is followed by a full re-read, so the window only ever shows what the mouse reports.
    private func run(_ label: String, fresh: Bool = false, _ body: @escaping (X3Mouse) throws -> Void) {
        guard !busy else { return }
        busy = true
        status = label
        error = nil
        worker.submit { [weak self] in
            guard let self else { return }
            let result: Result<Snapshot, Error>
            do {
                if fresh { self.mouse = nil }
                if self.mouse == nil {
                    self.mouse = try X3Mouse()
                    self.mouse!.listen(0.5)
                }
                try body(self.mouse!)
                result = .success(try Self.readAll(self.mouse!))
            } catch {
                switch error {
                case X3Error.notFound, X3Error.openFailed: self.mouse = nil
                default: break
                }
                result = .failure(error)
            }
            DispatchQueue.main.async {
                self.busy = false
                switch result {
                case .success(let snap):
                    self.snapshot = snap
                    self.status = "Connected via \(snap.connection)"
                case .failure(X3Error.notFound):
                    self.snapshot = Snapshot()
                    self.status = "Not connected"
                case .failure(let e):
                    self.error = "\(e)"
                    self.status = self.snapshot.dpi == nil ? "Not connected" : "Connected via \(self.snapshot.connection)"
                }
                if self.reconnectPending {
                    self.reconnectPending = false
                    self.reconnect()
                }
            }
        }
    }
}
