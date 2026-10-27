import SwiftUI

@MainActor
struct VenusEnergyHistoryView: View {
    @ObservedObject var store: VenusEnergyStore
    var compact = false
    @State private var hours = 1

    var body: some View {
        let now = Date()
        let series = store.series(hours: hours, now: now)
        return VStack(spacing: compact ? 3 : 4) {
            HStack(spacing: 6) {
                Text("Потужність станції").font(.system(size: 12, weight: .medium)).lineLimit(1)
                Spacer(minLength: 4)
                ForEach([1, 3, 5, 24], id: \.self) { period in
                    Button { hours = period } label: {
                        Text(period == 24 ? "Доба" : "\(period) год").font(.system(size: 11, weight: .medium)).monospacedDigit()
                    }
                    .buttonStyle(VenusHistoryPeriodStyle(selected: period == hours))
                    .accessibilityLabel("Період графіка: \(period) год")
                    .accessibilityAddTraits(period == hours ? .isSelected : [])
                }
            }.frame(height: 32)
            if series.isEmpty {
                Text("Історія з’явиться під час роботи")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.35))
                    .frame(maxWidth: .infinity).frame(height: compact ? 26 : 32)
            } else {
                VenusEnergySparkline(series: series, start: now.addingTimeInterval(-Double(hours) * 3600), end: now)
                    .frame(height: compact ? 26 : 32).transaction { $0.animation = nil }
            }
            legend(series)
        }
        .padding(.horizontal, 10).padding(.vertical, compact ? 6 : 8).frame(height: compact ? 88 : 100)
        .modifier(SwiftfulUICardSurface(backgroundColor: .white.opacity(0.025), cornerRadius: 13))
        .help("Фактичні показники станції за останні \(hours) год. Пропуски понад 90 секунд розривають лінію. Мережевий канал — обмін через AC станції, не чиста потужність батареї й не споживання всього дому.")
    }

    private func legend(_ series: [VenusEnergySeries]) -> some View {
        HStack(spacing: 10) {
            ForEach(Array(series.enumerated()), id: \.element.id) { index, item in
                HStack(spacing: 4) {
                    Circle().fill(VenusEnergySparkline.color(index)).frame(width: 4, height: 4)
                    Text(item.id == "battery_power_w" ? "Батарея" : item.id == "grid_power_w" ? "Мережа" : "Резервний вихід").lineLimit(1)
                        .help(item.title)
                }
            }
            Spacer(minLength: 4)
            Text(rangeLabel(series)).monospacedDigit().lineLimit(1).fixedSize()
                .foregroundStyle(.white.opacity(0.55)).help("Мінімальна й максимальна потужність за обраний період.")
            if let error = store.persistenceError {
                Image(systemName: "exclamationmark.circle").help(error).accessibilityLabel(error)
            }
        }.font(.system(size: 10)).foregroundStyle(.white.opacity(0.45)).frame(height: 12)
    }

    private func rangeLabel(_ series: [VenusEnergySeries]) -> String {
        let values = series.flatMap(\.segments).flatMap { $0 }.map(\.value).filter(\.isFinite)
        guard let minimum = values.min(), let maximum = values.max() else { return "" }
        if minimum == maximum { return VenusVisuals.power(minimum) }
        return "\(VenusVisuals.power(minimum))…\(VenusVisuals.power(maximum))"
    }
}

private struct VenusEnergySparkline: View {
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
            func position(_ point: VenusEnergyPoint) -> CGPoint {
                let x = point.date.timeIntervalSince(start) / duration
                let y = (point.value - low) / span
                return CGPoint(x: min(size.width, max(0, x * size.width)), y: size.height * (1 - y))
            }
            let zeroY = size.height * (1 - (0 - low) / span)
            var baseline = Path()
            baseline.move(to: CGPoint(x: 0, y: zeroY)); baseline.addLine(to: CGPoint(x: size.width, y: zeroY))
            context.stroke(baseline, with: .color(.white.opacity(0.08)), style: StrokeStyle(lineWidth: 0.6, dash: [2, 4]))
            for (index, item) in series.enumerated() {
                for segment in item.segments {
                    let points = segment.filter { $0.value.isFinite && $0.date >= start && $0.date <= end }
                    guard let first = points.first else { continue }
                    var line = Path(); line.move(to: position(first))
                    var previous = first
                    for point in points.dropFirst() {
                        // Keep the visual gap rule even if a future data source forgets to segment.
                        if point.date.timeIntervalSince(previous.date) > 90 { line.move(to: position(point)) }
                        else { line.addLine(to: position(point)) }
                        previous = point
                    }
                    context.stroke(line, with: .color(Self.color(index)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    if points.count == 1 {
                        let point = position(first)
                        context.fill(Path(ellipseIn: CGRect(x: point.x - 1.5, y: point.y - 1.5, width: 3, height: 3)), with: .color(Self.color(index)))
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Графік потужності станції у ватах. Розриви означають відсутні показники.")
    }

    static func color(_ index: Int) -> Color {
        index == 0 ? .white.opacity(0.85) : Color(red: 0.52, green: 0.79, blue: 0.70)
    }
}

@MainActor
struct VenusEnergyForecastView: View {
    @ObservedObject var energy: VenusEnergyStore
    @ObservedObject var outages: VenusOutagesStore
    @State private var showingDetails = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let forecast = energy.forecast(now: context.date, outageStart: outages.currentOrNextOutageStart, outageEnd: outages.currentOrNextOutageEnd)
            if useful(forecast) {
                Button { showingDetails = true } label: { summary(forecast) }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 13).frame(height: 44)
                    .modifier(SwiftfulUICardSurface(backgroundColor: .white.opacity(0.035), cornerRadius: 13))
                    .popover(isPresented: $showingDetails, arrowEdge: .bottom) {
                        details(forecast).padding(17).frame(width: 310)
                            .preferredColorScheme(.dark)
                    }
                    .help("Приблизний прогноз за поточним навантаженням. Натисни для деталей.")
            }
        }
    }

    private func useful(_ forecast: VenusEnergyForecast) -> Bool {
        (forecast.chargeHours.map { $0 > 0 && duration($0) != nil } ?? false)
        || duration(forecast.runtimeHours) != nil
        || (forecast.enoughForOutage != nil && outages.currentOrNextOutageEnd != nil)
    }

    private func summary(_ forecast: VenusEnergyForecast) -> some View {
        HStack(spacing: 12) {
            if let enough = forecast.enoughForOutage, let end = outages.currentOrNextOutageEnd {
                Text(outageAdvice(forecast, enough: enough, end: end))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(enough ? VenusVisuals.supplying : VenusVisuals.charging)
                    .lineLimit(1).minimumScaleFactor(0.85)
                Spacer(minLength: 3)
            } else {
                if let hours = forecast.chargeHours, hours > 0, let text = duration(hours) { forecastValue("До 100%", value: text) }
                if let text = duration(forecast.runtimeHours) { forecastValue("Час роботи", value: text) }
            }
            Image(systemName: "info.circle").font(.system(size: 12)).foregroundStyle(.white.opacity(0.4))
        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
    }

    private func forecastValue(_ title: String, value: String) -> some View {
        HStack(spacing: 7) {
            Text(title).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
            Text(value).font(.system(size: 12, weight: .medium)).monospacedDigit().foregroundStyle(.white.opacity(0.9))
        }.frame(maxWidth: .infinity, alignment: .leading).lineLimit(1)
    }

    private func details(_ forecast: VenusEnergyForecast) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("Як розраховано прогноз").font(.system(size: 14, weight: .semibold))
            Text(basisText(forecast)).font(.system(size: 12)).foregroundStyle(.white.opacity(0.75))
            Text("У розрахунку залишаємо \(VenusVisuals.number(forecast.reservePercent, digits: 0))% заряду. Резерв можна змінити в налаштуваннях.")
                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
            if let available = forecast.availableWh {
                Text("Понад резерв доступно приблизно \(VenusVisuals.energy(available)).")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
            }
            if let hours = forecast.outageHours, let text = duration(hours) {
                Text("\(forecast.upcomingOutage ? "До завершення майбутнього відключення" : "До завершення відключення") за графіком: \(text).")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.65))
            }
            Text("Це оцінка: споживання й швидкість заряджання можуть змінитися.")
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
        }.fixedSize(horizontal: false, vertical: true)
    }

    private func outageAdvice(_ forecast: VenusEnergyForecast, enough: Bool, end: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = VenusOutagesReport.kyivCalendar.timeZone
        formatter.dateFormat = "HH:mm"
        let time = formatter.string(from: end)
        if enough { return "Має вистачити до \(time)" }
        if let budget = forecast.budgetW, budget > 0 { return "Знизь споживання до ≈\(VenusVisuals.power(budget))" }
        return "Запасу може не вистачити до \(time)"
    }

    private func basisText(_ forecast: VenusEnergyForecast) -> String {
        let basis = forecast.basis == .batteryPower ? "За потужністю батареї" : "За зміною запасу енергії"
        if let rate = forecast.rateW { return "\(basis): приблизно \(VenusVisuals.power(rate)) за поточного навантаження." }
        return "\(basis) за поточного навантаження."
    }

    private func duration(_ hours: Double?) -> String? {
        guard let hours, hours.isFinite, hours >= 0, hours <= 24 * 30 else { return nil }
        if hours == 0 { return "0 хв" }
        if hours < 1.0 / 60 { return "<1 хв" }
        if hours < 1 { return "≈\(max(1, Int((hours * 60).rounded(.up)))) хв" }
        if hours >= 24 { return "≈\(VenusVisuals.number(hours, digits: 1)) год" }
        let minutes = Int((hours * 60).rounded(.up))
        return minutes % 60 == 0 ? "≈\(minutes / 60) год" : "≈\(minutes / 60) год \(minutes % 60) хв"
    }
}

private struct VenusHistoryPeriodStyle: ButtonStyle {
    let selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(selected ? Color.black : .white.opacity(0.65))
            .padding(.horizontal, 8).frame(height: 27)
            .modifier(SwiftfulUICardSurface(backgroundColor: selected ? .white.opacity(0.9) : .white.opacity(0.025),
                                           borderColor: .white.opacity(selected ? 0.4 : 0.08), cornerRadius: 8))
            .modifier(SwiftfulUIPressFeedback(isPressed: configuration.isPressed))
    }
}

@MainActor
struct VenusEnergyReserveControl: View {
    @ObservedObject var store: VenusEnergyStore
    @State private var draft = 20.0

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Text("Резерв для прогнозу").font(.system(size: 13))
                Spacer(minLength: 4)
                Button { draft = max(0, draft - 5) } label: { Image(systemName: "minus").font(.system(size: 12)) }
                    .buttonStyle(VenusButtonStyle()).disabled(draft <= 0).accessibilityLabel("Зменшити резерв заряду")
                Text("\(VenusVisuals.number(draft, digits: 0))%")
                    .font(.system(size: 13)).monospacedDigit().frame(width: 40)
                Button { draft = min(100, draft + 5) } label: { Image(systemName: "plus").font(.system(size: 12)) }
                    .buttonStyle(VenusButtonStyle()).disabled(draft >= 100).accessibilityLabel("Збільшити резерв заряду")
                Button("Зберегти") { store.setReservePercent(draft) }
                    .buttonStyle(VenusButtonStyle(primary: true)).disabled(draft == store.reservePercent)
            }
            Text("Залишаємо цей заряд у запасі під час розрахунку часу роботи. Налаштування самої станції не змінюються.")
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.45)).fixedSize(horizontal: false, vertical: true)
                .help("Це запас для прогнозу VenusBar; він не керує заряджанням або розряджанням станції.")
        }.onAppear { draft = store.reservePercent }
    }
}
