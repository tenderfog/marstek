import SwiftUI

struct VenusControls: View {
    @ObservedObject private var localization = VenusLocalization.shared
    @ObservedObject var store: VenusStore
    let onBack: () -> Void
    @State private var dod = 80
    @State private var powerLimit = 800
    @State private var passivePower = ""
    @State private var passiveSeconds = "300"
    @State private var scheduleSlot = 0
    @State private var scheduleStart = "08:00"
    @State private var scheduleEnd = "20:00"
    @State private var scheduleDays = 127
    @State private var schedulePower = ""
    @State private var scheduleEnabled = true
    @State private var keepEnergy = true
    @State private var passiveExpanded = false
    @State private var scheduleExpanded = false
    @State private var resetExpanded = false
    @State private var resetConfirmation = false
    @State private var confirmedKeepEnergy = true
    @State private var confirmedEndpoint = ""
    @State private var inputError: String?

    private var canSend: Bool { store.isFresh && !store.commandBusy && store.model != .unknown }
    private var capacity: Int { store.model == .venusA ? 1500 : store.model == .venusE ? 2500 : 0 }
    private var endpoint: String { "\(store.model.rawValue)|\(store.ip):\(store.port)" }
    private var weekdays: [String] { [VL("Пн", "Mo"), VL("Вт", "Tu"), VL("Ср", "We"), VL("Чт", "Th"), VL("Пт", "Fr"), VL("Сб", "Sa"), VL("Нд", "Su")] }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 14) {
                Button(action: onBack) { Label(VL("Назад", "Back"), systemImage: "chevron.left") }
                    .buttonStyle(VenusButtonStyle()).accessibilityLabel(VL("Повернутися до огляду", "Back to overview"))
                Text(VL("Керування станцією", "Station controls")).font(.system(size: 17, weight: .semibold))
                Spacer()
                Text(store.model.title).font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
            }.frame(height: 44)
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    modes
                    separator
                    systemSettings
                    separator
                    passive
                    separator
                    schedule
                    separator
                    reset
                }.padding(.vertical, 2).padding(.trailing, 3)
            }
            .scrollIndicators(.automatic)
            .frame(maxHeight: .infinity)
            .disabled(store.commandBusy)
            status
        }
        .padding(24)
        .frame(width: 520, height: 610, alignment: .topLeading)
        .background(Color.clear)
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .onAppear(perform: selectSupportedPower)
        .onChange(of: store.powerLimits) { _ in selectSupportedPower() }
        .confirmationDialog(VL("Скинути \(store.model.title) до заводських налаштувань?", "Reset \(store.model.title) to factory settings?"),
                            isPresented: $resetConfirmation, titleVisibility: .visible) {
            Button(confirmedKeepEnergy ? VL("Скинути зі збереженням лічильників", "Reset and keep energy counters") : VL("Скинути й видалити лічильники", "Reset and clear energy counters"), role: .destructive) {
                guard endpoint == confirmedEndpoint, store.supportsSystemControls else {
                    inputError = VL("Підключення змінилося. Перевір станцію й повтори підтвердження.", "The connection changed. Check the station and confirm again.")
                    return
                }
                send(.factoryReset(keepEnergy: confirmedKeepEnergy))
            }
            Button(VL("Скасувати", "Cancel"), role: .cancel) {}
        } message: {
            Text("\(store.ip):\(store.port)\n\(confirmedKeepEnergy ? VL("Накопичені лічильники енергії буде збережено.", "Accumulated energy counters will be kept.") : VL("Накопичені лічильники енергії буде видалено.", "Accumulated energy counters will be deleted.")) \(VL("Інші налаштування станції буде скинуто; після цього може знадобитися повторне підключення в MARSTEK.", "Other station settings will be reset; you may need to reconnect in MARSTEK afterwards."))")
        }
    }

    private var modes: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                heading(VL("Режим роботи", "Operating mode"))
                Spacer()
                Text(VL("Поточний: \(currentModeLabel)", "Current: \(currentModeLabel)")).font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
            }
            HStack(spacing: 4) {
                ForEach(store.controlModes, id: \.rawValue) { mode in
                    Button { send(.setMode(mode)) } label: {
                        HStack(spacing: 5) {
                            Text(modeLabel(mode)).lineLimit(1).fixedSize(horizontal: true, vertical: false)
                            if store.report?.mode?.caseInsensitiveCompare(mode.rawValue) == .orderedSame {
                                Image(systemName: "checkmark").font(.system(size: 9, weight: .semibold))
                            }
                        }.font(.system(size: 13, weight: .medium)).frame(maxWidth: .infinity).padding(.vertical, 3)
                    }
                    .buttonStyle(VenusButtonStyle(compact: true)).disabled(!canSend)
                }
            }
            note(VL("Auto — самоспоживання з лічильником; AI — оптимізація MARSTEK; Manual — розклад; UPS — резервне живлення.", "Auto — self-consumption with a meter; AI — MARSTEK optimization; Manual — schedule; UPS — backup power."))
        }
    }

    private var systemSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading(VL("Параметри станції", "Station settings"))
            if !store.supportsSystemControls {
                note(VL("DOD, LED, Bluetooth і ліміт потужності потребують підтримуваної моделі з прошивкою 150 або новішою.", "DOD, LED, Bluetooth and power limits require a supported model with firmware 150 or later."))
            }
            Group {
                row(VL("Глибина розряду", "Depth of discharge")) {
                    HStack(spacing: 6) {
                        Button { dod -= 1 } label: { Image(systemName: "minus") }.disabled(dod <= 30).accessibilityLabel(VL("Зменшити DOD", "Decrease DOD"))
                        Text("\(dod)%").font(.system(size: 14)).monospacedDigit().frame(width: 43)
                        Button { dod += 1 } label: { Image(systemName: "plus") }.disabled(dod >= 88).accessibilityLabel(VL("Збільшити DOD", "Increase DOD"))
                    }.buttonStyle(VenusButtonStyle(compact: true))
                    Button(VL("Застосувати", "Apply")) { send(.setDOD(dod)) }.buttonStyle(VenusButtonStyle(compact: true))
                }
                note(VL("Станція зможе використати \(dod)% заряду й залишить \(100 - dod)%. Це нове налаштування; поточне значення недоступне.", "The station can use \(dod)% of its charge and keep \(100 - dod)%. This is a new setting; the current value is unavailable."))
                row(VL("LED станції", "Station LED")) {
                    Button(VL("Увімкнути", "Turn on")) { send(.setLED(true)) }
                    Button(VL("Вимкнути", "Turn off")) { send(.setLED(false)) }
                }.buttonStyle(VenusButtonStyle(compact: true))
                row(VL("Видимість Bluetooth", "Bluetooth visibility")) {
                    Button(VL("Увімкнути", "Turn on")) { send(.setBluetooth(true)) }
                    Button(VL("Вимкнути", "Turn off")) { send(.setBluetooth(false)) }
                }.buttonStyle(VenusButtonStyle(compact: true))
                row(VL("Ліміт потужності, Вт", "Power limit, W")) {
                    HStack(spacing: 5) {
                        ForEach(store.powerLimits, id: \.self) { watts in
                            Button("\(watts)") { powerLimit = watts }
                                .buttonStyle(VenusButtonStyle(primary: powerLimit == watts, compact: true))
                                .accessibilityLabel(VL("Новий ліміт \(watts) ватів", "New limit: \(watts) watts"))
                        }
                    }
                    Button(VL("Застосувати", "Apply")) {
                        guard store.powerLimits.contains(powerLimit) else { inputError = VL("Обери ліміт для визначеної моделі.", "Choose a limit supported by this model."); return }
                        send(.setPowerLimit(powerLimit))
                    }.buttonStyle(VenusButtonStyle(compact: true))
                }
                note(VL("LED, Bluetooth і поточний ліміт не мають документованого читання стану. Кнопки надсилають нове налаштування.", "The API does not document reading the LED setting, Bluetooth visibility or current limit. These buttons send a new setting."))
            }.disabled(!canSend || !store.supportsSystemControls)
        }
    }

    private var passive: some View {
        DisclosureGroup(isExpanded: $passiveExpanded) {
            VStack(alignment: .leading, spacing: 11) {
                row(VL("Задана потужність, Вт", "Target power, W")) { integerField(VL("±Вт", "±W"), text: $passivePower) }
                row(VL("Тривалість, с", "Duration, s")) { integerField("1…86400", text: $passiveSeconds) }
                note(VL("Нові параметри Passive. Знак напрямку потужності ще не перевірений у прошивці. Межа застосунку: ±\(capacity) Вт і 1…86400 с.", "New Passive settings. Power direction has not been verified for this firmware. App bounds: ±\(capacity) W and 1…86400 s."))
                HStack {
                    Spacer()
                    Button(VL("Застосувати Passive", "Apply Passive")) {
                        do {
                            let values = try VenusControlInput.passive(power: passivePower, seconds: passiveSeconds, capacity: capacity)
                            send(.setPassive(power: values.power, seconds: values.seconds))
                        } catch { inputError = error.localizedDescription }
                    }.buttonStyle(VenusButtonStyle(primary: true)).disabled(!canSend)
                }
            }.padding(.top, 10)
        } label: { heading(VL("Розширено · Passive", "Advanced · Passive")) }
    }

    private var schedule: some View {
        DisclosureGroup(isExpanded: $scheduleExpanded) {
            VStack(alignment: .leading, spacing: 11) {
                note(VL("Новий запис розкладу. Застосування перемкне станцію в Manual і запише обраний слот; наявний вміст слота не зчитується.", "New schedule entry. Applying switches to Manual and writes the selected slot; its existing contents are not read."))
                row(VL("Слот розкладу", "Schedule slot")) {
                    HStack(spacing: 6) {
                        Button { scheduleSlot -= 1 } label: { Image(systemName: "minus") }.disabled(scheduleSlot <= 0).accessibilityLabel(VL("Попередній слот", "Previous slot"))
                        Text("\(scheduleSlot)").font(.system(size: 14)).monospacedDigit().frame(width: 30)
                        Button { scheduleSlot += 1 } label: { Image(systemName: "plus") }.disabled(scheduleSlot >= 9).accessibilityLabel(VL("Наступний слот", "Next slot"))
                    }.buttonStyle(VenusButtonStyle(compact: true))
                }
                HStack(spacing: 9) {
                    Text(VL("Час", "Time")).frame(width: 138, alignment: .leading)
                    TextField("HH:mm", text: $scheduleStart).textFieldStyle(VenusTextFieldStyle()).frame(width: 92).accessibilityLabel(VL("Початок розкладу, години та хвилини", "Schedule start, hours and minutes"))
                    Text("—").foregroundStyle(.white.opacity(0.4))
                    TextField("HH:mm", text: $scheduleEnd).textFieldStyle(VenusTextFieldStyle()).frame(width: 92).accessibilityLabel(VL("Кінець розкладу, години та хвилини", "Schedule end, hours and minutes"))
                    Spacer(minLength: 0)
                }.font(.system(size: 12))
                HStack(spacing: 4) {
                    Text(VL("Дні", "Days")).frame(width: 138, alignment: .leading)
                    ForEach(0..<7, id: \.self) { day in
                        let selected = scheduleDays & (1 << day) != 0
                        Button(weekdays[day]) { scheduleDays ^= 1 << day }
                            .buttonStyle(VenusButtonStyle(primary: selected, compact: true))
                            .accessibilityValue(selected ? VL("Обрано", "Selected") : VL("Не обрано", "Not selected"))
                    }
                }.font(.system(size: 12))
                row(VL("Задана потужність, Вт", "Target power, W")) { integerField(VL("±Вт", "±W"), text: $schedulePower) }
                Toggle(VL("Увімкнути цей слот", "Enable this slot"), isOn: $scheduleEnabled).toggleStyle(.switch).font(.system(size: 12))
                note(VL("Діапазон застосунку: ±\(capacity) Вт. Напрямок знака ще не перевірений у прошивці. Час — HH:mm, щонайменше один день.", "App bounds: ±\(capacity) W. Power direction has not been verified for this firmware. Time: HH:mm; select at least one day."))
                HStack {
                    Spacer()
                    Button(VL("Записати новий слот", "Save new slot")) {
                        do {
                            let watts = try VenusControlInput.schedule(slot: scheduleSlot, start: scheduleStart, end: scheduleEnd,
                                weekmask: scheduleDays, power: schedulePower, capacity: capacity)
                            send(.setSchedule(slot: scheduleSlot, start: scheduleStart, end: scheduleEnd,
                                weekmask: scheduleDays, power: watts, enabled: scheduleEnabled))
                        } catch { inputError = error.localizedDescription }
                    }.buttonStyle(VenusButtonStyle(primary: true)).disabled(!canSend)
                }
            }.padding(.top, 10)
        } label: { heading(VL("Розширено · Новий розклад", "Advanced · New schedule")) }
    }

    private var reset: some View {
        DisclosureGroup(isExpanded: $resetExpanded) {
            VStack(alignment: .leading, spacing: 11) {
                note(VL("Заводське скидання змінює налаштування станції. Доступне з прошивки 150; перед надсиланням буде окреме підтвердження.", "Factory reset changes station settings. Requires firmware 150 or later; a separate confirmation is required."))
                Toggle(VL("Зберегти накопичені лічильники енергії", "Keep accumulated energy counters"), isOn: $keepEnergy)
                    .toggleStyle(.switch).font(.system(size: 12))
                HStack {
                    Spacer()
                    Button(VL("Скинути станцію…", "Reset station…"), role: .destructive) {
                        confirmedKeepEnergy = keepEnergy
                        confirmedEndpoint = endpoint
                        resetConfirmation = true
                    }.buttonStyle(VenusButtonStyle(compact: true)).disabled(!canSend || !store.supportsSystemControls)
                }
            }.padding(.top, 10)
        } label: { heading(VL("Заводське скидання", "Factory reset")) }
        .disabled(store.commandBusy || !store.supportsSystemControls)
    }

    private var status: some View {
        HStack(alignment: .top, spacing: 8) {
            if store.commandBusy { ProgressView() }
            else { Image(systemName: inputError == nil ? "info.circle" : "exclamationmark.circle").font(.system(size: 12)) }
            Text(inputError ?? store.commandStatus ?? (!store.isFresh ? VL("Для команд потрібна свіжа відповідь станції.", "A fresh station response is required for commands.") : VL("Підтвердження API означає прийняття команди; фізичний стан може відрізнятися.", "API confirmation means the command was accepted; the physical state may differ.")))
                .font(.system(size: 12)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                .help(inputError ?? store.commandStatus ?? "")
        }.foregroundStyle(.white.opacity(0.6)).frame(minHeight: 28, alignment: .top)
    }

    private var separator: some View { Rectangle().fill(.white.opacity(0.08)).frame(height: 1) }
    private func modeLabel(_ mode: VenusMode) -> String {
        switch mode {
        case .auto: return VL("Авто", "Auto")
        case .ai: return "AI"
        case .manual: return VL("Ручний", "Manual")
        case .ups: return "UPS"
        }
    }
    private var currentModeLabel: String {
        guard let raw = store.report?.mode else { return "—" }
        return VenusMode.allCases.first(where: { $0.rawValue.caseInsensitiveCompare(raw) == .orderedSame }).map(modeLabel) ?? raw
    }
    private func heading(_ text: String) -> some View { Text(text).font(.system(size: 13, weight: .semibold)) }
    private func note(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(.white.opacity(0.46)).fixedSize(horizontal: false, vertical: true)
    }
    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 9) {
            Text(title).frame(width: 155, alignment: .leading)
            Spacer(minLength: 0)
            content()
        }.font(.system(size: 14)).frame(minHeight: 36)
    }
    private func integerField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text).textFieldStyle(VenusTextFieldStyle()).multilineTextAlignment(.trailing)
            .frame(width: 112).monospacedDigit()
    }
    private func selectSupportedPower() { if !store.powerLimits.contains(powerLimit) { powerLimit = store.powerLimits.first ?? 800 } }
    private func send(_ action: VenusAction) {
        guard canSend else { inputError = VL("Дочекайся свіжої відповіді станції та завершення попередньої команди.", "Wait for a fresh station response and for the previous command to finish."); return }
        inputError = nil
        store.perform(action)
    }
}

enum VenusControlInput {
    private struct Invalid: LocalizedError {
        let errorDescription: String?
        init(_ text: String) { errorDescription = text }
    }

    static func power(_ text: String, capacity: Int) throws -> Int {
        guard capacity > 0, let value = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)),
              (-capacity...capacity).contains(value) else { throw Invalid(VL("Введи цілу потужність від −\(capacity) до \(capacity) Вт.", "Enter a whole number from −\(capacity) to \(capacity) W.")) }
        return value
    }

    static func passive(power: String, seconds: String, capacity: Int) throws -> (power: Int, seconds: Int) {
        let watts = try self.power(power, capacity: capacity)
        guard let duration = Int(seconds.trimmingCharacters(in: .whitespacesAndNewlines)), (1...86400).contains(duration) else {
            throw Invalid(VL("Тривалість Passive має бути цілим числом від 1 до 86400 секунд.", "Passive duration must be a whole number from 1 to 86400 seconds."))
        }
        return (watts, duration)
    }

    static func schedule(slot: Int, start: String, end: String, weekmask: Int, power: String, capacity: Int) throws -> Int {
        guard (0...9).contains(slot), validTime(start), validTime(end), (1...127).contains(weekmask) else {
            throw Invalid(VL("Вибери слот 0–9, час HH:mm та щонайменше один день тижня.", "Choose slot 0–9, HH:mm times and at least one weekday."))
        }
        return try self.power(power, capacity: capacity)
    }

    private static func validTime(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard bytes.count == 5, bytes[2] == 58,
              [bytes[0], bytes[1], bytes[3], bytes[4]].allSatisfy({ (48...57).contains($0) }) else { return false }
        return Int(value.prefix(2))! < 24 && Int(value.suffix(2))! < 60
    }

    static func selfCheck() throws {
        func require(_ value: Bool) throws { if !value { throw Invalid("VenusControls input regression") } }
        let passive = try passive(power: "-2500", seconds: "86400", capacity: 2500)
        try require(passive.power == -2500 && passive.seconds == 86400)
        try require(try schedule(slot: 9, start: "00:00", end: "23:59", weekmask: 127, power: "1500", capacity: 1500) == 1500)
        for (power, seconds, limit) in [("1501", "1", 1500), ("1.5", "1", 2500), ("0", "0", 2500), ("0", "86401", 2500)] {
            var rejected = false
            do { _ = try self.passive(power: power, seconds: seconds, capacity: limit) } catch { rejected = true }
            try require(rejected)
        }
        for (slot, start, end, days) in [(10, "08:00", "20:00", 127), (0, "24:00", "20:00", 127),
                                       (0, "08:0", "20:00", 127), (0, "08:00", "20:60", 127),
                                       (0, "08:00", "20:00", 0), (0, "08:00", "20:00", 128)] {
            var rejected = false
            do { _ = try schedule(slot: slot, start: start, end: end, weekmask: days, power: "0", capacity: 2500) } catch { rejected = true }
            try require(rejected)
        }
    }
}
