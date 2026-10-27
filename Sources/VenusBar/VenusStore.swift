import AppKit
import Foundation
import ServiceManagement
import SwiftUI

enum VenusModel: String, Codable, CaseIterable {
    case unknown, venusE, venusA
    var title: String { switch self { case .unknown: return "Marstek Venus"; case .venusE: return "Venus E 3.0"; case .venusA: return "Venus A" } }
    static func identify(_ name: String?) -> Self {
        switch name {
        case "VenusE3.0", "VenusE 3.0", "Venus E 3.0", "VNSE3-0": return .venusE
        case "VenusA", "Venus A", "VNSA-0": return .venusA
        default: return .unknown
        }
    }
}

enum VenusFlowState: String, Codable {
    case supplyingHome, charging, mains, standby, unknown
    var title: String {
        switch self {
        case .supplyingHome: return VL("Розряджається", "Discharging")
        case .charging: return VL("Заряджається", "Charging")
        case .mains: return VL("Загальна мережа", "Grid supply")
        case .standby: return VL("Очікування", "Standby")
        case .unknown: return VL("Стан не визначено", "State unknown")
        }
    }
    var color: Color {
        switch self {
        case .supplyingHome: return VenusVisuals.supplying
        case .charging: return VenusVisuals.charging
        case .mains: return Color(white: 0.65)
        case .standby: return Color(white: 0.9)
        case .unknown: return Color(white: 0.48)
        }
    }
}

enum VenusMode: String, CaseIterable {
    case auto = "Auto", ai = "AI", manual = "Manual", ups = "UPS"
    var title: String { switch self { case .auto: return VL("Автоматичний", "Automatic"); case .ai: return "AI"; case .manual: return VL("Ручний", "Manual"); case .ups: return "UPS" } }
}

enum VenusAction {
    case setMode(VenusMode), setDOD(Int), setLED(Bool), setBluetooth(Bool), setPowerLimit(Int)
    case setPassive(power: Int, seconds: Int)
    case setSchedule(slot: Int, start: String, end: String, weekmask: Int, power: Int, enabled: Bool)
    case factoryReset(keepEnergy: Bool)
    var parameters: [String: Any] {
        switch self {
        case .setMode(let mode): return ["action": "set_mode", "mode": mode.rawValue]
        case .setDOD(let value): return ["action": "set_dod", "value": value]
        case .setLED(let value): return ["action": "set_led", "value": value]
        case .setBluetooth(let value): return ["action": "set_bluetooth_advertising", "value": value]
        case .setPowerLimit(let value): return ["action": "set_power_version", "value": value]
        case .setPassive(let power, let seconds): return ["action": "set_passive", "power": power, "seconds": seconds]
        case .setSchedule(let slot, let start, let end, let weekmask, let power, let enabled):
            return ["action": "set_schedule", "slot": slot, "start": start, "end": end, "weekmask": weekmask, "power": power, "enabled": enabled]
        case .factoryReset(let keepEnergy): return ["action": "factory_reset", "keep_energy": keepEnergy, "confirmed": true]
        }
    }
}

struct VenusDiscoveredDevice: Codable, Identifiable {
    let name: String
    let ip: String
    let port: Int
    let firmware: Int?
    let wifiMac: String?
    let bleMac: String?
    var id: String { "\(ip):\(port)" }
    enum CodingKeys: String, CodingKey {
        case name, ip, port, firmware, wifiMac = "wifi_mac", bleMac = "ble_mac"
    }

    func isSameStation(as other: Self) -> Bool {
        guard name == other.name, ip == other.ip, port == other.port else { return false }
        for (left, right) in [(wifiMac, other.wifiMac), (bleMac, other.bleMac)] {
            if left == nil && right == nil { continue }
            // Missing known identity is uncertain; never transfer old readings to it.
            guard let left, let right else { return false }
            func canonical(_ value: String) -> String {
                value.replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "-", with: "").lowercased()
            }
            let key = canonical(left)
            guard key.count == 12, key.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
                  key == canonical(right) else { return false }
        }
        return true
    }
}

struct VenusPV: Codable, Identifiable {
    let id: Int
    let powerW: Double?
    let voltageV: Double?
    let currentA: Double?
    let isWorking: Bool?
    enum CodingKeys: String, CodingKey {
        case id, powerW = "power_w", voltageV = "voltage_v", currentA = "current_a", isWorking = "is_working"
    }
}

struct VenusReport: Codable {
    let schemaVersion: Int
    let observedAt: String
    let socPercent: Double?
    let batteryPowerW: Double?
    let gridPowerW: Double?
    let offgridPowerW: Double?
    let batteryTemperatureC: Double?
    let batteryRemainingWh: Double?
    let batteryRatedWh: Double?
    let pvPowerW: Double?
    let mode: String?
    let gridInputWh: Double?
    let gridOutputWh: Double?
    let loadEnergyWh: Double?
    let solarEnergyWh: Double?
    let channels: [VenusPV]?
    let metricObservedAt: [String: String]?
    let ctConnected: Bool?
    let bluetoothConnected: Bool?
    let bluetoothState: String?
    let wifiIP: String?
    let wifiSSID: String?
    let wifiRSSIDbm: Double?
    let ctTotalW: Double?
    let ctInputWh: Double?
    let ctOutputWh: Double?
    let componentStatus: [String: String]?
    let componentObservedAt: [String: String]?
    var pvChannels: [VenusPV] { channels ?? [] }
    var observationDate: Date? { Self.date(observedAt) }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version", observedAt = "observed_at", socPercent = "soc_percent"
        case batteryPowerW = "battery_power_w", gridPowerW = "grid_power_w", offgridPowerW = "offgrid_power_w"
        case batteryTemperatureC = "battery_temperature_c", batteryRemainingWh = "battery_remaining_wh", batteryRatedWh = "battery_rated_wh"
        case pvPowerW = "pv_power_w", mode, gridInputWh = "grid_input_wh", gridOutputWh = "grid_output_wh"
        case loadEnergyWh = "load_energy_wh", solarEnergyWh = "solar_energy_wh", channels = "pv_channels"
        case metricObservedAt = "metric_observed_at"
        case ctConnected = "ct_connected", bluetoothConnected = "bluetooth_connected", bluetoothState = "bluetooth_state"
        case wifiIP = "wifi_ip", wifiSSID = "wifi_ssid", wifiRSSIDbm = "wifi_rssi_dbm"
        case ctTotalW = "ct_total_w", ctInputWh = "ct_input_wh", ctOutputWh = "ct_output_wh"
        case componentStatus = "component_status", componentObservedAt = "component_observed_at"
    }

    func fresh(_ metric: String, now: Date = Date()) -> Bool {
        guard let value = metricObservedAt?[metric], let date = Self.date(value) else { return false }
        return (-2...90).contains(now.timeIntervalSince(date))
    }

    func validate() throws {
        guard schemaVersion == 1, observationDate != nil else { throw VenusStoreError.message(VL("Некоректний звіт станції.", "Invalid station report.")) }
        if let value = socPercent, !value.isFinite || !(0...100).contains(value) { throw VenusStoreError.message(VL("Некоректний заряд батареї.", "Invalid battery charge.")) }
        for value in [batteryPowerW, gridPowerW, offgridPowerW, pvPowerW].compactMap({ $0 }) {
            guard value.isFinite, abs(value) <= 20_000 else { throw VenusStoreError.message(VL("Потужність поза підтримуваними межами.", "Power is outside the supported range.")) }
        }
        if let value = batteryTemperatureC, !value.isFinite || !(-273.15...150).contains(value) { throw VenusStoreError.message(VL("Некоректна температура батареї.", "Invalid battery temperature.")) }
        for value in [batteryRemainingWh, batteryRatedWh, gridInputWh, gridOutputWh, loadEnergyWh, solarEnergyWh].compactMap({ $0 }) {
            guard value.isFinite, value >= 0 else { throw VenusStoreError.message(VL("Некоректний лічильник енергії.", "Invalid energy counter.")) }
        }
        guard pvChannels.count <= 4, Set(pvChannels.map(\.id)).count == pvChannels.count,
              pvChannels.allSatisfy({ (1...4).contains($0.id) }) else { throw VenusStoreError.message(VL("Некоректні сонячні входи.", "Invalid solar inputs.")) }
    }

    static func date(_ text: String) -> Date? {
        let format = ISO8601DateFormatter()
        format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return format.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}

enum VenusStoreError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let message) = self { return message }; return nil }
}

struct VenusConfiguration: Codable {
    var ip: String
    var port: Int
    var enabled: Bool = true
    var refreshInterval: Double = 10
    var expectedName: String?
    var chargingGridSign: Int?
    var confirmedMainsAt: Date?
    func validate() throws {
        let parts = ip.split(separator: ".", omittingEmptySubsequences: false)
        let octets = parts.compactMap { Int($0) }
        guard parts.count == 4, octets.count == 4, zip(parts, octets).allSatisfy({ String($0.1) == String($0.0) }), octets.allSatisfy({ (0...255).contains($0) }),
              octets[0] == 10 || octets[0] == 192 && octets[1] == 168 || octets[0] == 172 && (16...31).contains(octets[1]),
              (1024...65535).contains(port), [10.0, 30.0, 60.0].contains(refreshInterval),
              chargingGridSign == nil || chargingGridSign == -1 || chargingGridSign == 1 else {
            throw VenusStoreError.message(VL("Вкажи приватну IPv4-адресу станції та порт 1024–65535.", "Enter the station’s private IPv4 address and a port from 1024 to 65535."))
        }
    }
}

private struct VenusLastReading: Codable {
    let schemaVersion: Int
    let device: VenusDiscoveredDevice
    let report: VenusReport

    func matches(_ configuration: VenusConfiguration, now: Date) -> Bool {
        guard schemaVersion == 1, device.ip == configuration.ip, device.port == configuration.port,
              configuration.expectedName == nil || configuration.expectedName == device.name,
              let date = report.observationDate, date <= now.addingTimeInterval(2) else { return false }
        do { try report.validate(); return true }
        catch { return false }
    }
}

private struct VenusEnvelope: Decodable {
    struct Issue: Decodable { let message: String; let field: String? }
    let ok: Bool
    let status: String
    let device: VenusDiscoveredDevice?
    let devices: [VenusDiscoveredDevice]?
    let report: VenusReport?
    let error: Issue?
    let errors: [Issue]?
    let accepted: Bool?
    let verified: Bool?
}

@MainActor
final class VenusStore: ObservableObject {
    @Published private(set) var report: VenusReport?
    @Published private(set) var isRestoredReport = false
    @Published private(set) var device: VenusDiscoveredDevice?
    @Published private(set) var discoveredDevices: [VenusDiscoveredDevice] = []
    @Published private(set) var isReading = false
    @Published private(set) var isDiscovering = false
    @Published private(set) var isPolling = false
    @Published private(set) var error: String?
    @Published private(set) var commandBusy = false
    @Published private(set) var commandStatus: String?
    @Published private(set) var startsAtLogin = false
    @Published private(set) var configuration: VenusConfiguration?
    @Published private(set) var warning: String?
    private let directory: URL
    private var operation: Task<Void, Never>?
    private var activeAPI: VenusAPI?
    private var timer: Timer?
    private var generation = 0
    private var clock: Timer?

    var ip: String { configuration?.ip ?? "" }
    var port: Int { configuration?.port ?? 30000 }
    var model: VenusModel { VenusModel.identify(device?.name) }
    var refreshInterval: Double { configuration?.refreshInterval ?? 10 }
    var controlModes: [VenusMode] { model == .unknown ? [] : VenusMode.allCases }
    var supportsSystemControls: Bool { model != .unknown && (device?.firmware ?? 0) >= 150 }
    var powerLimits: [Int] { model == .venusA ? [800, 1200, 1500] : model == .venusE ? [800, 2500] : [] }
    var isFresh: Bool { !isRestoredReport && Self.isRecent(report: report, polling: isPolling, now: Date()) }
    var flowState: VenusFlowState {
        Self.flow(report: report, configuration: configuration, fresh: isFresh, now: Date(), model: model)
    }
    var flowText: String {
        if !isPolling, configuration != nil { return VL("Читання призупинено", "Reading paused") }
        if report != nil, !isFresh { return VL("Немає свіжих даних", "No recent data") }
        return flowState.title
    }
    var statusText: String {
        if isDiscovering { return VL("Шукаємо станції в локальній мережі…", "Searching the local network for stations…") }
        if isReading { return VL("Читаємо локальний API…", "Reading the local API…") }
        if let connectionNotice { return connectionNotice }
        if let date = report?.observationDate {
            return "\(isFresh ? VL("Локальний API", "Local API") : VL("Остання відповідь", "Last response")) · \(date.formatted(.dateTime.hour().minute().locale(VenusLanguage.current.locale)))"
        }
        return VL("Підключи станцію через локальний API", "Connect a station using its local API")
    }
    var connectionNotice: String? {
        guard let error else { return nil }
        return isFresh ? VL("Тимчасово немає відповіді · повторюємо запит", "Temporarily no response · retrying") : error
    }
    var stationImage: NSImage? { nil }

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("VenusBar", isDirectory: true)
        startsAtLogin = SMAppService.mainApp.status == .enabled
        let url = self.directory.appendingPathComponent("connection.json")
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                let data = try Data(contentsOf: url)
                guard data.count <= 8192 else { throw VenusStoreError.message(VL("Налаштування завеликі.", "Settings are too large.")) }
                let config = try JSONDecoder().decode(VenusConfiguration.self, from: data)
                try config.validate()
                configuration = config
                restoreReading(for: config)
                if config.enabled { start() }
            } catch { self.error = VL("Не вдалося відновити підключення: \(error.localizedDescription)", "Could not restore the connection: \(error.localizedDescription)") }
        }
        clock = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.objectWillChange.send() }
        }
    }

    func configure(ip: String, port: Int, model: VenusModel = .unknown) throws {
        guard !commandBusy else { throw VenusStoreError.message(VL("Дочекайся завершення команди.", "Wait for the command to finish.")) }
        let config = VenusConfiguration(ip: ip.trimmingCharacters(in: .whitespacesAndNewlines), port: port)
        try config.validate()
        try persist(config)
        stop()
        configuration = config
        report = nil; device = nil; isRestoredReport = false; error = nil; warning = nil; commandStatus = nil
        start()
    }

    func reload() { guard configuration != nil, !isReading, !commandBusy, !isDiscovering else { return }; enqueue(.read) }
    func start() {
        guard var config = configuration else { return }
        config.enabled = true
        do { try persist(config); configuration = config } catch { self.error = error.localizedDescription; return }
        isPolling = true
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
        reload()
    }
    func pause() {
        stop()
        if var config = configuration {
            config.enabled = false
            do { try persist(config); configuration = config } catch { self.error = error.localizedDescription }
        }
    }
    func stop() {
        timer?.invalidate(); timer = nil
        generation += 1
        operation?.cancel(); activeAPI?.cancel()
        if commandBusy { commandStatus = VL("Команду перервано; результат не підтверджено. Перевір стан перед повторенням.", "Command interrupted; its result is unconfirmed. Check the station before retrying.") }
        commandBusy = false
        isPolling = false; isReading = false; isDiscovering = false
    }
    func discover() { discover(port: port) }
    func discover(port: Int) {
        guard !commandBusy, !isDiscovering else { return }
        discoveredDevices = []
        enqueue(.discover(port))
    }
    func perform(_ action: VenusAction) {
        guard configuration != nil, device != nil, isFresh, !commandBusy else { return }
        commandStatus = nil
        enqueue(.command(action))
    }
    func setRefreshInterval(_ value: Double) {
        guard [10.0, 30.0, 60.0].contains(value), var config = configuration else { return }
        config.refreshInterval = value
        do { try persist(config); configuration = config; if isPolling { start() } } catch { self.error = error.localizedDescription }
    }
    func setStartsAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            startsAtLogin = SMAppService.mainApp.status == .enabled
            if enabled, !startsAtLogin { error = VL("Дозволь VenusBar працювати у фоновому режимі в налаштуваннях macOS.", "Allow VenusBar to run in the background in macOS Settings.") }
        } catch { self.error = VL("Автозапуск недоступний. Перемісти VenusBar до «Програм» і спробуй ще раз.", "Launch at login is unavailable. Move VenusBar to Applications and try again.") }
    }

    func calibrate(_ state: VenusFlowState) throws {
        guard isFresh, let report, var config = configuration, let device else { throw VenusStoreError.message(VL("Спочатку отримай свіжі показники станції.", "Get recent station readings first.")) }
        if state == .mains {
            guard report.fresh("grid_power_w"), let watts = report.gridPowerW, abs(watts) <= 25,
                  !report.fresh("offgrid_power_w") || abs(report.offgridPowerW ?? 0) <= 25 else {
                throw VenusStoreError.message(VL("Станція передає енергію. Перевір фактичне джерело живлення.", "The station is transferring energy. Check the actual power source."))
            }
            config.confirmedMainsAt = Date()
        } else if state == .charging || state == .supplyingHome {
            guard report.fresh("grid_power_w"), let watts = report.gridPowerW, abs(watts) > 25 else {
                throw VenusStoreError.message(VL("Для перевірки напрямку потрібен помітний потік у мережевому каналі.", "A measurable flow through the grid channel is needed to check its direction."))
            }
            let sign = watts < 0 ? -1 : 1
            config.chargingGridSign = state == .charging ? sign : -sign
            config.confirmedMainsAt = nil
        } else { return }
        config.expectedName = device.name
        try persist(config); configuration = config
    }

    nonisolated static func flow(report: VenusReport?, configuration: VenusConfiguration?, fresh: Bool, now: Date, model: VenusModel = .unknown) -> VenusFlowState {
        guard fresh, let report, let config = configuration else { return .unknown }
        let grid = report.fresh("grid_power_w", now: now) ? report.gridPowerW : nil
        let offgrid = report.fresh("offgrid_power_w", now: now) ? report.offgridPowerW : nil
        let pv = report.fresh("pv_power_w", now: now) ? report.pvPowerW : nil
        let battery = report.fresh("battery_power_w", now: now) ? report.batteryPowerW : nil
        // Venus A can supply either AC outlet from solar. No battery-sign convention
        // is documented here: use a measured near-zero net battery value only as a veto.
        let batteryIdle = model == .venusA && battery.map { abs($0) <= 25 } == true
        // Empirical Venus E3 profile; explicit station calibration always overrides it.
        let chargingSign = config.chargingGridSign ?? (model == .venusE ? -1 : nil)
        if let grid, abs(grid) > 25, let sign = chargingSign, !batteryIdle,
           model != .venusA || pv == 0 {
            return (grid < 0 ? -1 : 1) == sign ? .charging : .supplyingHome
        }
        if let offgrid, offgrid > 25, !batteryIdle {
            if model != .venusA { return .supplyingHome }
            // With no grid exchange, only the output exceeding known solar input
            // establishes a battery contribution. Missing/stale PV is not zero.
            if grid == 0, let pv, pv >= 0, offgrid > pv + 25 { return .supplyingHome }
        }
        if let watts = grid, abs(watts) <= 25, (offgrid.map({ abs($0) <= 25 }) ?? true),
           let confirmation = config.confirmedMainsAt, (0...90).contains(now.timeIntervalSince(confirmation)) { return .mains }
        if grid == 0 && offgrid == 0, model != .venusA || pv == 0 { return .standby }
        return .unknown
    }

    nonisolated static func isRecent(report: VenusReport?, polling: Bool, now: Date) -> Bool {
        guard polling, let date = report?.observationDate else { return false }
        return (-2...90).contains(now.timeIntervalSince(date))
    }

    nonisolated static func mergedReport(previous: VenusReport?, previousDevice: VenusDiscoveredDevice?,
                                        incoming: VenusReport, device: VenusDiscoveredDevice,
                                        now: Date = Date()) throws -> VenusReport {
        try incoming.validate()
        guard let previous, let previousDevice, previousDevice.isSameStation(as: device) else { return incoming }
        do { try previous.validate() } catch { return incoming }
        let encoder = JSONEncoder()
        guard let old = try JSONSerialization.jsonObject(with: encoder.encode(previous)) as? [String: Any],
              var combined = try JSONSerialization.jsonObject(with: encoder.encode(incoming)) as? [String: Any] else {
            throw VenusStoreError.message(VL("Не вдалося поєднати показники станції.", "Could not combine station readings."))
        }
        let metadata: Set<String> = ["schema_version", "observed_at", "metric_observed_at", "component_status", "component_observed_at"]
        var clocks = incoming.metricObservedAt ?? [:]
        for (key, value) in old where !metadata.contains(key) && combined[key] == nil {
            guard let original = previous.metricObservedAt?[key], let date = VenusReport.date(original),
                  date <= now else { continue }
            combined[key] = value
            clocks[key] = original // Even a timestamp-only update cannot freshen an omitted value.
        }
        combined["metric_observed_at"] = clocks
        // Top-level receipt belongs to this round; freshness of every retained metric remains separate.
        let result = try JSONDecoder().decode(VenusReport.self, from: JSONSerialization.data(withJSONObject: combined))
        try result.validate()
        return result
    }

    private enum Job { case read, discover(Int), command(VenusAction) }
    private func enqueue(_ job: Job) {
        let previous = operation
        previous?.cancel(); activeAPI?.cancel()
        generation += 1
        let token = generation
        if case .command = job { commandBusy = true } else { commandBusy = false }
        isReading = false; isDiscovering = false
        operation = Task { [weak self] in
            await previous?.value
            guard let self, !Task.isCancelled, token == self.generation else { return }
            let api = VenusAPI()
            self.activeAPI = api
            if case .read = job { self.isReading = true }
            if case .discover = job { self.isDiscovering = true }
            defer {
                if token == self.generation { self.isReading = false; self.isDiscovering = false; self.commandBusy = false; self.activeAPI = nil }
            }
            do {
                let config = self.configuration
                let name = self.device?.name
                let data = try await withTaskCancellationHandler(operation: {
                    try await Task.detached(priority: .utility) {
                        switch job {
                        case .read:
                            guard let config else { throw VenusStoreError.message(VL("Немає підключення.", "No connection.")) }
                            return try api.read(ip: config.ip, port: config.port)
                        case .discover(let selectedPort): return try api.discover(port: selectedPort)
                        case .command(let action):
                            guard let config, let name else { throw VenusStoreError.message(VL("Станцію не визначено.", "Station not identified.")) }
                            var command = action.parameters
                            command["ip"] = config.ip; command["port"] = config.port; command["expected_device"] = name
                            return try api.command(command)
                        }
                    }.value
                }, onCancel: { api.cancel() })
                guard !Task.isCancelled, token == self.generation else { return }
                guard data.count <= 64 * 1024 else { throw VenusStoreError.message(VL("Відповідь станції завелика.", "Station response is too large.")) }
                let envelope = try JSONDecoder().decode(VenusEnvelope.self, from: data)
                guard envelope.ok else { throw VenusStoreError.message(envelope.error?.message ?? VL("Станція не відповіла.", "The station did not respond.")) }
                switch job {
                case .discover:
                    self.discoveredDevices = Array((envelope.devices ?? []).prefix(16))
                    self.error = self.discoveredDevices.isEmpty ? VL("Не отримали відповідь. Спробуй ще раз або введи IP вручну.", "No response received. Try again or enter the IP manually.") : nil
                case .read:
                    guard let report = envelope.report, let device = envelope.device else { throw VenusStoreError.message(VL("Показників ще немає.", "No readings yet.")) }
                    let identityChanged = self.device.map { !$0.isSameStation(as: device) } ?? false
                    let nameChanged = (self.configuration?.expectedName).map { $0 != device.name } ?? false
                    let combined = try Self.mergedReport(previous: self.report, previousDevice: self.device,
                                                         incoming: report, device: device)
                    if identityChanged || nameChanged {
                        self.configuration?.chargingGridSign = nil; self.configuration?.confirmedMainsAt = nil
                    }
                    self.report = combined; self.device = device
                    self.isRestoredReport = false
                    self.error = nil
                    self.warning = envelope.errors?.first?.message
                    do { try self.persistReading(device: device, report: combined) }
                    catch { self.warning = VL("Не вдалося зберегти останні показники на Mac.", "Could not save the latest readings on this Mac.") }
                case .command(let action):
                    self.commandStatus = envelope.verified == true ? VL("Новий режим підтверджено станцією.", "The station confirmed the new mode.") : VL("API прийняв команду. Поточний фізичний стан ще не підтверджено.", "The API accepted the command. The actual physical state is still unconfirmed.")
                    if case .factoryReset = action {
                        self.pause()
                        self.commandStatus = VL("API прийняв скидання. Підключи станцію заново в MARSTEK, а потім у VenusBar.", "The API accepted the reset. Reconnect the station in MARSTEK, then in VenusBar.")
                    } else {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.reload() }
                    }
                }
            } catch {
                guard !Task.isCancelled, token == self.generation else { return }
                if case .command = job { self.commandStatus = error.localizedDescription }
                else { self.error = error.localizedDescription }
            }
        }
    }

    private func restoreReading(for configuration: VenusConfiguration) {
        let url = directory.appendingPathComponent("last-reading.local.json")
        guard let data = try? Data(contentsOf: url), data.count <= 64 * 1024,
              let cache = try? JSONDecoder().decode(VenusLastReading.self, from: data),
              cache.matches(configuration, now: Date()) else { return }
        report = cache.report
        device = cache.device
        isRestoredReport = true
    }

    private func persistReading(device: VenusDiscoveredDevice, report: VenusReport) throws {
        let cache = VenusLastReading(schemaVersion: 1, device: device, report: report)
        let url = directory.appendingPathComponent("last-reading.local.json")
        try JSONEncoder().encode(cache).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func persist(_ config: VenusConfiguration) throws {
        try config.validate()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let url = directory.appendingPathComponent("connection.json")
        try JSONEncoder().encode(config).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    nonisolated static func selfCheck() throws {
        let time = "2026-10-27T13:00:00Z"
        let later = "2026-10-27T13:00:30Z"
        let now = VenusReport.date(time)!
        let next = VenusReport.date(later)!
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw VenusStoreError.message(message) }
        }
        func sample(_ fields: [String: Any], at: String = "2026-10-27T13:00:00Z", clocks: [String: String]? = nil) throws -> VenusReport {
            var object = fields
            object["schema_version"] = 1; object["observed_at"] = at
            object["metric_observed_at"] = clocks ?? Dictionary(uniqueKeysWithValues: fields.keys.filter { !$0.hasPrefix("component_") }.map { ($0, at) })
            return try JSONDecoder().decode(VenusReport.self, from: JSONSerialization.data(withJSONObject: object))
        }
        func station(name: String = "VenusE3.0", ip: String = "192.168.1.12", port: Int = 30000,
                     mac: String? = "020000000001") throws -> VenusDiscoveredDevice {
            var object: [String: Any] = ["name": name, "ip": ip, "port": port, "firmware": 150]
            object["wifi_mac"] = mac
            return try JSONDecoder().decode(VenusDiscoveredDevice.self, from: JSONSerialization.data(withJSONObject: object))
        }
        var config = VenusConfiguration(ip: "192.168.1.12", port: 30000)
        try config.validate()
        let charging = try sample(["soc_percent": 68, "grid_power_w": -1990, "offgrid_power_w": 200])
        try charging.validate()
        try require(flow(report: charging, configuration: config, fresh: true, now: now, model: .venusE) == .charging,
                    "E3 charging takes priority over backup output")
        try require(flow(report: charging, configuration: config, fresh: false, now: now, model: .venusE) == .unknown,
                    "Paused/stale data cannot determine flow")
        let uncalibrated = try sample(["grid_power_w": -100, "offgrid_power_w": 0])
        for model in [VenusModel.venusA, .unknown] {
            try require(flow(report: uncalibrated, configuration: config, fresh: true, now: now, model: model) == .unknown,
                        "No assumed sign profile for other models")
        }
        config.chargingGridSign = 1
        try require(flow(report: uncalibrated, configuration: config, fresh: true, now: now, model: .venusE) == .supplyingHome,
                    "Explicit calibration overrides empirical E3 profile")
        config.chargingGridSign = nil
        let gridCases: [(Double, VenusFlowState)] = [(-25.01, .charging), (-25, .unknown), (0, .standby), (25, .unknown), (25.01, .supplyingHome)]
        for (watts, expected) in gridCases {
            let report = try sample(["grid_power_w": watts, "offgrid_power_w": 0])
            try require(flow(report: report, configuration: config, fresh: true, now: now, model: .venusE) == expected,
                        "Grid deadband/standby regression")
        }
        for (watts, expected) in [(25.0, VenusFlowState.unknown), (25.01, .supplyingHome)] {
            let report = try sample(["grid_power_w": 0, "offgrid_power_w": watts])
            try require(flow(report: report, configuration: config, fresh: true, now: now) == expected,
                        "Backup output threshold regression")
        }
        let zero = try sample(["grid_power_w": 0, "offgrid_power_w": 0])
        try require(flow(report: zero, configuration: config, fresh: true, now: now) == .standby,
                    "Zero power is standby, never proof of mains")
        let onlyGrid = try sample(["grid_power_w": 0])
        try require(flow(report: onlyGrid, configuration: config, fresh: true, now: now) == .unknown,
                    "Missing backup data is not zero")
        let staleComponent = try sample(["grid_power_w": 0, "offgrid_power_w": 0], clocks: ["grid_power_w": time, "offgrid_power_w": "2026-10-27T12:58:00Z"])
        try require(flow(report: staleComponent, configuration: config, fresh: true, now: now) == .unknown,
                    "A stale component cannot establish standby")
        let freshBackup = try sample(["grid_power_w": -1990, "offgrid_power_w": 100], clocks: ["grid_power_w": "2026-10-27T12:58:00Z", "offgrid_power_w": time])
        try require(flow(report: freshBackup, configuration: config, fresh: true, now: now, model: .venusE) == .supplyingHome,
                    "Stale charging evidence cannot block fresh backup output")
        config.confirmedMainsAt = now
        try require(flow(report: zero, configuration: config, fresh: true, now: now) == .mains,
                    "Manual mains confirmation regression")
        let refreshedZero = try sample(["grid_power_w": 0, "offgrid_power_w": 0], at: "2026-10-27T13:01:31Z")
        try require(flow(report: refreshedZero, configuration: config, fresh: true, now: now.addingTimeInterval(91)) == .standby,
                    "Mains confirmation expires even with fresh zero readings")
        var solarConfig = VenusConfiguration(ip: "192.168.1.12", port: 30000)
        for fields: [String: Any] in [
            ["grid_power_w": 0, "offgrid_power_w": 500, "pv_power_w": 500, "battery_power_w": 0],
            ["grid_power_w": 0, "offgrid_power_w": 500, "pv_power_w": 700],
            ["grid_power_w": 0, "offgrid_power_w": 500],
            ["offgrid_power_w": 500, "pv_power_w": 0],
            ["grid_power_w": 0, "offgrid_power_w": 0, "pv_power_w": 500],
            ["grid_power_w": 0, "offgrid_power_w": 500, "pv_power_w": 0, "battery_power_w": 0]
        ] {
            let solar = try sample(fields)
            try require(flow(report: solar, configuration: solarConfig, fresh: true, now: now, model: .venusA) == .unknown,
                        "Solar/unknown input or measured idle battery cannot prove discharge")
        }
        let solarDeficit = try sample(["grid_power_w": 0, "offgrid_power_w": 600, "pv_power_w": 500])
        try require(flow(report: solarDeficit, configuration: solarConfig, fresh: true, now: now, model: .venusA) == .supplyingHome,
                    "Fresh backup output exceeding solar with zero grid proves battery contribution")
        let staleSolar = try sample(["grid_power_w": 0, "offgrid_power_w": 600, "pv_power_w": 0],
                                    clocks: ["grid_power_w": time, "offgrid_power_w": time, "pv_power_w": "2026-10-27T12:58:00Z"])
        try require(flow(report: staleSolar, configuration: solarConfig, fresh: true, now: now, model: .venusA) == .unknown,
                    "Stale solar zero cannot establish battery contribution")
        let solarIdle = try sample(["grid_power_w": 0, "offgrid_power_w": 0, "pv_power_w": 0])
        try require(flow(report: solarIdle, configuration: solarConfig, fresh: true, now: now, model: .venusA) == .standby,
                    "Fresh zero input/output is standby without mains inference")
        solarConfig.chargingGridSign = -1
        let solarGridCharge = try sample(["grid_power_w": -1000, "offgrid_power_w": 200, "pv_power_w": 0])
        try require(flow(report: solarGridCharge, configuration: solarConfig, fresh: true, now: now, model: .venusA) == .charging,
                    "Explicit calibrated charging without solar takes priority over backup")
        let solarExport = try sample(["grid_power_w": 300, "offgrid_power_w": 200, "pv_power_w": 500, "battery_power_w": 0])
        try require(flow(report: solarExport, configuration: solarConfig, fresh: true, now: now, model: .venusA) == .unknown,
                    "Solar covers calibrated grid export and backup without battery discharge")
        let mixedSolar = try sample(["grid_power_w": -1000, "offgrid_power_w": 200, "pv_power_w": 500])
        try require(flow(report: mixedSolar, configuration: solarConfig, fresh: true, now: now, model: .venusA) == .unknown,
                    "Active solar plus grid exchange has no guessed battery direction")
        let measuredIdle = try sample(["grid_power_w": -1000, "offgrid_power_w": 200, "pv_power_w": 0, "battery_power_w": 0])
        try require(flow(report: measuredIdle, configuration: solarConfig, fresh: true, now: now, model: .venusA) == .unknown,
                    "Measured idle battery vetoes a charging claim")
        let noSolarExport = try sample(["grid_power_w": 300, "offgrid_power_w": 200, "pv_power_w": 0])
        try require(flow(report: noSolarExport, configuration: solarConfig, fresh: true, now: now, model: .venusA) == .supplyingHome,
                    "Calibrated export remains valid with known zero solar")
        try require(isRecent(report: charging, polling: true, now: now.addingTimeInterval(90)) &&
                    !isRecent(report: charging, polling: true, now: now.addingTimeInterval(91)) &&
                    !isRecent(report: charging, polling: false, now: now), "Recent data survives a retry, expires after 90 s and pauses")
        let device = try station()
        let cached = VenusLastReading(schemaVersion: 1, device: device, report: charging)
        let restored = try JSONDecoder().decode(VenusLastReading.self, from: JSONEncoder().encode(cached))
        try require(restored.matches(config, now: now) && restored.report.observedAt == time,
                    "Saved readings preserve their original receipt time")
        var otherConfiguration = config
        otherConfiguration.ip = "192.168.1.13"
        try require(!restored.matches(otherConfiguration, now: now) && !restored.matches(config, now: now.addingTimeInterval(-3)),
                    "A saved reading cannot cross endpoints or come from the future")
        let old = try sample(["soc_percent": 68, "battery_temperature_c": 21, "ct_connected": true,
                              "component_status": ["Bat.GetStatus": "received"], "component_observed_at": ["Bat.GetStatus": time]])
        let incoming = try sample(["soc_percent": 69, "ct_connected": false,
                                   "component_status": ["Bat.GetStatus": "timeout"], "component_observed_at": ["ES.GetStatus": later]], at: later,
                                  clocks: ["soc_percent": later, "ct_connected": later, "battery_temperature_c": later])
        let merged = try mergedReport(previous: old, previousDevice: device, incoming: incoming, device: device, now: next)
        try require(merged.socPercent == 69 && merged.ctConnected == false && merged.batteryTemperatureC == 21,
                    "Partial values must retain old fields and accept actual false/new values")
        try require(merged.metricObservedAt?["battery_temperature_c"] == time && merged.metricObservedAt?["soc_percent"] == later && merged.observedAt == later,
                    "Omitted metrics must preserve original clocks without aging new metrics")
        try require(merged.componentStatus?["Bat.GetStatus"] == "timeout" && merged.componentObservedAt?["Bat.GetStatus"] == nil,
                    "Diagnostics describe this round, never an old successful component")
        let hour = "2026-10-27T14:00:00Z"
        let hourly = try sample(["soc_percent": 70], at: hour)
        let retained = try mergedReport(previous: old, previousDevice: device, incoming: hourly, device: device, now: now.addingTimeInterval(3600))
        try require(retained.batteryTemperatureC == 21 && !retained.fresh("battery_temperature_c", now: now.addingTimeInterval(3600)) && retained.fresh("soc_percent", now: now.addingTimeInterval(3600)),
                    "Expired values remain last-known while actual new metrics stay fresh")
        let noNewClock = try sample(["soc_percent": 71], at: later, clocks: [:])
        let unclocked = try mergedReport(previous: old, previousDevice: device, incoming: noNewClock, device: device, now: next)
        try require(unclocked.socPercent == 71 && unclocked.metricObservedAt?["soc_percent"] == nil,
                    "A new value cannot borrow an old receipt clock")
        let future = try sample(["battery_temperature_c": 22], clocks: ["battery_temperature_c": "2026-10-27T13:02:00Z"])
        let rejectedFuture = try mergedReport(previous: future, previousDevice: device, incoming: incoming, device: device, now: next)
        try require(rejectedFuture.batteryTemperatureC == nil, "Future retained values are not valid history")
        for other in [try station(name: "VenusA"), try station(ip: "192.168.1.13"), try station(port: 30001),
                      try station(mac: "020000000002"), try station(mac: nil)] {
            let separated = try mergedReport(previous: old, previousDevice: device, incoming: incoming, device: other, now: next)
            try require(separated.batteryTemperatureC == nil, "Different/uncertain identity cannot inherit readings")
        }
        let canonicalDevice = try station(mac: "02:00:00:00:00:01")
        try require(device.isSameStation(as: canonicalDevice), "Canonical MAC comparison regression")
        try require(VenusModel.identify("VNSA-0") == .venusA && VenusModel.identify("VenusE 3.0") == .venusE, "Model regression")
        var rejected = false
        do { try sample(["soc_percent": 101]).validate() } catch { rejected = true }
        try require(rejected, "SOC validation regression")
        rejected = false
        do { try VenusConfiguration(ip: "192.168.1.12.bad", port: 30000).validate() } catch { rejected = true }
        try require(rejected, "IP validation regression")
    }
}
