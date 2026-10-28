import AppKit
import Combine
import Sparkle

/// VenusBar releases use a monotonically increasing integer CFBundleVersion.
struct VenusUpdateRelease: Equatable {
    let version: String
    let build: String

    static func buildNumber(_ value: String) -> UInt64? {
        guard !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }),
              let number = UInt64(value), number > 0 else { return nil }
        return number
    }

    func isNewer(than currentBuild: String) -> Bool {
        guard !version.isEmpty, version.count <= 64,
              let release = Self.buildNumber(build), let current = Self.buildNumber(currentBuild) else { return false }
        return release > current
    }
}

/// Sparkle owns download validation, replacement, relaunch and its preferences.
@MainActor
final class VenusUpdates: NSObject, ObservableObject, SPUStandardUserDriverDelegate, SPUUpdaterDelegate {
    static let shared = VenusUpdates()
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false
    @Published private(set) var availableVersion: String?
    @Published private(set) var availableBuild: String?
    private lazy var controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
    private let currentBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    private static let availableReleaseKey = "updates.availableRelease"
    var isAvailable: Bool { Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String != nil }
    var isPresentingUpdate: Bool { isAvailable && controller.updater.sessionInProgress }
    var beforePresentingUpdate: (() -> Void)?
    var availableReleaseLabel: String? {
        guard let availableVersion, let availableBuild else { return nil }
        return VL("\(availableVersion) · збірка \(availableBuild)", "\(availableVersion) · build \(availableBuild)")
    }

    private override init() {
        super.init()
        guard isAvailable else { return }
        if let saved = UserDefaults.standard.dictionary(forKey: Self.availableReleaseKey),
           let version = saved["version"] as? String, let build = saved["build"] as? String,
           VenusUpdateRelease(version: version, build: build).isNewer(than: currentBuild) {
            availableVersion = version
            availableBuild = build
        } else { clearAvailableRelease() }
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main).assign(to: &$canCheckForUpdates)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates)
            .receive(on: RunLoop.main).assign(to: &$automaticallyChecksForUpdates)
        controller.startUpdater()
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        beforePresentingUpdate?()
        controller.checkForUpdates(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        guard isAvailable else { return }
        controller.updater.automaticallyChecksForUpdates = enabled
    }

    // A menu-bar app signals available updates without stealing another app's focus.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }
    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool { false }
    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        let release = VenusUpdateRelease(version: update.displayVersionString, build: update.versionString)
        let background = !state.userInitiated
        DispatchQueue.main.async { [weak self] in
            guard let self, release.isNewer(than: self.currentBuild) else { return }
            self.remember(release)
            VenusNotificationsStore.shared.notifyUpdate(release, currentBuild: self.currentBuild, background: background)
        }
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        let build = update.versionString
        DispatchQueue.main.async { VenusNotificationsStore.shared.dismissUpdateNotice(build: build) }
    }

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let release = VenusUpdateRelease(version: item.displayVersionString, build: item.versionString)
        DispatchQueue.main.async { [weak self] in self?.remember(release) }
    }

    nonisolated func updater(_ updater: SPUUpdater, userDidMake choice: SPUUserUpdateChoice, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        guard choice == .skip else { return }
        let build = update.versionString
        DispatchQueue.main.async { [weak self] in
            guard let self, self.availableBuild == build else { return }
            self.clearAvailableRelease()
        }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        DispatchQueue.main.async { [weak self] in self?.clearAvailableRelease() }
    }

    private func remember(_ release: VenusUpdateRelease) {
        guard release.isNewer(than: currentBuild) else { return }
        availableVersion = release.version
        availableBuild = release.build
        UserDefaults.standard.set(["version": release.version, "build": release.build], forKey: Self.availableReleaseKey)
    }

    private func clearAvailableRelease() {
        availableVersion = nil
        availableBuild = nil
        UserDefaults.standard.removeObject(forKey: Self.availableReleaseKey)
    }

    static func selfCheck() throws {
        func check(_ value: Bool, _ message: String) throws {
            guard value else { throw VenusStoreError.message("Update release: \(message)") }
        }
        try check(VenusUpdateRelease(version: "0.1", build: "5").isNewer(than: "4"), "same version newer build is available")
        try check(!VenusUpdateRelease(version: "0.1", build: "4").isNewer(than: "4"), "installed build does not advertise itself")
        try check(!VenusUpdateRelease(version: "0.1", build: "3").isNewer(than: "4"), "older release ignored")
        for invalid in ["", "0", "-1", "+5", "5.1", "５", "18446744073709551616"] {
            try check(!VenusUpdateRelease(version: "0.1", build: invalid).isNewer(than: "4"), "invalid build ignored")
        }
        try check(!VenusUpdateRelease(version: "", build: "5").isNewer(than: "4"), "missing display version ignored")
    }
}
