import Foundation
import IOKit.hid

/// Calls `onChange` on the main thread whenever an X3 receiver or cable connection appears or disappears.
public final class DeviceWatcher {
    private let manager: IOHIDManager
    private let onChange: () -> Void

    public init(onChange: @escaping () -> Void) {
        self.onChange = onChange
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matches: [[String: Any]] = HIDDevice.productIDs.keys.map {
            [kIOHIDVendorIDKey: HIDDevice.vendorID, kIOHIDProductIDKey: $0,
             kIOHIDPrimaryUsagePageKey: 0x01, kIOHIDPrimaryUsageKey: 0x80]
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOHIDDeviceCallback = { ctx, _, _, _ in
            guard let ctx else { return }
            Unmanaged<DeviceWatcher>.fromOpaque(ctx).takeUnretainedValue().onChange()
        }
        IOHIDManagerRegisterDeviceMatchingCallback(manager, callback, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, callback, ctx)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    }

    deinit {
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    }
}
