import Foundation
import X3Kit

let usage = """
usage: x3ctl <command> [--trace]

  info                         read everything the mouse reports
  polling [125|250|500|1000]   show or set the polling rate
  dpi                          show DPI stages and sensor options
  dpi set <stage> <dpi>        set a stage's DPI (50-10000, steps of 50)
  dpi stage <n>                switch to DPI stage n
  dpi stages <n>               number of enabled stages (1-8)
  dpi lod <1|2|0.7>            lift-off distance in mm
  dpi angle-snap|motion-sync|ripple <on|off>
  debounce [ms]                show or set button debounce (4-50, even)
  buttons                      show the button assignments
  battery                      wait for a battery report
  measure [seconds] [mm]       count pointer reports while you move the mouse
  read <hex id>                dump one allowlisted report (debugging)
"""

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write("error: \(msg)\n".data(using: .utf8)!)
    exit(1)
}

func onOff(_ s: String?) -> Bool {
    switch s { case "on": return true; case "off": return false; default: fail("expected on or off") }
}

func describe(_ d: DPISettings) {
    print("DPI stage \(d.activeStage) of \(d.stageCount) active (profile \(d.profile))")
    for i in 0..<d.stageCount {
        let c = d.stageCode(i), rgb = d.color(i)
        let value = d.stageDPI(i).map { "\($0) DPI" } ?? String(format: "code %02x/%02x (not decodable)", c.low, c.high)
        print(String(format: "  stage %d: %@  LED #%02x%02x%02x%@", i + 1, value, rgb.r, rgb.g, rgb.b,
                     i + 1 == d.activeStage ? "  ← active" : ""))
    }
    print("lift-off \(DPISettings.liftOffNames[d.liftOff] ?? "?"), angle snap \(d.angleSnap ? "on" : "off"), motion sync \(d.motionSync ? "on" : "off"), ripple control \(d.rippleControl ? "on" : "off")")
}

var args = Array(CommandLine.arguments.dropFirst())
let trace = args.contains("--trace")
args.removeAll { $0 == "--trace" }
let command = args.first ?? "info"

if command == "help" || command == "-h" || command == "--help" { print(usage); exit(0) }

if command == "measure" {
    let secs = Double(args.dropFirst().first ?? "") ?? 5
    do {
        let meter = try PointerMeter()
        print("Move the mouse now (\(Int(secs)) s)...")
        let r = meter.record(seconds: secs)
        print("via \(r.source): reports: \(r.reports)  peak rate: ~\(r.peakRate) Hz  dx: \(r.dx)  dy: \(r.dy)  counts: \(Int(r.distance))")
        if args.count > 2, let mm = Double(args[2]), mm > 0 {
            print("≈ \(Int((r.distance / (mm / 25.4)).rounded())) DPI over \(mm) mm")
        }
    } catch { fail("\(error)") }
    exit(0)
}

do {
    let mouse = try X3Mouse()
    mouse.hid.trace = trace
    mouse.listen(0.5)
    switch command {
    case "info":
        print("\(mouse.hid.productName) via \(mouse.hid.mode.rawValue), firmware \(String(mouse.hid.firmwareVersion, radix: 16))")
        let p = try mouse.readPolling()
        print("polling rate: \(p.rate.map { "\($0.rawValue) Hz" } ?? "unknown")")
        describe(try mouse.readDPI())
        let prefs = try mouse.readPreferences()
        print("debounce \(prefs.debounceMs) ms, sleep after \(prefs.sleepMinutes) min, deep sleep after \(prefs.deepSleepMinutes) min")
        print("battery:", mouse.battery?.description ?? "no report yet (try `x3ctl battery`)")
        if let id = mouse.deviceID { print(String(format: "device id: 0x%02x", id)) }
    case "polling":
        if args.count > 1 {
            guard let hz = Int(args[1]), let rate = PollingRate(rawValue: hz) else { fail("rate must be 125, 250, 500 or 1000") }
            print("polling rate now \(try mouse.setPolling(rate).rate!.rawValue) Hz (read back from the mouse)")
        } else {
            print("polling rate: \(try mouse.readPolling().rate.map { "\($0.rawValue) Hz" } ?? "unknown")")
        }
    case "dpi":
        let current = try mouse.readDPI()
        guard args.count > 2 else { describe(current); break }
        if args[1] == "set" {
            guard args.count > 3, let stage = Int(args[2]), let value = Int(args[3]) else { fail("usage: dpi set <stage> <dpi>") }
            describe(try mouse.setStageDPI(stage: stage, dpi: value))
            break
        }
        let value = args[2]
        let next: DPISettings
        switch args[1] {
        case "stage":
            guard let n = Int(value), (1...current.stageCount).contains(n) else { fail("stage must be 1-\(current.stageCount)") }
            next = current.setting(activeStage: n)
        case "stages":
            guard let n = Int(value), (1...8).contains(n) else { fail("stages must be 1-8") }
            next = current.setting(activeStage: min(current.activeStage, n), stageCount: n)
        case "lod":
            guard let code = DPISettings.liftOffNames.first(where: { $0.value == "\(value) mm" })?.key else { fail("lod must be 1, 2 or 0.7") }
            next = current.setting(liftOff: code)
        case "angle-snap": next = current.setting(angleSnap: onOff(value))
        case "motion-sync": next = current.setting(motionSync: onOff(value))
        case "ripple": next = current.setting(rippleControl: onOff(value))
        default: fail(usage)
        }
        describe(try mouse.apply(next))
    case "debounce":
        if args.count > 1 {
            guard let ms = Int(args[1]) else { fail("debounce must be a number of ms") }
            print("debounce now \(try mouse.setDebounce(ms: ms).debounceMs) ms (read back from the mouse)")
        } else {
            print("debounce: \(try mouse.readPreferences().debounceMs) ms")
        }
    case "buttons":
        for s in try mouse.readButtons().used {
            print(String(format: "  slot %2d: %@", s.slot, s.actionName))
        }
    case "battery":
        mouse.listen(5)
        print("battery:", mouse.battery?.description ?? "no report within 5 s; move the mouse and retry")
    case "read":
        guard args.count > 1, let id = UInt8(args[1].replacingOccurrences(of: "0x", with: ""), radix: 16) else { fail("usage: read <hex id>") }
        print(hexString(try mouse.read(id)))
    default:
        fail(usage)
    }
} catch {
    fail("\(error)")
}
