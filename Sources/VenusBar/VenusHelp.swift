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
    private var title: String { VL("Як увімкнути Local API ↗", "Enable Local API ↗") }

    var body: some View {
        Group {
            if model == .unknown {
                Menu(title) {
                    Link("Venus E 3.0", destination: url(for: .venusE))
                    Link("Venus A", destination: url(for: .venusA))
                }.menuStyle(.borderlessButton).fixedSize()
            } else {
                Link(title, destination: url(for: model))
            }
        }.font(.system(size: 12)).foregroundStyle(.white.opacity(0.65))
    }

    private func url(for model: VenusModel) -> URL {
        URL(string: "https://static-eu.marstekenergy.com/ems/resource/agreement/app/venus/\(model == .venusA ? "Venus_A" : "Venus_E3").pdf")!
    }
}
