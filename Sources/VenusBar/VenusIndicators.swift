import Foundation

/// Presentation evidence only. These estimates never determine power source,
/// operating mode, boiler permission, or any other automation decision.
struct VenusIndicatorEvidence: Equatable {
    enum Level { case confirmedOn, estimatedOn, estimatedOff, unavailable }
    let level: Level
    let explanation: String

    private static func power(_ value: Double?, signed: Bool = false) -> Double? {
        guard let value, value.isFinite, abs(value) <= 20_000, signed || value >= 0 else { return nil }
        return value
    }
    private static func charge(_ value: Double?) -> Double? {
        guard let value, value.isFinite, (0...100).contains(value) else { return nil }
        return value
    }

    static func grid(soc: Double?, gridPowerW: Double?, offgridPowerW: Double?,
                     flow: VenusFlowState, apiOnline: Bool) -> Self {
        guard apiOnline else { return .init(level: .unavailable, explanation: "GRID — немає свіжих даних станції. Пунктир означає невідомий стан, а не вимкнену мережу.") }
        let grid = power(gridPowerW, signed: true)
        let backup = power(offgridPowerW)
        if let grid, abs(grid) > 25 {
            return .init(level: .confirmedOn, explanation: "GRID — свіжий API підтверджує обмін енергією з мережею. Світіння показує цей потік; фізичний LED окремо не зчитується.")
        }
        if flow == .mains {
            return .init(level: .confirmedOn, explanation: "GRID — наявність загальної мережі нещодавно підтверджено вручну. Фізичний LED окремо не зчитується.")
        }
        if grid == 0, backup == 0, let soc = charge(soc), soc >= 99.5 {
            return .init(level: .estimatedOn, explanation: "GRID — імовірно підключено: батарея повна, обидва AC-потоки нульові. Це оцінка для індикації; 0 Вт сам по собі не підтверджує наявність мережі.")
        }
        if grid == 0, let backup, backup > 25, flow == .supplyingHome {
            return .init(level: .estimatedOff, explanation: "GRID — імовірно не використовується: є резервне навантаження та розряджання без мережевого потоку. Мережа може залишатися підключеною, зокрема в ручному режимі; це лише оцінка.")
        }
        return .init(level: .unavailable, explanation: "GRID — даних недостатньо для оцінки. Нульова потужність або неповна батарея не доводять відсутність мережі; фізичний LED не зчитується.")
    }

    static func backup(soc: Double?, offgridPowerW: Double?, model: VenusModel, apiOnline: Bool) -> Self {
        guard apiOnline else { return .init(level: .unavailable, explanation: "BACKUP — немає свіжих даних станції. Готовність резервного виходу невідома.") }
        let backup = power(offgridPowerW)
        if let backup, backup > 25 {
            return .init(level: .confirmedOn, explanation: "BACKUP — API підтверджує живлення навантаження від резервного виходу. Це потік на виході, а не окреме читання фізичного LED чи доказ відсутності загальної мережі.")
        }
        if model == .venusE, backup == 0, charge(soc) != nil {
            return .init(level: .estimatedOn, explanation: "BACKUP — імовірно готовий без навантаження: Venus E3 відповідає, заряд відомий, на виході 0 Вт. За звичайною поведінкою станції індикатор залишається увімкненим; готовність окремо не підтверджена API.")
        }
        return .init(level: .unavailable, explanation: "BACKUP — готовність не підтверджена. Нульове або відсутнє навантаження не означає, що резервний вихід вимкнений; фізичний LED не зчитується.")
    }

    static func pv(powerW: Double?, apiOnline: Bool) -> Self {
        if apiOnline, let value = power(powerW), value > 0 {
            return .init(level: .estimatedOn, explanation: "PV — API показує сонячну генерацію. Світіння оцінено за потужністю; фізичний LED PV окремо не зчитується.")
        }
        return .init(level: .unavailable, explanation: "PV — стан індикатора невідомий. Нульова або відсутня генерація не підтверджує вимкнений фізичний LED.")
    }

    /// Pure visual-policy checks; no sockets, persisted source claims, or device commands.
    static func selfCheck() throws {
        func check(_ condition: Bool) throws {
            if !condition { throw VenusStoreError.message("Indicator evidence self-check failed") }
        }
        for watts in [-26.0, 26.0, -1990.0] {
            try check(grid(soc: nil, gridPowerW: watts, offgridPowerW: nil, flow: .unknown, apiOnline: true).level == .confirmedOn)
        }
        try check(grid(soc: nil, gridPowerW: nil, offgridPowerW: nil, flow: .mains, apiOnline: true).level == .confirmedOn)
        for soc in [99.5, 100.0] {
            try check(grid(soc: soc, gridPowerW: 0, offgridPowerW: 0, flow: .standby, apiOnline: true).level == .estimatedOn)
        }
        for soc in [0.0, 30, 99.49] {
            try check(grid(soc: soc, gridPowerW: 0, offgridPowerW: 0, flow: .standby, apiOnline: true).level == .unavailable)
        }
        try check(grid(soc: 70, gridPowerW: 0, offgridPowerW: 500, flow: .supplyingHome, apiOnline: true).level == .estimatedOff)
        try check(grid(soc: 70, gridPowerW: 0, offgridPowerW: 500, flow: .unknown, apiOnline: true).level == .unavailable)
        try check(grid(soc: 100, gridPowerW: 0, offgridPowerW: nil, flow: .standby, apiOnline: true).level == .unavailable)
        try check(grid(soc: nil, gridPowerW: 0, offgridPowerW: 0, flow: .standby, apiOnline: true).level == .unavailable)
        try check(grid(soc: 100, gridPowerW: 0, offgridPowerW: 0, flow: .standby, apiOnline: false).level == .unavailable)
        try check(grid(soc: 100, gridPowerW: 1000, offgridPowerW: 0, flow: .charging, apiOnline: false).level == .unavailable)
        try check(grid(soc: .nan, gridPowerW: .infinity, offgridPowerW: 0, flow: .unknown, apiOnline: true).level == .unavailable)
        try check(backup(soc: 70, offgridPowerW: 0, model: .venusE, apiOnline: true).level == .estimatedOn)
        try check(backup(soc: nil, offgridPowerW: 0, model: .venusE, apiOnline: true).level == .unavailable)
        try check(backup(soc: 70, offgridPowerW: 0, model: .venusA, apiOnline: true).level == .unavailable)
        try check(backup(soc: 70, offgridPowerW: 500, model: .venusA, apiOnline: true).level == .confirmedOn)
        try check(backup(soc: 70, offgridPowerW: 500, model: .venusE, apiOnline: false).level == .unavailable)
        try check(backup(soc: 70, offgridPowerW: nil, model: .venusE, apiOnline: true).level == .unavailable)
        try check(pv(powerW: 1, apiOnline: true).level == .estimatedOn)
        try check(pv(powerW: 0, apiOnline: true).level == .unavailable)
        try check(pv(powerW: nil, apiOnline: true).level == .unavailable)
        try check(pv(powerW: 100, apiOnline: false).level == .unavailable)
    }
}
