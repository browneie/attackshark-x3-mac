import Foundation
import IOKit.hid

/// Listens to the mouse's ordinary pointer reports (read-only) to measure real report rate and counts.
/// With both the cable and the receiver attached the mouse may send motion through either, so all are watched.
public final class PointerMeter {
    public struct Result {
        public let source: String
        public let reports: Int
        public let peakRate: Int
        public let dx: Int
        public let dy: Int
        public var distance: Double { (Double(dx * dx + dy * dy)).squareRoot() }
    }

    private final class Tap {
        let device: IOHIDDevice
        let name: String
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 16)
        var stamps: [Double] = []
        var dx = 0, dy = 0

        init(_ device: IOHIDDevice) {
            self.device = device
            let pid = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
            name = HIDDevice.productIDs[pid]?.rawValue ?? String(format: "%04x", pid)
        }

        deinit { buffer.deallocate() }
    }

    private let taps: [Tap]

    public init() throws {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matches: [[String: Any]] = HIDDevice.productIDs.keys.map {
            [kIOHIDVendorIDKey: HIDDevice.vendorID, kIOHIDProductIDKey: $0,
             kIOHIDPrimaryUsagePageKey: 0x01, kIOHIDPrimaryUsageKey: 0x02]
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)
        let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []
        var opened: [Tap] = []
        var lastError: IOReturn = kIOReturnSuccess
        for d in devices {
            let r = IOHIDDeviceOpen(d, IOOptionBits(kIOHIDOptionsTypeNone))
            if r == kIOReturnSuccess { opened.append(Tap(d)) } else { lastError = r }
        }
        guard !opened.isEmpty else { throw devices.isEmpty ? X3Error.notFound : X3Error.openFailed(lastError) }
        taps = opened
    }

    deinit {
        for t in taps { IOHIDDeviceClose(t.device, IOOptionBits(kIOHIDOptionsTypeNone)) }
    }

    /// Report layout from the descriptor: buttons byte, X int16, Y int16, wheel, AC pan.
    public func record(seconds: Double) -> Result {
        for t in taps {
            let ctx = Unmanaged.passUnretained(t).toOpaque()
            IOHIDDeviceRegisterInputReportCallback(t.device, t.buffer, 16, { ctx, _, _, _, _, report, length in
                guard let ctx, length >= 5 else { return }
                let tap = Unmanaged<Tap>.fromOpaque(ctx).takeUnretainedValue()
                let x = Int(Int16(bitPattern: UInt16(report[1]) | UInt16(report[2]) << 8))
                let y = Int(Int16(bitPattern: UInt16(report[3]) | UInt16(report[4]) << 8))
                if x != 0 || y != 0 {
                    tap.dx += x; tap.dy += y
                    tap.stamps.append(CFAbsoluteTimeGetCurrent())
                }
            }, ctx)
            IOHIDDeviceScheduleWithRunLoop(t.device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        }
        CFRunLoopRunInMode(.defaultMode, seconds, false)
        for t in taps { IOHIDDeviceUnscheduleFromRunLoop(t.device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue) }

        let best = taps.max { $0.stamps.count < $1.stamps.count }!
        var peak = 0, lo = 0
        for hi in best.stamps.indices {
            while best.stamps[hi] - best.stamps[lo] > 0.25 { lo += 1 }
            peak = max(peak, hi - lo + 1)
        }
        return Result(source: best.name, reports: best.stamps.count, peakRate: peak * 4, dx: best.dx, dy: best.dy)
    }
}
