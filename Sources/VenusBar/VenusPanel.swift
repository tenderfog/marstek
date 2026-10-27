import AppKit
import SwiftUI

@MainActor
struct VenusPanel: View {
    @ObservedObject var store: VenusStore
    @ObservedObject var outages: VenusOutagesStore
    @ObservedObject var energy: VenusEnergyStore
    @State private var page = Page.overview
    @State private var address = ""
    @State private var port = "30000"
    @State private var formMessage: String?
    @State private var helpReturnPage = Page.overview
    @State private var clarificationExpanded = false
    @State private var connectionDraftLoaded = false
    @State private var controlsReturnPage = Page.overview
    private enum Page { case overview, settings, stationSettings, outageSettings, otherSettings, controls, help }

    var body: some View {
        Group {
            if store.configuration == nil { VenusOnboarding(store: store) }
            else {
                switch page {
                case .overview:
                    if store.report == nil { connecting } else { overview }
                case .settings: settings
                case .stationSettings: stationSettings
                case .outageSettings: VenusOutagesSettings(store: outages) { page = .settings }
                case .otherSettings: otherSettings
                case .controls: VenusControls(store: store) { page = controlsReturnPage }
                case .help: VenusHelp { page = helpReturnPage }
                }
            }
        }
        .frame(width: 520, height: panelHeight)
        .preference(key: VenusPanelHeightPreferenceKey.self, value: panelHeight)
        .background(.clear).foregroundStyle(.white).preferredColorScheme(.dark)
    }

    private var panelHeight: CGFloat {
        guard store.configuration != nil else { return 430 }
        if page == .overview { return outages.selection == nil ? 530 : 610 }
        return 610
    }

    private var overview: some View {
        VStack(spacing: 8) {
            overviewHeader
            energyOverview
            if outages.selection != nil {
                VenusTodayOutageCard(store: outages) { page = .outageSettings }
            }
            VenusEnergyForecastView(energy: energy, outages: outages).frame(height: 44)
            VenusEnergyHistoryView(store: energy, compact: true)
            Spacer(minLength: 0)
            rule
            overviewFooter
        }.padding(.horizontal, 24).padding(.vertical, 12)
    }

    private var energyOverview: some View {
        VStack(spacing: 8) {
            VenusStationFascia(soc: store.report?.socPercent, fresh: fresh("soc_percent"), flow: store.flowState,
                               model: store.model,
                               ctConnected: fresh("ct_connected") ? store.report?.ctConnected : nil,
                               bluetoothConnected: fresh("bluetooth_connected") ? store.report?.bluetoothConnected : nil,
                               wifiIP: fresh("wifi_ip") ? store.report?.wifiIP : nil,
                               gridPowerW: fresh("grid_power_w") ? store.report?.gridPowerW : nil,
                               offgridPowerW: fresh("offgrid_power_w") ? store.report?.offgridPowerW : nil,
                               pvPowerW: fresh("pv_power_w") ? store.report?.pvPowerW : nil,
                               apiOnline: store.isFresh, compact: true)
            HStack(spacing: 24) {
                VenusSOCOrb(value: store.report?.socPercent, fresh: fresh("soc_percent"), flow: store.flowState, status: orbStatus, diameter: 160)
                    .help(receiptHelp("soc_percent"))
                VStack(spacing: 0) {
                    powerMetric(powerSnapshot.charge, title: powerSnapshot.charge?.title ?? "Вхід із мережі", symbol: "arrow.down.left")
                    rule
                    powerMetric(powerSnapshot.output, title: powerSnapshot.output?.metricKey == "offgrid_power_w" ? "Навантаження" : (powerSnapshot.output?.title ?? "Навантаження"), symbol: "arrow.up.right", output: true)
                    rule
                    metric("Температура", symbol: "thermometer.medium", value: store.report?.batteryTemperatureC.map { "\(VenusVisuals.number($0))°C" } ?? "—", key: "battery_temperature_c")
                    if store.model == .venusA, let solar = store.report?.pvPowerW {
                        rule
                        metric("Сонце", symbol: "sun.max", value: VenusVisuals.power(solar), key: "pv_power_w", compact: true)
                    }
                }.frame(maxWidth: .infinity)
            }.frame(height: 160)
        }.frame(height: 220, alignment: .top)
    }

    private var overviewFooter: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "battery.100percent").font(.system(size: 13)).foregroundStyle(.white.opacity(0.55))
                Text("Місткість \(VenusVisuals.energy(store.report?.batteryRatedWh))")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)).monospacedDigit()
                    .help(receiptHelp("battery_rated_wh"))
                Spacer(minLength: 8)
                Text("Запас \(VenusVisuals.energy(store.report?.batteryRemainingWh))")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(fresh("battery_remaining_wh") ? 0.6 : 0.35)).monospacedDigit()
                    .help(receiptHelp("battery_remaining_wh"))
            }.frame(height: 18)
            HStack(spacing: 8) {
                Text(lastUpdateText).monospacedDigit()
                Spacer(minLength: 4)
                if let caption = lastDataCaption { Text(caption).lineLimit(1) }
            }
            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
            .frame(height: 14)
            .help(store.error ?? "Час останньої відповіді API; значення можуть надходити окремо.")
        }
    }

    private var lastUpdateText: String {
        guard let date = store.report?.observationDate else { return "Очікуємо перше оновлення" }
        let time = date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits))
        return "Останнє оновлення — \(time)"
    }

    private var lastDataCaption: String? {
        if store.error != nil { return store.isFresh ? "Повторюємо запит" : "Немає відповіді" }
        if store.isRestoredReport { return "Збережені покази" }
        if !store.isPolling { return "Пауза" }
        if !store.isFresh { return "Останні покази" }
        return nil
    }

    private var overviewHeader: some View {
        HStack(spacing: 9) {
            Text(store.model == .unknown ? "VenusBar" : store.model.title).font(.system(size: 17, weight: .semibold))
            Menu {
                Button("Керування станцією…") { openControls(from: .overview) }
                Button("Мережа…", action: openStationSettings)
                if outages.selection != nil { Button("Графіки відключень…") { page = .outageSettings } }
                if let mode = store.report?.mode { Text("Режим: \(mode)") }
                if needsFlowClarification { Button("Уточнення індикації потоку", action: openClarification) }
                Button("Оновити показники", action: store.reload).disabled(store.isReading)
                if store.isPolling { Button("Призупинити читання", action: store.pause) }
                else { Button("Продовжити читання", action: store.start) }
                Divider()
                Button("Як користуватися VenusBar") { openHelp(from: .overview) }
                Divider()
                Button("Вийти з VenusBar") { NSApplication.shared.terminate(nil) }
            } label: {
                Image(systemName: "chevron.down").font(.system(size: 12, weight: .semibold)).frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 36).accessibilityLabel("Меню станції")
            Spacer()
            Button(action: openSettings) { Image(systemName: "gearshape").font(.system(size: 16)) }
                .buttonStyle(VenusButtonStyle(compact: true)).help("Налаштування VenusBar").accessibilityLabel("Налаштування VenusBar")
        }.frame(height: 36)
            .help("\(store.report?.mode.map { "Режим станції: \($0)." } ?? "") \(store.warning ?? "")")
    }

    private var connecting: some View {
        VStack(spacing: 12) {
            overviewHeader
            VenusStationFascia(soc: nil, fresh: false, flow: .unknown, model: store.model)
            HStack(spacing: 24) {
                VenusLoadingOrb(active: store.isReading, symbol: store.error == nil ? "bolt" : "wifi.exclamationmark")
                VStack(alignment: .leading, spacing: 10) {
                    Text(firstReadTitle).font(.system(size: 18, weight: .medium))
                    Text(store.error ?? "Перші показники з’являться після відповіді локального API. Це може тривати кілька секунд.")
                        .font(.system(size: 13)).foregroundStyle(.white.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true).lineLimit(3)
                    Text("\(store.ip):\(store.port)").font(.system(size: 11, design: .monospaced)).foregroundStyle(.white.opacity(0.35))
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(minHeight: 124).padding(.horizontal, 12)
            Spacer(minLength: 0)
            HStack(spacing: 12) {
                Button("Спробувати ще", action: store.reload).buttonStyle(VenusButtonStyle()).disabled(store.isReading)
                Button("Підключення", action: openStationSettings).buttonStyle(VenusButtonStyle(primary: true))
            }
        }.padding(.horizontal, 24).padding(.vertical, 20)
    }

    private var firstReadTitle: String {
        if store.isReading { return "Отримуємо перші показники" }
        return store.error == nil ? "Готові до підключення" : "Станція поки не відповіла"
    }

    private var orbStatus: String {
        if !store.isPolling { return "Читання на паузі" }
        if store.report == nil { return "Очікуємо покази" }
        if !fresh("soc_percent") { return "Останній відомий заряд" }
        if store.flowState == .standby {
            return store.report?.socPercent == 100 ? "Батарея повна" : "Очікування"
        }
        return store.flowState == .unknown ? "Потік енергії" : store.flowState.title
    }
    private var rule: some View { Rectangle().fill(.white.opacity(0.085)).frame(height: 0.5) }
    private var powerSnapshot: VenusPowerSnapshot {
        VenusPowerSnapshot.make(report: store.report, model: store.model,
                                chargingGridSign: store.configuration?.chargingGridSign, fresh: store.isFresh)
    }
    private func fresh(_ metric: String) -> Bool { store.isFresh && store.report?.fresh(metric) == true }

    private func powerMetric(_ metric: VenusPowerMetric?, title: String, symbol: String, output: Bool = false) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 17, weight: .light)).frame(width: 28)
                    .foregroundStyle(metric?.isFresh == true ? (output ? VenusVisuals.supplying : VenusVisuals.charging) : .white.opacity(0.3))
                Text(title).font(.system(size: 12)).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
                Spacer(minLength: 3)
                if let metric {
                    Text(VenusVisuals.power(metric.watts)).font(.system(size: 22, weight: .medium)).monospacedDigit()
                        .foregroundStyle(.white.opacity(metric.isFresh ? 0.95 : 0.4)).lineLimit(1).minimumScaleFactor(0.75)
                } else { VenusSoftPlaceholder().frame(height: 27) }
            }
            if output {
                Text(loadCaption).font(.system(size: 11)).monospacedDigit()
                    .foregroundStyle(.white.opacity(metric?.isFresh == true ? 0.55 : 0.3))
                    .frame(maxWidth: .infinity, alignment: .trailing).frame(height: 14)
                VenusOutputLoadTrack(snapshot: powerSnapshot).padding(.leading, 38)
            }
        }.frame(maxHeight: .infinity)
            .help(powerHelp(metric))
    }

    private var loadCaption: String {
        guard let maximum = powerSnapshot.outputMaximumW, let ratio = powerSnapshot.utilization,
              maximum.isFinite, ratio.isFinite else { return "" }
        return "із \(VenusVisuals.number(maximum, digits: 0)) Вт · \(VenusVisuals.number(ratio * 100, digits: 1))%"
    }

    private func powerHelp(_ metric: VenusPowerMetric?) -> String {
        guard let metric else { return "Потужність цього каналу ще не отримано." }
        let scope = metric.metricKey == "offgrid_power_w" ? " Споживання приладів, підключених до резервного виходу, не обов’язково всього дому." : ""
        let date = metric.observedAt.flatMap(VenusReport.date)
        let receipt = date.map { " \(metric.isFresh ? "Отримано" : "Останній показ") \($0.formatted(date: .abbreviated, time: .standard))." } ?? ""
        return metric.meaning + scope + receipt
    }
    private func receiptHelp(_ metric: String) -> String {
        let meaning: String
        switch metric {
        case "soc_percent": meaning = "Заряд батареї у відсотках від її повної місткості."
        case "grid_power_w": meaning = "Потужність через мережевий AC-канал станції, у ватах або кіловатах. Це потік енергії, а не напруга й не споживання всього дому."
        case "battery_temperature_c":
            let temperature = VenusTemperature.evaluate(value: store.report?.batteryTemperatureC, fresh: fresh(metric))
            meaning = temperature.title + ". " + temperature.explanation
        case "battery_remaining_wh": meaning = "Запас енергії, що залишився в батареї, у Вт·год або кВт·год."
        case "battery_rated_wh": meaning = "Повна місткість батареї за API, у Вт·год або кВт·год; не поточний запас."
        case "pv_power_w": meaning = "Потужність сонячних входів за API, у ватах або кіловатах."
        default: meaning = "Показник, отриманий від станції через локальний API."
        }
        guard let text = store.report?.metricObservedAt?[metric], let date = VenusReport.date(text) else { return "\(meaning) Показник ще не отримано." }
        return "\(meaning) \(fresh(metric) ? "Отримано" : "Остання відповідь") \(date.formatted(date: .abbreviated, time: .standard)). Це час відповіді API, не час фізичного виміру."
    }
    private func metric(_ title: String, symbol: String, value: String, key: String, compact: Bool = false) -> some View {
        HStack(spacing: 12) {
            if key == "battery_temperature_c" {
                VenusTemperatureIcon(temperature: store.report?.batteryTemperatureC, fresh: fresh(key), size: 28)
            } else {
                Image(systemName: symbol).font(.system(size: compact ? 14 : 18, weight: .light)).frame(width: 28)
                    .foregroundStyle(.white.opacity(fresh(key) ? 0.8 : 0.3))
            }
            Text(title).font(.system(size: compact ? 12 : 13)).foregroundStyle(.white.opacity(0.65))
            Spacer(minLength: 5)
            if value == "—" {
                VenusSoftPlaceholder().frame(height: compact ? 23 : 28)
            } else {
                Text(value).font(.system(size: compact ? 19 : 23, weight: .medium)).monospacedDigit()
                    .foregroundStyle(.white.opacity(fresh(key) ? 0.95 : 0.4)).lineLimit(1).minimumScaleFactor(0.7)
            }
        }.frame(maxHeight: .infinity).help(receiptHelp(key))
    }
    private var settings: some View {
        settingsPage("Налаштування", back: .overview) {
            settingsRow("Керування станцією", subtitle: "Режими, заряджання та ліміти", symbol: "slider.horizontal.3") { openControls(from: .settings) }
            settingsRow("Мережа", subtitle: "Пошук станції, IP та Local API", symbol: "wifi", action: openStationSettings)
            settingsRow("Графіки відключень", subtitle: "Область, оператор та твоя група", symbol: "bolt.slash") { page = .outageSettings }
            settingsRow("Інші параметри", subtitle: "Оновлення, автозапуск і довідка", symbol: "slider.horizontal.3") { page = .otherSettings }
        }
    }

    private var stationSettings: some View {
        settingsPage("Мережа", back: .settings) {
            connectionSettings
            rule
            clarificationSettings
            if let message = formMessage ?? store.error {
                Text(message).font(.system(size: 13)).foregroundStyle(.white.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var connectionSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Підключення").font(.system(size: 14, weight: .semibold))
            HStack(spacing: 9) {
                TextField("IP-адреса станції", text: $address)
                TextField("Порт", text: $port).frame(width: 92)
                Button("Зберегти", action: saveConnection).buttonStyle(VenusButtonStyle(primary: true)).disabled(store.commandBusy)
            }.textFieldStyle(VenusTextFieldStyle())
            HStack {
                Button("Шукати автоматично", action: scan).buttonStyle(VenusButtonStyle()).disabled(store.isDiscovering || store.commandBusy)
                Spacer()
                VenusLocalAPIHelpLink(model: store.model)
            }
            if store.isDiscovering {
                Text("Шукаємо станцію…").font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
            }
            ForEach(store.discoveredDevices) { item in
                Button { address = item.ip; port = String(item.port); saveConnection() } label: {
                    HStack { Text(item.name); Spacer(); Text(item.ip).monospacedDigit(); Image(systemName: "arrow.right") }
                        .font(.system(size: 13)).foregroundStyle(.white.opacity(0.85))
                }.buttonStyle(VenusButtonStyle(compact: true)).disabled(store.commandBusy)
            }
        }
    }

    private var clarificationSettings: some View {
        DisclosureGroup(isExpanded: $clarificationExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                Text("«Розряджається» означає, що станція віддає енергію. Тут можна уточнити індикацію за фактичним станом; режим роботи станції не змінюється.")
                    .font(.system(size: 13)).foregroundStyle(.white.opacity(0.65)).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    calibration("Заряджається", state: .charging)
                    calibration("Розряджається", state: .supplyingHome)
                    calibration("Від мережі", state: .mains)
                }.buttonStyle(VenusButtonStyle(compact: true)).disabled(!store.isFresh || store.commandBusy)
                Text("Очікування означає відсутність помітного потоку енергії й не підтверджує живлення від мережі. Ручне підтвердження мережі діє 90 секунд.")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.5)).fixedSize(horizontal: false, vertical: true)
            }.padding(.top, 12)
        } label: {
            Text("Уточнення показників").font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.75)).frame(minHeight: 32)
        }
    }

    private var otherSettings: some View {
        settingsPage("Інші параметри", back: .settings) {
            HStack {
                Text("Оновлення").font(.system(size: 14))
                Spacer()
                HStack(spacing: 7) {
                    ForEach([10.0, 30.0, 60.0], id: \.self) { seconds in
                        Button("\(Int(seconds)) с") { store.setRefreshInterval(seconds) }
                            .buttonStyle(VenusButtonStyle(primary: store.refreshInterval == seconds, compact: true))
                            .disabled(store.commandBusy)
                    }
                }.accessibilityLabel("Інтервал оновлення")
            }
            Toggle("Запускати разом із macOS", isOn: Binding(get: { store.startsAtLogin }, set: { store.setStartsAtLogin($0) }))
                .font(.system(size: 14)).toggleStyle(.switch).frame(minHeight: 44)
            VenusEnergyReserveControl(store: energy)
            HStack {
                Text(store.isPolling ? "Фонове читання ввімкнено" : "Читання на паузі").font(.system(size: 13)).foregroundStyle(.white.opacity(0.65))
                Spacer()
                if store.isPolling { Button("Пауза", action: store.pause) }
                else { Button("Продовжити", action: store.start) }
            }.buttonStyle(VenusButtonStyle())
            rule
            Button { openHelp(from: .otherSettings) } label: {
                Label("Як користуватися VenusBar", systemImage: "questionmark.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(VenusButtonStyle())
            if let error = store.error {
                Text(error).font(.system(size: 13)).foregroundStyle(.white.opacity(0.65)).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func settingsPage<Content: View>(_ title: String, back: Page, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Button { page = back } label: { Label("Назад", systemImage: "chevron.left") }
                    .buttonStyle(VenusButtonStyle())
                Text(title).font(.system(size: 17, weight: .semibold))
                Spacer(minLength: 0)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18, content: content)
                    .padding(.vertical, 2).padding(.trailing, 3)
            }.scrollIndicators(.automatic)
        }.padding(22)
    }

    private func settingsRow(_ title: String, subtitle: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol).font(.system(size: 22, weight: .light)).frame(width: 32)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.system(size: 15, weight: .medium))
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.45))
            }.padding(.vertical, 14).frame(maxWidth: .infinity, alignment: .leading)
        }.buttonStyle(VenusButtonStyle())
    }
    private var needsFlowClarification: Bool {
        guard store.isFresh, store.flowState == .unknown, store.configuration?.chargingGridSign == nil,
              fresh("grid_power_w"), let watts = store.report?.gridPowerW else { return false }
        return abs(watts) > 25
    }
    private func openClarification() { openStationSettings(); clarificationExpanded = true }
    private func openHelp(from origin: Page) { helpReturnPage = origin; page = .help }
    private func loadConnectionDraft() {
        guard !connectionDraftLoaded else { return }
        address = store.ip; port = String(store.port); connectionDraftLoaded = true
    }
    private func openSettings() { loadConnectionDraft(); page = .settings }
    private func openStationSettings() { loadConnectionDraft(); page = .stationSettings }
    private func openControls(from origin: Page) { controlsReturnPage = origin; page = .controls }
    private func saveConnection() {
        guard let value = Int(port), (1024...65535).contains(value) else { formMessage = "Порт має бути числом від 1024 до 65535."; return }
        do { try store.configure(ip: address, port: value); formMessage = nil; page = .overview }
        catch { formMessage = error.localizedDescription }
    }
    private func scan() {
        guard let value = Int(port), (1024...65535).contains(value) else { formMessage = "Порт має бути числом від 1024 до 65535."; return }
        formMessage = nil; store.discover(port: value)
    }
    private func calibration(_ title: String, state: VenusFlowState) -> some View {
        Button(title) {
            do { try store.calibrate(state); formMessage = "Індикацію уточнено для цієї станції." }
            catch { formMessage = error.localizedDescription }
        }
    }
}

@MainActor
struct VenusIslandContent: View {
    @ObservedObject var store: VenusStore
    let onDetails: () -> Void
    private var powerSnapshot: VenusPowerSnapshot {
        VenusPowerSnapshot.make(report: store.report, model: store.model,
                                chargingGridSign: store.configuration?.chargingGridSign, fresh: store.isFresh)
    }
    private var charge: VenusPowerMetric? { powerSnapshot.charge.flatMap { $0.watts > 0 ? $0 : nil } }
    private var output: VenusPowerMetric? { powerSnapshot.output.flatMap { $0.watts > 0 ? $0 : nil } }
    private func fresh(_ key: String) -> Bool { store.isFresh && store.report?.fresh(key) == true }

    var body: some View {
        Button(action: onDetails) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let soc = store.report?.socPercent {
                        Image(systemName: "battery.75percent").font(.system(size: 17, weight: .medium))
                            .foregroundStyle(Color.primary.opacity(fresh("soc_percent") ? 0.7 : 0.35))
                        Text(VenusVisuals.soc(soc)).font(.system(size: 25, weight: .medium, design: .rounded)).monospacedDigit()
                            .foregroundStyle(Color.primary.opacity(fresh("soc_percent") ? 0.96 : 0.4))
                    }
                    Spacer(minLength: 4)
                    if let charge {
                        powerBadge(charge, symbol: "arrow.down.left", color: VenusVisuals.charging)
                    }
                    if let output {
                        powerBadge(output, symbol: "arrow.up.right", color: VenusVisuals.supplying, output: true)
                    }
                }.frame(height: 36)
                HStack(spacing: 7) {
                    Image(systemName: flowSymbol).font(.system(size: 12, weight: .medium))
                    Text(store.flowText).font(.system(size: 12, weight: .medium)).lineLimit(1).minimumScaleFactor(0.85)
                    Spacer(minLength: 5)
                    if let temperature = store.report?.batteryTemperatureC {
                        VenusTemperatureIcon(temperature: temperature, fresh: fresh("battery_temperature_c"), size: 20, adaptive: true)
                        Text("\(VenusVisuals.number(temperature)) °C").font(.system(size: 12)).monospacedDigit()
                            .foregroundStyle(Color.primary.opacity(fresh("battery_temperature_c") ? 0.6 : 0.35))
                    }
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.primary.opacity(0.3))
                }.foregroundStyle(VenusVisuals.accent(store.flowState, fresh: store.isFresh))
            }.frame(width: 300, height: 76)
                .contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(.primary).background(.clear)
            .accessibilityLabel(accessibilitySummary)
    }

    private func powerBadge(_ metric: VenusPowerMetric, symbol: String, color: Color, output: Bool = false) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 11, weight: .medium))
                    .foregroundStyle(metric.isFresh ? color : .primary.opacity(0.3))
                Text(VenusVisuals.power(metric.watts)).font(.system(size: 19, weight: .medium)).monospacedDigit()
                    .foregroundStyle(Color.primary.opacity(metric.isFresh ? 0.96 : 0.4))
                    .lineLimit(1).minimumScaleFactor(0.75)
            }
            if output { VenusOutputLoadTrack(snapshot: powerSnapshot).frame(width: 60) }
            else { Color.clear.frame(height: 3) }
        }
    }

    private var flowSymbol: String {
        switch store.flowState {
        case .charging: return "arrow.down.left"
        case .supplyingHome: return "arrow.up.right"
        case .mains: return "powerplug.fill"
        case .standby: return "pause"
        case .unknown: return "waveform"
        }
    }
    private var accessibilitySummary: String {
        var values = [store.model.title]
        if let soc = store.report?.socPercent { values.append("Заряд \(VenusVisuals.soc(soc))") }
        if let charge { values.append("\(charge.isFresh ? "" : "Останній показ. ")\(charge.title): \(VenusVisuals.power(charge.watts))") }
        if let output { values.append("\(output.isFresh ? "" : "Останній показ. ")\(output.title): \(VenusVisuals.power(output.watts))") }
        if let temperature = store.report?.batteryTemperatureC { values.append("Температура батареї \(VenusVisuals.number(temperature)) градусів Цельсія") }
        values.append(store.flowText)
        values.append("Відкрити подробиці")
        return values.joined(separator: ". ")
    }
}

private struct VenusOutputLoadTrack: View {
    let snapshot: VenusPowerSnapshot

    private var active: Bool {
        guard let output = snapshot.output, output.isFresh, output.watts > 0,
              let maximum = snapshot.outputMaximumW, maximum > 0,
              let ratio = snapshot.utilization, ratio.isFinite, ratio >= 0 else { return false }
        return true
    }

    var body: some View {
        Group {
            if active, let ratio = snapshot.utilization {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08))
                        Capsule().fill(trackColor)
                            .frame(width: geometry.size.width * min(1, max(0, ratio)))
                    }
                }.help(ratioDescription).accessibilityLabel(ratioDescription)
            } else { Color.clear.accessibilityHidden(true) }
        }.frame(height: 3)
    }

    private var trackColor: Color {
        guard let ratio = snapshot.utilization else { return .clear }
        if ratio >= 1 { return .red }
        if ratio >= 0.9 { return .orange }
        if ratio >= 0.8 { return .yellow }
        return VenusVisuals.supplying
    }

    private var ratioDescription: String {
        guard let watts = snapshot.outputW, let maximum = snapshot.outputMaximumW, let ratio = snapshot.utilization else { return "" }
        let source = snapshot.maximumSource.map { " \($0)" } ?? ""
        return "\(VenusVisuals.number(watts, digits: 0)) із \(VenusVisuals.number(maximum, digits: 0)) Вт · \(VenusVisuals.number(ratio * 100, digits: 1))%.\(source) Це відношення до номінальної потужності, а не зчитаний встановлений ліміт. Колір — орієнтир завантаження, не стан апаратного захисту."
    }
}
