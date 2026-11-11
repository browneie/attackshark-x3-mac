import Foundation

public final class X3Mouse {
    public let hid: HIDDevice
    public private(set) var deviceID: UInt8?
    public private(set) var battery: Battery?

    public init() throws {
        hid = try HIDDevice.open()
        hid.onEvent = { [weak self] e in self?.observe(e) }
    }

    private func observe(_ e: Event) {
        deviceID = e.deviceID
        if e.code == 0x40 || e.code == 0x41 { battery = Battery(state: e.p1, level: min(Int(e.p2), 10)) }
    }

    /// Single-use read authorisation (0xA0), then GET_REPORT of the target.
    public func read(_ id: UInt8, parameter: UInt8 = 0x01) throws -> [UInt8] {
        guard let len = Safety.reportLength[id] else { throw X3Error.blocked("unknown report 0x\(hex8(id))") }
        var req = [UInt8](repeating: 0, count: 8)
        req[0] = 0xa0; req[1] = id; req[2] = UInt8(len); req[4] = parameter
        // A sleeping mouse or a busy receiver can ignore the request, so ask again a few times. Collecting
        // the target first clears any earlier grant the receiver may still be holding for it.
        var granted = false
        for attempt in 0..<4 where !granted {
            if attempt > 0 {
                _ = try? hid.getFeature(id, length: len)
                hid.pump(0.75)
            }
            try retryingStalls { try hid.setFeature(req) }
            for _ in 0..<10 {
                hid.pump(0.1)
                if let g = try? hid.getFeature(0xa0, length: 8), g.count > 1, g[1] == 0x01 { granted = true; break }
            }
        }
        guard granted else { throw X3Error.readDenied(id) }
        var data: [UInt8] = []
        for _ in 0..<4 {
            hid.pump(0.3)
            data = try retryingStalls { try hid.getFeature(id, length: len) }
            if data.first == id { break }
        }
        hid.pump(0.2)
        guard data.first == id else { throw X3Error.unexpected("Reply to 0x\(hex8(id)) started with \(hexString(Array(data.prefix(2))))") }
        return data
    }

    /// The receiver stalls EP0 while it is still relaying the previous request over the air.
    private func retryingStalls<T>(_ body: () throws -> T) throws -> T {
        var last: Error?
        for _ in 0..<3 {
            do { return try body() } catch let e as X3Error {
                guard case .ioFailed = e else { throw e }
                last = e
                hid.pump(1.0)
            }
        }
        throw last!
    }

    /// Sends a validated report. A NACK is final; a missing ACK (lost over the air) is settled by the caller's readback.
    func write(_ bytes: [UInt8]) throws {
        guard [0xfa60, 0xfa61].contains(hid.productID) else {
            throw X3Error.blocked(String(format: "changes are disabled for untested product ID %04x", hid.productID))
        }
        _ = hid.drainEvents().map(observe)
        try retryingStalls { try hid.setFeature(bytes) }
        guard let ack = hid.waitForEvent(timeout: 2.0, where: { $0.code == 0x50 && $0.p2 == bytes[0] }) else { return }
        guard ack.p1 == 0x00 else { throw X3Error.nack(bytes[0]) }
    }

    /// The firmware stalls or times out for a moment after a write while it stores the change.
    private let settleAfterWrite = 1.0

    public func readPolling() throws -> PollingReport { try PollingReport(raw: read(0x06)) }
    public func readDPI() throws -> DPISettings { try DPISettings(raw: read(0x04)) }

    /// Writes, then reads back to confirm the mouse really holds the new value.
    @discardableResult
    public func setPolling(_ rate: PollingRate) throws -> PollingReport {
        let current = try readPolling()
        try write(current.setting(rate))
        listen(settleAfterWrite)
        let after = try readPolling()
        guard after.rate == rate else { throw X3Error.unexpected("Change did not stick; mouse reads back \(after.rate.map { "\($0.rawValue) Hz" } ?? "?")") }
        return after
    }

    public func readPreferences() throws -> Preferences { try Preferences(raw: read(0x05)) }
    public func readButtons() throws -> ButtonMap { try ButtonMap(raw: read(0x08)) }

    /// Changes the documented option fields of report 0x04; stage codes and colours are copied through untouched.
    @discardableResult
    public func apply(_ dpi: DPISettings) throws -> DPISettings {
        let current = try readDPI()
        guard Array(current.raw[6...23]) == Array(dpi.raw[6...23]), Array(current.raw[25...49]) == Array(dpi.raw[25...49]) else {
            throw X3Error.blocked("use setStageDPI to change a stage's DPI; colours are not editable")
        }
        return try commit(dpi)
    }

    /// Changes one stage's DPI; every byte outside that stage's code and flag bits must stay identical.
    @discardableResult
    public func setStageDPI(stage: Int, dpi: Int) throws -> DPISettings {
        let current = try readDPI()
        guard (1...current.stageCount).contains(stage) else { throw X3Error.blocked("stage must be 1-\(current.stageCount)") }
        guard let next = current.setting(stage: stage - 1, dpi: dpi) else {
            throw X3Error.blocked("DPI must be 50-10,000 in steps of 50")
        }
        let i = stage - 1
        let mask = ~UInt8(1 << i)
        for k in 2...49 where k != 8 + i && k != 16 + i {
            let a = current.raw[k], b = next.raw[k]
            guard (k == 6 || k == 7) ? (a & mask) == (b & mask) : a == b else {
                throw X3Error.blocked("refusing a DPI write that would change byte \(k)")
            }
        }
        return try commit(next)
    }

    private func commit(_ dpi: DPISettings) throws -> DPISettings {
        try write(dpi.raw)
        listen(settleAfterWrite)
        let after = try readDPI()
        guard Array(after.raw[2...49]) == Array(dpi.raw[2...49]) else {
            throw X3Error.unexpected("Change did not stick; mouse reads back \(hexString(after.raw))")
        }
        return after
    }

    @discardableResult
    public func setDebounce(ms: Int) throws -> Preferences {
        guard Preferences.debounceRange.contains(ms) else { throw X3Error.blocked("debounce must be 4–50 ms in steps of 2") }
        let current = try readPreferences()
        try write(current.setting(debounceMs: ms))
        listen(settleAfterWrite)
        let after = try readPreferences()
        guard after.debounceMs == ms else { throw X3Error.unexpected("Change did not stick; mouse reads back \(after.debounceMs) ms") }
        return after
    }

    /// Lets queued events (battery, device ID) arrive.
    public func listen(_ seconds: Double) { hid.pump(seconds) }
}

public struct Battery {
    public let state: UInt8
    /// The X3 reports 0–10, not a percentage like the X11 does.
    public let level: Int
    public var percent: Int { level * 10 }
    public var charging: Bool { state == 0x03 }
    public var description: String {
        switch state {
        case 0x02: return "\(percent)% (full)"
        case 0x03: return "\(percent)% (charging, last known)"
        default: return "\(percent)%"
        }
    }
}
