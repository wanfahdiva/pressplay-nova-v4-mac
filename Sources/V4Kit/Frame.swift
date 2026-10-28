// Feature report 0x0C used by GamingMS.exe (NOVA V4 driver) for every request.
// Layout recovered from the report builders at 0x437bc0, 0x437740, 0x438b40, 0x438cf0, 0x43a670:
//   [0] 0x0C report ID      [1] 0x01            [2] command     [3] 0
//   [4] sequence counter    [5] 0x01 (chunk byte for 0x0E, 0 for 0x20)
//   [6] data length         [7...] data, zero padded to 33 bytes

import Foundation

public enum V4IDs {
    public static let vendorID = 0x248A
    public static let wiredProductID = 0x5B2E
    /// Accepted by the Windows app next to the wired ID; most likely the 2.4 GHz receiver.
    public static let receiverProductID = 0x5B2F
    public static let productIDs = [wiredProductID, receiverProductID]
}

public enum Command: UInt8, CustomStringConvertible, Sendable {
    case button = 0x04
    case dpiStages = 0x05
    case dpiColors = 0x06
    case pollingRate = 0x07
    case lighting = 0x08
    case liftOff = 0x09
    case debounce = 0x0A
    case powerSaving = 0x0B
    case motionWake = 0x0C
    case macro = 0x0E
    case restoreDefaults = 0x0F
    case status = 0x20

    public var description: String { String(format: "0x%02X", rawValue) }
}

public struct Frame: Equatable, Sendable {
    public static let reportID: UInt8 = 0x0C
    public static let size = 33
    public static let maxData = size - 7

    public var bytes: [UInt8]

    public init(_ command: Command, data: [UInt8] = [], sequence: UInt8 = 0, chunk: UInt8 = 0x01) {
        precondition(data.count <= Self.maxData)
        var b = [UInt8](repeating: 0, count: Self.size)
        b[0] = Self.reportID
        b[1] = 0x01
        b[2] = command.rawValue
        b[4] = sequence
        b[5] = chunk
        b[6] = UInt8(data.count)
        b.replaceSubrange(7..<(7 + data.count), with: data)
        bytes = b
    }

    public init(raw: [UInt8]) {
        bytes = raw + [UInt8](repeating: 0, count: max(0, Self.size - raw.count))
    }

    public var command: UInt8 { bytes[2] }
    public var length: Int { Int(bytes[6]) }
    public var data: ArraySlice<UInt8> { bytes[7..<min(Self.size, 7 + length)] }

    public var hex: String { bytes.map { String(format: "%02X", $0) }.joined(separator: " ") }
}

/// Reply to the 0x20 status query (parsed at 0x43a950).
public struct DeviceStatus: Equatable, Sendable {
    public enum Power: Equatable, Sendable { case battery, charging, full }

    public var model: String
    public var sensorCode: UInt8
    public var batteryLevel: Int
    public var power: Power
    /// Byte 0x15. The Windows app treats it as "mouse reachable" when going through the receiver.
    public var mouseOnline: Bool
    /// Bytes 0x10 and 0x11 echo the last DPI header (count | active stage + 1 << 4) and polling-rate code.
    /// Not used by the Windows app; observed on the mouse after writing commands 0x05 and 0x07.
    public var dpiHeader: UInt8
    public var pollingCode: UInt8
    public var raw: [UInt8]

    /// Active DPI stage (0-based), nil until a DPI configuration was written.
    public var activeStage: Int? { dpiHeader & 0x0F == 0 || dpiHeader >> 4 == 0 ? nil : Int(dpiHeader >> 4) - 1 }
    public var pollingRate: PollingRate? { PollingRate.allCases.first { $0.code == pollingCode } }

    public init?(_ reply: [UInt8]) {
        guard reply.count >= 0x16, reply[2] == Command.status.rawValue, reply[3] == 0 else { return nil }
        model = String(decoding: reply[8..<13].filter { (0x20..<0x7F).contains($0) }, as: UTF8.self)
        sensorCode = reply[0x0F]
        switch reply[0x13] {
        case 1: power = .charging
        case 2: power = .full
        default: power = .battery
        }
        batteryLevel = power == .full ? 100 : Int(reply[0x12])
        mouseOnline = reply[0x15] != 0
        dpiHeader = reply[0x10]
        pollingCode = reply[0x11]
        raw = reply
    }

    /// Sensor names from the switch at 0x43aa4b (codes map to PAW part numbers).
    public var sensorName: String {
        let names: [UInt8: String] = [0x04: "3104", 0x25: "3325", 0x27: "3327", 0x12: "3212", 0x11: "3311",
                                      0x35: "3335", 0x60: "3360", 0x70: "3370", 0x89: "3389", 0x95: "3395", 0x99: "3399"]
        return names[sensorCode].map { "PAW\($0)" } ?? String(format: "unknown (0x%02X)", sensorCode)
    }
}
