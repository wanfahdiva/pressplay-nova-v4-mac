// IOKit transport. GamingMS.exe opens the interface whose feature report is 0x21 (33) bytes long
// (check at 0x4354ee), writes with HidD_SetFeature and waits 60 ms after every write. The status query
// (0x43a670) writes command 0x20, waits 10 ms, reads the report back and retries once if it is empty.

import Foundation
import IOKit
import IOKit.hid

public enum V4Error: Error, LocalizedError, Equatable {
    case noDevice
    case openFailed(IOReturn)
    case notPermitted
    case sendFailed(IOReturn)
    case readFailed(IOReturn)
    case noStatus

    public var errorDescription: String? {
        switch self {
        case .noDevice: "No NOVA V4 found."
        case .openFailed(let r): String(format: "Could not open the mouse's configuration interface (IOReturn 0x%08X).", r)
        case .notPermitted: "macOS blocked access to the mouse. Allow this app under System Settings > Privacy & Security > Input Monitoring, then try again."
        case .sendFailed(let r): String(format: "Sending a setting failed (IOReturn 0x%08X).", r)
        case .readFailed(let r): String(format: "Reading from the mouse failed (IOReturn 0x%08X).", r)
        case .noStatus: "The mouse did not answer the status request."
        }
    }
}

public enum ConnectionKind: String, Sendable {
    case wired = "USB cable"
    case receiver = "2.4 GHz receiver"
}

public struct V4DeviceHandle: @unchecked Sendable, Identifiable, Hashable {
    public let device: IOHIDDevice
    public let registryID: UInt64
    public let productID: Int
    public let productName: String
    public var id: UInt64 { registryID }
    public var kind: ConnectionKind { productID == V4IDs.wiredProductID ? .wired : .receiver }

    public static func == (a: Self, b: Self) -> Bool { a.registryID == b.registryID }
    public func hash(into h: inout Hasher) { h.combine(registryID) }
}

private func intProperty(_ d: IOHIDDevice, _ key: String) -> Int? {
    (IOHIDDeviceGetProperty(d, key as CFString) as? NSNumber)?.intValue
}

private func registryID(of d: IOHIDDevice) -> UInt64 {
    var id: UInt64 = 0
    IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(d), &id)
    return id
}

/// Finds NOVA V4 configuration interfaces and reports hot-plug changes.
@MainActor
public final class V4DeviceBrowser {
    private let manager: IOHIDManager
    public private(set) var devices: [V4DeviceHandle] = []
    /// The mouse is connected over Bluetooth, which has no configuration report.
    public private(set) var bluetoothConnected = false
    public var onChange: (([V4DeviceHandle]) -> Void)?

    public init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching = (V4IDs.productIDs + [V4IDs.bluetoothProductID]).map {
            [kIOHIDVendorIDKey: V4IDs.vendorID, kIOHIDProductIDKey: $0] as CFDictionary
        } as CFArray
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOHIDDeviceCallback = { ctx, _, _, _ in
            guard let ctx else { return }
            let me = Unmanaged<V4DeviceBrowser>.fromOpaque(ctx).takeUnretainedValue()
            MainActor.assumeIsolated { me.refresh() }
        }
        IOHIDManagerRegisterDeviceMatchingCallback(manager, callback, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, callback, ctx)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        refresh()
    }

    public func refresh() {
        let all = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
        let list = all
            .filter { intProperty($0, kIOHIDMaxFeatureReportSizeKey) == Frame.size }
            .map { d in
                V4DeviceHandle(device: d, registryID: registryID(of: d),
                               productID: intProperty(d, kIOHIDProductIDKey) ?? 0,
                               productName: (IOHIDDeviceGetProperty(d, kIOHIDProductKey as CFString) as? String) ?? "NOVA V4")
            }
            .sorted { ($0.productID, $0.registryID) < ($1.productID, $1.registryID) }
        let bluetooth = all.contains { intProperty($0, kIOHIDProductIDKey) == V4IDs.bluetoothProductID }
        if list != devices || bluetooth != bluetoothConnected {
            devices = list
            bluetoothConnected = bluetooth
            onChange?(list)
        }
    }

    /// Every HID interface with the NOVA V4 IDs (diagnostics).
    public func allInterfaces() -> [String] {
        let all = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
        return all.map { d in
            String(format: "PID %04X usage %04X:%04X maxIn %d maxFeature %d%@",
                   intProperty(d, kIOHIDProductIDKey) ?? 0,
                   intProperty(d, kIOHIDPrimaryUsagePageKey) ?? 0, intProperty(d, kIOHIDPrimaryUsageKey) ?? 0,
                   intProperty(d, kIOHIDMaxInputReportSizeKey) ?? 0, intProperty(d, kIOHIDMaxFeatureReportSizeKey) ?? 0,
                   intProperty(d, kIOHIDMaxFeatureReportSizeKey) == Frame.size ? "  <- config" : "")
        }.sorted()
    }
}

/// An open configuration interface. Requests are serialised; each write is followed by the 60 ms
/// pause the Windows app uses.
public actor V4Session {
    public nonisolated let handle: V4DeviceHandle
    private var sequence: UInt8 = 0
    private var isOpen = false
    /// Optional packet trace (direction, frame).
    private var trace: (@Sendable (String, Frame) -> Void)?

    public static let writePause: Duration = .milliseconds(60)
    public static let readDelay: Duration = .milliseconds(10)

    public init(handle: V4DeviceHandle) throws {
        self.handle = handle
        let r = IOHIDDeviceOpen(handle.device, IOOptionBits(kIOHIDOptionsTypeNone))
        if r == kIOReturnNotPermitted { throw V4Error.notPermitted }
        guard r == kIOReturnSuccess else { throw V4Error.openFailed(r) }
        isOpen = true
    }

    public func setTrace(_ t: (@Sendable (String, Frame) -> Void)?) { trace = t }

    public func close() {
        guard isOpen else { return }
        isOpen = false
        IOHIDDeviceClose(handle.device, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    private func write(_ frame: Frame) throws {
        var f = frame
        f.bytes[4] = sequence
        sequence &+= 1
        trace?("->", f)
        let r = f.bytes.withUnsafeBufferPointer {
            IOHIDDeviceSetReport(handle.device, kIOHIDReportTypeFeature, CFIndex(Frame.reportID), $0.baseAddress!, $0.count)
        }
        guard r == kIOReturnSuccess else { throw r == kIOReturnNotPermitted ? V4Error.notPermitted : V4Error.sendFailed(r) }
    }

    private func read() throws -> Frame {
        var buf = [UInt8](repeating: 0xFF, count: Frame.size)
        buf[0] = Frame.reportID
        var len = CFIndex(buf.count)
        let r = IOHIDDeviceGetReport(handle.device, kIOHIDReportTypeFeature, CFIndex(Frame.reportID), &buf, &len)
        guard r == kIOReturnSuccess else { throw V4Error.readFailed(r) }
        let f = Frame(raw: Array(buf.prefix(Int(len))))
        trace?("<-", f)
        return f
    }

    /// Sends frames in order, pausing after each one.
    public func send(_ frames: [Frame]) async throws {
        for f in frames {
            try write(f)
            try await Task.sleep(for: Self.writePause)
        }
    }

    /// Command 0x20: model, sensor, battery.
    public func status() async throws -> DeviceStatus {
        for _ in 0..<2 {
            var q = Frame(.status)
            q.bytes[5] = 0
            q.bytes[6] = 0
            try write(q)
            try await Task.sleep(for: Self.readDelay)
            if let s = DeviceStatus(try read().bytes) { return s }
        }
        throw V4Error.noStatus
    }

    /// Writes the given groups of `settings`.
    public func apply(_ settings: V4Settings, groups: [SettingsGroup]) async throws {
        for g in groups { try await send(settings.frames(for: g)) }
    }
}

public enum InputMonitoringAccess {
    public static var isGranted: Bool { IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted }
    @discardableResult
    public static func request() -> Bool { IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) }
}
