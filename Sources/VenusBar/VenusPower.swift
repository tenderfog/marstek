import Foundation

struct VenusPowerMetric {
    let watts: Double
    let metricKey: String
    let observedAt: String?
    let isFresh: Bool
    let title: String
    let meaning: String
    var observationDate: Date? { observedAt.flatMap(VenusReport.date) }
}

struct VenusPowerSnapshot {
    let charge: VenusPowerMetric?
    let output: VenusPowerMetric?
    let backupOutput: VenusPowerMetric?
    let gridOutput: VenusPowerMetric?
    let backupMaximumW: Double?
    let outputMaximumW: Double?
    let maximumSource: String?
    let maximumReferenceURL: URL?

    var chargeW: Double? { charge?.watts }
    var outputW: Double? { output?.watts }
    var chargeFresh: Bool { charge?.isFresh == true }
    var outputFresh: Bool { output?.isFresh == true }
    var utilization: Double? {
        guard let outputW, let outputMaximumW, outputMaximumW > 0 else { return nil }
        return outputW / outputMaximumW
    }
    var utilizationFresh: Bool { outputFresh && utilization != nil }
    var overMaximum: Bool { utilization.map { $0 > 1 } ?? false }

    // Official E3 brochure: 2.5kW on-grid and 2.5kVA rated backup, not the 3.5kVA peak.
    static let e3SpecificationURL = URL(string: "https://cdn.shopify.com/s/files/1/0746/1575/0952/files/MARSTEK_VENUS_E3.0_Brochure_EU_EN.pdf?v=1776130081")!

    static func make(report: VenusReport?, model: VenusModel, chargingGridSign: Int? = nil,
                     configuredMaximumW: Double? = nil, fresh: Bool = true, now: Date = Date()) -> Self {
        let knownBackupMaximum: Double? = model == .venusE ? 2500 : nil
        // Caller may supply only an API-confirmed maximum for the BACKUP channel.
        // SYS.SetPowerVersion is a grid limit and is not such a confirmation.
        let configured = configuredMaximumW.flatMap { $0.isFinite && $0 > 0 && $0 <= 20_000 ? $0 : nil }
        let backupMaximum = configured ?? knownBackupMaximum
        let sign = chargingGridSign.flatMap { [-1, 1].contains($0) ? $0 : nil } ?? (model == .venusE ? -1 : nil)
        let receiptFresh = report?.observationDate.map { (0...90).contains(now.timeIntervalSince($0)) } == true

        func metric(_ watts: Double, key: String, title: String, meaning: String) -> VenusPowerMetric? {
            guard watts.isFinite, (0...20_000).contains(watts) else { return nil }
            let clock = report?.metricObservedAt?[key]
            let date = clock.flatMap(VenusReport.date)
            if let date, date > now { return nil }
            let current = fresh && receiptFresh && date.map { (0...90).contains(now.timeIntervalSince($0)) } == true
            return VenusPowerMetric(watts: watts, metricKey: key, observedAt: clock, isFresh: current, title: title, meaning: meaning)
        }

        var charge: VenusPowerMetric?
        var gridOutput: VenusPowerMetric?
        if let grid = report?.gridPowerW, grid.isFinite, abs(grid) <= 20_000 {
            let inputMeaning = "Потік у мережевому AC-каналі до станції. Це не чиста потужність заряду батареї: частина енергії може живити резервний вихід, а перетворення має втрати. Напрямок — із профілю E3 або явного калібрування станції."
            let outputMeaning = "Потік із мережевого AC-виходу станції. Це не споживання всього дому й не доказ розряду батареї: Venus A може передавати сонячну енергію."
            if grid == 0 {
                charge = metric(0, key: "grid_power_w", title: "Вхід із мережі", meaning: inputMeaning)
                gridOutput = metric(0, key: "grid_power_w", title: "Вихід у мережу", meaning: outputMeaning)
            } else if let sign {
                if (grid < 0 ? -1 : 1) == sign {
                    charge = metric(abs(grid), key: "grid_power_w", title: "Вхід із мережі", meaning: inputMeaning)
                } else {
                    gridOutput = metric(abs(grid), key: "grid_power_w", title: "Вихід у мережу", meaning: outputMeaning)
                }
            }
        }

        let backup = report?.offgridPowerW.flatMap {
            metric($0, key: "offgrid_power_w", title: "Резервний вихід",
                   meaning: "Навантаження AC-порту BACKUP за API. Це вихід станції, а не чистий розряд батареї та не обов’язково навантаження всього дому. У Venus A джерелом також може бути сонце.")
        }
        // Preserve both actual channels; a zero backup reading must not hide a known grid export.
        let output: VenusPowerMetric?
        if let backup, backup.isFresh, backup.watts > 0 { output = backup }
        else if let gridOutput, gridOutput.isFresh, gridOutput.watts > 0 { output = gridOutput }
        else if let backup, backup.watts > 0 { output = backup }
        else if let gridOutput, gridOutput.watts > 0 { output = gridOutput }
        else { output = backup ?? gridOutput }
        let usesBackup = output?.metricKey == "offgrid_power_w"
        let maximum: Double? = output == nil || usesBackup ? backupMaximum : (model == .venusE ? 2500 : nil)
        let maximumSource: String?
        if maximum == nil { maximumSource = nil }
        else if (usesBackup || output == nil) && configured != nil {
            maximumSource = "Підтверджений API максимум резервного виходу."
        } else if usesBackup || output == nil {
            maximumSource = "Номінал резервного виходу E3: 2,5 кВА (2500 Вт за коефіцієнта потужності 1). Це не короткочасний піковий режим; реальна допустима активна потужність залежить від навантаження."
        } else {
            maximumSource = "Номінальна мережна AC-потужність E3: 2500 Вт. Фактично встановлений мережевий ліміт може бути нижчим; API його тут не підтвердив."
        }
        return Self(charge: charge, output: output, backupOutput: backup, gridOutput: gridOutput,
                    backupMaximumW: backupMaximum, outputMaximumW: maximum, maximumSource: maximumSource,
                    maximumReferenceURL: model == .venusE ? e3SpecificationURL : nil)
    }

    static func selfCheck() throws {
        func expect(_ value: @autoclosure () -> Bool, _ message: String) throws {
            guard value() else { throw VenusStoreError.message("Power: \(message)") }
        }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let clock = ISO8601DateFormatter().string(from: now)
        func report(_ values: [String: Double], clocks: [String: String]? = nil) throws -> VenusReport {
            var json: [String: Any] = ["schema_version": 1, "observed_at": clock,
                                      "metric_observed_at": clocks ?? values.mapValues { _ in clock }]
            for (key, value) in values { json[key] = value }
            return try JSONDecoder().decode(VenusReport.self, from: JSONSerialization.data(withJSONObject: json))
        }
        let concurrent = make(report: try report(["grid_power_w": -1990, "offgrid_power_w": 800]), model: .venusE, now: now)
        try expect(concurrent.chargeW == 1990 && concurrent.outputW == 800, "concurrent grid input and backup load")
        try expect(concurrent.charge?.metricKey == "grid_power_w" && concurrent.output?.metricKey == "offgrid_power_w", "distinct source channels")
        try expect(concurrent.outputMaximumW == 2500 && concurrent.utilization == 0.32, "800W / 2500W = 32 percent")
        try expect(concurrent.charge?.observedAt == clock && concurrent.chargeFresh && concurrent.outputFresh, "original source clocks")
        let zero = make(report: try report(["grid_power_w": 0, "offgrid_power_w": 0]), model: .venusE, now: now)
        try expect(zero.chargeW == 0 && zero.outputW == 0 && zero.utilization == 0, "actual zero load")
        let absent = make(report: try report([:]), model: .venusE, now: now)
        try expect(absent.chargeW == nil && absent.outputW == nil && absent.utilization == nil, "unknown is not zero")
        let overload = make(report: try report(["offgrid_power_w": 3000]), model: .venusE, now: now)
        try expect(overload.utilization == 1.2 && overload.overMaximum, "overload is not silently clamped")
        let export = make(report: try report(["grid_power_w": 800, "offgrid_power_w": 0]), model: .venusE, now: now)
        try expect(export.outputW == 800 && export.output?.metricKey == "grid_power_w" && export.chargeW == nil, "grid export is not hidden by zero backup")
        let solar = make(report: try report(["grid_power_w": 0, "offgrid_power_w": 800, "pv_power_w": 1000, "battery_power_w": 0]), model: .venusA, now: now)
        try expect(solar.outputW == 800 && solar.output?.metricKey == "offgrid_power_w" && solar.output?.title == "Резервний вихід", "A solar output is not called battery discharge")
        try expect(solar.outputMaximumW == nil && solar.utilization == nil, "unknown A variant has no invented maximum")
        let unknownDirection = make(report: try report(["grid_power_w": -1000, "battery_power_w": -1000]), model: .venusA, now: now)
        try expect(unknownDirection.chargeW == nil && unknownDirection.outputW == nil, "no guessed A grid or battery direction")
        let calibrated = make(report: try report(["grid_power_w": 1000]), model: .venusA, chargingGridSign: 1, now: now)
        try expect(calibrated.chargeW == 1000, "explicit station grid direction")
        let configured = make(report: try report(["offgrid_power_w": 800]), model: .unknown, configuredMaximumW: 1600, now: now)
        try expect(configured.outputMaximumW == 1600 && configured.utilization == 0.5, "explicit backup maximum")
        let wrongChannel = make(report: try report(["grid_power_w": 800]), model: .unknown, chargingGridSign: -1, configuredMaximumW: 1600, now: now)
        try expect(wrongChannel.outputW == 800 && wrongChannel.outputMaximumW == nil, "backup limit cannot constrain a different channel")
        let staleClock = ISO8601DateFormatter().string(from: now.addingTimeInterval(-91))
        let stale = make(report: try report(["grid_power_w": -1000, "offgrid_power_w": 800], clocks: ["grid_power_w": clock, "offgrid_power_w": staleClock]), model: .venusE, now: now)
        try expect(stale.chargeFresh && stale.outputW == 800 && !stale.outputFresh && !stale.utilizationFresh, "stale channel retains its own clock and is not live")
        try expect(stale.output?.observedAt == staleClock, "retained original time")
        let paused = make(report: try report(["offgrid_power_w": 800]), model: .venusE, fresh: false, now: now)
        try expect(paused.outputW == 800 && !paused.outputFresh, "paused is not live")
        let futureClock = ISO8601DateFormatter().string(from: now.addingTimeInterval(1))
        let future = make(report: try report(["offgrid_power_w": 800], clocks: ["offgrid_power_w": futureClock]), model: .venusE, now: now)
        try expect(future.outputW == nil, "future sample rejected")
        let negativeBackup = make(report: try report(["offgrid_power_w": -100]), model: .venusE, now: now)
        try expect(negativeBackup.outputW == nil, "backup input cannot be called load")
        let invalidLimit = make(report: try report(["offgrid_power_w": 800]), model: .unknown, configuredMaximumW: .nan, now: now)
        try expect(invalidLimit.outputMaximumW == nil, "invalid maximum rejected")
    }
}
