import Combine
import Foundation

enum VenusOutagesError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let message) = self { return message }; return nil }
}

private enum VenusOutageValidation {
    static func id(_ decoder: Decoder) throws -> String {
        let container = try decoder.singleValueContainer()
        let value: String
        if let number = try? container.decode(Int.self) { value = String(number) }
        else { value = try container.decode(String.self) }
        guard validID(value) else { throw VenusOutagesError.message("YASNO повернув некоректний ідентифікатор адреси.") }
        return value
    }

    static func validID(_ value: String) -> Bool {
        value.range(of: #"\A[1-9][0-9]{0,18}\z"#, options: .regularExpression) != nil
    }

    static func name(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 256,
              !trimmed.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw VenusOutagesError.message("YASNO повернув некоректну назву адреси.")
        }
        return trimmed
    }

    static func unique<T: Identifiable>(_ values: [T]) throws -> [T] where T.ID == String {
        guard values.count <= 10_000, Set(values.map(\.id)).count == values.count else {
            throw VenusOutagesError.message("Довідник YASNO містить неоднозначні адреси.")
        }
        return Array(values.prefix(80))
    }
}

struct VenusOutageDSO: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    private enum CodingKeys: String, CodingKey { case id, name }
    init(id: String, name: String) { self.id = id; self.name = name }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try VenusOutageValidation.id(container.superDecoder(forKey: .id))
        name = try VenusOutageValidation.name(container.decode(String.self, forKey: .name))
    }
}

struct VenusOutageRegion: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let hasCities: Bool
    let dsos: [VenusOutageDSO]
    private enum CodingKeys: String, CodingKey { case id, name = "value", hasCities, dsos }
    init(id: String, name: String, hasCities: Bool, dsos: [VenusOutageDSO]) {
        self.id = id; self.name = name; self.hasCities = hasCities; self.dsos = dsos
    }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try VenusOutageValidation.id(container.superDecoder(forKey: .id))
        name = try VenusOutageValidation.name(container.decode(String.self, forKey: .name))
        hasCities = try container.decode(Bool.self, forKey: .hasCities)
        dsos = try VenusOutageValidation.unique(container.decode([VenusOutageDSO].self, forKey: .dsos))
        guard !dsos.isEmpty else { throw VenusOutagesError.message("Для цього регіону YASNO не вказав оператора.") }
    }
}

struct VenusOutageAddressItem: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    private enum CodingKeys: String, CodingKey { case id, name = "value" }
    init(id: String, name: String) { self.id = id; self.name = name }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try VenusOutageValidation.id(container.superDecoder(forKey: .id))
        if let text = try? container.decode(String.self, forKey: .name) {
            name = try VenusOutageValidation.name(text)
        } else {
            name = try VenusOutageValidation.name(String(container.decode(Int.self, forKey: .name)))
        }
    }
}

struct VenusOutageAddressQuery: Equatable, Sendable {
    let streetQuery: String
    let houseHint: String?
    let queries: [String]

    static func parse(_ raw: String) -> Self {
        guard raw.count <= 120 else { return Self(streetQuery: "", houseHint: nil, queries: []) }
        func compact(_ value: String) -> String {
            value.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;")))
        }
        var text = compact(raw.precomposedStringWithCompatibilityMapping)
        // Apartment numbers are neither needed nor sent to the public building lookup.
        text = text.replacingOccurrences(of: #"(?i)(?:[,;]\s*|\s+)(?:кв(?:артира)?|apt|apartment)\.?\s*\d.*\z"#,
                                         with: "", options: .regularExpression)
        var house: String?
        let pattern = #"\A(.+?)[\s,;]*(?:(?:буд(?:инок)?|дім)\.?\s*)?([0-9]{1,5}(?:\s*[-/]\s*[0-9\p{L}]{1,5})?(?:\s*[\p{L}])?)\s*\z"#
        if let expression = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
           let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let streetRange = Range(match.range(at: 1), in: text), let houseRange = Range(match.range(at: 2), in: text) {
            let street = compact(String(text[streetRange]))
            if street.unicodeScalars.contains(where: CharacterSet.letters.contains) {
                house = String(text[houseRange]).replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
                text = street
            }
        }
        let types = #"(?:вул(?:иця)?|бул(?:ьвар|ьв)?|бульв|просп(?:ект)?|пр-т|пров(?:улок)?|пл(?:оща)?|наб(?:ережна)?|шосе|узвіз|алея|тупик)"#
        text = text.replacingOccurrences(of: #"(?i)\A"# + types + #"(?:\s+|[.,]\s*)"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?i)(?:\s+|,\s*)"# + types + #"\.?\z"#, with: "", options: .regularExpression)
        text = compact(text)
        guard text.count >= 2, !text.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            return Self(streetQuery: text, houseHint: house, queries: [])
        }
        // Official names may put the surname before the given name. A bounded
        // single-word fallback also avoids requiring users to know that order.
        let words = text.components(separatedBy: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ",.")))
            .filter { $0.count >= 3 && $0.unicodeScalars.contains(where: CharacterSet.letters.contains) }
            .enumerated().sorted { $0.element.count == $1.element.count ? $0.offset < $1.offset : $0.element.count > $1.element.count }
            .map(\.element)
        var queries: [String] = []
        for query in [text] + words where !queries.contains(where: { $0.caseInsensitiveCompare(query) == .orderedSame }) {
            queries.append(query)
            if queries.count == 3 { break }
        }
        return Self(streetQuery: text, houseHint: house, queries: queries)
    }

    static func selfCheck() throws {
        func check(_ condition: Bool, _ message: String) throws {
            guard condition else { throw VenusOutagesError.message("Адреса: \(message)") }
        }
        for input in ["Тестова12", "Тестова 12", "вул. Тестова, буд. 12", "Тестова вулиця 12"] {
            let result = parse(input)
            try check(result.streetQuery == "Тестова" && result.houseHint == "12" && result.queries == ["Тестова"], "вулиця й будинок окремо")
        }
        let boulevard = parse("бул. Тараса Шевченка, 24-Б")
        try check(boulevard.streetQuery == "Тараса Шевченка" && boulevard.houseHint == "24-Б", "тип вулиці й літера будинку")
        try check(boulevard.queries == ["Тараса Шевченка", "Шевченка", "Тараса"], "порядок імені в довіднику")
        try check(parse("Тестова 12/2").houseHint == "12/2", "корпус через дріб")
        try check(parse("вул. 8 Березня, 12").streetQuery == "8 Березня", "цифра в назві вулиці")
        try check(parse("  Тестова\n  12, кв. 8 ").houseHint == "12" && !parse("Тестова 12, кв. 8").queries.joined().contains("8"), "квартира не надсилається")
        try check(parse("Бульварна 12").streetQuery == "Бульварна", "частина назви не є типом вулиці")
        try check(parse("Тестова").houseHint == nil && parse("Тестова").queries == ["Тестова"], "пошук лише вулиці")
        try check(parse(String(repeating: "а", count: 121)).queries.isEmpty, "обмеження довжини")
    }
}

struct VenusOutageSelection: Codable, Equatable, Sendable {
    let region: VenusOutageRegion
    let dso: VenusOutageDSO
    let city: VenusOutageAddressItem?
    let street: VenusOutageAddressItem
    let house: VenusOutageAddressItem
    let group: String

    var addressLabel: String {
        ([city?.name ?? region.name, street.name, house.name]).joined(separator: ", ")
    }
    fileprivate var cacheKey: String { "\(region.id)/\(dso.id)/\(group)" }
    fileprivate var isValid: Bool {
        VenusOutageValidation.validID(region.id) && VenusOutageValidation.validID(dso.id)
        && VenusOutageValidation.validID(street.id) && VenusOutageValidation.validID(house.id)
        && region.dsos.contains(where: { $0.id == dso.id })
        && (!region.hasCities || city != nil)
        && (city.map { VenusOutageValidation.validID($0.id) } ?? true)
        && VenusOutagesReport.validGroup(group)
    }
}

enum VenusOutagePlanState: String, Codable, Sendable {
    case noOutagePlanned, outagePlanned, unknown, emergency, stale
    var label: String {
        switch self {
        case .noOutagePlanned: return "Відключення не заплановано"
        case .outagePlanned: return "Планове відключення"
        case .unknown: return "Графік ще невідомий"
        case .emergency: return "Аварійні відключення"
        case .stale: return "Збережений графік: потрібне оновлення"
        }
    }
}

struct VenusOutageInterval: Identifiable, Equatable, Sendable {
    let start: Int
    let end: Int
    let state: VenusOutagePlanState
    var id: String { "\(start)-\(end)-\(state.rawValue)" }
    var timeRange: String { "\(Self.time(start))–\(Self.time(end))" }
    static func time(_ minute: Int) -> String { String(format: "%02d:%02d", minute / 60, minute % 60) }
}

struct VenusOutageSlot: Codable, Sendable {
    let start: Int
    let end: Int
    let type: String
}

struct VenusOutageDay: Codable, Sendable {
    let slots: [VenusOutageSlot]?
    let date: String?
    let status: String?
    func isFor(_ day: Date) -> Bool {
        guard let value = date.flatMap(VenusOutagesReport.parseTimestamp) else { return false }
        return VenusOutagesReport.kyivCalendar.isDate(value, inSameDayAs: day)
    }
}

struct VenusOutageGroupSchedule: Codable, Sendable {
    let today: VenusOutageDay?
    let tomorrow: VenusOutageDay?
    let updatedOn: String?
}

struct VenusOutagesReport: Codable, Sendable {
    let schedules: [String: VenusOutageGroupSchedule]
    let fetchedAt: Date
    var groups: [String] { schedules.keys.sorted { $0.compare($1, options: .numeric) == .orderedAscending } }

    static var kyivCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        // Both IANA aliases are in the macOS timezone database; a fixed UTC fallback never uses the user's locale.
        calendar.timeZone = TimeZone(identifier: "Europe/Kyiv") ?? TimeZone(identifier: "Europe/Kiev") ?? TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func isFresh(at now: Date) -> Bool { (0...1800).contains(now.timeIntervalSince(fetchedAt)) }
    static func validGroup(_ group: String) -> Bool {
        group.count <= 20 && group.range(of: #"\A[0-9]+(?:\.[0-9]+)?\z"#, options: .regularExpression) != nil
    }

    static func parseTimestamp(_ value: String) -> Date? {
        let pattern = #"\A[0-9]{4}-(?:0[1-9]|1[0-2])-(?:0[1-9]|[12][0-9]|3[01])T(?:[01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9](?:\.[0-9]+)?(?:Z|[+-](?:[01][0-9]|2[0-3]):[0-5][0-9])\z"#
        guard value.range(of: pattern, options: .regularExpression) != nil else { return nil }
        let parts = value.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, parts[0] > 0 else { return nil }
        let leap = parts[0].isMultiple(of: 4) && (!parts[0].isMultiple(of: 100) || parts[0].isMultiple(of: 400))
        let days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        guard parts[2] <= days[parts[1] - 1] else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = value.contains(".") ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
        return formatter.date(from: value)
    }

    static func decode(_ data: Data, fetchedAt: Date = Date()) throws -> Self {
        guard data.count <= VenusOutageHTTP.maximumBytes else { throw VenusOutagesError.message("Відповідь YASNO завелика.") }
        let schedules = try JSONDecoder().decode([String: VenusOutageGroupSchedule].self, from: data)
        guard !schedules.isEmpty, schedules.count <= 500 else { throw VenusOutagesError.message("YASNO ще не опублікував графіки.") }
        for (group, schedule) in schedules {
            guard validGroup(group) else { throw VenusOutagesError.message("Невідомий формат груп YASNO.") }
            if let text = schedule.updatedOn {
                guard let date = parseTimestamp(text), date <= fetchedAt else {
                    throw VenusOutagesError.message("Некоректний час оновлення графіка YASNO.")
                }
            }
            let days = [schedule.today, schedule.tomorrow].compactMap { $0 }
            for day in days {
                if let date = day.date, parseTimestamp(date) == nil { throw VenusOutagesError.message("Некоректна дата графіка YASNO.") }
                let slots = day.slots ?? []
                guard slots.count <= 1440 else { throw VenusOutagesError.message("Забагато інтервалів YASNO.") }
                var end = 0
                for slot in slots.sorted(by: { $0.start < $1.start }) {
                    guard slot.start >= end, slot.start < slot.end, slot.end <= 1440 else {
                        throw VenusOutagesError.message("Некоректні або накладені інтервали YASNO.")
                    }
                    end = slot.end
                }
            }
            if let first = schedule.today?.date.flatMap(parseTimestamp),
               let second = schedule.tomorrow?.date.flatMap(parseTimestamp), kyivCalendar.isDate(first, inSameDayAs: second) {
                throw VenusOutagesError.message("YASNO повернув неоднозначну дату графіка.")
            }
        }
        return Self(schedules: schedules, fetchedAt: fetchedAt)
    }

    func day(group: String, at now: Date) -> VenusOutageDay? {
        guard let schedule = schedules[group] else { return nil }
        return [schedule.today, schedule.tomorrow].compactMap { $0 }.first { $0.isFor(now) }
    }

    func intervals(group: String, at now: Date, serviceHealthy: Bool = true) -> [VenusOutageInterval] {
        guard let day = day(group: group, at: now) else { return [.init(start: 0, end: 1440, state: .unknown)] }
        guard isFresh(at: now), serviceHealthy else { return [.init(start: 0, end: 1440, state: .stale)] }
        if day.status == "EmergencyShutdowns" { return [.init(start: 0, end: 1440, state: .emergency)] }
        // Even an empty NoOutages response is not a measured or complete timeline.
        guard ["ScheduleApplies", "NoOutages"].contains(day.status ?? ""), let slots = day.slots, !slots.isEmpty else {
            return [.init(start: 0, end: 1440, state: .unknown)]
        }
        var result: [VenusOutageInterval] = []
        var end = 0
        for slot in slots.sorted(by: { $0.start < $1.start }) {
            if slot.start > end { result.append(.init(start: end, end: slot.start, state: .unknown)) }
            let state: VenusOutagePlanState = slot.type == "Definite" ? .outagePlanned : slot.type == "NotPlanned" ? .noOutagePlanned : .unknown
            result.append(.init(start: slot.start, end: slot.end, state: state))
            end = slot.end
        }
        if end < 1440 { result.append(.init(start: end, end: 1440, state: .unknown)) }
        return result
    }

    static func minute(at now: Date) -> Int {
        let parts = kyivCalendar.dateComponents([.hour, .minute], from: now)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    static func date(on day: Date, minute: Int) -> Date? {
        guard (0...1440).contains(minute) else { return nil }
        let calendar = kyivCalendar
        let midnight = calendar.startOfDay(for: day)
        if minute == 1440 { return calendar.date(byAdding: .day, value: 1, to: midnight) }
        // Wall-clock components, not seconds since midnight: Kyiv's DST days need not have 24 hours.
        let first = calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: midnight,
                                  matchingPolicy: .strict, repeatedTimePolicy: .first, direction: .forward)
        let last = calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: midnight,
                                 matchingPolicy: .strict, repeatedTimePolicy: .last, direction: .forward)
        // The provider supplies no DST-fold discriminator. Ambiguous/missing wall times cannot support a precise forecast.
        guard let first, first == last, calendar.isDate(first, inSameDayAs: day),
              calendar.component(.hour, from: first) == minute / 60,
              calendar.component(.minute, from: first) == minute % 60 else { return nil }
        return first
    }

    func currentOrNextOutage(group: String, at now: Date, serviceHealthy: Bool = true) -> VenusOutageInterval? {
        guard day(group: group, at: now)?.status == "ScheduleApplies" else { return nil }
        let timeline = intervals(group: group, at: now, serviceHealthy: serviceHealthy)
        guard !timeline.contains(where: { [.unknown, .stale, .emergency].contains($0.state) }) else { return nil }
        return timeline.first { $0.state == .outagePlanned && $0.end > Self.minute(at: now) }
    }
}

private enum VenusOutageGroupResponse: Decodable {
    case groups([String])
    private enum CodingKeys: String, CodingKey { case group, subgroup }
    private static func scalar(_ decoder: Decoder) throws -> String {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int.self), value >= 0 { return String(value) }
        let value = try container.decode(String.self)
        guard VenusOutagesReport.validGroup(value) else { throw VenusOutagesError.message("Невідома група YASNO.") }
        return value
    }
    init(from decoder: Decoder) throws {
        if var list = try? decoder.unkeyedContainer() {
            var groups: [String] = []
            while !list.isAtEnd {
                guard groups.count < 80 else { throw VenusOutagesError.message("Забагато груп для адреси.") }
                let item = try list.decode(Self.self)
                if case .groups(let values) = item { groups.append(contentsOf: values) }
                guard groups.count <= 80 else { throw VenusOutagesError.message("Забагато груп для адреси.") }
            }
            self = .groups(Array(Set(groups)).sorted { $0.compare($1, options: .numeric) == .orderedAscending })
        } else if let object = try? decoder.container(keyedBy: CodingKeys.self) {
            let group = try Self.scalar(object.superDecoder(forKey: .group))
            let subgroup = try object.decodeIfPresent(Int.self, forKey: .subgroup) ?? 0
            guard !group.contains("."), (0...9999).contains(subgroup) else { throw VenusOutagesError.message("Неоднозначна група YASNO.") }
            self = .groups([subgroup == 0 ? group : "\(group).\(subgroup)"])
        } else {
            self = .groups([try Self.scalar(decoder)])
        }
    }
    var values: [String] { if case .groups(let groups) = self { return groups }; return [] }
}

private final class VenusOutageNoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

private enum VenusOutageHTTP {
    static let maximumBytes = 1_048_576
    static let root = "https://app.yasno.ua/api/blackout-service/public/shutdowns/"
    static func url(_ path: String, query: [URLQueryItem] = []) throws -> URL {
        guard var components = URLComponents(string: root + path) else { throw VenusOutagesError.message("Некоректний запит YASNO.") }
        components.queryItems = query.isEmpty ? nil : query
        // URLQueryItem leaves '+' literal; ordinary query parsers interpret it as a space.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let url = components.url, url.scheme == "https", url.host == "app.yasno.ua" else {
            throw VenusOutagesError.message("Некоректний запит YASNO.")
        }
        return url
    }
    static func get(_ path: String, query: [URLQueryItem] = []) async throws -> Data {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil; config.httpCookieStorage = nil; config.urlCredentialStorage = nil
        config.httpShouldSetCookies = false; config.timeoutIntervalForRequest = 20; config.timeoutIntervalForResource = 25
        let session = URLSession(configuration: config, delegate: VenusOutageNoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: try url(path, query: query), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              response.expectedContentLength <= Int64(maximumBytes),
              response.mimeType?.lowercased().contains("json") == true else {
            throw VenusOutagesError.message("YASNO тимчасово недоступний або вимагає перевірку в браузері.")
        }
        var data = Data()
        for try await byte in bytes {
            if data.count.isMultiple(of: 4096) { try Task.checkCancellation() }
            guard data.count < maximumBytes else { throw VenusOutagesError.message("Відповідь YASNO завелика.") }
            data.append(byte)
        }
        try Task.checkCancellation()
        return data
    }
}

@MainActor
final class VenusOutagesStore: ObservableObject {
    @Published private(set) var regions: [VenusOutageRegion] = []
    @Published private(set) var dsos: [VenusOutageDSO] = []
    @Published private(set) var cities: [VenusOutageAddressItem] = []
    @Published private(set) var streets: [VenusOutageAddressItem] = []
    @Published private(set) var houses: [VenusOutageAddressItem] = []
    @Published private(set) var groups: [String] = []
    @Published private(set) var selectedRegion: VenusOutageRegion?
    @Published private(set) var selectedDSO: VenusOutageDSO?
    @Published private(set) var selectedCity: VenusOutageAddressItem?
    @Published private(set) var selectedStreet: VenusOutageAddressItem?
    @Published private(set) var selectedHouse: VenusOutageAddressItem?
    @Published private(set) var houseHint: String?
    @Published private(set) var selection: VenusOutageSelection?
    @Published private(set) var report: VenusOutagesReport?
    @Published private(set) var error: String?
    @Published private(set) var isLoading = false
    @Published private(set) var isSearching = false
    @Published private var usingSavedReport = false
    @Published private var refreshFailed = false

    private var searchTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var searchGeneration = 0
    private var refreshGeneration = 0
    private let fileURL: URL?

    private struct Saved: Codable {
        let schemaVersion: Int
        let selection: VenusOutageSelection
        let report: VenusOutagesReport?
    }

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("VenusBar", isDirectory: true)
        fileURL = base?.appendingPathComponent("outages.json")
        if let fileURL, FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
                guard (attributes[.size] as? NSNumber)?.intValue ?? Int.max <= VenusOutageHTTP.maximumBytes else {
                    throw VenusOutagesError.message("Збережений графік завеликий.")
                }
                let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
                let saved = try decoder.decode(Saved.self, from: Data(contentsOf: fileURL))
                guard saved.schemaVersion == 1, saved.selection.isValid else { throw VenusOutagesError.message("Некоректні збережені налаштування YASNO.") }
                selection = saved.selection
                selectedRegion = saved.selection.region; selectedDSO = saved.selection.dso; selectedCity = saved.selection.city
                selectedStreet = saved.selection.street; selectedHouse = saved.selection.house
                dsos = saved.selection.region.dsos; groups = [saved.selection.group]
                if let cached = saved.report, cached.fetchedAt <= Date() {
                    let data = try JSONEncoder().encode(cached.schedules)
                    report = try VenusOutagesReport.decode(data, fetchedAt: cached.fetchedAt)
                    usingSavedReport = true
                }
            } catch { self.error = "Не вдалося прочитати локальні налаштування YASNO. Обери адресу заново." }
        }
        if selection != nil { refresh(); startPolling() }
    }

    var fetchedAt: Date? { report?.fetchedAt }
    var updatedAt: Date? { selection.flatMap { report?.schedules[$0.group]?.updatedOn }.flatMap(VenusOutagesReport.parseTimestamp) }
    var isCached: Bool { report != nil && (usingSavedReport || refreshFailed || !(report?.isFresh(at: Date()) ?? false)) }
    var sourceURL: URL { URL(string: "https://static.yasno.ua/kyiv/outages")! }
    var todaySlots: [VenusOutageInterval] {
        guard let selection, let report else { return [.init(start: 0, end: 1440, state: .unknown)] }
        return report.intervals(group: selection.group, at: Date(), serviceHealthy: !refreshFailed)
    }
    var currentPlanState: VenusOutagePlanState {
        let minute = VenusOutagesReport.minute(at: Date())
        return todaySlots.first { $0.start <= minute && minute < $0.end }?.state ?? .unknown
    }
    var statusLabel: String { selection == nil ? "Обери адресу для графіка" : currentPlanState.label }
    func nextIntervals(limit: Int = 3) -> [VenusOutageInterval] {
        let minute = VenusOutagesReport.minute(at: Date())
        return Array(todaySlots.filter { $0.end > minute }.prefix(max(0, min(limit, 20))))
    }
    var currentOrNextOutageStart: Date? { currentOrNextOutageDate(end: false) }
    var currentOrNextOutageEnd: Date? { currentOrNextOutageDate(end: true) }
    private func currentOrNextOutageDate(end: Bool) -> Date? {
        let now = Date()
        guard let selection, let interval = report?.currentOrNextOutage(group: selection.group, at: now, serviceHealthy: !refreshFailed) else { return nil }
        return VenusOutagesReport.date(on: now, minute: end ? interval.end : interval.start)
    }

    func loadRegions() {
        guard regions.isEmpty else { return }
        search(debounce: false) { [weak self] in
            let data = try await VenusOutageHTTP.get("addresses/v2/regions")
            let result = try VenusOutageValidation.unique(JSONDecoder().decode([VenusOutageRegion].self, from: data))
            guard !result.isEmpty else { throw VenusOutagesError.message("YASNO поки не надав підтримуваних регіонів.") }
            return { [weak self] in
                self?.regions = result
                if let selectedID = self?.selectedRegion?.id, let region = result.first(where: { $0.id == selectedID }) {
                    self?.selectedRegion = region; self?.dsos = region.dsos
                }
            }
        }
    }

    func selectRegion(_ region: VenusOutageRegion) {
        guard regions.contains(region) else { return }
        cancelSearch(); selectedRegion = region; dsos = region.dsos; selectedDSO = nil
        selectedCity = nil; selectedStreet = nil; selectedHouse = nil; houseHint = nil
        cities = []; streets = []; houses = []; groups = []
    }
    func selectDSO(_ dso: VenusOutageDSO) {
        guard dsos.contains(dso) else { return }
        cancelSearch(); selectedDSO = dso; selectedCity = nil; selectedStreet = nil; selectedHouse = nil; houseHint = nil
        cities = []; streets = []; houses = []; groups = []
    }
    func selectCity(_ item: VenusOutageAddressItem) {
        guard cities.contains(item) else { return }
        cancelSearch(); selectedCity = item; selectedStreet = nil; selectedHouse = nil; houseHint = nil
        streets = []; houses = []; groups = []
    }
    func selectStreet(_ item: VenusOutageAddressItem) {
        guard streets.contains(item) else { return }
        cancelSearch(); selectedStreet = item; selectedHouse = nil; houses = []; groups = []
        searchHouses(houseHint ?? "")
    }

    func searchCities(_ query: String) {
        cities = []; selectedCity = nil; selectedStreet = nil; selectedHouse = nil; streets = []; houses = []; groups = []; houseHint = nil
        addressSearch(endpoint: "cities", query: query, minimum: 2) { [weak self] in self?.cities = $0 }
    }
    func searchStreets(_ query: String) {
        streets = []; selectedStreet = nil; selectedHouse = nil; houses = []; groups = []
        let parsed = VenusOutageAddressQuery.parse(query)
        houseHint = parsed.houseHint
        addressSearch(endpoint: "streets", query: parsed.streetQuery, minimum: 2, alternatives: parsed.queries) { [weak self] in self?.streets = $0 }
    }
    func searchHouses(_ query: String) {
        houses = []; selectedHouse = nil; groups = []
        addressSearch(endpoint: "houses", query: query, minimum: 0) { [weak self] in self?.houses = $0 }
    }

    private func addressQuery() -> [URLQueryItem]? {
        guard let region = selectedRegion, let dso = selectedDSO,
              VenusOutageValidation.validID(region.id), VenusOutageValidation.validID(dso.id) else { return nil }
        var query = [URLQueryItem(name: "regionId", value: region.id), URLQueryItem(name: "dsoId", value: dso.id)]
        if let city = selectedCity { query.append(URLQueryItem(name: "cityId", value: city.id)) }
        return query
    }
    private func addressSearch(endpoint: String, query: String, minimum: Int, alternatives: [String]? = nil,
                               publish: @escaping @MainActor ([VenusOutageAddressItem]) -> Void) {
        cancelSearch()
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= minimum, text.count <= 120, var parameters = addressQuery() else { return }
        if endpoint != "cities", selectedRegion?.hasCities == true, selectedCity == nil { return }
        if endpoint == "cities", selectedRegion?.hasCities != true { return }
        if endpoint == "houses" {
            guard let street = selectedStreet else { return }
            parameters.append(URLQueryItem(name: "streetId", value: street.id))
        }
        search {
            for candidate in (alternatives ?? [text]).prefix(3) {
                try Task.checkCancellation()
                let data = try await VenusOutageHTTP.get("addresses/v2/" + endpoint, query: parameters + [URLQueryItem(name: "query", value: candidate)])
                let result = try VenusOutageValidation.unique(JSONDecoder().decode([VenusOutageAddressItem].self, from: data))
                if !result.isEmpty { return { publish(result) } }
            }
            return { publish([]) }
        }
    }

    func selectHouse(_ item: VenusOutageAddressItem) {
        guard houses.contains(item), let street = selectedStreet, var parameters = addressQuery() else { return }
        cancelSearch(); selectedHouse = item; groups = []
        parameters.append(URLQueryItem(name: "streetId", value: street.id))
        parameters.append(URLQueryItem(name: "houseId", value: item.id))
        search(debounce: false) { [weak self] in
            let data = try await VenusOutageHTTP.get("addresses/v2/group", query: parameters)
            let groups = try JSONDecoder().decode(VenusOutageGroupResponse.self, from: data).values
            guard !groups.isEmpty else { throw VenusOutagesError.message("Для цієї адреси YASNO не надав групу.") }
            return { [weak self] in self?.groups = groups }
        }
    }

    func selectGroup(_ group: String) {
        guard groups.contains(group), let region = selectedRegion, let dso = selectedDSO,
              let street = selectedStreet, let house = selectedHouse else { return }
        let value = VenusOutageSelection(region: region, dso: dso, city: selectedCity, street: street, house: house, group: group)
        guard value.isValid else { return }
        cancelSearch(); cancelRefresh(); selection = value; report = nil; usingSavedReport = false; refreshFailed = false; error = nil
        save(); refresh(); startPolling()
    }

    private func cancelSearch() {
        searchGeneration += 1; searchTask?.cancel(); searchTask = nil; isSearching = false
    }
    private func search(debounce: Bool = true,
                        operation: @escaping @MainActor () async throws -> (@MainActor () -> Void)) {
        cancelSearch(); let generation = searchGeneration; isSearching = true
        searchTask = Task { [weak self] in
            do {
                if debounce { try await Task.sleep(nanoseconds: 350_000_000) }
                let publish = try await operation()
                try Task.checkCancellation()
                guard let self, self.searchGeneration == generation else { return }
                publish(); self.error = nil; self.isSearching = false; self.searchTask = nil
            } catch {
                guard !Task.isCancelled, let self, self.searchGeneration == generation else { return }
                self.error = (error as? VenusOutagesError)?.errorDescription ?? "Не вдалося завантажити довідник YASNO. Спробуй пізніше."
                self.isSearching = false; self.searchTask = nil
            }
        }
    }

    func refresh() {
        guard let selection, selection.isValid, refreshTask == nil else { return }
        let generation = refreshGeneration; let key = selection.cacheKey; isLoading = true
        refreshTask = Task { [weak self] in
            do {
                let data = try await VenusOutageHTTP.get("regions/\(selection.region.id)/dsos/\(selection.dso.id)/planned-outages")
                let result = try VenusOutagesReport.decode(data, fetchedAt: Date())
                try Task.checkCancellation()
                guard let self, self.refreshGeneration == generation, self.selection?.cacheKey == key else { return }
                guard result.schedules[selection.group] != nil else { throw VenusOutagesError.message("У графіку YASNO поки немає обраної групи.") }
                self.report = result; self.error = nil; self.usingSavedReport = false; self.refreshFailed = false
                self.isLoading = false; self.refreshTask = nil; self.save()
            } catch {
                guard !Task.isCancelled, let self, self.refreshGeneration == generation, self.selection?.cacheKey == key else { return }
                self.error = "Не вдалося оновити YASNO. Збережений графік потребує перевірки."
                self.refreshFailed = true
                self.isLoading = false; self.refreshTask = nil
            }
        }
    }
    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 300_000_000_000) } catch { return }
                guard let self, self.selection != nil, !Task.isCancelled else { return }
                self.refresh()
            }
        }
    }
    private func cancelRefresh() { refreshGeneration += 1; refreshTask?.cancel(); refreshTask = nil; isLoading = false }
    func stop() { cancelSearch(); cancelRefresh(); pollTask?.cancel(); pollTask = nil }
    func clearSelection() {
        stop(); selection = nil; report = nil; usingSavedReport = false; refreshFailed = false; error = nil
        selectedRegion = nil; selectedDSO = nil; selectedCity = nil; selectedStreet = nil; selectedHouse = nil; houseHint = nil
        dsos = []; cities = []; streets = []; houses = []; groups = []
        do { if let fileURL, FileManager.default.fileExists(atPath: fileURL.path) { try FileManager.default.removeItem(at: fileURL) } }
        catch { self.error = "Не вдалося видалити локальну адресу YASNO." }
    }
    private func save() {
        guard let selection, let fileURL else { return }
        do {
            let directory = fileURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            }
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(Saved(schemaVersion: 1, selection: selection, report: report))
            guard data.count <= VenusOutageHTTP.maximumBytes else { throw VenusOutagesError.message("Збережений графік завеликий.") }
            // A private staging file is atomically renamed; no transient world-readable address file.
            let temporary = directory.appendingPathComponent(".outages-\(UUID().uuidString).json")
            guard FileManager.default.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
                throw VenusOutagesError.message("Не вдалося зберегти адресу локально.")
            }
            defer { try? FileManager.default.removeItem(at: temporary) }
            if FileManager.default.fileExists(atPath: fileURL.path) {
                _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: temporary, options: .usingNewMetadataOnly)
            } else { try FileManager.default.moveItem(at: temporary, to: fileURL) }
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch { self.error = "Не вдалося зберегти адресу та графік локально." }
    }
}

extension VenusOutagesReport {
    /// Pure protocol/projection checks: no files, requests, saved address, or station actions.
    static func selfCheck() throws {
        try VenusOutageAddressQuery.selfCheck()
        func check(_ result: @autoclosure () -> Bool, _ message: String) throws {
            guard result() else { throw VenusOutagesError.message("Outages self-check: \(message)") }
        }
        func rejects(_ operation: () throws -> Void, _ message: String) throws {
            do { try operation() } catch { return }
            throw VenusOutagesError.message("Outages self-check accepted \(message)")
        }
        let now = parseTimestamp("2026-10-27T08:00:00Z")!
        let fixture = #"{"17.2":{"today":{"slots":[{"start":0,"end":600,"type":"NotPlanned"},{"start":600,"end":750,"type":"Definite"},{"start":750,"end":1440,"type":"NotPlanned"}],"date":"2026-10-27T00:00:00+02:00","status":"ScheduleApplies"},"tomorrow":{"slots":[],"date":"2026-10-28T00:00:00+02:00","status":"WaitingForSchedule"},"updatedOn":"2026-10-27T07:30:00Z"}}"#
        let report = try decode(Data(fixture.utf8), fetchedAt: now)
        let slots = report.intervals(group: "17.2", at: now)
        try check(slots.count == 3 && slots[1].timeRange == "10:00–12:30", "half-hour boundary")
        try check(slots[2].timeRange == "12:30–24:00", "24:00 end")
        try check(report.currentOrNextOutage(group: "17.2", at: now)?.start == 600, "current planned outage")
        try check(report.isFresh(at: now.addingTimeInterval(1800)), "fresh boundary")
        try check(!report.isFresh(at: now.addingTimeInterval(1800.001)), "old cache")
        try check(!report.isFresh(at: now.addingTimeInterval(-1)), "future cache")
        try check(report.intervals(group: "17.2", at: now, serviceHealthy: false).first?.state == .stale, "fetch failure cannot be green")
        try check(report.currentOrNextOutage(group: "17.2", at: now, serviceHealthy: false) == nil, "failed source forecast")
        for invalid in ["{}", fixture.replacingOccurrences(of: "\"end\":750", with: "\"end\":1441"),
                        fixture.replacingOccurrences(of: "\"start\":600", with: "\"start\":599"),
                        fixture.replacingOccurrences(of: "\"start\":600", with: "\"start\":760"),
                        fixture.replacingOccurrences(of: "\"start\":600", with: "\"start\":-1"),
                        fixture.replacingOccurrences(of: "\"end\":750", with: "\"end\":750.5"),
                        fixture.replacingOccurrences(of: "\"start\":600", with: "\"start\":true"),
                        fixture.replacingOccurrences(of: "2026-10-27T00:00:00+02:00", with: "2026-02-30T00:00:00Z"),
                        fixture.replacingOccurrences(of: "2026-10-27T07:30:00Z", with: "2026-10-27T09:00:00Z")] {
            try rejects({ _ = try decode(Data(invalid.utf8), fetchedAt: now) }, "invalid schedule")
        }
        let unknown = try decode(Data(fixture.replacingOccurrences(of: "Definite", with: "FutureType").utf8), fetchedAt: now)
        try check(unknown.intervals(group: "17.2", at: now)[1].state == .unknown, "unknown slot type")
        let gap = try decode(Data(fixture.replacingOccurrences(of: "\"start\":600", with: "\"start\":630").utf8), fetchedAt: now)
        try check(gap.intervals(group: "17.2", at: now).contains(where: { $0.start == 600 && $0.end == 630 && $0.state == .unknown }), "gap is unknown")
        try check(gap.currentOrNextOutage(group: "17.2", at: now) == nil, "incomplete plan forecast")
        let emergency = try decode(Data(fixture.replacingOccurrences(of: "ScheduleApplies", with: "EmergencyShutdowns").utf8), fetchedAt: now)
        try check(emergency.intervals(group: "17.2", at: now).first?.state == .emergency, "emergency overrides slots")
        try check(emergency.currentOrNextOutage(group: "17.2", at: now) == nil, "no emergency forecast")
        let tomorrow = parseTimestamp("2026-10-27T22:10:00Z")!
        let freshTomorrow = Self(schedules: report.schedules, fetchedAt: tomorrow)
        try check(freshTomorrow.day(group: "17.2", at: tomorrow)?.status == "WaitingForSchedule", "Kyiv date rollover uses tomorrow")
        try check(freshTomorrow.intervals(group: "17.2", at: tomorrow).first?.state == .unknown, "empty tomorrow is unknown")
        let fallbackDay = parseTimestamp("2026-10-25T12:00:00Z")!
        let midnight = kyivCalendar.startOfDay(for: fallbackDay)
        let end = date(on: fallbackDay, minute: 1440)!
        try check(end.timeIntervalSince(midnight) == 25 * 3600, "DST end uses next local midnight")
        try check(date(on: fallbackDay, minute: 210) == nil, "ambiguous DST wall time has no invented timestamp")
        let springDay = parseTimestamp("2026-03-29T12:00:00Z")!
        try check(date(on: springDay, minute: 1440)!.timeIntervalSince(kyivCalendar.startOfDay(for: springDay)) == 23 * 3600, "DST start uses next local midnight")
        try check(date(on: springDay, minute: 210) == nil, "missing DST wall time has no invented timestamp")
        try check(parseTimestamp("2026-02-29T00:00:00Z") == nil && parseTimestamp("2024-02-29T00:00:00Z") != nil, "leap date validation")
        let addresses = try JSONDecoder().decode([VenusOutageAddressItem].self, from: Data(#"[{"id":123,"value":"Тестова вулиця"},{"id":"124","value":7}]"#.utf8))
        try check(addresses.map(\.id) == ["123", "124"] && addresses[1].name == "7", "opaque IDs and numeric house labels")
        try rejects({ _ = try JSONDecoder().decode(VenusOutageAddressItem.self, from: Data(#"{"id":true,"value":"Тест"}"#.utf8)) }, "Boolean address ID")
        try rejects({ _ = try VenusOutageValidation.unique(addresses + addresses) }, "ambiguous address IDs")
        let groups = try JSONDecoder().decode(VenusOutageGroupResponse.self, from: Data(#"[{"group":17,"subgroup":2},{"group":17,"subgroup":3}]"#.utf8)).values
        try check(groups == ["17.2", "17.3"], "multiple address groups preserved for explicit choice")
        try rejects({ _ = try JSONDecoder().decode(VenusOutageGroupResponse.self, from: Data("true".utf8)) }, "Boolean group")
        let url = try VenusOutageHTTP.url("addresses/v2/streets", query: [URLQueryItem(name: "query", value: "Тест & №1/2+")])
        try check(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "Тест & №1/2+", "query encoding")
        try check(url.absoluteString.contains("%2B"), "literal plus is escaped for server query parser")
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(Self.self, from: encoder.encode(report))
        try check(restored.fetchedAt == now && !restored.isFresh(at: now.addingTimeInterval(1801)), "cache never freshens receipt")
    }
}
