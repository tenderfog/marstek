import AppKit
import SwiftUI

@MainActor
struct VenusPanel: View {
    @ObservedObject private var localization = VenusLocalization.shared
    @ObservedObject private var notifications = VenusNotificationsStore.shared
    @ObservedObject private var updates = VenusUpdates.shared
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
    @AppStorage("VenusBar.outageWelcomePending") private var addressSetupPending = false
    @State private var outageReturnPage = Page.settings
    @AppStorage("VenusBar.outageWelcomeCompleted") private var addressWelcomeCompleted = false
    private enum Page { case overview, settings, stationSettings, outageSettings, notificationsSettings, updateSettings, otherSettings, controls, help, about }

    var body: some View {
        Group {
            if store.configuration == nil { VenusOnboarding(store: store, onConnected: connectedForFirstTime) }
            else if addressSetupPending && store.report != nil && store.device != nil { addressWelcome }
            else {
                switch page {
                case .overview:
                    if store.report == nil { connecting } else { overview }
                case .settings: settings
                case .stationSettings: stationSettings
                case .outageSettings: VenusOutagesSettings(store: outages) { page = outageReturnPage }
                case .notificationsSettings: notificationSettings
                case .updateSettings: updateSettings
                case .otherSettings: otherSettings
                case .controls: VenusControls(store: store) { page = controlsReturnPage }
                case .help: VenusHelp { page = helpReturnPage }
                case .about: about
                }
            }
        }
        .frame(width: 520, height: designHeight)
        .scaleEffect(panelHeight / designHeight, anchor: .top)
        .frame(width: 520, height: panelHeight, alignment: .top)
        .preference(key: VenusPanelHeightPreferenceKey.self, value: panelHeight)
        .background(.clear).foregroundStyle(.white).preferredColorScheme(.dark)
        .environment(\.locale, localization.language.locale)
    }

    private var panelHeight: CGFloat {
        // Keep the complete overview visible on smaller displays without scrolling.
        min(designHeight, max(430, (NSScreen.main?.visibleFrame.height ?? 900) - 24))
    }

    private var designHeight: CGFloat {
        guard store.configuration != nil, !addressSetupPending else { return 430 }
        if page == .overview { return outages.selection == nil ? 690 : 820 }
        return 610
    }

    private var overview: some View {
        VStack(spacing: 12) {
            overviewHeader
            energyOverview
            if outages.selection != nil {
                VenusTodayOutageCard(store: outages) { openOutages(from: .overview) }
            }
            if hasForecast {
                VenusEnergyForecastView(energy: energy, outages: outages).frame(height: 76)
            }
            VenusEnergyHistoryView(store: energy, compact: true, chargingGridSign: store.configuration?.chargingGridSign)
            Spacer(minLength: 0)
            rule
            overviewFooter
        }.padding(.horizontal, 26).padding(.vertical, 18)
    }

    private var hasForecast: Bool {
        let forecast = energy.forecast(outageStart: outages.currentOrNextOutageStart, outageEnd: outages.currentOrNextOutageEnd)
        return forecast.chargeHours.map { $0.isFinite && $0 > 0 } == true
            || forecast.runtimeHours.map { $0.isFinite && $0 > 0 } == true
            || forecast.enoughForOutage != nil
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
                VenusSOCOrb(value: store.report?.socPercent, fresh: fresh("soc_percent"), flow: store.flowState, status: orbStatus,
                            remainingWh: store.report?.batteryRemainingWh, remainingFresh: fresh("battery_remaining_wh"), diameter: 160)
                    .help(receiptHelp("soc_percent"))
                VStack(spacing: 0) {
                    powerMetric(powerSnapshot.charge, title: VL("Заряд", "Charge"), symbol: "arrow.down.left")
                    rule
                    powerMetric(powerSnapshot.output, title: VL("Розряд", "Discharge"), symbol: "arrow.up.right", output: true)
                    rule
                    metric(VL("Температура", "Temperature"), symbol: "thermometer.medium", value: store.report?.batteryTemperatureC.map { "\(VenusVisuals.number($0))°C" } ?? "—", key: "battery_temperature_c")
                    if store.model == .venusA, let solar = store.report?.pvPowerW {
                        rule
                        metric(VL("Сонце", "Solar"), symbol: "sun.max", value: VenusVisuals.power(solar), key: "pv_power_w", compact: true)
                    }
                }.frame(maxWidth: .infinity)
            }.frame(height: 160)
        }.frame(height: 220, alignment: .top)
    }

    private var overviewFooter: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "battery.100percent").font(.system(size: 13)).foregroundStyle(.white.opacity(0.55))
                Text(VL("Місткість \(VenusVisuals.energy(store.report?.batteryRatedWh))", "Capacity \(VenusVisuals.energy(store.report?.batteryRatedWh))"))
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)).monospacedDigit()
                    .help(receiptHelp("battery_rated_wh"))
                Spacer(minLength: 8)
                Text(VL("Запас \(VenusVisuals.energy(store.report?.batteryRemainingWh))", "Stored \(VenusVisuals.energy(store.report?.batteryRemainingWh))"))
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
            .help(store.error ?? VL("Час останньої відповіді API; значення можуть надходити окремо.", "Last API response time; individual values may arrive separately."))
        }
    }

    private var lastUpdateText: String {
        guard let date = store.report?.observationDate else { return VL("Очікуємо перше оновлення", "Waiting for the first update") }
        let time = date.formatted(.dateTime.locale(localization.language.locale).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits))
        return VL("Останнє оновлення — \(time)", "Last updated — \(time)")
    }

    private var lastDataCaption: String? {
        if store.error != nil { return store.isFresh ? VL("Повторюємо запит", "Retrying") : VL("Немає відповіді", "No response") }
        if store.isRestoredReport { return VL("Збережені покази", "Saved readings") }
        if !store.isPolling { return VL("Пауза", "Pause") }
        if !store.isFresh { return VL("Останні покази", "Last readings") }
        return nil
    }

    private var overviewHeader: some View {
        HStack(spacing: 9) {
            Text(store.model == .unknown ? "VenusBar" : store.model.title).font(.system(size: 17, weight: .semibold))
            Menu {
                Button(VL("Керування станцією…", "Station controls…")) { openControls(from: .overview) }
                Button(VL("Мережа…", "Network…"), action: openStationSettings)
                if outages.selection != nil { Button(VL("Графіки відключень…", "Outage schedules…")) { openOutages(from: .overview) } }
                if let mode = store.report?.mode { Text(VL("Режим: \(mode)", "Mode: \(mode)")) }
                if needsFlowClarification { Button(VL("Уточнення індикації потоку", "Adjust flow indication"), action: openClarification) }
                Button(VL("Оновити показники", "Refresh readings"), action: store.reload).disabled(store.isReading)
                if store.isPolling { Button(VL("Призупинити оновлення", "Pause updates"), action: store.pause) }
                else { Button(VL("Відновити оновлення", "Resume updates"), action: store.start) }
                Divider()
                Button(VL("Як користуватися VenusBar", "How to use VenusBar")) { openHelp(from: .overview) }
                Button(VL("Про VenusBar", "About VenusBar")) { page = .about }
                Button(VL("Перевірити оновлення…", "Check for Updates…"), action: updates.checkForUpdates)
                    .disabled(!updates.canCheckForUpdates)
                Divider()
                Button(VL("Вийти з VenusBar", "Quit VenusBar")) { NSApplication.shared.terminate(nil) }
            } label: {
                Image(systemName: "chevron.down").font(.system(size: 12, weight: .semibold)).frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 36).accessibilityLabel(VL("Меню станції", "Station menu"))
            Spacer()
            Button(action: openSettings) { Image(systemName: "gearshape").font(.system(size: 16)) }
                .overlay(alignment: .topTrailing) {
                    if updates.availableVersion != nil {
                        Circle().fill(Color.accentColor).frame(width: 7, height: 7).offset(x: 2, y: -2)
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(VenusButtonStyle(compact: true)).help(VL("Налаштування VenusBar", "VenusBar settings")).accessibilityLabel(VL("Налаштування VenusBar", "VenusBar settings"))
        }.frame(height: 36)
            .help("\(store.report?.mode.map { VL("Режим станції: \($0).", "Station mode: \($0).") } ?? "") \(store.warning ?? "")")
    }

    private var connecting: some View {
        VStack(spacing: 12) {
            overviewHeader
            VenusStationFascia(soc: nil, fresh: false, flow: .unknown, model: store.model)
            HStack(spacing: 24) {
                VenusLoadingOrb(active: store.isReading, symbol: store.error == nil ? "bolt" : "wifi.exclamationmark")
                VStack(alignment: .leading, spacing: 10) {
                    Text(firstReadTitle).font(.system(size: 18, weight: .medium))
                    Text(store.error ?? VL("Перші показники з’являться після відповіді локального API. Це може тривати кілька секунд.", "The first readings will appear when the local API responds. This may take a few seconds."))
                        .font(.system(size: 13)).foregroundStyle(.white.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true).lineLimit(3)
                    Text("\(store.ip):\(store.port)").font(.system(size: 11, design: .monospaced)).foregroundStyle(.white.opacity(0.35))
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(minHeight: 124).padding(.horizontal, 12)
            Spacer(minLength: 0)
            HStack(spacing: 12) {
                Button(VL("Спробувати ще", "Try again"), action: store.reload).buttonStyle(VenusButtonStyle()).disabled(store.isReading)
                Button(VL("Підключення", "Connection"), action: openStationSettings).buttonStyle(VenusButtonStyle(primary: true))
            }
        }.padding(.horizontal, 24).padding(.vertical, 20)
    }

    private var firstReadTitle: String {
        if store.isReading { return VL("Отримуємо перші показники", "Getting the first readings") }
        return store.error == nil ? VL("Готові до підключення", "Ready to connect") : VL("Станція поки не відповіла", "The station has not responded yet")
    }

    private var orbStatus: String {
        if !store.isPolling { return VL("Оновлення призупинено", "Updates paused") }
        if store.report == nil { return VL("Очікуємо покази", "Waiting for readings") }
        if !fresh("soc_percent") { return VL("Останній відомий заряд", "Last known charge") }
        if store.flowState == .standby {
            return store.report?.socPercent == 100 ? VL("Батарея повна", "Battery full") : VL("Очікування", "Standby")
        }
        return store.flowState == .unknown ? VL("Уточнюємо стан", "Checking status") : store.flowState.title
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
        return VL("із \(VenusVisuals.number(maximum, digits: 0)) Вт · \(VenusVisuals.number(ratio * 100, digits: 1))%", "of \(VenusVisuals.number(maximum, digits: 0)) W · \(VenusVisuals.number(ratio * 100, digits: 1))%")
    }

    private func powerHelp(_ metric: VenusPowerMetric?) -> String {
        guard let metric else { return VL("Потужність цього каналу ще не отримано.", "Power for this channel has not been received yet.") }
        let scope = metric.metricKey == "offgrid_power_w" ? VL(" Споживання приладів, підключених до резервного виходу, не обов’язково всього дому.", " Consumption by devices connected to the backup output, not necessarily the whole home.") : ""
        let date = metric.observedAt.flatMap(VenusReport.date)
        let receipt = date.map { " \(metric.isFresh ? VL("Отримано", "Received") : VL("Останній показ", "Last reading")) \($0.formatted(.dateTime.locale(localization.language.locale).day().month().year().hour().minute().second()))." } ?? ""
        return metric.meaning + scope + receipt
    }
    private func receiptHelp(_ metric: String) -> String {
        let meaning: String
        switch metric {
        case "soc_percent": meaning = VL("Заряд батареї у відсотках від її повної місткості.", "Battery charge as a percentage of its full capacity.")
        case "grid_power_w": meaning = VL("Потужність через мережевий AC-канал станції, у ватах або кіловатах. Це потік енергії, а не напруга й не споживання всього дому.", "Power through the station’s grid AC channel, in watts or kilowatts. This is energy flow, not voltage or total home consumption.")
        case "battery_temperature_c":
            let temperature = VenusTemperature.evaluate(value: store.report?.batteryTemperatureC, fresh: fresh(metric))
            meaning = temperature.title + ". " + temperature.explanation
        case "battery_remaining_wh": meaning = VL("Запас енергії, що залишився в батареї, у Вт·год або кВт·год.", "Energy remaining in the battery, in Wh or kWh.")
        case "battery_rated_wh": meaning = VL("Повна місткість батареї за API, у Вт·год або кВт·год; не поточний запас.", "Full battery capacity reported by the API, in Wh or kWh; not the energy currently stored.")
        case "pv_power_w": meaning = VL("Потужність сонячних входів за API, у ватах або кіловатах.", "Solar input power reported by the API, in watts or kilowatts.")
        default: meaning = VL("Показник, отриманий від станції через локальний API.", "A reading received from the station through the local API.")
        }
        guard let text = store.report?.metricObservedAt?[metric], let date = VenusReport.date(text) else { return VL("\(meaning) Показник ще не отримано.", "\(meaning) This reading has not been received yet.") }
        return "\(meaning) \(fresh(metric) ? VL("Отримано", "Received") : VL("Остання відповідь", "Last response")) \(date.formatted(.dateTime.locale(localization.language.locale).day().month().year().hour().minute().second()))." + VL(" Це час відповіді API, не час фізичного виміру.", " This is the API response time, not the physical measurement time.")
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
        settingsPage(VL("Налаштування", "Settings"), back: .overview) {
            settingsRow(VL("Керування станцією", "Station controls"), subtitle: VL("Режими, заряджання та ліміти", "Modes, charging and limits"), symbol: "slider.horizontal.3") { openControls(from: .settings) }
            settingsRow(VL("Мережа", "Network"), subtitle: VL("Пошук станції, IP та Local API", "Station discovery, IP and Local API"), symbol: "wifi", action: openStationSettings)
            settingsRow(VL("Графіки відключень", "Outage schedules"), subtitle: VL("Область, оператор та твоя група", "Region, operator and your group"), symbol: "bolt.slash") { openOutages(from: .settings) }
            settingsRow(VL("Сповіщення", "Notifications"), subtitle: VL("Події станції та високе навантаження", "Station events and high load"), symbol: "bell") { page = .notificationsSettings }
            settingsRow(VL("Оновлення застосунку", "App updates"), subtitle: updateSubtitle, symbol: "arrow.down.circle") { page = .updateSettings }
            settingsRow(VL("Інші параметри", "Other settings"), subtitle: VL("Мова, автозапуск і довідка", "Language, launch at login and help"), symbol: "slider.horizontal.3") { page = .otherSettings }
            settingsRow(VL("Про застосунок", "About the app"), subtitle: VL("Версія, розробник і контакти", "Version, developer and contacts"), symbol: "info.circle") { page = .about }
        }
    }

    private var stationSettings: some View {
        settingsPage(VL("Мережа", "Network"), back: .settings) {
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
            Text(VL("Підключення", "Connection")).font(.system(size: 14, weight: .semibold))
            HStack(alignment: .bottom, spacing: 9) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(VL("IP-адреса", "IP address")).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                    TextField("192.168.1.100", text: $address).onSubmit(saveConnection)
                        .accessibilityLabel(VL("IP-адреса станції", "Station IP address"))
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(VL("Порт", "Port")).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                    TextField("30000", text: $port).onSubmit(saveConnection)
                        .accessibilityLabel(VL("Порт Local API", "Local API port"))
                }.frame(width: 84)
                Button(VL("Підключити", "Connect"), action: saveConnection)
                    .buttonStyle(VenusButtonStyle(primary: true)).disabled(store.commandBusy || store.isDiscovering)
            }.textFieldStyle(VenusTextFieldStyle())
            VenusConnectionHints()
            Button(action: scan) {
                HStack(spacing: 9) {
                    if store.isDiscovering {
                        ProgressView().controlSize(.small).tint(.white)
                    } else { Image(systemName: "magnifyingglass") }
                    Text(store.isDiscovering ? VL("Шукаємо станцію…", "Finding your station…")
                         : store.error != nil ? VL("Спробувати пошук ще раз", "Try discovery again") : VL("Шукати автоматично", "Find automatically"))
                }.frame(maxWidth: .infinity)
            }.buttonStyle(VenusButtonStyle()).disabled(store.isDiscovering || store.commandBusy)
            VenusLocalAPIHelpLink(model: store.model)
            if store.error != nil && !store.isDiscovering {
                Text(VL("Перевір IP-адресу й порт у MARSTEK, тоді натисни «Підключити». Пошук також можна повторити.", "Check the IP address and port in MARSTEK, then click Connect. You can also try discovery again."))
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if #available(macOS 15, *), store.error != nil {
                Text(VL("Дозволь VenusBar доступ до локальної мережі: Системні параметри → Приватність і безпека → Локальна мережа.", "Allow VenusBar access in System Settings → Privacy & Security → Local Network."))
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
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
                Text(VL("«Розряджається» означає, що станція віддає енергію. Тут можна уточнити індикацію за фактичним станом; режим роботи станції не змінюється.", "“Discharging” means that the station is supplying energy. Adjust the indication to match its actual state; this does not change the station’s operating mode."))
                    .font(.system(size: 13)).foregroundStyle(.white.opacity(0.65)).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    calibration(VL("Заряджається", "Charging"), state: .charging)
                    calibration(VL("Розряджається", "Discharging"), state: .supplyingHome)
                    calibration(VL("Від мережі", "Mains"), state: .mains)
                }.buttonStyle(VenusButtonStyle(compact: true)).disabled(!store.isFresh || store.commandBusy)
                Text(VL("Очікування означає відсутність помітного потоку енергії й не підтверджує живлення від мережі. Ручне підтвердження мережі діє 90 секунд.", "Standby means there is no significant energy flow; it does not confirm mains power. Manual mains confirmation lasts 90 seconds."))
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.5)).fixedSize(horizontal: false, vertical: true)
            }.padding(.top, 12)
        } label: {
            Text(VL("Уточнення показників", "Adjust readings")).font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.75)).frame(minHeight: 32)
        }
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Button { page = .settings } label: { Label(VL("Назад", "Back"), systemImage: "chevron.left") }
                    .buttonStyle(VenusButtonStyle())
                Text(VL("Про VenusBar", "About VenusBar")).font(.system(size: 17, weight: .semibold))
                Spacer(minLength: 0)
            }
            Spacer(minLength: 12)
            VStack(spacing: 13) {
                if let icon = NSApp.applicationIconImage {
                    Image(nsImage: icon).resizable().interpolation(.high)
                        .frame(width: 64, height: 64).accessibilityHidden(true)
                }
                Text("VenusBar").font(.system(size: 26, weight: .semibold, design: .rounded))
                Text(versionLabel)
                    .font(.system(size: 13)).foregroundStyle(.white.opacity(0.5))
                Text(VL("Розробник · tenderfog", "Developer · tenderfog")).font(.system(size: 14)).foregroundStyle(.white.opacity(0.75))
                Text(VL("Зроблено в Україні", "Made in Ukraine")).font(.system(size: 14, weight: .medium)).padding(.top, 3)
            }.frame(maxWidth: .infinity)
            VStack(spacing: 10) {
                Link(destination: URL(string: "https://github.com/tenderfog/marstek")!) {
                    HStack { Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right"); Spacer(); Image(systemName: "arrow.up.right") }
                        .frame(maxWidth: .infinity)
                }.buttonStyle(VenusButtonStyle())
                Link(destination: URL(string: "mailto:tenderfog.site@gmail.com")!) {
                    HStack { Label("tenderfog.site@gmail.com", systemImage: "envelope"); Spacer(); Image(systemName: "arrow.up.right") }
                        .frame(maxWidth: .infinity)
                }.buttonStyle(VenusButtonStyle())
            }.font(.system(size: 14)).padding(.top, 13)
            Spacer(minLength: 12)
        }.padding(22)
    }

    private var versionLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "2"
        return VL("Версія \(version) · збірка \(build)", "Version \(version) · build \(build)")
    }

    private var notificationSettings: some View {
        settingsPage(VL("Сповіщення", "Notifications"), back: .settings) {
            VStack(alignment: .leading, spacing: 8) {
                Toggle(VL("Дозволити сповіщення", "Enable notifications"), isOn: Binding(
                    get: { notifications.masterEnabled },
                    set: { notifications.setMasterEnabled($0) }))
                    .font(.system(size: 15, weight: .medium)).toggleStyle(.switch)
                    .frame(minHeight: 44).disabled(notifications.isRequestingPermission)
                Text(VL("Локальні сповіщення VenusBar на цьому Mac. Дозвіл macOS запитується після ввімкнення.", "Local VenusBar notifications on this Mac. macOS asks for permission when you turn them on."))
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
                Text(notifications.isRequestingPermission ? VL("Очікуємо дозволу macOS…", "Waiting for macOS permission…") : notifications.permissionStatus)
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
                if notifications.permissionDenied {
                    Button(action: notifications.openSystemSettings) {
                        Label(VL("Відкрити налаштування macOS", "Open macOS Settings"), systemImage: "arrow.up.right")
                    }.buttonStyle(VenusButtonStyle())
                }
            }
            rule
            VStack(alignment: .leading, spacing: 14) {
                Toggle(VL("Високе навантаження", "High load"), isOn: Binding(
                    get: { notifications.highLoadEnabled },
                    set: { notifications.setHighLoadEnabled($0) }))
                    .font(.system(size: 15, weight: .medium)).toggleStyle(.switch)
                    .frame(minHeight: 44).disabled(!notifications.masterEnabled)
                Text(VL("Попередження, коли вихідна потужність станції перевищує обраний поріг. Наприклад, після ввімкнення потужного приладу; VenusBar не визначає, який саме прилад працює.", "An alert when the station’s output power exceeds your threshold, for example after a high-power appliance turns on. VenusBar does not identify the appliance."))
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(VL("Поріг сповіщення", "Alert threshold")).font(.system(size: 13)).foregroundStyle(.white.opacity(0.6))
                        Spacer(minLength: 8)
                        Text(VL("\(VenusVisuals.number(notifications.thresholdW, digits: 0)) Вт", "\(VenusVisuals.number(notifications.thresholdW, digits: 0)) W"))
                            .font(.system(size: 27, weight: .medium, design: .rounded)).monospacedDigit()
                    }
                    Slider(value: Binding(get: { notifications.thresholdW }, set: { notifications.setThresholdWatts($0) }),
                           in: 100...notificationThresholdMaximum, step: 50)
                        .tint(.white.opacity(0.8))
                        .accessibilityLabel(VL("Поріг високого навантаження у ватах", "High load threshold in watts"))
                        .accessibilityValue(VL("\(Int(notifications.thresholdW)) ват", "\(Int(notifications.thresholdW)) watts"))
                    HStack {
                        Text(VL("100 Вт", "100 W"))
                        Spacer()
                        Text(VL("\(Int(notificationThresholdMaximum)) Вт", "\(Int(notificationThresholdMaximum)) W"))
                    }.font(.system(size: 11)).foregroundStyle(.white.opacity(0.4)).monospacedDigit()
                }.disabled(!notifications.masterEnabled || !notifications.highLoadEnabled)
                    .opacity(notifications.masterEnabled && notifications.highLoadEnabled ? 1 : 0.45)
                Text(VL("Це лише поріг сповіщення. Він не змінює ліміти, режим або захист станції.", "This is only an alert threshold. It does not change the station’s limits, mode or protection."))
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var notificationThresholdMaximum: Double { store.model == .venusE ? 2500 : 5000 }

    private var updateSettings: some View {
        settingsPage(VL("Оновлення застосунку", "App updates"), back: .settings) {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 34, weight: .light)).foregroundStyle(.white.opacity(0.8))
                    .accessibilityHidden(true)
                Text("VenusBar").font(.system(size: 23, weight: .semibold))
                Text(versionLabel).font(.system(size: 13)).foregroundStyle(.white.opacity(0.55))
                if let version = updates.availableVersion {
                    Label(VL("Доступна версія \(version)", "Version \(version) is available"), systemImage: "arrow.down.circle.fill")
                        .font(.system(size: 14, weight: .medium)).foregroundStyle(Color.accentColor)
                }
                Text(VL("Перевіряємо нові версії на GitHub. Коли з’явиться оновлення, побачиш, що змінилося, і зможеш встановити його.", "We check GitHub for new versions. When an update is available, you can see what changed and choose to install it."))
                    .font(.system(size: 13)).foregroundStyle(.white.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
                Button(VL("Перевірити оновлення", "Check for Updates"), action: updates.checkForUpdates)
                    .buttonStyle(VenusButtonStyle(primary: true)).disabled(!updates.canCheckForUpdates)
            }.padding(.vertical, 8)
            rule
            VStack(alignment: .leading, spacing: 9) {
                Toggle(VL("Перевіряти автоматично", "Check automatically"), isOn: Binding(
                    get: { updates.automaticallyChecksForUpdates },
                    set: { updates.setAutomaticallyChecksForUpdates($0) }))
                    .font(.system(size: 15, weight: .medium)).toggleStyle(.switch)
                    .frame(minHeight: 44).disabled(!updates.isAvailable)
                Text(VL("Завантаження та встановлення — після твого підтвердження. Підключення до станції, адреса й налаштування збережуться.", "Downloading and installing require your confirmation. Your station connection, address and settings are kept."))
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
                if !updates.isAvailable {
                    Text(VL("Оновлення недоступні в цій збірці.", "Updates are not available in this build."))
                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
                }
            }
        }
    }

    private var updateSubtitle: String {
        updates.availableVersion.map { VL("Доступна версія \($0)", "Version \($0) is available") }
            ?? VL("Нові версії VenusBar", "New versions of VenusBar")
    }

    private var otherSettings: some View {
        settingsPage(VL("Інші параметри", "Other settings"), back: .settings) {
            VStack(alignment: .leading, spacing: 9) {
                Text(VL("Мова", "Language")).font(.system(size: 14))
                Picker(VL("Мова застосунку", "App language"), selection: Binding(get: { localization.language }, set: { localization.choose($0) })) {
                    Text("Українська").tag(VenusLanguage.uk)
                    Text("English").tag(VenusLanguage.en)
                    Text("Суржик").tag(VenusLanguage.surzhyk)
                }.pickerStyle(.segmented)
            }
            HStack {
                Text(VL("Оновлення показників", "Readings refresh")).font(.system(size: 14))
                Spacer()
                HStack(spacing: 7) {
                    ForEach([10.0, 30.0, 60.0], id: \.self) { seconds in
                        Button(VL("\(Int(seconds)) с", "\(Int(seconds)) s")) { store.setRefreshInterval(seconds) }
                            .buttonStyle(VenusButtonStyle(primary: store.refreshInterval == seconds, compact: true))
                            .disabled(store.commandBusy)
                    }
                }.accessibilityLabel(VL("Інтервал оновлення", "Refresh interval"))
            }
            Toggle(VL("Запускати разом із macOS", "Launch at login"), isOn: Binding(get: { store.startsAtLogin }, set: { store.setStartsAtLogin($0) }))
                .font(.system(size: 14)).toggleStyle(.switch).frame(minHeight: 44)
            VenusEnergyReserveControl(store: energy)
            HStack {
                Text(store.isPolling ? VL("Показники оновлюються автоматично", "Readings refresh automatically") : VL("Оновлення показників призупинено", "Readings refresh paused")).font(.system(size: 13)).foregroundStyle(.white.opacity(0.65))
                Spacer()
                if store.isPolling { Button(VL("Пауза", "Pause"), action: store.pause) }
                else { Button(VL("Продовжити", "Resume"), action: store.start) }
            }.buttonStyle(VenusButtonStyle())
            rule
            Button { openHelp(from: .otherSettings) } label: {
                Label(VL("Як користуватися VenusBar", "How to use VenusBar"), systemImage: "questionmark.circle")
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
                Button { page = back } label: { Label(VL("Назад", "Back"), systemImage: "chevron.left") }
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
    private func openOutages(from origin: Page) { outageReturnPage = origin; page = .outageSettings }
    private func connectedForFirstTime() {
        if !addressWelcomeCompleted && outages.selection == nil { addressSetupPending = true }
    }
    private func completeAddressWelcome(setUp: Bool) {
        addressWelcomeCompleted = true
        addressSetupPending = false
        if setUp { openOutages(from: .overview) } else { page = .overview }
    }
    private var addressWelcome: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "bolt.slash").font(.system(size: 30, weight: .light)).padding(.bottom, 4)
            Text(VL("Станцію підключено", "Station connected")).font(.system(size: 23, weight: .semibold))
            Text(VL("Додати графік відключень?", "Add an outage schedule?")).font(.system(size: 17, weight: .medium))
            Text(VL("Обери свою адресу, щоб бачити план оператора й оцінку запасу енергії до повернення світла. Це можна зробити пізніше в налаштуваннях.", "Choose your address to see the operator’s schedule and an estimate of stored energy until power returns. You can also do this later in Settings."))
                .font(.system(size: 14)).foregroundStyle(.white.opacity(0.65)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button { completeAddressWelcome(setUp: true) } label: {
                Text(VL("Налаштувати графік", "Set up outage schedule")).frame(maxWidth: .infinity)
            }.buttonStyle(VenusButtonStyle(primary: true))
            Button { completeAddressWelcome(setUp: false) } label: {
                Text(VL("Налаштувати пізніше", "Set up later")).frame(maxWidth: .infinity)
            }.buttonStyle(VenusButtonStyle())
        }.padding(28)
    }
    private func openHelp(from origin: Page) { helpReturnPage = origin; page = .help }
    private func loadConnectionDraft() {
        guard !connectionDraftLoaded else { return }
        address = store.ip; port = String(store.port); connectionDraftLoaded = true
    }
    private func openSettings() { loadConnectionDraft(); page = .settings }
    private func openStationSettings() { loadConnectionDraft(); page = .stationSettings }
    private func openControls(from origin: Page) { controlsReturnPage = origin; page = .controls }
    private func saveConnection() {
        guard let value = Int(port), (1024...65535).contains(value) else { formMessage = VL("Порт має бути числом від 1024 до 65535.", "Port must be a number from 1024 to 65535."); return }
        do { try store.configure(ip: address, port: value); formMessage = nil; page = .overview }
        catch { formMessage = error.localizedDescription }
    }
    private func scan() {
        guard let value = Int(port), (1024...65535).contains(value) else { formMessage = VL("Порт має бути числом від 1024 до 65535.", "Port must be a number from 1024 to 65535."); return }
        formMessage = nil; store.discover(port: value)
    }
    private func calibration(_ title: String, state: VenusFlowState) -> some View {
        Button(title) {
            do { try store.calibrate(state); formMessage = VL("Індикацію уточнено для цієї станції.", "The indication has been adjusted for this station.") }
            catch { formMessage = error.localizedDescription }
        }
    }
}

@MainActor
struct VenusIslandContent: View {
    @ObservedObject private var localization = VenusLocalization.shared
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
            .environment(\.locale, localization.language.locale)
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
        if let soc = store.report?.socPercent { values.append(VL("Заряд \(VenusVisuals.soc(soc))", "Charge \(VenusVisuals.soc(soc))")) }
        if let charge { values.append("\(charge.isFresh ? "" : VL("Останній показ. ", "Last reading. "))\(charge.title): \(VenusVisuals.power(charge.watts))") }
        if let output { values.append("\(output.isFresh ? "" : VL("Останній показ. ", "Last reading. "))\(output.title): \(VenusVisuals.power(output.watts))") }
        if let temperature = store.report?.batteryTemperatureC { values.append(VL("Температура батареї \(VenusVisuals.number(temperature)) градусів Цельсія", "Battery temperature \(VenusVisuals.number(temperature)) degrees Celsius")) }
        values.append(store.flowText)
        values.append(VL("Відкрити подробиці", "Open details"))
        return values.joined(separator: ". ")
    }
}

private struct VenusOutputLoadTrack: View {
    @ObservedObject private var localization = VenusLocalization.shared
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
        return VL("\(VenusVisuals.number(watts, digits: 0)) із \(VenusVisuals.number(maximum, digits: 0)) Вт · \(VenusVisuals.number(ratio * 100, digits: 1))%.\(source) Це відношення до номінальної потужності, а не зчитаний встановлений ліміт. Колір — орієнтир завантаження, не стан апаратного захисту.", "\(VenusVisuals.number(watts, digits: 0)) of \(VenusVisuals.number(maximum, digits: 0)) W · \(VenusVisuals.number(ratio * 100, digits: 1))%.\(source) This compares output with the nominal rating, not a configured limit read from the station. Colour indicates utilization, not hardware protection status.")
    }
}
