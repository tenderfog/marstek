import SwiftUI

struct VenusControls: View {
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
    private let weekdays = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Нд"]

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 12) {
                Button(action: onBack) { Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold)) }
                    .buttonStyle(VenusButtonStyle(compact: true)).accessibilityLabel("Повернутися до огляду")
                Text("Керування станцією").font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(store.model.title).font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
            }
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
        .padding(17)
        .frame(width: 520, height: 430)
        .background(Color.clear)
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .onAppear(perform: selectSupportedPower)
        .onChange(of: store.powerLimits) { _ in selectSupportedPower() }
        .confirmationDialog("Скинути \(store.model.title) до заводських налаштувань?",
                            isPresented: $resetConfirmation, titleVisibility: .visible) {
            Button(confirmedKeepEnergy ? "Скинути зі збереженням лічильників" : "Скинути й видалити лічильники", role: .destructive) {
                guard endpoint == confirmedEndpoint, store.supportsSystemControls else {
                    inputError = "Підключення змінилося. Перевір станцію й повтори підтвердження."
                    return
                }
                send(.factoryReset(keepEnergy: confirmedKeepEnergy))
            }
            Button("Скасувати", role: .cancel) {}
        } message: {
            Text("\(store.ip):\(store.port)\n\(confirmedKeepEnergy ? "Накопичені лічильники енергії буде збережено." : "Накопичені лічильники енергії буде видалено.") Інші налаштування станції буде скинуто; після цього може знадобитися повторне підключення в MARSTEK.")
        }
    }

    private var modes: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                heading("Режим роботи")
                Spacer()
                Text("Поточний: \(store.report?.mode ?? "—")").font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
            }
            HStack(spacing: 7) {
                ForEach(store.controlModes, id: \.rawValue) { mode in
                    Button { send(.setMode(mode)) } label: {
                        HStack(spacing: 5) {
                            Text(mode.title)
                            if store.report?.mode?.caseInsensitiveCompare(mode.rawValue) == .orderedSame {
                                Image(systemName: "checkmark").font(.system(size: 9, weight: .semibold))
                            }
                        }.font(.system(size: 14)).frame(maxWidth: .infinity).padding(.vertical, 3)
                    }
                    .buttonStyle(VenusButtonStyle(compact: true)).disabled(!canSend)
                }
            }
            note("Auto — самоспоживання з лічильником; AI — оптимізація MARSTEK; Manual — розклад; UPS — резервне живлення.")
        }
    }

    private var systemSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading("Нові системні налаштування")
            if !store.supportsSystemControls {
                note("DOD, LED, Bluetooth і ліміт потужності потребують підтримуваної моделі з прошивкою 150 або новішою.")
            }
            Group {
                row("Глибина розряду") {
                    HStack(spacing: 6) {
                        Button { dod -= 1 } label: { Image(systemName: "minus") }.disabled(dod <= 30).accessibilityLabel("Зменшити DOD")
                        Text("\(dod)%").font(.system(size: 14)).monospacedDigit().frame(width: 43)
                        Button { dod += 1 } label: { Image(systemName: "plus") }.disabled(dod >= 88).accessibilityLabel("Збільшити DOD")
                    }.buttonStyle(VenusButtonStyle(compact: true))
                    Button("Застосувати") { send(.setDOD(dod)) }.buttonStyle(VenusButtonStyle(compact: true))
                }
                note("Обраний запас — \(100 - dod)%. Це нове значення; поточний DOD через API не зчитується.")
                row("LED станції") {
                    Button("Увімкнути") { send(.setLED(true)) }
                    Button("Вимкнути") { send(.setLED(false)) }
                }.buttonStyle(VenusButtonStyle(compact: true))
                row("Видимість Bluetooth") {
                    Button("Увімкнути") { send(.setBluetooth(true)) }
                    Button("Вимкнути") { send(.setBluetooth(false)) }
                }.buttonStyle(VenusButtonStyle(compact: true))
                row("Ліміт потужності, Вт") {
                    HStack(spacing: 5) {
                        ForEach(store.powerLimits, id: \.self) { watts in
                            Button("\(watts)") { powerLimit = watts }
                                .buttonStyle(VenusButtonStyle(primary: powerLimit == watts, compact: true))
                                .accessibilityLabel("Новий ліміт \(watts) ватів")
                        }
                    }
                    Button("Застосувати") {
                        guard store.powerLimits.contains(powerLimit) else { inputError = "Обери ліміт для визначеної моделі."; return }
                        send(.setPowerLimit(powerLimit))
                    }.buttonStyle(VenusButtonStyle(compact: true))
                }
                note("LED, Bluetooth і поточний ліміт не мають документованого читання стану. Кнопки надсилають нове налаштування.")
            }.disabled(!canSend || !store.supportsSystemControls)
        }
    }

    private var passive: some View {
        DisclosureGroup(isExpanded: $passiveExpanded) {
            VStack(alignment: .leading, spacing: 11) {
                row("Задана потужність, Вт") { integerField("±Вт", text: $passivePower) }
                row("Тривалість, с") { integerField("1…86400", text: $passiveSeconds) }
                note("Нові параметри Passive. Знак напрямку потужності ще не перевірений у прошивці. Межа застосунку: ±\(capacity) Вт і 1…86400 с.")
                HStack {
                    Spacer()
                    Button("Застосувати Passive") {
                        do {
                            let values = try VenusControlInput.passive(power: passivePower, seconds: passiveSeconds, capacity: capacity)
                            send(.setPassive(power: values.power, seconds: values.seconds))
                        } catch { inputError = error.localizedDescription }
                    }.buttonStyle(VenusButtonStyle(primary: true)).disabled(!canSend)
                }
            }.padding(.top, 10)
        } label: { heading("Розширено · Passive") }
    }

    private var schedule: some View {
        DisclosureGroup(isExpanded: $scheduleExpanded) {
            VStack(alignment: .leading, spacing: 11) {
                note("Новий запис розкладу. Застосування перемкне станцію в Manual і запише обраний слот; наявний вміст слота не зчитується.")
                row("Слот розкладу") {
                    HStack(spacing: 6) {
                        Button { scheduleSlot -= 1 } label: { Image(systemName: "minus") }.disabled(scheduleSlot <= 0).accessibilityLabel("Попередній слот")
                        Text("\(scheduleSlot)").font(.system(size: 14)).monospacedDigit().frame(width: 30)
                        Button { scheduleSlot += 1 } label: { Image(systemName: "plus") }.disabled(scheduleSlot >= 9).accessibilityLabel("Наступний слот")
                    }.buttonStyle(VenusButtonStyle(compact: true))
                }
                HStack(spacing: 9) {
                    Text("Час").frame(width: 138, alignment: .leading)
                    TextField("HH:mm", text: $scheduleStart).textFieldStyle(VenusTextFieldStyle()).frame(width: 92).accessibilityLabel("Початок розкладу, години та хвилини")
                    Text("—").foregroundStyle(.white.opacity(0.4))
                    TextField("HH:mm", text: $scheduleEnd).textFieldStyle(VenusTextFieldStyle()).frame(width: 92).accessibilityLabel("Кінець розкладу, години та хвилини")
                    Spacer(minLength: 0)
                }.font(.system(size: 12))
                HStack(spacing: 4) {
                    Text("Дні").frame(width: 138, alignment: .leading)
                    ForEach(0..<7, id: \.self) { day in
                        let selected = scheduleDays & (1 << day) != 0
                        Button(weekdays[day]) { scheduleDays ^= 1 << day }
                            .buttonStyle(VenusButtonStyle(primary: selected, compact: true))
                            .accessibilityValue(selected ? "Обрано" : "Не обрано")
                    }
                }.font(.system(size: 12))
                row("Задана потужність, Вт") { integerField("±Вт", text: $schedulePower) }
                Toggle("Увімкнути цей слот", isOn: $scheduleEnabled).toggleStyle(.switch).font(.system(size: 12))
                note("Діапазон застосунку: ±\(capacity) Вт. Напрямок знака ще не перевірений у прошивці. Час — HH:mm, щонайменше один день.")
                HStack {
                    Spacer()
                    Button("Записати новий слот") {
                        do {
                            let watts = try VenusControlInput.schedule(slot: scheduleSlot, start: scheduleStart, end: scheduleEnd,
                                weekmask: scheduleDays, power: schedulePower, capacity: capacity)
                            send(.setSchedule(slot: scheduleSlot, start: scheduleStart, end: scheduleEnd,
                                weekmask: scheduleDays, power: watts, enabled: scheduleEnabled))
                        } catch { inputError = error.localizedDescription }
                    }.buttonStyle(VenusButtonStyle(primary: true)).disabled(!canSend)
                }
            }.padding(.top, 10)
        } label: { heading("Розширено · Новий розклад") }
    }

    private var reset: some View {
        DisclosureGroup(isExpanded: $resetExpanded) {
            VStack(alignment: .leading, spacing: 11) {
                note("Заводське скидання змінює налаштування станції. Доступне з прошивки 150; перед надсиланням буде окреме підтвердження.")
                Toggle("Зберегти накопичені лічильники енергії", isOn: $keepEnergy)
                    .toggleStyle(.switch).font(.system(size: 12))
                HStack {
                    Spacer()
                    Button("Скинути станцію…", role: .destructive) {
                        confirmedKeepEnergy = keepEnergy
                        confirmedEndpoint = endpoint
                        resetConfirmation = true
                    }.buttonStyle(VenusButtonStyle(compact: true)).disabled(!canSend || !store.supportsSystemControls)
                }
            }.padding(.top, 10)
        } label: { heading("Заводське скидання") }
        .disabled(store.commandBusy || !store.supportsSystemControls)
    }

    private var status: some View {
        HStack(alignment: .top, spacing: 8) {
            if store.commandBusy { ProgressView() }
            else { Image(systemName: inputError == nil ? "info.circle" : "exclamationmark.circle").font(.system(size: 12)) }
            Text(inputError ?? store.commandStatus ?? (!store.isFresh ? "Для команд потрібна свіжа відповідь станції." : "Підтвердження API означає прийняття команди; фізичний стан може відрізнятися."))
                .font(.system(size: 12)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                .help(inputError ?? store.commandStatus ?? "")
        }.foregroundStyle(.white.opacity(0.6)).frame(minHeight: 28, alignment: .top)
    }

    private var separator: some View { Rectangle().fill(.white.opacity(0.08)).frame(height: 1) }
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
        guard canSend else { inputError = "Дочекайся свіжої відповіді станції та завершення попередньої команди."; return }
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
              (-capacity...capacity).contains(value) else { throw Invalid("Введи цілу потужність від −\(capacity) до \(capacity) Вт.") }
        return value
    }

    static func passive(power: String, seconds: String, capacity: Int) throws -> (power: Int, seconds: Int) {
        let watts = try self.power(power, capacity: capacity)
        guard let duration = Int(seconds.trimmingCharacters(in: .whitespacesAndNewlines)), (1...86400).contains(duration) else {
            throw Invalid("Тривалість Passive має бути цілим числом від 1 до 86400 секунд.")
        }
        return (watts, duration)
    }

    static func schedule(slot: Int, start: String, end: String, weekmask: Int, power: String, capacity: Int) throws -> Int {
        guard (0...9).contains(slot), validTime(start), validTime(end), (1...127).contains(weekmask) else {
            throw Invalid("Вибери слот 0–9, час HH:mm та щонайменше один день тижня.")
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
