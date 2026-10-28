import AppKit
import SwiftUI
import V4Kit

enum Pane: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case dpi = "DPI"
    case performance = "Performance"
    case lighting = "Lighting"
    case buttons = "Buttons"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .overview: "computermouse"
        case .dpi: "scope"
        case .performance: "speedometer"
        case .lighting: "lightbulb"
        case .buttons: "button.programmable"
        }
    }
}

struct ContentView: View {
    @Environment(DeviceStore.self) private var store
    @State private var pane: Pane? = .overview

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $pane) { s in
                Label(s.rawValue, systemImage: s.symbol).tag(s)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
            .safeAreaInset(edge: .bottom) { StatusFooter().padding(10) }
        } detail: {
            switch store.phase {
            case .ready:
                detail(for: pane ?? .overview)
            case .searching:
                ContentUnavailableView("Connect your NOVA V4", systemImage: "cable.connector",
                                       description: Text("Plug in the mouse with its USB cable, or plug in its 2.4 GHz receiver."))
            case .failed(let message):
                FailureView(message: message)
            }
        }
    }

    @ViewBuilder
    private func detail(for pane: Pane) -> some View {
        switch pane {
        case .overview: OverviewView()
        case .dpi: DPIView()
        case .performance: PerformanceView()
        case .lighting: LightingView()
        case .buttons: ButtonsView()
        }
    }
}

struct StatusFooter: View {
    @Environment(DeviceStore.self) private var store
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let h = store.handle {
                Label(h.kind.rawValue, systemImage: h.kind == .wired ? "cable.connector" : "antenna.radiowaves.left.and.right")
                    .font(.caption)
            }
            if store.saving {
                Label("Saving…", systemImage: "arrow.triangle.2.circlepath").font(.caption).foregroundStyle(.secondary)
            } else if let e = store.lastError {
                Label(e, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange).lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct FailureView: View {
    @Environment(DeviceStore.self) private var store
    var message: String
    var body: some View {
        ContentUnavailableView {
            Label("Can't talk to the mouse", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            HStack {
                if store.needsInputMonitoring {
                    Button("Request Input Monitoring Access") { store.requestInputMonitoring() }
                }
                Button("Try Again") { store.retry() }.keyboardShortcut(.defaultAction)
            }
        }
    }
}

// MARK: Overview

struct OverviewView: View {
    @Environment(DeviceStore.self) private var store
    @State private var confirmReset = false

    var body: some View {
        Form {
            Section("Mouse") {
                LabeledContent("Connection", value: store.handle?.kind.rawValue ?? "–")
                if let s = store.status {
                    LabeledContent("Model", value: s.model)
                    LabeledContent("Sensor", value: s.sensorName)
                    LabeledContent("Battery") {
                        Label("\(s.batteryLevel)%" + (s.power == .charging ? ", charging" : s.power == .full ? ", full" : ""),
                              systemImage: s.power == .battery ? "battery.75percent" : "battery.100percent.bolt")
                    }
                    if store.handle?.kind == .receiver {
                        LabeledContent("Mouse", value: s.mouseOnline ? "Connected" : "Asleep or off")
                    }
                }
            }
            Section {
                LabeledContent("Unsent changes", value: store.pendingGroups.isEmpty ? "None" : "\(store.pendingGroups.count) group(s)")
                Button("Write All Settings to Mouse") { Task { await store.writeAll() } }
                Button("Reset Settings in This App…", role: .destructive) { confirmReset = true }
            } header: {
                Text("Settings")
            } footer: {
                Text("The mouse can't report its settings, so this app keeps its own copy and sends a group whenever you change it. Use “Write All” if the mouse was set up elsewhere, for example in the Windows app.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("NOVA V4")
        .confirmationDialog("Reset all settings to the defaults? They are written to the mouse right away.",
                            isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { store.resetToDefaults() }
        }
    }
}

// MARK: DPI

struct DPIView: View {
    @Environment(DeviceStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Form {
            if !store.dpiSupported {
                Section {
                    Label("This mouse reports a \(store.status?.sensorName ?? "unknown") sensor. DPI values are only known for the PAW3311, so DPI changes are not sent. Colours still work.",
                          systemImage: "exclamationmark.triangle")
                }
            }
            Section {
                ForEach(0..<DPITable.maxStages, id: \.self) { i in
                    StageRow(index: i, stage: $store.settings.stages[i],
                             isActive: store.settings.currentStage == i,
                             canDisable: store.settings.stages.filter(\.enabled).count > 1,
                             activate: {
                                 store.settings.stages[i].enabled = true
                                 store.settings.currentStage = i
                             })
                }
            } header: {
                Text("Stages")
            } footer: {
                Text("\(DPITable.minimum)–\(DPITable.maximum) DPI in steps of \(DPITable.step). The DPI button cycles through the enabled stages; the colour is shown while switching.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("DPI")
    }
}

private struct StageRow: View {
    var index: Int
    @Binding var stage: DPIStage
    var isActive: Bool
    var canDisable: Bool
    var activate: () -> Void
    @State private var text = ""

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: $stage.enabled)
                .labelsHidden()
                .disabled(isActive || (stage.enabled && !canDisable))
                .help("Include this stage in the DPI button cycle")
            Button(action: activate) {
                Image(systemName: isActive ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isActive ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .help("Make this the active stage")
            Text("\(index + 1)").monospacedDigit().frame(width: 16)
            Slider(value: Binding(
                get: { Double(stage.dpi) },
                set: { stage.dpi = DPITable.snap(Int($0)) }), in: Double(DPITable.minimum)...Double(DPITable.maximum))
            TextField("DPI", text: $text)
                .frame(width: 70)
                .multilineTextAlignment(.trailing)
                .onSubmit { if let v = Int(text) { stage.dpi = DPITable.snap(v) }; text = "\(stage.dpi)" }
            ColorPicker("", selection: Binding(get: { Color(stage.color) }, set: { stage.color = RGB($0) }), supportsOpacity: false)
                .labelsHidden()
        }
        .opacity(stage.enabled ? 1 : 0.5)
        .onAppear { text = "\(stage.dpi)" }
        .onChange(of: stage.dpi) { _, v in text = "\(v)" }
    }
}

// MARK: Performance

struct PerformanceView: View {
    @Environment(DeviceStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Form {
            Section("Sensor") {
                Picker("Polling rate", selection: $store.settings.pollingRate) {
                    ForEach(PollingRate.allCases) { Text("\($0.hertz) Hz").tag($0) }
                }
                Picker("Lift-off distance", selection: $store.settings.liftOff) {
                    Text("1 mm").tag(1)
                    Text("2 mm").tag(2)
                }
                .pickerStyle(.segmented)
            }
            Section("Buttons") {
                Stepper("Debounce: \(store.settings.debounceMs) ms", value: $store.settings.debounceMs, in: 2...20, step: 2)
            }
            Section {
                Stepper("Sleep after \(store.settings.sleepMinutes) min", value: $store.settings.sleepMinutes, in: 3...10)
                Toggle("Lights off while the mouse moves", isOn: $store.settings.lightsOffWhileMoving)
                Toggle("Wake up on motion", isOn: $store.settings.motionWake)
            } header: {
                Text("Wireless power saving")
            } footer: {
                Text("Only matters on battery. These labels are matched to the Windows app's Power Manager by position.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Performance")
    }
}

// MARK: Lighting

struct LightingView: View {
    @Environment(DeviceStore.self) private var store

    var body: some View {
        @Bindable var store = store
        let l = store.settings.lighting
        Form {
            Section("Effect") {
                Picker("Mode", selection: $store.settings.lighting.mode) {
                    ForEach(LightingMode.allCases) { Text($0.name).tag($0) }
                }
                if l.mode != .off {
                    Picker("Brightness", selection: $store.settings.lighting.brightness) {
                        ForEach(Lighting.levels, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                if l.mode.hasSpeed {
                    Picker("Speed", selection: $store.settings.lighting.speed) {
                        ForEach(Lighting.levels, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                if l.mode.hasDirection {
                    Toggle("Reverse direction", isOn: $store.settings.lighting.reverse)
                }
            }
            if l.mode.colorSlots > 0 {
                Section("Colours") {
                    HStack(spacing: 14) {
                        ForEach(0..<l.mode.colorSlots, id: \.self) { i in
                            VStack(spacing: 6) {
                                ColorPicker("", selection: Binding(
                                    get: { Color(store.settings.lighting.colors[i]) },
                                    set: { store.settings.lighting.colors[i] = RGB($0) }), supportsOpacity: false)
                                    .labelsHidden()
                                if l.mode.colorSlots == 7 {
                                    Toggle("", isOn: $store.settings.lighting.selected[i]).labelsHidden()
                                }
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Lighting")
    }
}

// MARK: Buttons

struct ButtonsView: View {
    @Environment(DeviceStore.self) private var store

    var body: some View {
        Form {
            Section {
                ForEach(PhysicalButton.allCases) { b in
                    ButtonRow(button: b)
                }
            } footer: {
                Text("One button always keeps the left click. Keyboard shortcuts, media keys and macros aren't available yet: their codes weren't recovered from the Windows driver.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Buttons")
    }
}

private struct ButtonRow: View {
    @Environment(DeviceStore.self) private var store
    var button: PhysicalButton

    var body: some View {
        let current = store.settings.buttons[button.rawValue]
        Picker(button.name, selection: Binding(
            get: { current },
            set: { store.settings.buttons[button.rawValue] = $0 })) {
            ForEach(KeyFunction.known, id: \.1) { Text($0.0).tag($0.1) }
            if !KeyFunction.known.contains(where: { $0.1 == current }) {
                Text("Custom (\(current.name))").tag(current)
            }
        }
        .disabled(!store.canChange(button: button))
    }
}

// MARK: Colour bridging

extension Color {
    init(_ rgb: RGB) {
        self.init(.sRGB, red: Double(rgb.r) / 255, green: Double(rgb.g) / 255, blue: Double(rgb.b) / 255)
    }
}

extension RGB {
    init(_ color: Color) {
        let c = NSColor(color).usingColorSpace(.sRGB) ?? .white
        self.init(UInt8(clamping: Int((c.redComponent * 255).rounded())),
                  UInt8(clamping: Int((c.greenComponent * 255).rounded())),
                  UInt8(clamping: Int((c.blueComponent * 255).rounded())))
    }
}
