import SwiftUI

struct VenusHelp: View {
    @ObservedObject private var localization = VenusLocalization.shared
    var height: CGFloat = 610
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Button(action: onBack) { Label(VL("Назад", "Back"), systemImage: "chevron.left") }
                    .buttonStyle(VenusButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Text(VL("Як користуватися VenusBar", "How to use VenusBar"))
                    .font(.system(size: 18, weight: .semibold))
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    section(VL("Завжди в рядку меню", "Always in the menu bar"), symbol: "bolt.fill",
                            text: VL("Знайди блискавку в рядку меню macOS. Поруч з’являється заряд станції, коли його отримано. Наведи курсор для короткого огляду; натисни, щоб відкрити головну панель.", "Look for the lightning bolt in the macOS menu bar. The station’s charge appears beside it once received. Hover for a quick overview; click to open the main panel."))
                    flowLegend
                    section(VL("Підключення та оновлення", "Connection and updates"), symbol: "gearshape",
                            text: VL("Натисни шестерню й обери «Шукати автоматично». Або введи IP-адресу та UDP-порт вручну; типовий порт — 30000. На станції має бути ввімкнений Local API, а Mac має бути в тій самій мережі.", "Click the gear and choose “Find automatically”. Or enter the IP address and UDP port manually; the default port is 30000. Local API must be enabled on the station, and your Mac must be on the same network."))
                    section(VL("Фонове читання", "Background readings"), symbol: "arrow.clockwise",
                            text: VL("У налаштуваннях обери інтервал 10, 30 або 60 секунд і, за потреби, запуск разом із macOS. «Пауза» зупиняє лише читання. «Продовжити» відновлює його; «Оновити показники» запитує нову відповідь одразу.", "In Settings, choose a 10, 30 or 60 second interval and optionally launch at login. “Pause” only stops readings. “Resume” starts them again; “Refresh readings” requests a new response immediately."))
                    section(VL("Керування станцією", "Station controls"), symbol: "slider.horizontal.3",
                            text: VL("Кнопка «Керування» відкриває режими Auto, AI, Manual і UPS та доступні для моделі налаштування. Обери нове значення й натисни «Застосувати». Підтвердження API означає, що команду прийнято; перевір результат на станції. Скидання має окреме підтвердження.", "“Controls” opens Auto, AI, Manual and UPS modes and the settings available for your model. Choose a new value and click “Apply”. An API acknowledgement means the command was accepted; verify the result on your station. Reset requires a separate confirmation."))
                    section(VL("Як читати останні покази", "Reading the last known values"), symbol: "clock",
                            text: VL("При втраті зв’язку або паузі останні покази залишаються приглушеними. Коротка смуга в головній панелі означає, що показник ще не отримано. Наведи курсор на значення, щоб побачити час відповіді API; це не час фізичного виміру.", "If the connection is lost or paused, the last readings remain visible but dimmed. A short bar in the main panel means a value has not been received yet. Hover over a value to see the API response time; this is not the time of the physical measurement."))
                }.padding(.vertical, 2).padding(.trailing, 5)
            }.scrollIndicators(.automatic)
        }
        .padding(24).frame(width: 520, height: height)
        .foregroundStyle(.white).background(.clear).preferredColorScheme(.dark)
        .environment(\.locale, localization.language.locale)
    }

    private var flowLegend: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(VL("Колір і значок стану", "State colour and icon")).font(.system(size: 14, weight: .semibold))
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    flow(VL("Розряджається", "Discharging"), symbol: "arrow.up.right", color: VenusVisuals.supplying)
                    flow(VL("Очікування", "Standby"), symbol: "pause", color: .white.opacity(0.8))
                    flow(VL("Від мережі", "Mains"), symbol: "powerplug.fill", color: .gray)
                }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 12) {
                    flow(VL("Заряджається", "Charging"), symbol: "arrow.down.left", color: VenusVisuals.charging)
                    flow(VL("Покази уточнюються", "Readings being verified"), symbol: "waveform", color: .white.opacity(0.45))
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(VL("«Розряджається» — станція віддає енергію. «Очікування» означає відсутність помітного потоку, зокрема при повній батареї; це не підтвердження живлення від мережі. За потреби індикацію можна уточнити в налаштуваннях → «Уточнення показників», не змінюючи режим станції.", "“Discharging” means the station is supplying energy. “Standby” means there is no significant flow, including when the battery is full; this does not confirm mains power. If needed, adjust the indication in Settings → “Adjust readings” without changing the station’s mode."))
                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func flow(_ title: String, symbol: String, color: Color) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol).font(.system(size: 15, weight: .medium)).foregroundStyle(color).frame(width: 22)
            Text(title).font(.system(size: 12)).foregroundStyle(.white.opacity(0.85))
        }
    }

    private func section(_ title: String, symbol: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol).font(.system(size: 14, weight: .semibold))
            Text(text).font(.system(size: 13)).foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true).lineSpacing(3)
        }
    }
}

/// Manufacturer app setup is separate from VenusBar's built-in usage help.
struct VenusLocalAPIHelpLink: View {
    @ObservedObject private var localization = VenusLocalization.shared
    let model: VenusModel
    @State private var guideShown = false

    var body: some View {
        Button { guideShown = true } label: {
            Label(VL("Інструкція: де знайти IP і порт", "Guide: where to find IP and port"), systemImage: "questionmark.circle")
                .font(.system(size: 12, weight: .medium))
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                .contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(.white.opacity(0.72))
            .popover(isPresented: $guideShown, arrowEdge: .bottom) {
                VenusConnectionGuide { guideShown = false }
            }
    }
}

struct VenusConnectionHints: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(VL("IP-адреса: MARSTEK → станція → ⚙ → Wi-Fi / IP.", "IP address: MARSTEK → station → ⚙ → Wi-Fi / IP."))
            Text(VL("Порт: налаштування станції → Local API → Ports.", "Port: station settings → Local API → Ports."))
        }.font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct VenusConnectionGuide: View {
    @ObservedObject private var localization = VenusLocalization.shared
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(alignment: .top) {
                Text(VL("Де знайти IP і порт", "Where to find IP and port"))
                    .font(.system(size: 18, weight: .semibold))
                Spacer(minLength: 8)
                Button(action: onClose) { Image(systemName: "xmark").frame(width: 28, height: 28) }
                    .buttonStyle(.plain).accessibilityLabel(VL("Закрити інструкцію", "Close guide"))
                    .keyboardShortcut(.cancelAction)
            }
            VStack(alignment: .leading, spacing: 10) {
                guideStep("1", title: VL("Відкрий станцію в MARSTEK", "Open your station in MARSTEK"),
                          text: VL("Натисни ⚙ та знайди IP-адресу в параметрах Wi-Fi або мережі. Введи її у VenusBar без змін.", "Tap ⚙ and find the IP address under Wi-Fi or network settings. Enter that address in VenusBar."))
                guideStep("2", title: VL("Увімкни Local API", "Enable Local API"),
                          text: VL("У тих самих налаштуваннях відкрий Local API, увімкни його та скопіюй число з Ports у поле «Порт». 30000 — лише стандартне значення.", "In the same settings, open Local API, enable it and copy the number from Ports into the Port field. 30000 is only the default."))
            }
            Text(VL("Mac і станція мають бути в одній локальній мережі. Назви пунктів у MARSTEK можуть відрізнятися.", "Your Mac and station must be on the same local network. Menu names in MARSTEK can vary."))
                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                Text(VL("Офіційні інструкції MARSTEK · PDF", "Official MARSTEK guides · PDF"))
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                instructionLink(.venusE, name: "Venus E3")
                instructionLink(.venusA, name: "Venus A")
            }
        }.padding(22).frame(width: 390)
            .foregroundStyle(.white).preferredColorScheme(.dark)
            .environment(\.locale, localization.language.locale)
    }

    private func guideStep(_ number: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number).font(.system(size: 12, weight: .semibold)).frame(width: 24, height: 24)
                .background(Circle().fill(.white.opacity(0.1)))
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(text).font(.system(size: 12)).foregroundStyle(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func instructionLink(_ model: VenusModel, name: String) -> some View {
        Link(destination: URL(string: "https://static-eu.marstekenergy.com/ems/resource/agreement/app/venus/\(model == .venusA ? "Venus_A" : "Venus_E3").pdf")!) {
            HStack {
                Text(VL("Відкрити інструкцію \(name)", "Open \(name) guide"))
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right")
            }.frame(maxWidth: .infinity)
        }.buttonStyle(VenusButtonStyle(compact: true))
    }
}
