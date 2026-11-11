import Foundation

/// Every byte that leaves this app passes through here.
/// 0x10 reboots this firmware family into its Beken bootloader, and the 0x2x reports are undocumented,
/// so only reports whose layout has been read back from this mouse and decoded are allowed.
enum Safety {
    /// Total feature report length (report ID included), from the receiver's HID descriptor.
    static let reportLength: [UInt8: Int] = [
        0x04: 52, 0x05: 13, 0x06: 9, 0x07: 8, 0x08: 59, 0x0a: 8, 0x0b: 8, 0x0c: 6, 0xa0: 8,
    ]

    /// Byte 1 of a write is the total report length; the mouse's replies carry that value + 2.
    static let lengthByte: [UInt8: UInt8] = [0x04: 0x34, 0x05: 0x0d, 0x06: 0x09]

    static let readable: Set<UInt8> = [0x04, 0x05, 0x06, 0x08, 0x0b]
    static let writable: Set<UInt8> = [0xa0, 0x04, 0x05, 0x06]
    static let forbidden: Set<UInt8> = [0x09, 0x10, 0x22]

    static func checkRead(_ id: UInt8) throws {
        guard !forbidden.contains(id) else { throw X3Error.blocked("report 0x\(hex8(id)) is never read") }
        guard readable.contains(id) || id == 0xa0 else { throw X3Error.blocked("report 0x\(hex8(id)) is not on the read allowlist") }
    }

    static func checkWrite(_ b: [UInt8]) throws {
        guard let id = b.first else { throw X3Error.blocked("empty report") }
        guard !forbidden.contains(id) else { throw X3Error.blocked("report 0x\(hex8(id)) is never sent") }
        guard writable.contains(id) else { throw X3Error.blocked("report 0x\(hex8(id)) is not on the write allowlist") }
        guard b.count == reportLength[id] else {
            throw X3Error.blocked("report 0x\(hex8(id)) must be \(reportLength[id] ?? 0) bytes, got \(b.count)")
        }
        switch id {
        case 0xa0:
            guard readable.contains(b[1]), b[2] == UInt8(reportLength[b[1]] ?? 0) else {
                throw X3Error.blocked("read request for 0x\(hex8(b[1])) with length \(b[2])")
            }
        case 0x06:
            guard b[1] == lengthByte[0x06], (1...5).contains(b[2]), PollingRate(code: b[3]) != nil, b[4] == 0xff &- b[3] else {
                throw X3Error.blocked("malformed polling-rate report")
            }
        case 0x04:
            guard b[1] == lengthByte[0x04], (1...5).contains(b[2]), DPISettings.checksumOK(b),
                  b[5] != 0, (1...8).contains(b[24]), b[5] & (1 << (b[24] - 1)) != 0,
                  DPISettings.liftOffNames[b[3] >> 4] != nil else {
                throw X3Error.blocked("malformed DPI report")
            }
        case 0x05:
            guard b[1] == lengthByte[0x05], (1...5).contains(b[2]), Preferences.checksumOK(b),
                  Preferences.debounceRange.contains(Int(b[10]) * 2),
                  Preferences.sleepRange.contains(Int(b[9])),
                  Preferences.deepSleepRange.contains(Int(b[4] & 0xf0 | b[5] >> 4)) else {
                throw X3Error.blocked("malformed preferences report")
            }
        default: break
        }
    }
}
