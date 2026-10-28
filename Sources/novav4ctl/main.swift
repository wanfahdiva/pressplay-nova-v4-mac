// Command-line access to the NOVA V4 configuration interface.

import Foundation
import V4Kit

let usage = """
usage: novav4ctl <command> [--trace]
  list                       HID interfaces with the NOVA V4 IDs
  status                     model, sensor, battery (read-only)
  rate <125|250|500|1000>    polling rate
  dpi <stage> <dpi>...       DPI stages (100-12000, step 100); <stage> is the active one, 1-based
  liftoff <1|2>              lift-off distance in mm
  debounce <ms>
  raw <cmd> [data bytes]     send one frame, hex, e.g. "raw 07 01"
"""

@MainActor
func run() async -> Int32 {
    var args = Array(CommandLine.arguments.dropFirst())
    let trace = args.contains("--trace")
    args.removeAll { $0 == "--trace" }
    guard let command = args.first else { print(usage); return 64 }
    let rest = Array(args.dropFirst())

    let browser = V4DeviceBrowser()
    if command == "list" {
        browser.allInterfaces().forEach { print($0) }
        return 0
    }
    guard let handle = browser.devices.first else { print(V4Error.noDevice.localizedDescription); return 1 }

    do {
        let session = try V4Session(handle: handle)
        if trace { await session.setTrace { dir, f in print(dir, f.hex) } }
        defer { Task { await session.close() } }

        var s = V4Settings()
        let frames: [Frame]
        switch command {
        case "status":
            let st = try await session.status()
            print("connection: \(handle.kind.rawValue) (PID \(String(format: "%04X", handle.productID)))")
            print("model:      \(st.model)")
            print("sensor:     \(st.sensorName)")
            print("battery:    \(st.batteryLevel)% (\(st.power))")
            print("online:     \(st.mouseOnline)")
            return 0
        case "rate":
            guard let hz = rest.first.flatMap(Int.init), let r = PollingRate.allCases.first(where: { $0.hertz == hz }) else { print(usage); return 64 }
            s.pollingRate = r
            frames = s.frames(for: .pollingRate)
        case "dpi":
            let n = rest.compactMap(Int.init)
            guard n.count >= 2, (1...n.count - 1).contains(n[0]), n.count - 1 <= DPITable.maxStages else { print(usage); return 64 }
            let st = try await session.status()
            guard st.sensorCode == DPITable.sensorCode else { print("DPI table for \(st.sensorName) is not known; refusing."); return 1 }
            for i in 0..<DPITable.maxStages {
                s.stages[i].enabled = i < n.count - 1
                if i < n.count - 1 { s.stages[i].dpi = DPITable.snap(n[i + 1]) }
            }
            s.currentStage = n[0] - 1
            frames = s.frames(for: .dpiStages)
        case "liftoff":
            guard let mm = rest.first.flatMap(Int.init), [1, 2].contains(mm) else { print(usage); return 64 }
            s.liftOff = mm
            frames = s.frames(for: .liftOff)
        case "debounce":
            guard let ms = rest.first.flatMap(Int.init), (0...255).contains(ms) else { print(usage); return 64 }
            s.debounceMs = ms
            frames = s.frames(for: .debounce)
        case "raw":
            let bytes = rest.compactMap { UInt8($0, radix: 16) }
            guard bytes.count == rest.count, let c = bytes.first.flatMap(Command.init(rawValue:)) else { print(usage); return 64 }
            frames = [Frame(c, data: Array(bytes.dropFirst()))]
        default:
            print(usage); return 64
        }
        try await session.send(frames)
        print("sent \(frames.count) frame(s)")
        return 0
    } catch {
        print(error.localizedDescription)
        return 1
    }
}

exit(await run())
