// Encoding checks against values derived from GamingMS.exe (no XCTest with Command Line Tools only).

import Foundation
import V4Kit

var failures = 0
func check(_ name: String, _ got: [UInt8], _ want: [UInt8]) {
    if got == want { print("ok   \(name)") } else {
        failures += 1
        print("FAIL \(name)\n  got  \(got.map { String(format: "%02X", $0) }.joined(separator: " "))\n  want \(want.map { String(format: "%02X", $0) }.joined(separator: " "))")
    }
}
func head(_ f: Frame, _ n: Int) -> [UInt8] { Array(f.bytes.prefix(n)) }

var s = V4Settings()

// Header: 0C 01 cmd 00 seq 01 len.
s.pollingRate = .hz500
check("polling 500 Hz", head(s.frames(for: .pollingRate)[0], 8), [0x0C, 0x01, 0x07, 0x00, 0x00, 0x01, 0x01, 0x02])
s.pollingRate = .hz1000
check("polling 1000 Hz", head(s.frames(for: .pollingRate)[0], 8), [0x0C, 0x01, 0x07, 0x00, 0x00, 0x01, 0x01, 0x01])
check("frame size", [UInt8(s.frames(for: .pollingRate)[0].bytes.count)], [33])

// Default profile key 0 (Key0Value=100100) in slot 0; profile keys 3/4 are swapped into slots 4/3.
let b = s.frames(for: .buttons)
check("button slot 0", head(b[0], 11), [0x0C, 0x01, 0x04, 0x00, 0x00, 0x01, 0x04, 0x00, 0x10, 0x01, 0x00])
check("button slot 3 = back", Array(b[3].bytes[7...10]), [0x03, 0x10, 0x08, 0x00])
check("button slot 5 = DPI cycle", Array(b[5].bytes[7...10]), [0x05, 0x40, 0x01, 0x00])

// DPI: 5 enabled stages, active stage index 1 -> 0x25; mask 0x1F; codes dpi/100.
let d = s.frames(for: .dpiStages)[0]
check("dpi header", head(d, 7), [0x0C, 0x01, 0x05, 0x00, 0x00, 0x01, 0x12])
check("dpi data", Array(d.bytes[7..<25]), [0x25, 0x1F, 4, 0, 8, 0, 16, 0, 32, 0, 64, 0, 120, 0, 120, 0, 120, 0])
check("dpi snap", [UInt8(DPITable.snap(1649) / 100), UInt8(DPITable.snap(20) / 100), UInt8(DPITable.snap(50000) / 100)], [16, 1, 120])

// DPI colours: 8 x RGB, 24 bytes.
let c = s.frames(for: .dpiColors)[0]
check("dpi colours", Array(c.bytes[5...12]), [0x01, 0x18, 0xFF, 0x00, 0x00, 0x00, 0xFF, 0x00])

// Lighting: [mode, bright<<4 | speed, ...].
s.lighting.mode = .colorfulStreaming; s.lighting.brightness = 2; s.lighting.speed = 2; s.lighting.reverse = false
check("lighting streaming", Array(s.frames(for: .lighting)[0].bytes[5...9]), [0x01, 0x03, 0x01, 0x22, 0x00])
s.lighting.mode = .steady; s.lighting.colors[0] = RGB(0xFF, 0x00, 0xFF)
check("lighting steady", Array(s.frames(for: .lighting)[0].bytes[5...11]), [0x01, 0x05, 0x03, 0x22, 0xFF, 0x00, 0xFF])
s.lighting.mode = .breathing; s.lighting.selected = [true, false, true, false, false, false, false]
let br = s.frames(for: .lighting)[0]
check("lighting breathing", Array(br.bytes[5...16]), [0x01, 0x09, 0x02, 0x22, 0x02, 0xFF, 0x00, 0xFF, 0x00, 0x00, 0xFF, 0x00])
s.lighting.mode = .colorfulSteady
check("lighting colorful steady length", [s.frames(for: .lighting)[0].bytes[6]], [23])
s.lighting.mode = .off
check("lighting off", Array(s.frames(for: .lighting)[0].bytes[5...9]), [0x01, 0x02, 0x00, 0x22, 0x00])

// Single-byte groups.
check("lift-off 1 mm", { var t = s; t.liftOff = 1; return Array(t.frames(for: .liftOff)[0].bytes[2...7]) }(), [0x09, 0x00, 0x00, 0x01, 0x01, 0x01])
check("debounce", { var t = s; t.debounceMs = 8; return Array(t.frames(for: .debounce)[0].bytes[2...7]) }(), [0x0A, 0x00, 0x00, 0x01, 0x01, 0x08])
check("power", Array(s.frames(for: .power)[0].bytes[2...8]), [0x0B, 0x00, 0x00, 0x01, 0x02, 0x05, 0x00])

// Change tracking.
var t = s
t.debounceMs += 2
let changed = t.changedGroups(since: s)
check("changed groups", [UInt8(changed.count), changed == [.debounce] ? 1 : 0], [1, 1])
check("first apply sends all", [UInt8(s.changedGroups(since: nil).count)], [UInt8(SettingsGroup.allCases.count)])

// Status reply captured from the mouse on this Mac.
let reply: [UInt8] = [0x0C, 0x01, 0x20, 0x00, 0x00, 0x01, 0x10, 0x00, 0x4D, 0x32, 0x39, 0x38, 0x32, 0x01, 0x55, 0x11,
                      0x10, 0x08, 0x64, 0x01, 0xFF, 0x01, 0x00, 0xFB, 0x02, 0x20, 0x38, 0xFF, 0xE0, 0xA2, 0x00, 0x00, 0x42]
if let st = DeviceStatus(reply) {
    check("status", [st.sensorCode, UInt8(st.batteryLevel), st.power == .charging ? 1 : 0, st.mouseOnline ? 1 : 0], [0x11, 100, 1, 1])
    print("     model \(st.model), sensor \(st.sensorName)")
} else { failures += 1; print("FAIL status parse") }

print(failures == 0 ? "all checks passed" : "\(failures) check(s) failed")
exit(failures == 0 ? 0 : 1)
