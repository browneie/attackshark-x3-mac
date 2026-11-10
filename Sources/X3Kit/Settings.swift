import Foundation

public enum PollingRate: Int, CaseIterable, Identifiable {
    case hz125 = 125, hz250 = 250, hz500 = 500, hz1000 = 1000
    public var id: Int { rawValue }

    public init?(code: UInt8) {
        switch code {
        case 0x08: self = .hz125
        case 0x04: self = .hz250
        case 0x02: self = .hz500
        case 0x01: self = .hz1000
        default: return nil
        }
    }

    public var code: UInt8 {
        switch self {
        case .hz125: return 0x08
        case .hz250: return 0x04
        case .hz500: return 0x02
        case .hz1000: return 0x01
        }
    }
}

/// Report 0x06, 9 bytes: id, length constant, profile, rate code, 0xFF - rate code, padding.
public struct PollingReport {
    public var raw: [UInt8]
    public var profile: UInt8 { raw[2] }
    public var rate: PollingRate? { PollingRate(code: raw[3]) }

    init(raw: [UInt8]) throws {
        guard raw.count >= 9, raw[0] == 0x06, raw[4] == 0xff &- raw[3] else {
            throw X3Error.unexpected("Polling report doesn't match the known layout: \(hexString(raw))")
        }
        self.raw = Array(raw.prefix(9))
        self.raw[1] = Safety.lengthByte[0x06]!
    }

    func setting(_ rate: PollingRate) -> [UInt8] {
        var b = raw
        b[3] = rate.code
        b[4] = 0xff &- rate.code
        return b
    }
}

public struct RGB: Equatable {
    public var r, g, b: UInt8
    public init(r: UInt8, g: UInt8, b: UInt8) { self.r = r; self.g = g; self.b = b }
}

/// Report 0x04, 52 bytes. Layout matches the X11 family; checksum is the big-endian sum of bytes 3...49.
public struct DPISettings {
    public var raw: [UInt8]

    init(raw: [UInt8]) throws {
        guard raw.count >= 52, raw[0] == 0x04, DPISettings.checksumOK(raw) else {
            throw X3Error.unexpected("DPI report doesn't match the known layout: \(hexString(raw))")
        }
        self.raw = Array(raw.prefix(52))
        self.raw[1] = Safety.lengthByte[0x04]!
    }

    static func checksum(_ b: [UInt8]) -> UInt16 { b[3...49].reduce(0) { $0 &+ UInt16($1) } }

    static func checksumOK(_ b: [UInt8]) -> Bool {
        b.count >= 52 && checksum(b) == UInt16(b[50]) << 8 | UInt16(b[51])
    }

    public var profile: UInt8 { raw[2] }
    public var liftOff: UInt8 { raw[3] >> 4 }
    public var angleSnap: Bool { raw[3] & 0x0f != 0 }
    public var motionSync: Bool { raw[4] >> 4 != 0 }
    public var rippleControl: Bool { raw[4] & 0x0f != 0 }
    public var enabledMask: UInt8 { raw[5] }
    public var stageCount: Int { (0..<8).filter { enabledMask & (1 << $0) != 0 }.count }
    public var activeStage: Int { Int(raw[24]) }
    public func stageCode(_ i: Int) -> (low: UInt8, high: UInt8) { (raw[8 + i], raw[16 + i]) }
    public func color(_ i: Int) -> RGB { RGB(r: raw[25 + i * 3], g: raw[26 + i * 3], b: raw[27 + i * 3]) }
    public var indicatorMode: UInt8 { raw[49] }

    mutating func seal() {
        let c = DPISettings.checksum(raw)
        raw[50] = UInt8(c >> 8)
        raw[51] = UInt8(c & 0xff)
    }
}

extension DPISettings {
    public static let liftOffNames: [UInt8: String] = [0x00: "1 mm", 0x01: "2 mm", 0x02: "0.7 mm"]

    func with(_ edit: (inout [UInt8]) -> Void) -> DPISettings {
        var copy = self
        edit(&copy.raw)
        copy.seal()
        return copy
    }

    public func setting(activeStage: Int? = nil, stageCount: Int? = nil, liftOff: UInt8? = nil,
                        angleSnap: Bool? = nil, motionSync: Bool? = nil, rippleControl: Bool? = nil) -> DPISettings {
        with { b in
            if let s = stageCount { b[5] = UInt8((1 << s) - 1) }
            if let a = activeStage { b[24] = UInt8(a) }
            if let l = liftOff { b[3] = l << 4 | (b[3] & 0x0f) }
            if let v = angleSnap { b[3] = (b[3] & 0xf0) | (v ? 1 : 0) }
            if let v = motionSync { b[4] = (v ? 0x10 : 0) | (b[4] & 0x0f) }
            if let v = rippleControl { b[4] = (b[4] & 0xf0) | (v ? 1 : 0) }
        }
    }
}

/// Report 0x05, 13 bytes. Same layout as the X11 "user preferences"; checksum is the big-endian sum of bytes 3...10.
public struct Preferences {
    public var raw: [UInt8]

    init(raw: [UInt8]) throws {
        guard raw.count >= 13, raw[0] == 0x05, Preferences.checksumOK(raw) else {
            throw X3Error.unexpected("Preferences report doesn't match the known layout: \(hexString(raw))")
        }
        self.raw = Array(raw.prefix(13))
        self.raw[1] = Safety.lengthByte[0x05]!
    }

    static func checksum(_ b: [UInt8]) -> UInt16 { b[3...10].reduce(0) { $0 &+ UInt16($1) } }
    static func checksumOK(_ b: [UInt8]) -> Bool { b.count >= 13 && checksum(b) == UInt16(b[11]) << 8 | UInt16(b[12]) }

    public static let debounceRange = stride(from: 4, through: 50, by: 2).map { $0 }

    public var lightingMode: UInt8 { raw[3] >> 4 }
    public var ledSpeed: UInt8 { raw[4] & 0x0f }
    public var brightness: UInt8 { raw[5] & 0x0f }
    public var deepSleepMinutes: Int { Int(raw[4] & 0xf0 | raw[5] >> 4) }
    public var color: RGB { RGB(r: raw[6], g: raw[7], b: raw[8]) }
    public var sleepMinutes: Double { Double(raw[9]) / 2 }
    public var debounceMs: Int { Int(raw[10]) * 2 }

    func setting(debounceMs ms: Int) -> [UInt8] {
        var b = raw
        b[10] = UInt8(ms / 2)
        let c = Preferences.checksum(b)
        b[11] = UInt8(c >> 8); b[12] = UInt8(c & 0xff)
        return b
    }
}

public struct ButtonSlot {
    public let slot: Int
    public let action: UInt8
    public let modifiers: UInt8
    public let usage: UInt8

    public var actionName: String { ButtonSlot.names[action] ?? String(format: "action 0x%02x", action) }

    static let names: [UInt8: String] = [
        0x01: "Disabled", 0x02: "Left click", 0x03: "Right click", 0x04: "Middle click", 0x05: "Back", 0x06: "Forward",
        0x07: "Double click", 0x08: "Fire", 0x09: "Scroll up", 0x0a: "Scroll down", 0x0d: "DPI cycle", 0x0e: "DPI +",
        0x0f: "DPI −", 0x10: "Sniper DPI", 0x11: "Keyboard key", 0x12: "Macro", 0x13: "Launch program",
        0x15: "Media player", 0x16: "Previous track", 0x17: "Next track", 0x18: "Play/pause", 0x19: "Stop",
        0x1a: "Mute", 0x1b: "Volume +", 0x1c: "Volume −", 0x28: "Polling-rate cycle", 0x29: "Lighting cycle",
        0x34: "Profile cycle", 0x3c: "Mode key (fixed)",
    ]
}

/// Report 0x08, 59 bytes: 18 three-byte slots from offset 3. Read-only here: the firmware reorders slots on
/// readback and write-protects some, so remapping needs a per-slot mapping scan first.
public struct ButtonMap {
    public let slots: [ButtonSlot]

    init(raw: [UInt8]) throws {
        guard raw.count >= 59, raw[0] == 0x08 else { throw X3Error.unexpected("Button report doesn't match: \(hexString(raw))") }
        slots = (0..<18).map { i in ButtonSlot(slot: i + 1, action: raw[3 + i * 3], modifiers: raw[4 + i * 3], usage: raw[5 + i * 3]) }
    }

    public var used: [ButtonSlot] { slots.filter { $0.action != 0x01 } }
}

/// Stage DPI encoding of this firmware family (PAW3311-style register table).
/// Table from attack-shark-x11-driver, Copyright (c) 2026 HarukaYamamoto0, MIT License.
/// Only the single-byte range is used: 50–10,000 DPI in steps of 50, high byte 0, multiplier flags clear.
/// Confirmed on this X3: code 0x17 measured ≈ 940 DPI over a 100 mm slide (table: 1000).
public enum DPIEncoding {
    public static let range = stride(from: 50, through: 10_000, by: 50).map { $0 }

    static let codes: [UInt8] = [
        0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0e, 0x0f, 0x10, 0x11, 0x12, 0x13, 0x15, 0x16, 0x17,
        0x18, 0x19, 0x1b, 0x1c, 0x1d, 0x1e, 0x1f, 0x20, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x29, 0x2a, 0x2b, 0x2c, 0x2d, 0x2f,
        0x30, 0x31, 0x32, 0x33, 0x34, 0x36, 0x37, 0x38, 0x39, 0x3a, 0x3b, 0x3d, 0x3e, 0x3f, 0x40, 0x41, 0x43, 0x44, 0x45, 0x46,
        0x47, 0x48, 0x4a, 0x4b, 0x4c, 0x4d, 0x4e, 0x4f, 0x51, 0x52, 0x53, 0x54, 0x55, 0x57, 0x58, 0x59, 0x5a, 0x5b, 0x5c, 0x5e,
        0x5f, 0x60, 0x61, 0x62, 0x63, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6b, 0x6c, 0x6d, 0x6e, 0x6f, 0x70, 0x72, 0x73, 0x74, 0x75,
        0x76, 0x77, 0x79, 0x7a, 0x7b, 0x7c, 0x7d, 0x7f, 0x80, 0x81, 0x82, 0x83, 0x84, 0x86, 0x87, 0x88, 0x89, 0x8a, 0x8b, 0x8d,
        0x8e, 0x8f, 0x90, 0x91, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x9a, 0x9b, 0x9c, 0x9d, 0x9e, 0x9f, 0xa1, 0xa2, 0xa3, 0xa4,
        0xa5, 0xa7, 0xa8, 0xa9, 0xaa, 0xab, 0xac, 0xae, 0xaf, 0xb0, 0xb1, 0xb2, 0xb3, 0xb5, 0xb6, 0xb7, 0xb8, 0xb9, 0xbb, 0xbc,
        0xbd, 0xbe, 0xbf, 0xc0, 0xc2, 0xc3, 0xc4, 0xc5, 0xc6, 0xc7, 0xc9, 0xca, 0xcb, 0xcc, 0xcd, 0xcf, 0xd0, 0xd1, 0xd2, 0xd3,
        0xd4, 0xd6, 0xd7, 0xd8, 0xd9, 0xda, 0xdb, 0xdd, 0xde, 0xdf, 0xe0, 0xe1, 0xe3, 0xe4, 0xe5, 0xe6, 0xe7, 0xe8, 0xea, 0xeb
    ]

    public static func code(for dpi: Int) -> UInt8? {
        guard dpi % 50 == 0, (50...10_000).contains(dpi) else { return nil }
        return codes[dpi / 50 - 1]
    }

    public static func dpi(low: UInt8, high: UInt8, double: Bool, triple: Bool) -> Int? {
        guard high == 0, !double, !triple, let i = codes.firstIndex(of: low) else { return nil }
        return (i + 1) * 50
    }
}

extension DPISettings {
    public func stageDPI(_ i: Int) -> Int? {
        let c = stageCode(i)
        return DPIEncoding.dpi(low: c.low, high: c.high, double: raw[6] & (1 << i) != 0, triple: raw[7] & (1 << i) != 0)
    }

    public func setting(stage i: Int, dpi: Int) -> DPISettings? {
        guard (0..<8).contains(i), let code = DPIEncoding.code(for: dpi) else { return nil }
        return with { b in
            b[8 + i] = code
            b[16 + i] = 0
            b[6] &= ~UInt8(1 << i)
            b[7] &= ~UInt8(1 << i)
        }
    }
}
