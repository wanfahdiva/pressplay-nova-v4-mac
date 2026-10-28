import Foundation
import Observation
import V4Kit

@MainActor
@Observable
final class DeviceStore {
    enum Phase: Equatable {
        case searching
        case ready
        case failed(String)
    }

    var phase: Phase = .searching
    private(set) var handle: V4DeviceHandle?
    var status: DeviceStatus?
    var saving = false
    var lastError: String?

    /// Edited settings; changed groups are written about 0.35 s after editing stops.
    var settings: V4Settings {
        didSet {
            guard settings != oldValue else { return }
            save(settings, as: Self.settingsKey)
            if phase == .ready { scheduleApply() }
        }
    }
    /// What the mouse is believed to hold. The firmware can't be read back, so this is our own record.
    private var sent: V4Settings

    private let browser = V4DeviceBrowser()
    private var session: V4Session?
    private var applyTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?

    private static let settingsKey = "settings", sentKey = "sentSettings"

    init() {
        let stored: V4Settings? = Self.load(Self.settingsKey)
        settings = stored ?? V4Settings()
        // Until something has been written we assume the mouse matches what is shown, so opening the
        // app never overwrites settings that were made in Windows.
        sent = Self.load(Self.sentKey) ?? stored ?? V4Settings()
        browser.onChange = { [weak self] list in self?.devicesChanged(list) }
        devicesChanged(browser.devices)
    }

    var needsInputMonitoring: Bool { !InputMonitoringAccess.isGranted }
    func requestInputMonitoring() { InputMonitoringAccess.request() }

    /// DPI codes are only known for the PAW3311 (the sensor this mouse reports).
    var dpiSupported: Bool { status.map { $0.sensorCode == DPITable.sensorCode } ?? false }

    var pendingGroups: [SettingsGroup] { settings.changedGroups(since: sent) }

    // MARK: Connection

    private func devicesChanged(_ list: [V4DeviceHandle]) {
        if let h = handle, !list.contains(h) { disconnect() }
        if session == nil, let first = list.first { connect(first) }
    }

    func retry() {
        disconnect()
        browser.refresh()
        devicesChanged(browser.devices)
    }

    private func connect(_ h: V4DeviceHandle) {
        do {
            session = try V4Session(handle: h)
            handle = h
            Task { await start() }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func disconnect() {
        applyTask?.cancel(); pollTask?.cancel()
        if let s = session { Task { await s.close() } }
        session = nil
        handle = nil
        status = nil
        phase = .searching
    }

    private func start() async {
        guard let s = session else { return }
        do {
            let st = try await s.status()
            status = st
            sync(from: st)
            phase = .ready
            if !pendingGroups.isEmpty { scheduleApply() }
            startPolling()
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self, let s = self.session, !self.saving, self.applyTask == nil else { continue }
                if let st = try? await s.status() {
                    self.status = st
                    self.sync(from: st)
                }
            }
        }
    }

    /// Picks up the active DPI stage and polling rate the mouse reports, e.g. after the DPI button
    /// was pressed. Both are applied to the edited and the sent copy, so nothing is written back.
    private func sync(from st: DeviceStatus) {
        guard pendingGroups.isEmpty else { return }
        var c = settings
        if let stage = st.activeStage, stage < c.stages.count {
            c.currentStage = stage
            c.stages[stage].enabled = true
            sent.currentStage = stage
            sent.stages[stage].enabled = true
        }
        if let rate = st.pollingRate {
            c.pollingRate = rate
            sent.pollingRate = rate
        }
        if c != settings {
            save(sent, as: Self.sentKey)
            settings = c
        }
    }

    func shutdown() async {
        applyTask?.cancel()
        if !pendingGroups.isEmpty { await applyNow() }
        await session?.close()
    }

    // MARK: Writing

    private func scheduleApply() {
        applyTask?.cancel()
        applyTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await self?.applyNow()
            // A newer edit cancels this task before replacing it, so only clear our own slot.
            if !Task.isCancelled { self?.applyTask = nil }
        }
    }

    private func applyNow(groups: [SettingsGroup]? = nil) async {
        guard let s = session else { return }
        var target = settings
        if !dpiSupported {
            // Never send DPI codes for a sensor whose table we don't know.
            for i in target.stages.indices {
                target.stages[i].dpi = sent.stages[i].dpi
                target.stages[i].enabled = sent.stages[i].enabled
            }
            target.currentStage = sent.currentStage
        }
        let list = (groups ?? target.changedGroups(since: sent)).filter { dpiSupported || $0 != .dpiStages }
        guard !list.isEmpty else { return }
        saving = true
        defer { saving = false }
        do {
            try await s.apply(target, groups: list)
            for g in list { sent.copy(g, from: target) }
            save(sent, as: Self.sentKey)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Sends every group, e.g. after the mouse was configured elsewhere.
    func writeAll() async {
        await applyNow(groups: SettingsGroup.allCases)
    }

    func resetToDefaults() {
        settings = V4Settings()
    }

    // MARK: Buttons

    /// At least one button has to keep the left click (Windows app, Lan_En.txt 151).
    func canChange(button: PhysicalButton) -> Bool {
        settings.buttons[button.rawValue] != .leftClick
            || settings.buttons.enumerated().contains { $0.offset != button.rawValue && $0.element == .leftClick }
    }

    // MARK: Persistence

    private func save<T: Encodable>(_ value: T, as key: String) {
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: key) }
    }

    private static func load<T: Decodable>(_ key: String) -> T? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }
}

private extension V4Settings {
    /// Copies the fields behind one request group.
    mutating func copy(_ group: SettingsGroup, from o: V4Settings) {
        switch group {
        case .buttons: buttons = o.buttons
        case .dpiStages:
            for i in stages.indices { stages[i].dpi = o.stages[i].dpi; stages[i].enabled = o.stages[i].enabled }
            currentStage = o.currentStage
        case .dpiColors: for i in stages.indices { stages[i].color = o.stages[i].color }
        case .pollingRate: pollingRate = o.pollingRate
        case .liftOff: liftOff = o.liftOff
        case .debounce: debounceMs = o.debounceMs
        case .lighting: lighting = o.lighting
        case .power: sleepMinutes = o.sleepMinutes; lightsOffWhileMoving = o.lightsOffWhileMoving
        case .motionWake: motionWake = o.motionWake
        }
    }
}
