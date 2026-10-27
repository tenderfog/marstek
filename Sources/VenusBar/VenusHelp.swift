import SwiftUI

struct VenusHelp: View {
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Button(action: onBack) { Label("Назад", systemImage: "chevron.left") }
                    .buttonStyle(VenusButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Text("Як користуватися VenusBar")
                    .font(.system(size: 18, weight: .semibold))
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    section("Завжди в рядку меню", symbol: "bolt.fill",
                            text: "Знайди блискавку в рядку меню macOS. Поруч з’являється заряд станції, коли його отримано. Наведи курсор для короткого огляду; натисни, щоб відкрити головну панель.")
                    flowLegend
                    section("Підключення та оновлення", symbol: "gearshape",
                            text: "Натисни шестерню й обери «Шукати автоматично». Або введи IP-адресу та UDP-порт вручну; типовий порт — 30000. На станції має бути ввімкнений Local API, а Mac має бути в тій самій мережі.")
                    section("Фонове читання", symbol: "arrow.clockwise",
                            text: "У налаштуваннях обери інтервал 10, 30 або 60 секунд і, за потреби, запуск разом із macOS. «Пауза» зупиняє лише читання. «Продовжити» відновлює його; «Оновити показники» запитує нову відповідь одразу.")
                    section("Керування станцією", symbol: "slider.horizontal.3",
                            text: "Кнопка «Керування» відкриває режими Auto, AI, Manual і UPS та доступні для моделі налаштування. Обери нове значення й натисни «Застосувати». Підтвердження API означає, що команду прийнято; перевір результат на станції. Скидання має окреме підтвердження.")
                    section("Як читати останні покази", symbol: "clock",
                            text: "При втраті зв’язку або паузі останні покази залишаються приглушеними. Коротка смуга в головній панелі означає, що показник ще не отримано. Наведи курсор на значення, щоб побачити час відповіді API; це не час фізичного виміру.")
                }.padding(.vertical, 2).padding(.trailing, 5)
            }.scrollIndicators(.automatic)
        }
        .padding(24).frame(width: 520, height: 430)
        .foregroundStyle(.white).background(.clear).preferredColorScheme(.dark)
    }

    private var flowLegend: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Колір і значок стану").font(.system(size: 14, weight: .semibold))
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    flow("Розряджається", symbol: "arrow.up.right", color: Color(red: 0.36, green: 0.85, blue: 0.56))
                    flow("Очікування", symbol: "pause", color: .white.opacity(0.8))
                    flow("Від мережі", symbol: "powerplug.fill", color: .gray)
                }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 12) {
                    flow("Заряджається", symbol: "arrow.down.left", color: Color(red: 1, green: 0.49, blue: 0.40))
                    flow("Покази уточнюються", symbol: "waveform", color: .white.opacity(0.45))
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("«Розряджається» — станція віддає енергію. «Очікування» означає відсутність помітного потоку, зокрема при повній батареї; це не підтвердження живлення від мережі. За потреби індикацію можна уточнити в налаштуваннях → «Уточнення показників», не змінюючи режим станції.")
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
    let model: VenusModel
    private let title = "Як увімкнути Local API ↗"

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
