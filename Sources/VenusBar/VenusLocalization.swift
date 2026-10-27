import Foundation
import Combine

enum VenusLanguage: String, CaseIterable, Identifiable {
    case uk, en, surzhyk
    var id: String { rawValue }
    var name: String { switch self { case .uk: return "Українська"; case .en: return "English"; case .surzhyk: return "Суржик" } }
    var locale: Locale { Locale(identifier: self == .en ? "en_GB" : "uk_UA") }
    static let preferenceKey = "interfaceLanguage"
    private static let checking = CommandLine.arguments.contains("--self-check")
    static var current: Self {
        if checking { return .uk }
        return UserDefaults.standard.string(forKey: preferenceKey).flatMap(Self.init(rawValue:)) ?? .uk
    }
}

/// Both copies stay beside their use, including interpolated values and accessibility text.
func VL(_ ukrainian: String, _ english: String, language: VenusLanguage = .current) -> String {
    switch language {
    case .uk: return ukrainian
    case .en: return english
    case .surzhyk: return VenusSurzhyk.copy[ukrainian] ?? ukrainian
    }
}

private enum VenusSurzhyk {
    // A casual UI voice. Numeric readings, addresses and safety explanations stay unchanged.
    static let copy = [
        "Налаштування": "Настройки", "Інші параметри": "Інші настройки",
        "Керування станцією": "Керуєм станцією", "Про застосунок": "Про апку",
        "Мова застосунку": "Мова апки", "Далі": "Дальше",
        "Підключити": "Підключить", "Підключити станцію": "Підключить станцію",
        "Заряджається": "Заряжається", "Розряджається": "Розряжається",
        "Батарея повна": "Батарейка повна", "Очікування": "Стоїть чекає",
        "Застосувати": "Примінить", "Увімкнути": "Включить", "Вимкнути": "Виключить",
        "Шукати автоматично": "Шукати самому", "Спробувати ще раз": "Попробувать ще раз",
        "Налаштувати пізніше": "Настроїть потом", "Пропустити": "Пропустить",
        "Вийти з VenusBar": "Закрить VenusBar", "Пошук станції": "Шукаєм станцію",
        "Графіки відключень": "Графік світла", "Параметри станції": "Настройки станції"
    ]
}

final class VenusLocalization: ObservableObject {
    static let shared = VenusLocalization()
    @Published private(set) var language: VenusLanguage
    @Published private(set) var hasChosen: Bool

    private init() {
        language = .current
        hasChosen = UserDefaults.standard.string(forKey: VenusLanguage.preferenceKey).flatMap(VenusLanguage.init(rawValue:)) != nil
    }

    @MainActor func choose(_ value: VenusLanguage) {
        UserDefaults.standard.set(value.rawValue, forKey: VenusLanguage.preferenceKey)
        language = value
        hasChosen = true
    }

    static func selfCheck() throws {
        guard VL("Зроблено в Україні", "Made in Ukraine", language: .uk) == "Зроблено в Україні",
              VL("Зроблено в Україні", "Made in Ukraine", language: .en) == "Made in Ukraine",
              VL("Налаштування", "Settings", language: .surzhyk) == "Настройки",
              VL("Світло до 18:30", "Power until 18:30", language: .surzhyk) == "Світло до 18:30",
              VenusLanguage(rawValue: "uk") == .uk, VenusLanguage(rawValue: "en") == .en,
              VenusLanguage(rawValue: "de") == nil,
              VenusLanguage.uk.locale.identifier == "uk_UA", VenusLanguage.en.locale.identifier == "en_GB" else {
            throw VenusStoreError.message("Language selection self-check failed")
        }
    }
}
