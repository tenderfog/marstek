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
        guard apiOnline else { return .init(level: .unavailable, explanation: VL("GRID — немає свіжих даних станції. Пунктир означає невідомий стан, а не вимкнену мережу.", "GRID — no recent station data. A dotted indicator means unknown, not that the grid is off.")) }
        let grid = power(gridPowerW, signed: true)
        let backup = power(offgridPowerW)
        if let grid, abs(grid) > 25 {
            return .init(level: .confirmedOn, explanation: VL("GRID — свіжий API підтверджує обмін енергією з мережею. Світіння показує цей потік; фізичний LED окремо не зчитується.", "GRID — recent API data confirms energy exchange with the grid. The glow represents this flow; the physical LED is not read separately."))
        }
        if flow == .mains {
            return .init(level: .confirmedOn, explanation: VL("GRID — наявність загальної мережі нещодавно підтверджено вручну. Фізичний LED окремо не зчитується.", "GRID — grid availability was recently confirmed manually. The physical LED is not read separately."))
        }
        if grid == 0, let backup, backup > 25, flow == .supplyingHome {
            return .init(level: .estimatedOff, explanation: VL("GRID — імовірно не використовується: є резервне навантаження та розряджання без мережевого потоку. Мережа може залишатися підключеною, зокрема в ручному режимі; це лише оцінка.", "GRID — likely unused: backup load and discharge are present without grid flow. The grid may remain connected, especially in Manual mode; this is only an estimate."))
        }
        return .init(level: .unavailable, explanation: VL("GRID — даних недостатньо для оцінки. Нульова потужність або неповна батарея не доводять відсутність мережі; фізичний LED не зчитується.", "GRID — insufficient data to estimate its state. Zero power or a partially charged battery does not prove the grid is absent; the physical LED is not read."))
    }

    static func backup(soc: Double?, offgridPowerW: Double?, model: VenusModel, apiOnline: Bool) -> Self {
        guard apiOnline else { return .init(level: .unavailable, explanation: VL("BACKUP — немає свіжих даних станції. Готовність резервного виходу невідома.", "BACKUP — no recent station data. Backup output readiness is unknown.")) }
        let backup = power(offgridPowerW)
        if let backup, backup > 25 {
            return .init(level: .confirmedOn, explanation: VL("BACKUP — API підтверджує живлення навантаження від резервного виходу. Це потік на виході, а не окреме читання фізичного LED чи доказ відсутності загальної мережі.", "BACKUP — the API confirms power flowing to the backup load. This is output flow, not a separate physical LED reading or proof of grid loss."))
        }
        if model == .venusE, backup == 0, charge(soc) != nil {
            return .init(level: .estimatedOn, explanation: VL("BACKUP — імовірно готовий без навантаження: Venus E3 відповідає, заряд відомий, на виході 0 Вт. За звичайною поведінкою станції індикатор залишається увімкненим; готовність окремо не підтверджена API.", "BACKUP — likely ready without load: Venus E3 responds, charge is known, and output is 0 W. The indicator normally stays on; readiness is not separately confirmed by the API."))
        }
        return .init(level: .unavailable, explanation: VL("BACKUP — готовність не підтверджена. Нульове або відсутнє навантаження не означає, що резервний вихід вимкнений; фізичний LED не зчитується.", "BACKUP — readiness is unconfirmed. Zero or missing load does not mean the backup output is off; the physical LED is not read."))
    }

    static func pv(powerW: Double?, apiOnline: Bool) -> Self {
        if apiOnline, let value = power(powerW), value > 0 {
            return .init(level: .estimatedOn, explanation: VL("PV — API показує сонячну генерацію. Світіння оцінено за потужністю; фізичний LED PV окремо не зчитується.", "PV — the API reports solar generation. The glow is estimated from power; the physical PV LED is not read separately."))
        }
        return .init(level: .unavailable, explanation: VL("PV — стан індикатора невідомий. Нульова або відсутня генерація не підтверджує вимкнений фізичний LED.", "PV — indicator state unknown. Zero or missing generation does not confirm that the physical LED is off."))
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
            try check(grid(soc: soc, gridPowerW: 0, offgridPowerW: 0, flow: .standby, apiOnline: true).level == .unavailable)
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
