import AppKit
import Combine
import Foundation
import UserNotifications

/// Consumes actual output observations; a stale or repeated packet cannot rearm it.
struct VenusHighLoadGate {
    private(set) var armed = true
    private(set) var lastObservedAt: Date?
    var lastAlertAt: Date?

    mutating func resetEpisode() { armed = true; lastObservedAt = nil }

    mutating func evaluate(watts: Double?, observedAt: Date?, fresh: Bool, restored: Bool,
                           thresholdW: Double, now: Date) -> Bool {
        guard fresh, !restored, let watts, watts.isFinite, (0...20_000).contains(watts),
              thresholdW.isFinite, (100...5000).contains(thresholdW), let observedAt,
              (0...90).contains(now.timeIntervalSince(observedAt)),
              lastObservedAt.map({ observedAt > $0 }) ?? true else { return false }
        lastObservedAt = observedAt
        if watts < thresholdW - max(50, thresholdW * 0.1) { armed = true }
        guard armed, watts > thresholdW else { return false }
        if let lastAlertAt, (0..<300).contains(now.timeIntervalSince(lastAlertAt)) { return false }
        armed = false
        lastAlertAt = now
        return true
    }

    mutating func deliveryFailed(previousAlertAt: Date?) {
        armed = true
        lastAlertAt = previousAlertAt
    }
}

struct VenusUpdateNoticeGate {
    static func shouldNotify(_ release: VenusUpdateRelease, currentBuild: String, lastNotifiedBuild: String?,
                             background: Bool, enabled: Bool, authorized: Bool) -> Bool {
        guard background, enabled, authorized, release.isNewer(than: currentBuild),
              let build = VenusUpdateRelease.buildNumber(release.build) else { return false }
        return lastNotifiedBuild.flatMap(VenusUpdateRelease.buildNumber).map { build > $0 } ?? true
    }
}

@MainActor
final class VenusNotificationsStore: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = VenusNotificationsStore()
    @Published private(set) var masterEnabled: Bool
    @Published private(set) var highLoadEnabled: Bool
    @Published private(set) var updateEnabled: Bool
    @Published private(set) var thresholdW: Double
    @Published private(set) var isRequestingPermission = false
    @Published private(set) var authorizationStatus: UNAuthorizationStatus?
    @Published private(set) var error: String?

    private let defaults: UserDefaults
    private let center: UNUserNotificationCenter
    private var gate = VenusHighLoadGate()
    private var stationID: String?
    private var generation = 0
    private var deliveryGeneration = 0
    private var permissionTask: Task<Void, Never>?
    private var deliveryTask: Task<Void, Never>?
    private var pendingRequestID: String?
    private static let requestID = "venusbar.high-load"
    nonisolated private static let updateRequestPrefix = "venusbar.update."
    private var updateDeliveryTask: Task<Void, Never>?
    private var updateDeliveryGeneration = 0
    private var pendingUpdateRequestID: String?
    private enum Key {
        static let master = "notifications.masterEnabled"
        static let highLoad = "notifications.highLoadEnabled"
        static let threshold = "notifications.highLoadThresholdW"
        static let lastAlert = "notifications.highLoadLastAlertAt"
        static let update = "notifications.updateEnabled"
        static let lastUpdate = "notifications.lastUpdateBuild"
    }

    var permissionDenied: Bool { authorizationStatus == .denied }
    var canDeliver: Bool {
        masterEnabled && highLoadEnabled && permissionAllowsDelivery
    }
    private var permissionAllowsDelivery: Bool {
        !isRequestingPermission && (authorizationStatus == .authorized || authorizationStatus == .provisional)
    }
    var permissionStatus: String {
        if let error { return error }
        if isRequestingPermission { return VL("Очікуємо дозвіл macOS…", "Waiting for macOS permission…") }
        switch authorizationStatus {
        case .authorized?: return VL("Сповіщення дозволено macOS", "Notifications allowed by macOS")
        case .provisional?: return VL("Дозволено тихі сповіщення", "Quiet notifications allowed")
        case .denied?: return VL("Дозволь сповіщення для VenusBar у налаштуваннях macOS", "Allow VenusBar notifications in macOS Settings")
        case .notDetermined?: return VL("Дозвіл запитаємо після ввімкнення", "Permission will be requested when enabled")
        default: return VL("Перевіряємо дозвіл macOS…", "Checking macOS permission…")
        }
    }

    init(defaults: UserDefaults = .standard, center: UNUserNotificationCenter = .current()) {
        self.defaults = defaults
        self.center = center
        masterEnabled = defaults.bool(forKey: Key.master)
        highLoadEnabled = defaults.object(forKey: Key.highLoad) as? Bool ?? true
        updateEnabled = defaults.object(forKey: Key.update) as? Bool ?? true
        let stored = defaults.object(forKey: Key.threshold) as? Double ?? 1000
        thresholdW = Self.threshold(stored)
        if let last = defaults.object(forKey: Key.lastAlert) as? Date, last <= Date() { gate.lastAlertAt = last }
        super.init()
        center.delegate = self
        refreshPermission() // Read-only. Startup never requests authorization.
    }

    /// Call only from the user's settings toggle.
    func setMasterEnabled(_ enabled: Bool) {
        generation += 1
        permissionTask?.cancel(); permissionTask = nil
        cancelDelivery()
        cancelUpdateDelivery()
        isRequestingPermission = false
        masterEnabled = enabled
        defaults.set(enabled, forKey: Key.master)
        gate.resetEpisode()
        error = nil
        if !enabled {
            return
        }
        let token = generation
        isRequestingPermission = true
        permissionTask = Task { [weak self] in
            guard let self else { return }
            var settings = await self.center.notificationSettings()
            guard !Task.isCancelled, token == self.generation, self.masterEnabled else { return }
            if settings.authorizationStatus == .notDetermined {
                do { _ = try await self.center.requestAuthorization(options: [.alert, .sound]) }
                catch {
                    guard token == self.generation else { return }
                    self.error = VL("Не вдалося отримати дозвіл на сповіщення. Перевір налаштування macOS.", "Could not obtain notification permission. Check macOS Settings.")
                }
                settings = await self.center.notificationSettings()
            }
            guard !Task.isCancelled, token == self.generation, self.masterEnabled else { return }
            self.authorizationStatus = settings.authorizationStatus
            self.isRequestingPermission = false
            self.permissionTask = nil
        }
    }

    func setHighLoadEnabled(_ enabled: Bool) {
        highLoadEnabled = enabled
        defaults.set(enabled, forKey: Key.highLoad)
        gate.resetEpisode()
        cancelDelivery()
    }

    func setUpdateEnabled(_ enabled: Bool) {
        updateEnabled = enabled
        defaults.set(enabled, forKey: Key.update)
        if !enabled { cancelUpdateDelivery() }
    }

    func setThresholdWatts(_ value: Double) {
        guard value.isFinite else { return }
        thresholdW = Self.threshold(value)
        defaults.set(thresholdW, forKey: Key.threshold)
    }

    func refreshPermission() {
        let token = generation
        Task { [weak self] in
            guard let self else { return }
            let settings = await self.center.notificationSettings()
            guard token == self.generation, !self.isRequestingPermission else { return }
            self.authorizationStatus = settings.authorizationStatus
        }
    }

    func openSystemSettings() {
        let pane = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!
        if !NSWorkspace.shared.open(pane) {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
        }
    }

    func evaluate(snapshot: VenusPowerSnapshot, isRestored: Bool, stationID: String? = nil, now: Date = Date()) {
        if stationID != self.stationID { self.stationID = stationID; gate.resetEpisode(); cancelDelivery() }
        guard canDeliver, deliveryTask == nil else { return }
        let previousAlert = gate.lastAlertAt
        guard gate.evaluate(watts: snapshot.outputW, observedAt: snapshot.output?.observationDate,
                            fresh: snapshot.outputFresh, restored: isRestored, thresholdW: thresholdW, now: now),
              let watts = snapshot.outputW else { return }
        let token = deliveryGeneration
        let content = UNMutableNotificationContent()
        content.title = VL("Високе споживання", "High power consumption")
        func number(_ value: Double) -> String {
            value.formatted(.number.precision(.fractionLength(0...1)).locale(VenusLanguage.current.locale))
        }
        content.body = VL("Станція віддає \(number(watts)) Вт — понад поріг \(number(thresholdW)) Вт. Можливо, увімкнено бойлер, чайник або фен.",
                          "The station is supplying \(number(watts)) W — above your \(number(thresholdW)) W threshold. A boiler, kettle, or hair dryer may be on.")
        content.sound = .default
        let requestID = Self.requestID + "." + UUID().uuidString
        pendingRequestID = requestID
        let request = UNNotificationRequest(identifier: requestID, content: content, trigger: nil)
        deliveryTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if token == self.deliveryGeneration { self.deliveryTask = nil; self.pendingRequestID = nil }
            }
            guard !Task.isCancelled, token == self.deliveryGeneration, self.canDeliver else { return }
            do {
                try await self.center.add(request)
                guard !Task.isCancelled, token == self.deliveryGeneration, self.canDeliver else {
                    self.center.removePendingNotificationRequests(withIdentifiers: [requestID])
                    return
                }
                self.defaults.set(now, forKey: Key.lastAlert)
                self.error = nil
            } catch {
                guard !Task.isCancelled, token == self.deliveryGeneration else { return }
                self.gate.deliveryFailed(previousAlertAt: previousAlert)
                self.error = VL("Не вдалося показати сповіщення. Перевір дозвіл macOS.", "Could not show the notification. Check macOS permission.")
                self.refreshPermission()
            }
        }
    }

    private func cancelDelivery() {
        deliveryGeneration += 1
        deliveryTask?.cancel(); deliveryTask = nil
        if let pendingRequestID { center.removePendingNotificationRequests(withIdentifiers: [pendingRequestID]) }
        pendingRequestID = nil
    }

    /// Only Sparkle's valid-update callback supplies this release; cached/offline state never alerts.
    func notifyUpdate(_ release: VenusUpdateRelease, currentBuild: String, background: Bool) {
        guard updateDeliveryTask == nil,
              VenusUpdateNoticeGate.shouldNotify(release, currentBuild: currentBuild,
                  lastNotifiedBuild: defaults.string(forKey: Key.lastUpdate), background: background,
                  enabled: masterEnabled && updateEnabled, authorized: permissionAllowsDelivery) else { return }
        let token = updateDeliveryGeneration
        let requestID = Self.updateRequestPrefix + release.build
        let content = UNMutableNotificationContent()
        content.title = VL("Оновлення VenusBar", "VenusBar update")
        content.body = VL("Доступна версія \(release.version), збірка \(release.build). Натисни, щоб завантажити й установити.",
                          "Version \(release.version), build \(release.build) is available. Click to download and install.")
        content.sound = .default
        content.userInfo = ["venusbar.action": "update"]
        pendingUpdateRequestID = requestID
        updateDeliveryTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if token == self.updateDeliveryGeneration { self.updateDeliveryTask = nil; self.pendingUpdateRequestID = nil }
            }
            guard !Task.isCancelled, token == self.updateDeliveryGeneration,
                  self.masterEnabled, self.updateEnabled, self.permissionAllowsDelivery else { return }
            do {
                try await self.center.add(UNNotificationRequest(identifier: requestID, content: content, trigger: nil))
                guard !Task.isCancelled, token == self.updateDeliveryGeneration,
                      self.masterEnabled, self.updateEnabled, self.permissionAllowsDelivery else {
                    self.center.removePendingNotificationRequests(withIdentifiers: [requestID])
                    self.center.removeDeliveredNotifications(withIdentifiers: [requestID])
                    return
                }
                self.defaults.set(release.build, forKey: Key.lastUpdate)
            } catch {
                guard !Task.isCancelled, token == self.updateDeliveryGeneration else { return }
                self.error = VL("Не вдалося показати сповіщення. Перевір дозвіл macOS.", "Could not show the notification. Check macOS permission.")
                self.refreshPermission()
            }
        }
    }

    private func cancelUpdateDelivery() {
        updateDeliveryGeneration += 1
        updateDeliveryTask?.cancel(); updateDeliveryTask = nil
        if let pendingUpdateRequestID { center.removePendingNotificationRequests(withIdentifiers: [pendingUpdateRequestID]) }
        pendingUpdateRequestID = nil
    }

    func dismissUpdateNotice(build: String) {
        let requestID = Self.updateRequestPrefix + build
        if pendingUpdateRequestID == requestID { cancelUpdateDelivery() }
        center.removePendingNotificationRequests(withIdentifiers: [requestID])
        center.removeDeliveredNotifications(withIdentifiers: [requestID])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier,
           response.notification.request.identifier.hasPrefix(Self.updateRequestPrefix),
           response.notification.request.content.userInfo["venusbar.action"] as? String == "update" {
            Task { @MainActor in VenusUpdates.shared.checkForUpdates() }
        }
        completionHandler()
    }

    private static func threshold(_ value: Double) -> Double {
        guard value.isFinite else { return 1000 }
        return min(5000, max(100, (value / 50).rounded() * 50))
    }

    static func selfCheck() throws {
        func check(_ value: Bool, _ message: String) throws {
            guard value else { throw VenusStoreError.message("Notification gate: \(message)") }
        }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var gate = VenusHighLoadGate()
        func event(_ watts: Double?, _ seconds: Double, fresh: Bool = true, restored: Bool = false, age: Double = 0) -> Bool {
            let time = now.addingTimeInterval(seconds)
            return gate.evaluate(watts: watts, observedAt: time.addingTimeInterval(-age), fresh: fresh, restored: restored, thresholdW: 1000, now: time)
        }
        try check(!event(1000, 0), "strictly above threshold only")
        try check(event(1001, 1), "first crossing")
        try check(!event(2000, 1) && !event(2000, 2) && !event(2000, 400), "duplicate and same episode do not repeat")
        try check(!event(900, 401) && !event(1100, 402), "hysteresis boundary does not rearm")
        try check(!event(899, 403) && event(1100, 404), "below hysteresis rearms after cooldown")
        try check(!event(800, 405) && !event(1100, 406), "five minute cooldown")
        try check(event(1100, 704), "pending high episode alerts when cooldown expires")
        try check(!event(800, 705, fresh: false) && !event(1100, 1005), "stale low cannot rearm")
        try check(!event(800, 1006, restored: true) && !event(1100, 1007), "restored low cannot rearm")
        try check(!event(nil, 1008) && !event(.nan, 1009) && !event(2000, 1010, age: 91) && !event(2000, 1011, age: -1), "nil invalid old and future readings ignored")
        gate.resetEpisode()
        try check(event(1100, 1012), "explicit new episode preserves valid cooldown")
        try check(threshold(824) == 800 && threshold(826) == 850 && threshold(-1) == 100 && threshold(9000) == 5000 && threshold(.nan) == 1000, "threshold bounds and step")
        var lowThreshold = VenusHighLoadGate()
        try check(lowThreshold.evaluate(watts: 201, observedAt: now, fresh: true, restored: false, thresholdW: 200, now: now), "custom threshold")
        try check(!lowThreshold.evaluate(watts: 151, observedAt: now.addingTimeInterval(301), fresh: true, restored: false, thresholdW: 200, now: now.addingTimeInterval(301)), "minimum 50W hysteresis")
        try check(!lowThreshold.evaluate(watts: 201, observedAt: now.addingTimeInterval(302), fresh: true, restored: false, thresholdW: 200, now: now.addingTimeInterval(302)), "not rearmed above low threshold boundary")
        let release = VenusUpdateRelease(version: "0.1", build: "5")
        func updateNotice(_ last: String? = nil, background: Bool = true, enabled: Bool = true, authorized: Bool = true) -> Bool {
            VenusUpdateNoticeGate.shouldNotify(release, currentBuild: "4", lastNotifiedBuild: last,
                                              background: background, enabled: enabled, authorized: authorized)
        }
        try check(updateNotice(), "valid background update can notify")
        try check(!updateNotice("5") && !updateNotice("6") && updateNotice("3"), "one notice per newer build")
        try check(!updateNotice(background: false) && !updateNotice(enabled: false) && !updateNotice(authorized: false), "manual checks and disabled or unauthorized alerts suppressed")
        try check(!VenusUpdateNoticeGate.shouldNotify(release, currentBuild: "5", lastNotifiedBuild: nil,
                                                     background: true, enabled: true, authorized: true), "installed release does not notify")
    }
}
