import Foundation

/// A visual attention scale for the measured battery temperature, shared by E3/A.
/// 45/50/55°C are VenusBar presentation choices, not published BMS warning,
/// charging/discharging limits, or shutdown thresholds. Never use this for control.
enum VenusTemperature {
    enum Level: String, Sendable { case unknown, normal, warm, hot, high }
    struct Result: Equatable, Sendable {
        let level: Level
        let progress: Double?
        let title: String
        let explanation: String
        let value: Double?
        let isFresh: Bool
    }

    // Manufacturer-authored, official-host sources. The E3 brochure p2 explicitly
    // labels -20...55°C as AMBIENT. Neither this range nor storage limits define
    // internal Bat.GetStatus.bat_temp warning thresholds. No A threshold is inferred.
    static let primarySourceURLs = [
        "https://static-eu.marstekenergy.com/ems/resource/agreement/MarstekDeviceOpenApi.pdf",
        "https://cdn.shopify.com/s/files/1/0746/1575/0952/files/MARSTEK_VENUS_E3.0_Brochure_EU_EN.pdf?v=1776130081",
        "https://cdn.shopify.com/s/files/1/0746/1575/0952/files/43A212010001_BIE5_01_140mmx210mm_120g_80g_VENUS-E_3.0_2025.05.08.29_compressed.pdf?v=1758512012",
        "https://www.evebatteryusa.com/_files/ugd/abe55e_7ba2e98dd2884f8d978b861be2b471e2.pdf"
    ]

    // Chemistry context only. No verified evidence identifies LF280K as a Marstek cell.
    static let chemistryReferenceExplanation = "Для прикладу LFP-комірки EVE LF280K виробник вказує заряджання 0–55 °C і розряджання −20–55 °C. Модель комірок Marstek не встановлена; ці межі не можна переносити на вашу станцію."
    private static let scaleExplanation = "Кільце: візуальна шкала 0–60 °C. Пороги уваги VenusBar 45/50/55 °C — не пороги BMS і не гарантія безпечного заряджання. Специфікація E3 з межею 55 °C описує довкілля, а не цей датчик. " + chemistryReferenceExplanation

    static func evaluate(value: Double?, fresh: Bool) -> Result {
        // These are the existing report's numeric sanity bounds, not safe-use limits.
        guard let value, value.isFinite, (-273.15...150).contains(value) else {
            return Result(level: .unknown, progress: nil, title: "Немає показу температури",
                          explanation: "Коректний показ температури акумулятора ще не отримано. " + scaleExplanation,
                          value: nil, isFresh: false)
        }
        let progress = min(1, max(0, value / 60))
        guard fresh else {
            return Result(level: .unknown, progress: progress, title: "Останній показ",
                          explanation: "Показ збережений; поточна температура невідома. Сіре кільце зберігає останнє значення без підтвердження його актуальності. " + scaleExplanation,
                          value: value, isFresh: false)
        }
        let level: Level
        let title: String
        if value >= 55 { level = .high; title = "Висока температура" }
        else if value >= 50 { level = .hot; title = "Помітне нагрівання" }
        else if value >= 45 { level = .warm; title = "Тепліша батарея" }
        else { level = .normal; title = "Температура акумулятора" }
        return Result(level: level, progress: progress, title: title,
                      explanation: "Температура акумулятора за Bat.GetStatus.bat_temp; це не температура повітря. " + scaleExplanation,
                      value: value, isFresh: true)
    }

    /// Pure boundary checks. No API requests, persisted settings, or physical commands.
    static func selfCheck() throws {
        func check(_ condition: Bool) throws {
            if !condition { throw VenusStoreError.message("Temperature attention self-check failed") }
        }
        let cases: [(Double, Level)] = [(44.9, .normal), (45, .warm), (49.9, .warm),
                                       (50, .hot), (54.9, .hot), (55, .high)]
        for (value, level) in cases {
            let result = evaluate(value: value, fresh: true)
            try check(result.level == level && result.isFresh && result.value == value)
            try check(result.progress == value / 60)
        }
        for value: Double? in [nil, .nan, .infinity, -.infinity, -273.16, 150.01] {
            let result = evaluate(value: value, fresh: true)
            try check(result.level == .unknown && !result.isFresh && result.value == nil && result.progress == nil)
        }
        for value in [20.0, 55.0, 75.0] {
            let result = evaluate(value: value, fresh: false)
            try check(result.level == .unknown && !result.isFresh && result.title == "Останній показ" && result.value == value)
            try check(result.progress == min(1, value / 60))
        }
        try check(evaluate(value: -10, fresh: true).progress == 0)
        try check(evaluate(value: 60, fresh: true).progress == 1)
        try check(evaluate(value: 150, fresh: true).progress == 1)
        try check(evaluate(value: 0, fresh: true).level == .normal) // Means below app attention, never a charging permission.
    }
}
