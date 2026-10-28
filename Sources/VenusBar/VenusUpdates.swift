import AppKit
import Combine
import Sparkle

/// Sparkle owns download validation, replacement, relaunch and its preferences.
@MainActor
final class VenusUpdates: NSObject, ObservableObject, SPUStandardUserDriverDelegate {
    static let shared = VenusUpdates()
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false
    @Published private(set) var availableVersion: String?
    private lazy var controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: self)
    var isAvailable: Bool { Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String != nil }
    var isPresentingUpdate: Bool { isAvailable && controller.updater.sessionInProgress }
    var beforePresentingUpdate: (() -> Void)?

    private override init() {
        super.init()
        guard isAvailable else { return }
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
        let version = update.displayVersionString
        DispatchQueue.main.async { [weak self] in self?.availableVersion = version }
    }
    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        DispatchQueue.main.async { [weak self] in self?.availableVersion = nil }
    }
    nonisolated func standardUserDriverWillFinishUpdateSession() {
        DispatchQueue.main.async { [weak self] in self?.availableVersion = nil }
    }
}
