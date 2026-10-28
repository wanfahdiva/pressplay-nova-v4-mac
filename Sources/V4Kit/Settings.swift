// Settings model and the request each group of settings turns into.
// The firmware has no read-back command for these values (the Windows app keeps its own copy in
// .psf profiles and re-sends a group only when it changed), so the app does the same.

import Foundation

public struct RGB: Codable, Equatable, Hashable, Sendable {
    public var r: UInt8, g: UInt8, b: UInt8
    public init(_ r: UInt8, _ g: UInt8, _ b: UInt8) { self.r = r; self.g = g; self.b = b }
    public var bytes: [UInt8] { [r, g, b] }
    public static let black = RGB(0, 0, 0)
}

// MARK: DPI

/// DPI table of the PAW3311 branch of 0x40d580: 120 entries of 50·2(i+1) DPI, code i+1.
public enum DPITable {
    public static let sensorCode: UInt8 = 0x11
    public static let minimum = 100, maximum = 12000, step = 100
    public static let maxStages = 8

    public static func snap(_ dpi: Int) -> Int {
        min(maximum, max(minimum, Int((Double(dpi) / Double(step)).rounded()) * step))
    }

    /// Two bytes, low first, as read from the 0x66da30 word table.
    public static func code(for dpi: Int) -> [UInt8] {
        let index = snap(dpi) / step
        return [UInt8(index & 0xFF), UInt8(index >> 8)]
    }
}

public struct DPIStage: Codable, Equatable, Hashable, Sendable {
    public var dpi: Int
    public var enabled: Bool
    public var color: RGB
    public init(dpi: Int, enabled: Bool, color: RGB) { self.dpi = dpi; self.enabled = enabled; self.color = color }
}

// MARK: Polling rate

public enum PollingRate: Int, Codable, CaseIterable, Identifiable, Sendable {
    case hz125 = 0, hz250, hz500, hz1000
    public var id: Int { rawValue }
    public var hertz: Int { [125, 250, 500, 1000][rawValue] }
    /// 0x437bc0: index 0..3 is sent as 8, 4, 2, 1 (ms per report).
    public var code: UInt8 { [8, 4, 2, 1][rawValue] }
}

// MARK: Lighting

public enum LightingMode: UInt8, Codable, CaseIterable, Identifiable, Sendable {
    case off = 0, colorfulStreaming, breathing, steady, neon, tail, colorfulSteady, flicker, tailing, wave
    public var id: UInt8 { rawValue }

    /// Names follow the order of Lan_En.txt entries 100–109, with "None" as mode 0.
    public var name: String {
        switch self {
        case .off: "Off"
        case .colorfulStreaming: "Colorful streaming"
        case .breathing: "Breathing"
        case .steady: "Steady"
        case .neon: "Neon"
        case .tail: "Tail"
        case .colorfulSteady: "Colorful steady"
        case .flicker: "Flicker"
        case .tailing: "Tailing"
        case .wave: "Wave"
        }
    }

    /// Number of colours the request carries (0x437bc0 switch on the mode byte).
    public var colorSlots: Int {
        switch self {
        case .breathing, .colorfulSteady: 7
        case .steady: 1
        case .flicker: 2
        default: 0
        }
    }

    public var hasDirection: Bool { self == .colorfulStreaming }
    public var hasSpeed: Bool { self != .off && self != .steady }
}

public struct Lighting: Codable, Equatable, Sendable {
    public static let levels = 1...5

    public var mode: LightingMode = .colorfulStreaming
    /// 1-based levels; sent as a nibble each (brightness high, speed low).
    public var brightness = 2
    public var speed = 2
    public var reverse = false
    public var colors: [RGB] = [RGB(255, 0, 0), RGB(0, 255, 0), RGB(0, 0, 255), RGB(0, 255, 255),
                                RGB(255, 255, 0), RGB(255, 0, 255), RGB(255, 255, 255)]
    /// Which of `colors` are used by breathing / colorful steady.
    public var selected: [Bool] = [true, true, true, true, true, true, true]

    public init() {}
}

// MARK: Buttons

/// 3-byte key function as stored in KeyNValue and sent with command 0x04.
public struct KeyFunction: Codable, Equatable, Hashable, Sendable {
    public var bytes: [UInt8]
    public init(_ b0: UInt8, _ b1: UInt8, _ b2: UInt8) { bytes = [b0, b1, b2] }

    public static let leftClick = KeyFunction(0x10, 0x01, 0x00)
    public static let rightClick = KeyFunction(0x10, 0x02, 0x00)
    public static let middleClick = KeyFunction(0x10, 0x04, 0x00)
    public static let back = KeyFunction(0x10, 0x08, 0x00)
    public static let forward = KeyFunction(0x10, 0x10, 0x00)
    public static let dpiCycle = KeyFunction(0x40, 0x01, 0x00)

    /// Functions confirmed by the shipped default profiles.
    public static let known: [(String, KeyFunction)] = [
        ("Left click", .leftClick), ("Right click", .rightClick), ("Middle click", .middleClick),
        ("Back", .back), ("Forward", .forward), ("DPI cycle", .dpiCycle),
    ]

    public var name: String {
        Self.known.first { $0.1 == self }?.0 ?? bytes.map { String(format: "%02X", $0) }.joined()
    }
}

/// Physical buttons in firmware slot order. GamingMS.exe swaps profile keys 3 and 4 when sending
/// (0x437740), so slot 3 is the back button and slot 4 the forward button.
public enum PhysicalButton: Int, CaseIterable, Identifiable, Sendable {
    case left = 0, right, middle, back, forward, dpi
    public var id: Int { rawValue }
    public var name: String { ["Left button", "Right button", "Middle button", "Back (side)", "Forward (side)", "DPI button"][rawValue] }
}

// MARK: All settings

public struct V4Settings: Codable, Equatable, Sendable {
    public var pollingRate: PollingRate = .hz1000
    public var stages: [DPIStage] = [
        DPIStage(dpi: 400, enabled: true, color: RGB(255, 0, 0)),
        DPIStage(dpi: 800, enabled: true, color: RGB(0, 255, 0)),
        DPIStage(dpi: 1600, enabled: true, color: RGB(0, 0, 255)),
        DPIStage(dpi: 3200, enabled: true, color: RGB(0, 255, 255)),
        DPIStage(dpi: 6400, enabled: true, color: RGB(255, 255, 0)),
        DPIStage(dpi: 12000, enabled: false, color: RGB(255, 0, 255)),
        DPIStage(dpi: 12000, enabled: false, color: RGB(255, 255, 255)),
        DPIStage(dpi: 12000, enabled: false, color: RGB(255, 255, 255)),
    ]
    public var currentStage = 1
    /// 1 = 1 mm, 2 = 2 mm.
    public var liftOff = 2
    public var debounceMs = 4
    public var lighting = Lighting()
    public var buttons: [KeyFunction] = [.leftClick, .rightClick, .middleClick, .back, .forward, .dpiCycle]
    public var sleepMinutes = 5
    public var lightsOffWhileMoving = false
    public var motionWake = true

    public init() {}

    /// The Windows app refuses a layout without a left click (Lan_En.txt 151).
    public var hasLeftClick: Bool { buttons.contains(.leftClick) }
}

/// One request per settings group, in the order GamingMS.exe sends them.
public enum SettingsGroup: CaseIterable, Sendable {
    case buttons, dpiStages, dpiColors, pollingRate, liftOff, debounce, lighting, power, motionWake
}

extension V4Settings {
    public func frames(for group: SettingsGroup) -> [Frame] {
        switch group {
        case .buttons:
            return buttons.enumerated().map { Frame(.button, data: [UInt8($0.offset)] + $0.element.bytes) }
        case .dpiStages:
            return [Frame(.dpiStages, data: dpiStagesData)]
        case .dpiColors:
            return [Frame(.dpiColors, data: stages.prefix(DPITable.maxStages).flatMap(\.color.bytes))]
        case .pollingRate:
            return [Frame(.pollingRate, data: [pollingRate.code])]
        case .liftOff:
            return [Frame(.liftOff, data: [liftOff == 1 ? 1 : 2])]
        case .debounce:
            return [Frame(.debounce, data: [UInt8(clamping: debounceMs)])]
        case .lighting:
            return [Frame(.lighting, data: lightingData)]
        case .power:
            return [Frame(.powerSaving, data: [UInt8(clamping: sleepMinutes), lightsOffWhileMoving ? 1 : 0])]
        case .motionWake:
            return [Frame(.motionWake, data: [motionWake ? 1 : 0])]
        }
    }

    /// Groups whose request differs from `other` (nil = everything).
    public func changedGroups(since other: V4Settings?) -> [SettingsGroup] {
        SettingsGroup.allCases.filter { g in
            guard let other else { return true }
            return frames(for: g).map(\.bytes) != other.frames(for: g).map(\.bytes)
        }
    }

    /// 0x437bc0 / command 0x05: [count | (current+1) << 4, enabled mask, 8 × code(lo, hi)].
    /// The Windows app fills only the first five codes; the 18-byte payload has room for eight.
    var dpiStagesData: [UInt8] {
        let list = Array(stages.prefix(DPITable.maxStages))
        var mask: UInt8 = 0
        for (i, s) in list.enumerated() where s.enabled { mask |= 1 << i }
        let count = UInt8(mask.nonzeroBitCount)
        var d: [UInt8] = [count & 0x0F | UInt8((currentStage + 1) & 0x0F) << 4, mask]
        for s in list { d += DPITable.code(for: s.dpi) }
        return d + [UInt8](repeating: 0, count: max(0, 18 - d.count))
    }

    /// 0x437bc0 / command 0x08: [mode, brightness << 4 | speed, mode-specific bytes].
    var lightingData: [UInt8] {
        let l = lighting
        let level = { (v: Int) in UInt8(min(15, max(1, v))) }
        var d: [UInt8] = [l.mode.rawValue, level(l.brightness) << 4 | level(l.speed)]
        switch l.mode {
        case .colorfulStreaming:
            d.append(l.reverse ? 1 : 0)
        case .breathing:
            // Like the Windows app, unselected and black colours are skipped.
            let picked = zip(l.colors, l.selected).filter { $0.1 && $0.0 != .black }.map(\.0).prefix(7)
            d.append(UInt8(picked.count))
            d += picked.flatMap(\.bytes)
        case .steady:
            d += (l.colors.first ?? .black).bytes
        case .colorfulSteady:
            for i in 0..<7 { d += (i < l.colors.count && l.selected[i]) ? l.colors[i].bytes : RGB.black.bytes }
        case .flicker:
            for i in 0..<2 { d += (i < l.colors.count ? l.colors[i] : .black).bytes }
        default:
            break
        }
        return d
    }
}
