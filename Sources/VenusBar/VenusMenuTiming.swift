import Foundation

enum VenusMenuTiming {
    static func isUrgentOutage(date: Date?, isRestoration: Bool, now: Date = Date()) -> Bool {
        guard !isRestoration, let date else { return false }
        let remaining = date.timeIntervalSince(now)
        return remaining > 0 && remaining <= 15 * 60
    }

    static func selfCheck() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        guard isUrgentOutage(date: now.addingTimeInterval(900), isRestoration: false, now: now),
              !isUrgentOutage(date: now.addingTimeInterval(901), isRestoration: false, now: now),
              !isUrgentOutage(date: now, isRestoration: false, now: now),
              !isUrgentOutage(date: now.addingTimeInterval(60), isRestoration: true, now: now),
              !isUrgentOutage(date: nil, isRestoration: false, now: now) else {
            throw VenusStoreError.message("Upcoming-outage badge timing self-check failed")
        }
    }
}
