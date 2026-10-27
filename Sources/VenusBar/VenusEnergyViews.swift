import SwiftUI

@MainActor
struct VenusEnergyHistoryView: View {
    @ObservedObject private var localization = VenusLocalization.shared
    @ObservedObject var store: VenusEnergyStore
    var compact = false
    var chargingGridSign: Int? = nil
    @State private var hours = 1

    var body: some View {
        let now = Date()
        let start = now.addingTimeInterval(-Double(hours) * 3600)
        let series = store.series(hours: hours, chargingGridSign: chargingGridSign, now: now)
        return VStack(spacing: 2) {
            HStack(spacing: 6) {
                Text(VL("Історія потужності", "Power history")).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Spacer(minLength: 4)
                HStack(spacing: 2) {
                    ForEach([1, 3, 5, 24], id: \.self) { period in
                        Button { hours = period } label: {
                            Text(period == 24 ? VL("Доба", "24 h") : VL("\(period) год", "\(period) h")).font(.system(size: 11, weight: .medium)).monospacedDigit()
                        }
                        .buttonStyle(VenusHistoryPeriodStyle(selected: period == hours))
                        .accessibilityLabel(VL("Період графіка: \(period) год", "Chart period: \(period) hours"))
                        .accessibilityAddTraits(period == hours ? .isSelected : [])
                    }
                }.padding(2).background(.white.opacity(0.045), in: Capsule())
            }.frame(height: 28)
            if series.isEmpty {
                Text(VL("Історія з’явиться під час роботи", "History will appear as the station runs"))
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.35))
                    .frame(maxWidth: .infinity).frame(height: compact ? 60 : 72)
            } else {
                VenusEnergySparkline(series: series, start: start, end: now)
                    .frame(height: compact ? 60 : 72).transaction { $0.animation = nil }
            }
            timeAxis(start: start, end: now)
            legend(series)
        }
        .padding(.horizontal, 10).padding(.vertical, 6).frame(height: compact ? 128 : 140)
        .help(VL("Фактичні показники станції за останні \(hours) год. Пропуски понад 90 секунд розривають лінію. Мережевий канал — обмін через AC станції, не чиста потужність батареї й не споживання всього дому.", "Actual station readings over the last \(hours) hours. Gaps over 90 seconds break the line. The grid channel is AC exchange at the station, not net battery power or whole-home usage."))
    }

    private func timeAxis(start: Date, end: Date) -> some View {
        HStack {
            Text(clock(start))
            Spacer()
            Text(clock(start.addingTimeInterval(end.timeIntervalSince(start) / 2)))
            Spacer()
            Text(VL("Зараз \(clock(end))", "Now \(clock(end))"))
        }.font(.system(size: 10)).monospacedDigit().foregroundStyle(.white.opacity(0.35))
            .padding(.leading, 43).frame(height: 10)
    }

    private func clock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = localization.language.locale
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func legend(_ series: [VenusEnergySeries]) -> some View {
        HStack(spacing: 10) {
            ForEach(Array(series.enumerated()), id: \.element.id) { index, item in
                HStack(spacing: 4) {
                    Circle().fill(VenusEnergySparkline.color(item.id)).frame(width: 4, height: 4)
                    Text(seriesTitle(item.id)).lineLimit(1).minimumScaleFactor(0.85)
                        .help(seriesTitle(item.id))
                }
            }
            Spacer(minLength: 4)
            Text(currentOutputLabel).monospacedDigit().lineLimit(1).fixedSize()
                .foregroundStyle(.white.opacity(0.65)).help(VL("Навантаження резервного виходу за останньою відповіддю. Діапазон історії: \(rangeLabel(series)).", "Backup output load from the latest response. History range: \(rangeLabel(series))."))
            if let error = store.persistenceError {
                Image(systemName: "exclamationmark.circle").help(error).accessibilityLabel(error)
            }
        }.font(.system(size: 10)).foregroundStyle(.white.opacity(0.6)).frame(height: 12)
    }

    private func seriesTitle(_ id: String) -> String {
        switch id {
        case "grid_input_w": return VL("Заряд", "Charge")
        case "output_w": return VL("Розряд", "Discharge")
        case "battery_power_w": return VL("Батарея", "Battery")
        default: return VL("Мережевий потік", "Grid flow")
        }
    }

    private var currentOutputLabel: String {
        guard let report = store.latestReport, report.fresh("offgrid_power_w"),
              let watts = report.offgridPowerW, watts >= 0 else { return VL("Останні покази", "Last readings") }
        return VL("Зараз \(VenusVisuals.power(watts))", "Now \(VenusVisuals.power(watts))")
    }

    private func rangeLabel(_ series: [VenusEnergySeries]) -> String {
        let values = series.flatMap(\.segments).flatMap { $0 }.map(\.value).filter(\.isFinite)
        guard let minimum = values.min(), let maximum = values.max() else { return "" }
        if minimum == maximum { return VenusVisuals.power(minimum) }
        return "\(VenusVisuals.power(minimum))…\(VenusVisuals.power(maximum))"
    }
}

private struct VenusEnergySparkline: View {
    @ObservedObject private var localization = VenusLocalization.shared
    let series: [VenusEnergySeries]
    let start: Date
    let end: Date

    var body: some View {
        Canvas { context, size in
            let values = series.flatMap(\.segments).flatMap { $0 }.map(\.value).filter(\.isFinite)
            guard let minimum = values.min(), let maximum = values.max(), end > start else { return }
            let lower = min(0, minimum)
            let upper = max(0, maximum)
            let padding = max(upper - lower, 1) * 0.08
            let low = lower - padding
            let high = upper + padding
            let span = max(high - low, 1)
            let duration = end.timeIntervalSince(start)
            let plot = CGRect(x: 43, y: 4, width: max(1, size.width - 43), height: max(1, size.height - 8))
            func position(_ point: VenusEnergyPoint) -> CGPoint {
                let x = point.date.timeIntervalSince(start) / duration
                let y = (point.value - low) / span
                return CGPoint(x: plot.minX + min(plot.width, max(0, x * plot.width)), y: plot.minY + plot.height * (1 - y))
            }
            let zeroY = plot.minY + plot.height * (1 - (0 - low) / span)
            var baseline = Path()
            baseline.move(to: CGPoint(x: plot.minX, y: zeroY)); baseline.addLine(to: CGPoint(x: plot.maxX, y: zeroY))
            context.stroke(baseline, with: .color(.white.opacity(0.14)), style: StrokeStyle(lineWidth: 0.6, dash: [2, 4]))
            if upper > 0 {
                context.draw(Text(VenusVisuals.power(upper)).font(.system(size: 10)).foregroundColor(.white.opacity(0.4)),
                             at: CGPoint(x: 0, y: 0), anchor: .topLeading)
            }
            context.draw(Text(VenusVisuals.power(0)).font(.system(size: 10)).foregroundColor(.white.opacity(0.35)),
                         at: CGPoint(x: 0, y: min(size.height - 10, max(0, zeroY - 5))), anchor: .topLeading)
            if lower < 0 {
                context.draw(Text(VenusVisuals.power(lower)).font(.system(size: 10)).foregroundColor(.white.opacity(0.35)),
                             at: CGPoint(x: 0, y: size.height), anchor: .bottomLeading)
            }
            for item in series {
                for segment in item.segments {
                    let points = segment.filter { $0.value.isFinite && $0.date >= start && $0.date <= end }
                    guard let first = points.first else { continue }
                    var line = Path(); line.move(to: position(first))
                    var previous = first
                    for point in points.dropFirst() {
                        // Keep the visual gap rule even if a future data source forgets to segment.
                        if point.date.timeIntervalSince(previous.date) > 90 { line.move(to: position(point)) }
                        else {
                            let a = position(previous), b = position(point)
                            let area = CGRect(x: a.x, y: min(a.y, zeroY), width: max(0, b.x - a.x), height: abs(zeroY - a.y))
                            if area.width > 0, area.height > 0 {
                                context.fill(Path(area), with: .color(Self.color(item.id).opacity(0.075)))
                            }
                            line.addLine(to: CGPoint(x: position(point).x, y: position(previous).y))
                            line.addLine(to: position(point))
                        }
                        previous = point
                    }
                    context.stroke(line, with: .color(Self.color(item.id)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .miter))
                    if points.count == 1 {
                        let point = position(first)
                        context.fill(Path(ellipseIn: CGRect(x: point.x - 1.5, y: point.y - 1.5, width: 3, height: 3)), with: .color(Self.color(item.id)))
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(VL("Графік потужності станції у ватах. Розриви означають відсутні показники.", "Station power history in watts. Gaps indicate missing readings."))
    }

    static func color(_ id: String) -> Color {
        switch id {
        case "grid_input_w": return VenusVisuals.charging
        case "output_w", "grid_output_w", "offgrid_power_w": return VenusVisuals.supplying
        default: return .white.opacity(0.8)
        }
    }
}

@MainActor
struct VenusEnergyForecastView: View {
    @ObservedObject private var localization = VenusLocalization.shared
    @ObservedObject var energy: VenusEnergyStore
    @ObservedObject var outages: VenusOutagesStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let forecast = energy.forecast(now: context.date, outageStart: outages.currentOrNextOutageStart, outageEnd: outages.currentOrNextOutageEnd)
            if useful(forecast) {
                summary(forecast)
                    .padding(12).frame(height: 76)
                    .modifier(SwiftfulUICardSurface(backgroundColor: .white.opacity(0.025),
                                                   borderColor: accent(forecast).opacity(0.2), cornerRadius: 15))
                    .accessibilityElement(children: .combine)
            }
        }
    }

    private func useful(_ forecast: VenusEnergyForecast) -> Bool {
        (forecast.chargeHours.map { $0 > 0 && duration($0) != nil } ?? false)
        || duration(forecast.runtimeHours) != nil
        || (forecast.enoughForOutage != nil && outages.currentOrNextOutageEnd != nil)
    }

    private func summary(_ forecast: VenusEnergyForecast) -> some View {
        HStack(alignment: .center, spacing: 11) {
            Image(systemName: symbol(forecast))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(accent(forecast))
                .frame(width: 34, height: 34)
                .background(accent(forecast).opacity(0.1), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(resultTitle(forecast)).font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95)).lineLimit(1).minimumScaleFactor(0.85)
                Text(explanation(forecast)).font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6)).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func resultTitle(_ forecast: VenusEnergyForecast) -> String {
        if let enough = forecast.enoughForOutage, let end = outages.currentOrNextOutageEnd {
            return outageAdvice(forecast, enough: enough, end: end)
        }
        if let hours = forecast.chargeHours, hours > 0, let text = duration(hours) {
            return VL("До 100% — \(text)", "To 100% — \(text)")
        }
        if let text = duration(forecast.runtimeHours) { return VL("Час роботи — \(text)", "Runtime — \(text)") }
        return VL("Прогноз", "Estimate")
    }

    private func accent(_ forecast: VenusEnergyForecast) -> Color {
        if let enough = forecast.enoughForOutage { return enough ? VenusVisuals.success : VenusVisuals.warning }
        return forecast.chargeHours != nil ? VenusVisuals.charging : VenusVisuals.supplying
    }

    private func symbol(_ forecast: VenusEnergyForecast) -> String {
        if let enough = forecast.enoughForOutage { return enough ? "checkmark" : "arrow.down" }
        return forecast.chargeHours != nil ? "bolt.fill" : "clock"
    }

    private func explanation(_ forecast: VenusEnergyForecast) -> String {
        guard let rate = forecast.rateW, rate.isFinite, rate > 0 else {
            return VL("Оцінка за останніми показами батареї. Споживання може змінитися.", "Estimated from recent battery readings. Usage may change.")
        }
        if let hours = forecast.chargeHours, hours > 0 {
            return VL("За останньої швидкості заряджання ≈\(VenusVisuals.power(rate)). Швидкість може змінитися.", "At the recent charging rate of ≈\(VenusVisuals.power(rate)). The rate may change.")
        }
        if let available = forecast.availableWh, available.isFinite, available >= 0 {
            let reserve = VenusVisuals.number(forecast.reservePercent, digits: 0)
            return VL("Ділимо доступні \(VenusVisuals.energy(available)) на середню витрату ≈\(VenusVisuals.power(rate)). Залишаємо \(reserve)% заряду.", "Available energy (\(VenusVisuals.energy(available))) ÷ recent usage (≈\(VenusVisuals.power(rate))). Keeping \(reserve)% charge in reserve.")
        }
        return VL("Оцінка за останньою витратою ≈\(VenusVisuals.power(rate)). Споживання може змінитися.", "Estimated at recent usage of ≈\(VenusVisuals.power(rate)). Usage may change.")
    }

    private func outageAdvice(_ forecast: VenusEnergyForecast, enough: Bool, end: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = VenusOutagesReport.kyivCalendar.timeZone
        formatter.dateFormat = "HH:mm"
        let time = formatter.string(from: end)
        if enough { return VL("Має вистачити до \(time)", "Should last until \(time)") }
        if let budget = forecast.budgetW, budget > 0 { return VL("Знизь споживання до ≈\(VenusVisuals.power(budget))", "Reduce usage to ≈\(VenusVisuals.power(budget))") }
        return VL("Запасу може не вистачити до \(time)", "May not last until \(time)")
    }

    private func duration(_ hours: Double?) -> String? {
        guard let hours, hours.isFinite, hours >= 0, hours <= 24 * 30 else { return nil }
        if hours == 0 { return VL("0 хв", "0 min") }
        if hours < 1.0 / 60 { return VL("<1 хв", "<1 min") }
        if hours < 1 { return VL("≈\(max(1, Int((hours * 60).rounded(.up)))) хв", "≈\(max(1, Int((hours * 60).rounded(.up)))) min") }
        if hours >= 24 { return VL("≈\(VenusVisuals.number(hours, digits: 1)) год", "≈\(VenusVisuals.number(hours, digits: 1)) h") }
        let minutes = Int((hours * 60).rounded(.up))
        return minutes % 60 == 0 ? VL("≈\(minutes / 60) год", "≈\(minutes / 60) h") : VL("≈\(minutes / 60) год \(minutes % 60) хв", "≈\(minutes / 60) h \(minutes % 60) min")
    }
}

private struct VenusHistoryPeriodStyle: ButtonStyle {
    let selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(selected ? Color.white : .white.opacity(0.5))
            .padding(.horizontal, 8).frame(height: 23)
            .background(selected ? Color.white.opacity(0.14) : .clear, in: Capsule())
            .modifier(SwiftfulUIPressFeedback(isPressed: configuration.isPressed))
    }
}

@MainActor
struct VenusEnergyReserveControl: View {
    @ObservedObject private var localization = VenusLocalization.shared
    @ObservedObject var store: VenusEnergyStore
    @State private var draft = 20.0

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Text(VL("Резерв для прогнозу", "Forecast reserve")).font(.system(size: 13))
                Spacer(minLength: 4)
                Button { draft = max(0, draft - 5) } label: { Image(systemName: "minus").font(.system(size: 12)) }
                    .buttonStyle(VenusButtonStyle()).disabled(draft <= 0).accessibilityLabel(VL("Зменшити резерв заряду", "Decrease charge reserve"))
                Text("\(VenusVisuals.number(draft, digits: 0))%")
                    .font(.system(size: 13)).monospacedDigit().frame(width: 40)
                Button { draft = min(100, draft + 5) } label: { Image(systemName: "plus").font(.system(size: 12)) }
                    .buttonStyle(VenusButtonStyle()).disabled(draft >= 100).accessibilityLabel(VL("Збільшити резерв заряду", "Increase charge reserve"))
                Button(VL("Зберегти", "Save")) { store.setReservePercent(draft) }
                    .buttonStyle(VenusButtonStyle(primary: true)).disabled(draft == store.reservePercent)
            }
            Text(VL("Залишаємо цей заряд у запасі під час розрахунку часу роботи. Налаштування самої станції не змінюються.", "This charge is kept in reserve when estimating runtime. The station settings are unchanged."))
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.45)).fixedSize(horizontal: false, vertical: true)
                .help(VL("Це запас для прогнозу VenusBar; він не керує заряджанням або розряджанням станції.", "This reserve is for the VenusBar forecast; it does not control station charging or discharging."))
        }.onAppear { draft = store.reservePercent }
    }
}
