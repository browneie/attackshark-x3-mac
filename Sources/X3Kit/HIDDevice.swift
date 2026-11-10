import Foundation
import IOKit
import IOKit.hid

public enum X3Error: Error, CustomStringConvertible {
    case notFound
    case openFailed(IOReturn)
    case ioFailed(String, IOReturn)
    case blocked(String)
    case readDenied(UInt8)
    case nack(UInt8)
    case unexpected(String)

    public var description: String {
        switch self {
        case .notFound: return "No Attack Shark X3 found (receiver 1d57:fa60 or cable 1d57:fa61)."
        case .openFailed(let r):
            if r == kIOReturnNotPermitted || r == kIOReturnNotPrivileged {
                return "macOS refused HID access (\(hex32(r))). Allow the launching app under System Settings > Privacy & Security > Input Monitoring."
            }
            return "Could not open the mouse (\(hex32(r)))."
        case .ioFailed(let what, let r): return "\(what) failed (\(hex32(r)))."
        case .blocked(let why): return "Blocked for safety: \(why)"
        case .readDenied(let id): return "Mouse refused read access for report 0x\(hex8(id))."
        case .nack(let id): return "Mouse rejected report 0x\(hex8(id)); nothing was changed."
        case .unexpected(let s): return s
        }
    }
}

func hex8(_ v: UInt8) -> String { String(format: "%02x", v) }
func hex32(_ v: IOReturn) -> String { String(format: "0x%08x", UInt32(bitPattern: v)) }
public func hexString(_ b: [UInt8]) -> String { b.map { String(format: "%02x", $0) }.joined(separator: " ") }

public enum ConnectionMode: String {
    case receiver = "2.4 GHz receiver"
    case cable = "USB cable"
}

public struct Event {
    public let deviceID: UInt8
    public let code: UInt8
    public let p1: UInt8
    public let p2: UInt8
    public let raw: [UInt8]
}

/// The vendor command collection (usage page 0x01 / usage 0x80 top-level, with pages 0x0A events and 0x0B commands).
public final class HIDDevice {
    public static let vendorID = 0x1d57
    public static let productIDs: [Int: ConnectionMode] = [0xfa60: .receiver, 0xfa61: .cable, 0xfa55: .cable]

    let device: IOHIDDevice
    public let mode: ConnectionMode
    public let productName: String
    public let firmwareVersion: Int
    public let productID: Int
    private let inputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
    private var events: [Event] = []
    public var onEvent: ((Event) -> Void)?
    public var trace = false
    private var runLoop: CFRunLoop?

    init(device: IOHIDDevice, mode: ConnectionMode) {
        self.device = device
        self.mode = mode
        productName = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "?"
        firmwareVersion = IOHIDDeviceGetProperty(device, kIOHIDVersionNumberKey as CFString) as? Int ?? 0
        productID = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
    }

    deinit {
        if let runLoop { IOHIDDeviceUnscheduleFromRunLoop(device, runLoop, CFRunLoopMode.defaultMode.rawValue) }
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        inputBuffer.deallocate()
    }

    public static func open() throws -> HIDDevice {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matches: [[String: Any]] = productIDs.keys.map {
            [kIOHIDVendorIDKey: vendorID, kIOHIDProductIDKey: $0,
             kIOHIDPrimaryUsagePageKey: 0x01, kIOHIDPrimaryUsageKey: 0x80]
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)
        guard let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
              let dev = set.first(where: { productIDs[pid($0)] == .cable }) ?? set.first else { throw X3Error.notFound }
        let r = IOHIDDeviceOpen(dev, IOOptionBits(kIOHIDOptionsTypeNone))
        guard r == kIOReturnSuccess else { throw X3Error.openFailed(r) }
        let h = HIDDevice(device: dev, mode: productIDs[pid(dev)] ?? .receiver)
        h.startInput()
        return h
    }

    private static func pid(_ d: IOHIDDevice) -> Int {
        IOHIDDeviceGetProperty(d, kIOHIDProductIDKey as CFString) as? Int ?? 0
    }

    private func startInput() {
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, inputBuffer, 64, { ctx, _, _, _, reportID, report, length in
            guard let ctx else { return }
            let me = Unmanaged<HIDDevice>.fromOpaque(ctx).takeUnretainedValue()
            let bytes = Array(UnsafeBufferPointer(start: report, count: length))
            me.handleInput(reportID: UInt8(truncatingIfNeeded: reportID), bytes: bytes)
        }, ctx)
        runLoop = CFRunLoopGetCurrent()
        IOHIDDeviceScheduleWithRunLoop(device, runLoop!, CFRunLoopMode.defaultMode.rawValue)
    }

    private func handleInput(reportID: UInt8, bytes: [UInt8]) {
        if trace { FileHandle.standardError.write("  <- in  \(hexString(bytes))\n".data(using: .utf8)!) }
        guard reportID == 0x03, bytes.count >= 5, bytes[0] == 0x03 else { return }
        let e = Event(deviceID: bytes[1], code: bytes[2], p1: bytes[3], p2: bytes[4], raw: bytes)
        events.append(e)
        onEvent?(e)
    }

    /// Pumps this thread's run loop (the one the device was opened on) so input reports (events, acks) get delivered.
    public func pump(_ seconds: Double) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            CFRunLoopRunInMode(.defaultMode, min(0.02, end.timeIntervalSinceNow), true)
        }
    }

    func drainEvents() -> [Event] { defer { events.removeAll() }; return events }

    func waitForEvent(timeout: Double, where match: (Event) -> Bool) -> Event? {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if let i = events.firstIndex(where: match) { return events.remove(at: i) }
            CFRunLoopRunInMode(.defaultMode, 0.02, true)
        }
        return events.firstIndex(where: match).map { events.remove(at: $0) }
    }

    // Raw transfers are internal: everything outside X3Kit goes through Protocol's allowlist.
    func setFeature(_ bytes: [UInt8]) throws {
        try Safety.checkWrite(bytes)
        if trace { FileHandle.standardError.write("  -> set \(hexString(bytes))\n".data(using: .utf8)!) }
        let r = bytes.withUnsafeBufferPointer {
            IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, CFIndex(bytes[0]), $0.baseAddress!, $0.count)
        }
        guard r == kIOReturnSuccess else { throw X3Error.ioFailed("SET_REPORT 0x\(hex8(bytes[0]))", r) }
    }

    func getFeature(_ id: UInt8, length: Int) throws -> [UInt8] {
        try Safety.checkRead(id)
        var buf = [UInt8](repeating: 0, count: length)
        buf[0] = id
        var len = CFIndex(length)
        let r = buf.withUnsafeMutableBufferPointer {
            IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, CFIndex(id), $0.baseAddress!, &len)
        }
        guard r == kIOReturnSuccess else { throw X3Error.ioFailed("GET_REPORT 0x\(hex8(id))", r) }
        let out = Array(buf.prefix(Int(len)))
        if trace { FileHandle.standardError.write("  <- get \(hexString(out))\n".data(using: .utf8)!) }
        return out
    }
}
