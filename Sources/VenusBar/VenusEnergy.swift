import Foundation
import Combine

struct VenusEnergyPoint: Identifiable {
    let date: Date
    let value: Double
    var id: Date { date }
}

struct VenusEnergySeries: Identifiable {
    let id: String
    let title: String
    let segments: [[VenusEnergyPoint]]
}

struct VenusEnergyForecast {
    enum Status { case collecting, standby, charging, supplying, full }
    enum Basis { case batteryPower, energyTrend }
    var status: Status = .collecting
    var rateW: Double?
    var basis: Basis?
    var chargeHours: Double?
    var runtimeHours: Double?
    var availableWh: Double?
    var reservePercent: Double = 20
    var enoughForOutage: Bool?
    var budgetW: Double?
    var outageHours: Double?
    var upcomingOutage = false
}

private struct VenusEnergySample: Codable, Sendable {
    let value: Double
    let date: Date
}

private struct VenusEnergyFrame: Codable, Sendable {
    var metrics: [String: VenusEnergySample]
}

// This snapshot contains copied value types; the device's identity fields are immutable.
private struct VenusEnergyArchive: Codable, @unchecked Sendable {
    var schemaVersion = 1
    var device: VenusDiscoveredDevice?
    var reservePercent = 20.0
    var frames: [VenusEnergyFrame] = []
}

@MainActor
final class VenusEnergyStore: ObservableObject {
    @Published private(set) var reservePercent = 20.0
    @Published private(set) var latestReport: VenusReport?
    @Published private(set) var historyCount = 0
    @Published private(set) var persistenceError: String?
    private var device: VenusDiscoveredDevice?
    private var flow: VenusFlowState = .unknown
    private var acceptedAt: Date?
    private var frames: [VenusEnergyFrame] = []
    private var newest: [String: Date] = [:]
    private let directory: URL
    private let writer = DispatchQueue(label: "local.VenusBar.energy", qos: .utility)
    private var lastSave = Date.distantPast
    private var generation = 0
    private static let horizon: TimeInterval = 48 * 3600
    private static let keys = ["battery_power_w", "grid_power_w", "offgrid_power_w", "battery_remaining_wh", "battery_rated_wh", "soc_percent"]

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("VenusBar", isDirectory: true)
        let path = self.directory.appendingPathComponent("energy.local.json")
        do {
            guard FileManager.default.fileExists(atPath: path.path) else { return }
            let size = try path.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 20_000_000 else { throw VenusStoreError.message(VL("Історія перевищує допустимий розмір.", "History exceeds the size limit.")) }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .secondsSince1970
            let archive = try decoder.decode(VenusEnergyArchive.self, from: Data(contentsOf: path))
            guard archive.schemaVersion == 1, archive.reservePercent.isFinite, (0...100).contains(archive.reservePercent) else {
                throw VenusStoreError.message(VL("Некоректний формат історії.", "Invalid history format."))
            }
            guard archive.device != nil || archive.frames.isEmpty else { throw VenusStoreError.message(VL("Історія не містить станції.", "History has no station identity.")) }
            reservePercent = archive.reservePercent
            device = archive.device
            frames = Self.pruned(archive.frames, now: Date())
            rebuildIndex()
        } catch {
            persistenceError = VL("Не вдалося прочитати локальну історію.", "Could not read local history.")
        }
    }

    func setReservePercent(_ value: Double) {
        guard value.isFinite, (0...100).contains(value), value != reservePercent else { return }
        reservePercent = value
        save(force: true)
    }

    func record(report: VenusReport, device: VenusDiscoveredDevice, flow: VenusFlowState) {
        record(report: report, device: device, flow: flow, now: Date())
    }

    private func record(report: VenusReport, device: VenusDiscoveredDevice, flow: VenusFlowState, now: Date) {
        guard (try? report.validate()) != nil, let receipt = report.observationDate, receipt <= now else { return }
        let changedStation = self.device.map { !$0.isSameStation(as: device) } ?? false
        if changedStation {
            frames.removeAll()
            newest.removeAll()
            generation += 1
        }
        self.device = device
        latestReport = report
        acceptedAt = now
        self.flow = flow
        let values: [String: Double?] = [
            "battery_power_w": report.batteryPowerW, "grid_power_w": report.gridPowerW,
            "offgrid_power_w": report.offgridPowerW, "battery_remaining_wh": report.batteryRemainingWh,
            "battery_rated_wh": report.batteryRatedWh, "soc_percent": report.socPercent
        ]
        var metrics: [String: VenusEnergySample] = [:]
        for key in Self.keys {
            guard let value = values[key] ?? nil, Self.valid(value, key: key),
                  let raw = report.metricObservedAt?[key], let date = VenusReport.date(raw),
                  date <= now, date >= now.addingTimeInterval(-Self.horizon),
                  newest[key].map({ date > $0 }) ?? true else { continue }
            metrics[key] = VenusEnergySample(value: value, date: date)
            newest[key] = date
        }
        if !metrics.isEmpty { frames.append(VenusEnergyFrame(metrics: metrics)) }
        frames = Self.pruned(frames, now: now)
        historyCount = frames.count
        save(force: changedStation)
    }

    func stop() { save(force: true, wait: true) }

    func series(hours: Int, chargingGridSign: Int? = nil, holdingLastKnown: Bool = false, now: Date = Date()) -> [VenusEnergySeries] {
        let hours = [1, 3, 5, 24].contains(hours) ? hours : 1
        let start = now.addingTimeInterval(-Double(hours) * 3600)
        func points(_ key: String) -> [VenusEnergyPoint] {
            let actual = samples(key).map { VenusEnergyPoint(date: $0.date, value: $0.value) }
            return Self.windowPoints(actual, start: start, end: now, holdingLastKnown: holdingLastKnown)
        }
        func parts(_ points: [VenusEnergyPoint]) -> [[VenusEnergyPoint]] {
            holdingLastKnown ? (points.isEmpty ? [] : [points]) : Self.segments(points)
        }
        let grid = points("grid_power_w")
        let sign = chargingGridSign.flatMap { [-1, 1].contains($0) ? $0 : nil }
            ?? (VenusModel.identify(device?.name) == .venusE ? -1 : nil)
        var result: [VenusEnergySeries] = []
        var gridOutput: [VenusEnergyPoint] = []
        if !grid.isEmpty, let sign {
            let input = grid.map { VenusEnergyPoint(date: $0.date, value: max(0, $0.value * Double(sign))) }
            let output = grid.map { VenusEnergyPoint(date: $0.date, value: max(0, -$0.value * Double(sign))) }
            // This is an AC-channel projection, never net battery charge/discharge.
            // Keep real zero samples around a pulse; omit only an entirely inactive opposite channel.
            if input.contains(where: { $0.value > 0 }) || (!holdingLastKnown && !output.contains(where: { $0.value > 0 })) {
                result.append(VenusEnergySeries(id: "grid_input_w", title: VL("Заряд", "Charge"), segments: parts(input)))
            }
            if output.contains(where: { $0.value > 0 }) {
                gridOutput = output
            }
        }
        let backup = points("offgrid_power_w").filter { $0.value >= 0 }
        let discharge = Self.dischargePoints(grid: gridOutput, backup: backup)
        if !discharge.isEmpty { result.append(VenusEnergySeries(id: "output_w", title: VL("Розряд", "Discharge"), segments: parts(discharge))) }
        return result
    }

    // Visual carry only: retain a real predecessor and its original clock. Neither an
    // endpoint sample nor a fresh measurement is manufactured for the display window.
    private nonisolated static func windowPoints(_ points: [VenusEnergyPoint], start: Date, end: Date,
                                                 holdingLastKnown: Bool) -> [VenusEnergyPoint] {
        let actual = points.filter { $0.value.isFinite && $0.date <= end }.sorted { $0.date < $1.date }
        let visible = actual.filter { $0.date >= start }
        guard holdingLastKnown, visible.first?.date != start,
              let previous = actual.last(where: { $0.date < start }) else { return visible }
        return [previous] + visible
    }

    private nonisolated static func dischargePoints(grid: [VenusEnergyPoint], backup: [VenusEnergyPoint]) -> [VenusEnergyPoint] {
        let dates = Set((grid + backup).map(\.date)).sorted()
        var gridIndex = 0, backupIndex = 0
        var latestGrid: VenusEnergyPoint?, latestBackup: VenusEnergyPoint?
        var result: [VenusEnergyPoint] = []
        for date in dates {
            while gridIndex < grid.count, grid[gridIndex].date <= date { latestGrid = grid[gridIndex]; gridIndex += 1 }
            while backupIndex < backup.count, backup[backupIndex].date <= date { latestBackup = backup[backupIndex]; backupIndex += 1 }
            let currentGrid = latestGrid.flatMap { date.timeIntervalSince($0.date) <= 90 ? $0 : nil }
            let currentBackup = latestBackup.flatMap { date.timeIntervalSince($0.date) <= 90 ? $0 : nil }
            let chosen: VenusEnergyPoint?
            if let currentBackup, currentBackup.value > 0 { chosen = currentBackup }
            else if let currentGrid, currentGrid.value > 0 { chosen = currentGrid }
            else { chosen = currentBackup ?? currentGrid }
            // The projection never stamps a retained source value with another channel's receipt.
            if let chosen, result.last.map({ chosen.date > $0.date }) ?? true { result.append(chosen) }
        }
        return result
    }

    func forecast(now: Date = Date(), outageStart: Date? = nil, outageEnd: Date? = nil) -> VenusEnergyForecast {
        var result = VenusEnergyForecast(reservePercent: reservePercent)
        guard let report = latestReport, let receipt = report.observationDate, (0...90).contains(now.timeIntervalSince(receipt)) else { return result }
        let full = actualFresh(report, "soc_percent", now: now) && report.socPercent == 100
        if full { result.status = .full }
        if flow == .standby || flow == .mains {
            result.status = full ? .full : .standby
            return result
        }
        guard let remaining = report.batteryRemainingWh, Self.valid(remaining, key: "battery_remaining_wh"),
              actualFresh(report, "battery_remaining_wh", now: now),
              let rated = report.batteryRatedWh, rated.isFinite, rated > 0, rated <= 1_000_000,
              let ratedClock = report.metricObservedAt?["battery_rated_wh"].flatMap(VenusReport.date), ratedClock <= (acceptedAt ?? .distantPast), ratedClock <= now,
              remaining <= rated * 1.02 else { return result }
        let available = max(0, remaining - rated * reservePercent / 100)
        result.availableWh = available
        var rate: Double?
        var charging: Bool?
        if let power = report.batteryPowerW, actualFresh(report, "battery_power_w", now: now), abs(power) < 5 { return result }
        if let power = report.batteryPowerW, actualFresh(report, "battery_power_w", now: now), abs(power) >= 5,
           flow == .charging || flow == .supplyingHome {
            rate = abs(power)
            charging = flow == .charging
            result.basis = .batteryPower
        } else if let trend = Self.trend(samples("battery_remaining_wh"), rated: rated, now: now) {
            rate = abs(trend)
            charging = trend > 0
            result.basis = .energyTrend
        }
        guard let rate, rate.isFinite, (5...20_000).contains(rate), let charging else { return result }
        result.rateW = rate
        result.status = charging ? (full ? .full : .charging) : .supplying
        if charging {
            let hours = full ? 0 : max(0, rated - remaining) / rate
            if hours.isFinite, hours <= 24 * 30 { result.chargeHours = hours }
        } else {
            let hours = available / rate
            if hours.isFinite, hours <= 24 * 30 { result.runtimeHours = hours }
            if let start = outageStart, let end = outageEnd, end > now, end > start {
                let upcoming = start > now
                let duration = end.timeIntervalSince(now) / 3600
                if duration.isFinite, duration > 0, duration <= 48 {
                    result.upcomingOutage = upcoming
                    result.outageHours = duration
                    result.enoughForOutage = available >= rate * duration
                    result.budgetW = floor(available / duration / 10) * 10
                }
            }
        }
        return result
    }

    private func samples(_ key: String) -> [VenusEnergySample] {
        frames.compactMap { $0.metrics[key] }.sorted { $0.date < $1.date }
    }

    private func actualFresh(_ report: VenusReport, _ key: String, now: Date) -> Bool {
        guard let clock = report.metricObservedAt?[key].flatMap(VenusReport.date), clock <= (acceptedAt ?? .distantPast) else { return false }
        return (0...90).contains(now.timeIntervalSince(clock))
    }

    private func rebuildIndex() {
        newest.removeAll()
        for frame in frames { for (key, sample) in frame.metrics { newest[key] = max(newest[key] ?? .distantPast, sample.date) } }
        historyCount = frames.count
    }

    private nonisolated static func valid(_ value: Double, key: String) -> Bool {
        guard value.isFinite else { return false }
        switch key {
        case "battery_power_w", "grid_power_w", "offgrid_power_w": return abs(value) <= 20_000
        case "battery_remaining_wh", "battery_rated_wh": return (0...1_000_000).contains(value)
        case "soc_percent": return (0...100).contains(value)
        default: return false
        }
    }

    private nonisolated static func pruned(_ frames: [VenusEnergyFrame], now: Date) -> [VenusEnergyFrame] {
        var newest: [String: Date] = [:]
        let validFrames = frames.compactMap { frame -> VenusEnergyFrame? in
            var metrics: [String: VenusEnergySample] = [:]
            for (key, sample) in frame.metrics {
                guard valid(sample.value, key: key), sample.date.timeIntervalSince1970.isFinite,
                      sample.date <= now, sample.date >= now.addingTimeInterval(-48 * 3600),
                      newest[key].map({ sample.date > $0 }) ?? true else { continue }
                metrics[key] = sample
                newest[key] = sample.date
            }
            return metrics.isEmpty ? nil : VenusEnergyFrame(metrics: metrics)
        }
        return Array(validFrames.suffix(18_000))
    }

    private nonisolated static func segments(_ points: [VenusEnergyPoint]) -> [[VenusEnergyPoint]] {
        var result: [[VenusEnergyPoint]] = []
        for point in points {
            if let previous = result.last?.last, point.date.timeIntervalSince(previous.date) <= 90 {
                result[result.count - 1].append(point)
            } else { result.append([point]) }
        }
        return result
    }

    private nonisolated static func trend(_ values: [VenusEnergySample], rated: Double, now: Date) -> Double? {
        let recent = values.filter { (0...600).contains(now.timeIntervalSince($0.date)) }.sorted { $0.date < $1.date }
        var values: [VenusEnergySample] = []
        for value in recent {
            if let previous = values.last, value.date.timeIntervalSince(previous.date) > 90 { values.removeAll() }
            values.append(value)
        }
        guard values.count >= 3, let first = values.first, let last = values.last,
              now.timeIntervalSince(last.date) <= 90, last.date.timeIntervalSince(first.date) >= 120,
              zip(values, values.dropFirst()).allSatisfy({ $1.date.timeIntervalSince($0.date) <= 90 }) else { return nil }
        let delta = last.value - first.value
        guard abs(delta) >= max(2, rated * 0.001) else { return nil }
        // Direction must be consistent; a charge/discharge transition is not a forecast.
        guard zip(values, values.dropFirst()).allSatisfy({ delta > 0 ? $1.value >= $0.value : $1.value <= $0.value }) else { return nil }
        let rate = delta * 3600 / last.date.timeIntervalSince(first.date)
        return rate.isFinite && (5...20_000).contains(abs(rate)) ? rate : nil
    }

    private func save(force: Bool = false, wait: Bool = false) {
        let now = Date()
        guard force || now.timeIntervalSince(lastSave) >= 60 else { return }
        lastSave = now
        let archive = VenusEnergyArchive(device: device, reservePercent: reservePercent, frames: frames)
        let path = directory.appendingPathComponent("energy.local.json")
        let directory = directory
        let expectedGeneration = generation
        let work: @Sendable () -> Void = { [weak self] in
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .secondsSince1970
                let data = try encoder.encode(archive)
                try data.write(to: path, options: [.atomic, .completeFileProtectionUnlessOpen])
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
                Task { @MainActor [weak self] in if self?.generation == expectedGeneration { self?.persistenceError = nil } }
            } catch {
                Task { @MainActor [weak self] in if self?.generation == expectedGeneration { self?.persistenceError = VL("Не вдалося зберегти локальну історію.", "Could not save local history.") } }
            }
        }
        if wait { writer.sync(execute: work) } else { writer.async(execute: work) }
    }

    static func selfCheck() throws {
        func expect(_ value: @autoclosure () -> Bool, _ message: String) throws {
            guard value() else { throw VenusStoreError.message("Energy: \(message)") }
        }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("venus-energy-check-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = VenusEnergyStore(directory: directory)
        let device = VenusDiscoveredDevice(name: "VenusE3.0", ip: "192.168.1.2", port: 30000, firmware: 150, wifiMac: nil, bleMac: nil)
        func report(at date: Date, remaining: Double = 3000, battery: Double? = nil, grid: Double = -1990, clock: Date? = nil, soc: Double = 60) throws -> VenusReport {
            let dateString = ISO8601DateFormatter().string(from: date)
            let metricString = ISO8601DateFormatter().string(from: clock ?? date)
            var data: [String: Any] = ["schema_version": 1, "observed_at": dateString, "soc_percent": soc,
                "battery_remaining_wh": remaining, "battery_rated_wh": 5000, "grid_power_w": grid,
                "metric_observed_at": ["soc_percent": metricString, "battery_remaining_wh": metricString, "battery_rated_wh": metricString, "grid_power_w": metricString, "battery_power_w": metricString]]
            if let battery { data["battery_power_w"] = battery }
            return try JSONDecoder().decode(VenusReport.self, from: JSONSerialization.data(withJSONObject: data))
        }
        for (seconds, wh) in [(-180.0, 3015.0), (-120, 3010), (-60, 3005), (0, 3000)] {
            store.record(report: try report(at: now.addingTimeInterval(seconds), remaining: wh), device: device, flow: .supplyingHome, now: now)
        }
        try expect(store.historyCount == 4, "actual samples")
        store.record(report: try report(at: now, clock: now), device: device, flow: .supplyingHome, now: now)
        try expect(store.historyCount == 4, "retained clocks deduplicated")
        let history = store.series(hours: 1, now: now)
        try expect(history.map(\.id) == ["grid_input_w"] && history[0].segments.flatMap({ $0 }).map(\.value) == [1990, 1990, 1990, 1990], "E3 negative AC input becomes positive without battery substitution")
        try expect(history[0].segments[0][0].date == now.addingTimeInterval(-180), "projection preserves original source clock")
        let reversed = store.series(hours: 1, chargingGridSign: 1, now: now)
        try expect(reversed.map(\.id) == ["output_w"] && reversed[0].segments[0][0].value == 1990, "explicit calibration overrides E3 history profile")
        let discharge = store.forecast(now: now, outageStart: now.addingTimeInterval(-100), outageEnd: now.addingTimeInterval(3600))
        try expect(discharge.status == .supplying && discharge.basis == .energyTrend && discharge.rateW == 300, "Wh trend rate")
        try expect(abs((discharge.runtimeHours ?? 0) - 2000.0 / 300) < 0.001 && discharge.enoughForOutage == true && discharge.budgetW == 2000, "reserve runtime and current outage")
        let future = store.forecast(now: now, outageStart: now.addingTimeInterval(3600), outageEnd: now.addingTimeInterval(7200))
        try expect(future.upcomingOutage && future.outageHours == 2, "upcoming forecast includes discharge before outage")
        try expect(store.forecast(now: now.addingTimeInterval(91)).status == .collecting, "stale forecast")
        store.record(report: try report(at: now, battery: 1000), device: device, flow: .charging, now: now)
        let charge = store.forecast(now: now)
        try expect(charge.status == .charging && charge.chargeHours == 2 && charge.basis == .batteryPower, "actual battery charge ETA")
        store.record(report: try report(at: now, battery: 1000), device: device, flow: .supplyingHome, now: now)
        let beforeOutage = store.forecast(now: now, outageStart: now.addingTimeInterval(7200), outageEnd: now.addingTimeInterval(10800))
        try expect(beforeOutage.runtimeHours == 2 && beforeOutage.enoughForOutage == false && beforeOutage.budgetW == 660, "pre-outage drain cannot falsely promise enough energy")
        store.record(report: try report(at: now, battery: 0), device: device, flow: .charging, now: now)
        try expect(store.forecast(now: now).chargeHours == nil, "zero battery power cannot revive an old trend")
        store.record(report: try report(at: now, battery: 1000, clock: now.addingTimeInterval(1)), device: device, flow: .charging, now: now)
        try expect(store.forecast(now: now).status == .collecting, "future field clocks cannot forecast")
        try expect(store.forecast(now: now.addingTimeInterval(2)).status == .collecting, "rejected future fields do not become valid as time passes")
        store.setReservePercent(40)
        try expect(store.reservePercent == 40, "reserve setting")
        store.setReservePercent(.nan)
        store.setReservePercent(101)
        try expect(store.reservePercent == 40, "invalid reserve ignored")
        store.record(report: try report(at: now, battery: 0), device: device, flow: .standby, now: now)
        try expect(store.forecast(now: now).status == .standby && store.forecast(now: now).runtimeHours == nil, "zero is not infinity")
        store.record(report: try report(at: now, battery: 1000, soc: 100), device: device, flow: .charging, now: now)
        try expect(store.forecast(now: now).status == .full, "full battery")
        let other = VenusDiscoveredDevice(name: "Venus A", ip: "192.168.1.3", port: 30000, firmware: 150, wifiMac: nil, bleMac: nil)
        store.record(report: try report(at: now), device: other, flow: .unknown, now: now)
        try expect(store.historyCount == 1 && store.forecast(now: now).rateW == nil, "station identity isolation and grid not battery")
        let unknownDirection = store.series(hours: 1, now: now)
        try expect(unknownDirection.isEmpty, "uncalibrated grid direction is not labelled charge or discharge")
        let combinedOutput = Self.dischargePoints(grid: [.init(date: now.addingTimeInterval(-30), value: 300), .init(date: now, value: 400)],
                                                  backup: [.init(date: now.addingTimeInterval(-60), value: 800), .init(date: now.addingTimeInterval(-20), value: 0)])
        try expect(combinedOutput.map(\.value) == [800, 300, 400] && combinedOutput.map(\.date) == [now.addingTimeInterval(-60), now.addingTimeInterval(-30), now], "one discharge projection preserves backup and export with their original clocks")
        let retainedOutput = Self.dischargePoints(grid: [.init(date: now, value: 400)], backup: [.init(date: now.addingTimeInterval(-30), value: 800)])
        try expect(retainedOutput.count == 1 && retainedOutput[0].date == now.addingTimeInterval(-30), "a retained backup sample does not inherit the grid receipt")
        let pulse = [VenusEnergyPoint(date: now.addingTimeInterval(-60), value: 0),
                     VenusEnergyPoint(date: now.addingTimeInterval(-30), value: 1990), .init(date: now, value: 0)]
        try expect(Self.segments(pulse).first?.map(\.value) == [0, 1990, 0], "real short pulse and surrounding zeros are retained")
        store.record(report: try report(at: now.addingTimeInterval(10)), device: other, flow: .unknown, now: now)
        try expect(store.historyCount == 1, "future report rejected")
        let split = Self.segments([.init(date: now.addingTimeInterval(-200), value: 1), .init(date: now.addingTimeInterval(-140), value: 2), .init(date: now, value: 3)])
        try expect(split.map(\.count) == [2, 1], "chart gaps")
        let held = Self.windowPoints([.init(date: now.addingTimeInterval(-4000), value: 12),
                                     .init(date: now.addingTimeInterval(-300), value: 20), .init(date: now.addingTimeInterval(-10), value: 30)],
                                    start: now.addingTimeInterval(-3600), end: now, holdingLastKnown: true)
        try expect(held.map(\.value) == [12, 20, 30] && held.last?.date == now.addingTimeInterval(-10), "visual carry retains actual clocks and does not append now")
        let zeroStore = VenusEnergyStore(directory: directory.appendingPathComponent("zero"))
        zeroStore.record(report: try report(at: now, grid: 0), device: device, flow: .standby, now: now)
        try expect(zeroStore.series(hours: 1, holdingLastKnown: true, now: now).allSatisfy { $0.id != "grid_input_w" }, "zero charge channel is hidden only in visual projection")
        try expect(zeroStore.series(hours: 1, now: now).first?.id == "grid_input_w", "raw series remains unchanged")
        zeroStore.stop()
        let carryStore = VenusEnergyStore(directory: directory.appendingPathComponent("carry"))
        carryStore.record(report: try report(at: now.addingTimeInterval(-300)), device: device, flow: .charging, now: now)
        carryStore.record(report: try report(at: now.addingTimeInterval(-10)), device: device, flow: .charging, now: now)
        try expect(carryStore.series(hours: 1, now: now).first?.segments.count == 2
                   && carryStore.series(hours: 1, holdingLastKnown: true, now: now).first?.segments.count == 1,
                   "only held visualization bridges a real missing interval")
        carryStore.stop()
        let heldHistory = store.series(hours: 1, chargingGridSign: 1, holdingLastKnown: true, now: now)
        try expect(heldHistory.allSatisfy { $0.segments.count <= 1 }, "held visual projection bridges gaps")
        let expired = VenusEnergyFrame(metrics: ["grid_power_w": .init(value: 1, date: now.addingTimeInterval(-48 * 3600 - 1))])
        try expect(Self.pruned([expired], now: now).isEmpty, "48 hour pruning")
        let futureSample = VenusEnergyFrame(metrics: ["grid_power_w": .init(value: 1, date: now.addingTimeInterval(1))])
        try expect(Self.pruned([futureSample], now: now).isEmpty, "future sample rejected")
        let bounded = (0..<18_001).map { index in
            VenusEnergyFrame(metrics: ["grid_power_w": .init(value: 1, date: now.addingTimeInterval(Double(index - 18_000)))])
        }
        try expect(Self.pruned(bounded, now: now).count == 18_000, "bounded history")
        let wild = [VenusEnergySample(value: 0, date: now.addingTimeInterval(-120)), .init(value: 2000, date: now.addingTimeInterval(-60)), .init(value: 4000, date: now)]
        try expect(Self.trend(wild, rated: 5000, now: now) == nil, "implausible trend rejected")
        let gap = [VenusEnergySample(value: 3010, date: now.addingTimeInterval(-240)), .init(value: 3005, date: now.addingTimeInterval(-180)), .init(value: 3000, date: now)]
        try expect(Self.trend(gap, rated: 5000, now: now) == nil, "forecast does not bridge a missing interval")
        let flat = [VenusEnergySample(value: 3000, date: now.addingTimeInterval(-120)), .init(value: 3000, date: now.addingTimeInterval(-60)), .init(value: 3000, date: now)]
        try expect(Self.trend(flat, rated: 5000, now: now) == nil, "zero energy delta is not infinity")
        store.setReservePercent(100)
        store.record(report: try report(at: now.addingTimeInterval(1), battery: 1000), device: other, flow: .supplyingHome, now: now.addingTimeInterval(1))
        let emptyBudget = store.forecast(now: now.addingTimeInterval(1), outageStart: now, outageEnd: now.addingTimeInterval(3600))
        try expect(emptyBudget.runtimeHours == 0 && emptyBudget.enoughForOutage == false && emptyBudget.budgetW == 0, "reserve floor and insufficient outage budget")
        store.stop()
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("energy.local.json").path)
        try expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600, "private local archive")
    }
}
