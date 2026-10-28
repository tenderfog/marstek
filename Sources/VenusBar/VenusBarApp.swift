import AppKit
import Combine
import QuartzCore
import SwiftUI

@main
struct VenusBarMain {
    @MainActor static func main() {
        do {
            if CommandLine.arguments.contains("--self-check") {
                try VenusAPI.selfCheck()
                try VenusStore.selfCheck()
                try VenusControlInput.selfCheck()
                try VenusWave.selfCheck()
                try VenusOnboarding.selfCheck()
                try VenusOutagesReport.selfCheck()
                try VenusEnergyStore.selfCheck()
                try VenusIndicatorEvidence.selfCheck()
                try VenusTemperature.selfCheck()
                try VenusPowerSnapshot.selfCheck()
                try VenusLocalization.selfCheck()
                try VenusMenuTiming.selfCheck()
                try VenusNotificationsStore.selfCheck()
                try VenusScrollMetrics.selfCheck()
                try VenusUpdates.selfCheck()
                print("VenusBar self-check: passed")
                return
            }
            if CommandLine.arguments.contains("--read-once") {
                let args = CommandLine.arguments
                guard let index = args.firstIndex(of: "--ip"), args.indices.contains(index + 1) else {
                    throw VenusStoreError.message(VL("Для --read-once вкажи --ip та, за потреби, --port.", "Use --ip and optionally --port with --read-once."))
                }
                let port: Int
                if let index = args.firstIndex(of: "--port") {
                    guard args.indices.contains(index + 1), let parsed = Int(args[index + 1]) else {
                        throw VenusStoreError.message(VL("Некоректний --port.", "Invalid --port."))
                    }
                    port = parsed
                } else { port = 30000 }
                let data = try VenusAPI().read(ip: args[index + 1], port: port)
                FileHandle.standardOutput.write(data)
                print()
                return
            }
            if NSRunningApplication.runningApplications(withBundleIdentifier: "local.offline.VenusBar")
                .contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
                DistributedNotificationCenter.default().postNotificationName(Notification.Name("local.offline.VenusBar.open"), object: nil)
                return
            }
            let application = NSApplication.shared
            application.setActivationPolicy(.accessory)
            let delegate = VenusAppDelegate()
            application.delegate = delegate
            withExtendedLifetime(delegate) { application.run() }
        } catch {
            FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
            exit(1)
        }
    }
}

struct VenusGlassBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        view.focusRingType = .none
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

struct VenusGlassSurface: View {
    var body: some View {
        VenusGlassBackground()
            .overlay(Color.black.opacity(0.24))
    }
}

private struct VenusMenuBarGlass: NSViewRepresentable {
    let appearance: NSAppearance?
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .menu
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = appearance
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) { view.appearance = appearance }
}

private final class VenusHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }
}

private final class VenusFloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

struct VenusPanelHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 610
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct MenuBarIslandShape: Shape {
    func path(in rect: CGRect) -> Path {
        let shoulder: CGFloat = 18
        let bottom: CGFloat = 18
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: 0))
        path.addCurve(to: CGPoint(x: rect.width - shoulder, y: shoulder),
                      control1: CGPoint(x: rect.width - shoulder * 0.6, y: 0),
                      control2: CGPoint(x: rect.width - shoulder, y: shoulder * 0.3))
        path.addLine(to: CGPoint(x: rect.width - shoulder, y: rect.height - bottom))
        path.addQuadCurve(to: CGPoint(x: rect.width - shoulder - bottom, y: rect.height),
                         control: CGPoint(x: rect.width - shoulder, y: rect.height))
        path.addLine(to: CGPoint(x: shoulder + bottom, y: rect.height))
        path.addQuadCurve(to: CGPoint(x: shoulder, y: rect.height - bottom), control: CGPoint(x: shoulder, y: rect.height))
        path.addLine(to: CGPoint(x: shoulder, y: shoulder))
        path.addCurve(to: .zero, control1: CGPoint(x: shoulder, y: shoulder * 0.3), control2: CGPoint(x: shoulder * 0.6, y: 0))
        path.closeSubpath()
        return path
    }
}

@MainActor
private struct VenusHoverSurface: View {
    @ObservedObject private var localization = VenusLocalization.shared
    @ObservedObject var store: VenusStore
    @ObservedObject var outages: VenusOutagesStore
    let appearance: NSAppearance?
    let onDetails: () -> Void

    var body: some View {
        Group {
            if store.report != nil {
                VStack(spacing: 8) {
                    VenusIslandContent(store: store, onDetails: onDetails)
                        .frame(width: 300, height: 76)
                    if outages.selection != nil {
                        VenusMiniOutageTimeline(store: outages)
                            .frame(width: 300, height: 58)
                            .contentShape(Rectangle()).onTapGesture(perform: onDetails)
                    }
                }
            } else {
                Button(action: onDetails) {
                    HStack(spacing: 13) {
                        Image(systemName: store.configuration == nil ? "bolt.horizontal.fill" : "antenna.radiowaves.left.and.right")
                            .font(.system(size: 23, weight: .light))
                            .foregroundStyle(Color.primary.opacity(0.9))
                            .frame(width: 30)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(title).font(.system(size: 14, weight: .semibold))
                            Text(subtitle).font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.55))
                        }
                        Spacer(minLength: 0)
                        if store.isReading || store.isDiscovering {
                            ProgressView().controlSize(.small).frame(width: 16)
                        } else {
                            Image(systemName: "arrow.up.right").font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.primary.opacity(0.65))
                        }
                    }.frame(width: 244, height: 50).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 28).padding(.top, 12).padding(.bottom, 20)
        .foregroundStyle(.primary)
        .background { VenusMenuBarGlass(appearance: appearance) }
        .clipShape(MenuBarIslandShape())
        .preferredColorScheme(appearance?.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light)
    }

    private var title: String {
        if store.configuration == nil { return VL("Підключити станцію", "Connect a station") }
        if store.isReading { return VL("З’єднуємося зі станцією", "Connecting to the station") }
        return store.error == nil ? VL("Станція очікує", "Station ready") : VL("Станція недоступна", "Station unavailable")
    }
    private var subtitle: String {
        if store.configuration == nil { return VL("Локально через Wi-Fi або LAN", "Locally over Wi-Fi or LAN") }
        return store.isReading ? store.ip : VL("Перевірити підключення", "Check connection")
    }
}

@MainActor
private final class VenusAppDelegate: NSObject, NSApplicationDelegate {
    private let store = VenusStore()
    private let outages = VenusOutagesStore()
    private let energy = VenusEnergyStore()
    private let notifications = VenusNotificationsStore.shared
    private var statusItem: NSStatusItem!
    private var fullPanel: NSPanel?
    private var island: NSPanel?
    private var subscription: AnyCancellable?
    private var outageSubscription: AnyCancellable?
    private var languageSubscription: AnyCancellable?
    private var exitMonitor: Any?
    private var localMonitor: Any?
    private var hideWork: DispatchWorkItem?
    private var openWork: DispatchWorkItem?
    private var overIcon = false
    private var overIsland = false
    private var islandAnimation = 0
    private var islandClosing = false
    private var statusPresentation: String?
    private var islandSize: NSSize {
        store.report == nil ? NSSize(width: 300, height: 82) : NSSize(width: 356, height: outages.selection == nil ? 108 : 174)
    }

    private func configureApplicationMenu() {
        let appMenu = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu(title: "VenusBar")
        applicationMenu.addItem(withTitle: VL("Перевірити оновлення…", "Check for Updates…"), action: #selector(checkForUpdates), keyEquivalent: "").target = self
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(withTitle: VL("Вийти з VenusBar", "Quit VenusBar"), action: #selector(quit), keyEquivalent: "q").target = self
        applicationItem.submenu = applicationMenu
        appMenu.addItem(applicationItem)
        NSApp.mainMenu = appMenu
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        VenusUpdates.shared.beforePresentingUpdate = { [weak self] in self?.closePanels() }
        configureApplicationMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.target = self
        button.toolTip = nil
        button.action = #selector(iconClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.addTrackingArea(NSTrackingArea(rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
        updateStatus()
        subscription = store.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateStatus() }
        }
        outageSubscription = outages.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateStatus(); self?.resizeIslandIfVisible() }
        }
        languageSubscription = VenusLocalization.shared.$language.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.configureApplicationMenu()
                self.statusPresentation = nil
                self.updateStatus()
                if self.store.isPolling { self.store.reload() }
            }
        }
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(showFromNotification),
            name: Notification.Name("local.offline.VenusBar.open"), object: nil)
        exitMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.dismissOutsideClick() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { [weak self] event in
            if event.type == .keyDown, event.keyCode == 53 {
                Task { @MainActor in self?.closePanels() }
                return nil
            }
            return event
        }
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1"
        let firstLaunchOfVersion = UserDefaults.standard.string(forKey: "presentedVersion") != version
        if store.configuration == nil || firstLaunchOfVersion || CommandLine.arguments.contains("--open-panel") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.showFullPanel()
                UserDefaults.standard.set(version, forKey: "presentedVersion")
            }
        } else if CommandLine.arguments.contains("--preview-island") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.showIsland() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stop()
        outages.stop()
        energy.stop()
        if let exitMonitor { NSEvent.removeMonitor(exitMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        DistributedNotificationCenter.default().removeObserver(self)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showFullPanel()
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        notifications.refreshPermission()
        DispatchQueue.main.async { [weak self] in
            guard let self, NSApp.isActive, !VenusUpdates.shared.isPresentingUpdate, self.fullPanel?.isVisible != true else { return }
            self.showFullPanel()
        }
    }

    @objc private func showFromNotification(_ notification: Notification) { showFullPanel() }

    @objc(mouseEntered:) func mouseEntered(with event: NSEvent) {
        overIcon = true
        hideWork?.cancel()
        guard fullPanel?.isVisible != true else { return }
        openWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.overIcon else { return }
            self.showIsland()
        }
        openWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    @objc(mouseExited:) func mouseExited(with event: NSEvent) {
        overIcon = false
        openWork?.cancel()
        scheduleIslandClose()
    }

    @objc private func iconClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            openWork?.cancel()
            overIcon = false
            hideIsland(animated: false)
            let menu = NSMenu()
            menu.addItem(withTitle: VL("Відкрити VenusBar", "Open VenusBar"), action: #selector(openPanelAction), keyEquivalent: "")
            menu.addItem(withTitle: VL("Перевірити оновлення…", "Check for Updates…"), action: #selector(checkForUpdates), keyEquivalent: "")
            menu.addItem(.separator())
            menu.addItem(withTitle: VL("Вийти з VenusBar", "Quit VenusBar"), action: #selector(quit), keyEquivalent: "q")
            for item in menu.items { item.target = self }
            if let button = statusItem.button {
                menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY), in: button)
            }
        } else if fullPanel?.isVisible == true { closePanels() }
        else { showFullPanel() }
    }
    @objc private func openPanelAction() { showFullPanel() }
    @objc private func checkForUpdates() { closePanels(); VenusUpdates.shared.checkForUpdates() }
    @objc private func quit() { NSApp.terminate(nil) }

    private func updateStatus() {
        resizeFullPanelIfVisible()
        if store.isFresh, let report = store.report, let device = store.device {
            energy.record(report: report, device: device, flow: store.flowState)
        }
        let power = VenusPowerSnapshot.make(report: store.report, model: store.model,
                                            chargingGridSign: store.configuration?.chargingGridSign, fresh: store.isFresh)
        notifications.evaluate(snapshot: power, isRestored: store.isRestoredReport,
                               stationID: store.device.map { "\($0.id)|\($0.wifiMac ?? $0.bleMac ?? $0.name)" })
        guard let button = statusItem?.button else { return }
        let bolt = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: VL("Станція", "Station"))
        bolt?.isTemplate = true
        if button.image == nil { button.image = bolt }
        button.imagePosition = .imageLeft
        guard let report = store.report else {
            let presentation = store.configuration == nil ? "disconnected" : "connecting"
            guard statusPresentation != presentation else { return }
            statusPresentation = presentation
            button.attributedTitle = NSAttributedString(string: "")
            button.setAccessibilityLabel(store.configuration == nil ? VL("VenusBar · Підключити станцію", "VenusBar · Connect a station") : VL("VenusBar · З’єднання зі станцією", "VenusBar · Connecting to station"))
            resizeIslandIfVisible()
            return
        }
        let percentage = report.socPercent.map { "\(Int($0.rounded()))%" } ?? ""
        let state = store.flowState
        let nextChange = outages.nextChange()
        let urgent = VenusMenuTiming.isUrgentOutage(date: nextChange?.time, isRestoration: nextChange?.isRestoration ?? false)
        let planState = outages.currentPlanState
        let presentation = "\(percentage)|\(state.rawValue)|\(store.isFresh)|\(nextChange?.titleShort ?? "")|\(nextChange?.timeText ?? "")|\(urgent)|\(VenusLanguage.current.rawValue)|\(planState)"
        guard statusPresentation != presentation else { return }
        statusPresentation = presentation
        let symbol: String
        switch state {
        case .charging: symbol = "arrow.down.circle.fill"
        case .supplyingHome: symbol = "arrow.up.circle.fill"
        case .mains: symbol = "powerplug.fill"
        case .standby: symbol = "pause.circle"
        case .unknown: symbol = store.isFresh ? "ellipsis.circle" : "wifi.slash"
        }
        let color = NSColor(state.color)
        let label = NSMutableAttributedString(string: percentage + " ", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.labelColor])
        if let image = coloredSymbol(symbol, color: color) {
            let attachment = NSTextAttachment()
            attachment.attachmentCell = NSTextAttachmentCell(imageCell: image)
            let suffix = NSMutableAttributedString(attachment: attachment)
            suffix.addAttribute(.baselineOffset, value: -2, range: NSRange(location: 0, length: suffix.length))
            label.append(suffix)
        }
        if outages.selection != nil, planState == .noOutagePlanned || planState == .outagePlanned {
            label.append(NSAttributedString(string: "  ", attributes: [.foregroundColor: NSColor.secondaryLabelColor]))
            let gridOn = planState == .noOutagePlanned
            let gridSymbol = gridOn ? "bolt.fill" : "bolt.slash.fill"
            let gridColor = gridOn ? NSColor.systemGreen : NSColor.systemRed
            if let image = coloredSymbol(gridSymbol, color: gridColor) {
                let attachment = NSTextAttachment()
                attachment.attachmentCell = NSTextAttachmentCell(imageCell: image)
                let icon = NSMutableAttributedString(attachment: attachment)
                icon.addAttribute(.baselineOffset, value: -2, range: NSRange(location: 0, length: icon.length))
                label.append(icon)
            }
            if let nextChange, urgent {
                label.append(NSAttributedString(string: " "))
                let attachment = NSTextAttachment()
                attachment.attachmentCell = NSTextAttachmentCell(imageCell: outageTimeBadge(nextChange.timeText))
                let badge = NSMutableAttributedString(attachment: attachment)
                badge.addAttribute(.baselineOffset, value: -3, range: NSRange(location: 0, length: badge.length))
                label.append(badge)
            } else if let nextChange {
                label.append(NSAttributedString(string: " " + nextChange.timeText, attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
                    .foregroundColor: NSColor.labelColor]))
            }
        }
        button.attributedTitle = label
        let scheduleLabel = nextChange.map { VL(", за графіком \($0.titleShort.lowercased()) о \($0.timeText)", ", \($0.titleShort.lowercased()) at \($0.timeText) according to the schedule") } ?? ""
        button.setAccessibilityLabel("VenusBar, \(percentage), \(store.flowText)\(scheduleLabel)")
        resizeIslandIfVisible()
    }

    private func outageTimeBadge(_ time: String) -> NSImage {
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold), .foregroundColor: NSColor.white]
        let textSize = (time as NSString).size(withAttributes: attributes)
        let image = NSImage(size: NSSize(width: ceil(textSize.width) + 12, height: 18))
        image.lockFocus()
        NSColor.systemRed.setFill()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: image.size), xRadius: 6, yRadius: 6).fill()
        (time as NSString).draw(at: NSPoint(x: 6, y: (18 - textSize.height) / 2), withAttributes: attributes)
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private func coloredSymbol(_ name: String, color: NSColor) -> NSImage? {
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: store.flowText) else { return nil }
        let image = NSImage(size: NSSize(width: 14, height: 14))
        image.lockFocus()
        let rect = NSRect(x: 0, y: 0, width: 14, height: 14)
        symbol.draw(in: rect)
        color.setFill(); rect.fill(using: .sourceIn)
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private func anchorRect() -> NSRect? {
        guard let button = statusItem.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }
    private func panelFrame(size: NSSize, attached: Bool) -> NSRect {
        let anchor = anchorRect() ?? NSRect(x: NSScreen.main?.frame.midX ?? 400, y: NSScreen.main?.visibleFrame.maxY ?? 700, width: 20, height: 24)
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main
        let bounds = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let x = min(max(anchor.midX - size.width / 2, bounds.minX + 8), bounds.maxX - size.width - 8)
        let menuBarBottom = statusItem.button?.window?.frame.minY ?? anchor.minY
        let top = attached ? menuBarBottom + 1 : menuBarBottom - 8
        return NSRect(x: x, y: max(bounds.minY + 8, top - size.height), width: size.width, height: size.height)
    }

    private func showFullPanel() {
        hideIsland(animated: false)
        openWork?.cancel()
        if fullPanel == nil {
            let panel = makePanel(size: NSSize(width: 520, height: 610), interactive: true)
            let view = VenusPanel(store: store, outages: outages, energy: energy)
                .background { VenusGlassSurface() }
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .preferredColorScheme(.dark)
                .onPreferenceChange(VenusPanelHeightPreferenceKey.self) { [weak self] height in
                    DispatchQueue.main.async {
                        guard let self, let panel = self.fullPanel, panel.isVisible else { return }
                        let size = NSSize(width: 520, height: max(430, min(820, height)))
                        panel.setFrame(self.panelFrame(size: size, attached: false), display: true)
                    }
                }
            let hosting = VenusHostingView(rootView: view)
            hosting.focusRingType = .none
            panel.contentView = hosting
            fullPanel = panel
        }
        guard let panel = fullPanel else { return }
        let fitting = panel.contentView?.fittingSize ?? NSSize(width: 520, height: 610)
        let size = NSSize(width: 520, height: max(430, min(820, fitting.height)))
        panel.setFrame(panelFrame(size: size, attached: false), display: true)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func showIsland() {
        guard fullPanel?.isVisible != true else { return }
        hideWork?.cancel()
        if island == nil {
            let panel = makePanel(size: islandSize, interactive: false)
            let content = VenusHoverSurface(store: store, outages: outages, appearance: statusItem.button?.effectiveAppearance,
                onDetails: { [weak self] in self?.showFullPanel() })
                .onHover { [weak self] inside in
                    self?.overIsland = inside
                    if inside { self?.hideWork?.cancel() } else { self?.scheduleIslandClose() }
                }
            panel.contentView = VenusHostingView(rootView: content)
            island = panel
        }
        guard let panel = island, !panel.isVisible || islandClosing else { return }
        islandAnimation += 1
        islandClosing = false
        let target = panelFrame(size: islandSize, attached: true)
        // Keep the content at its real size: shrinking the window squeezed its layout during hover.
        panel.setFrame(target, display: true)
        if !panel.isVisible { panel.alphaValue = 0 }
        panel.orderFrontRegardless()
        statusItem.button?.highlight(true)
        let reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reducedMotion ? 0 : 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    private func resizeIslandIfVisible() {
        guard let panel = island, panel.isVisible, !islandClosing else { return }
        let target = panelFrame(size: islandSize, attached: true)
        guard panel.frame != target else { return }
        panel.setFrame(target, display: true)
    }

    private func resizeFullPanelIfVisible() {
        guard let panel = fullPanel, panel.isVisible else { return }
        let height = max(430, min(820, panel.contentView?.fittingSize.height ?? 610))
        guard panel.frame.height != height else { return }
        panel.setFrame(panelFrame(size: NSSize(width: 520, height: height), attached: false), display: true)
    }

    private func makePanel(size: NSSize, interactive: Bool) -> NSPanel {
        let panel: NSPanel
        let rect = NSRect(origin: .zero, size: size)
        if interactive { panel = VenusFloatingPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false) }
        else { panel = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false) }
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = interactive
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.appearance = NSAppearance(named: .darkAqua)
        return panel
    }

    private func scheduleIslandClose() {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.overIcon, !self.overIsland else { return }
            self.hideIsland(animated: true)
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func hideIsland(animated: Bool) {
        hideWork?.cancel()
        statusItem?.button?.highlight(false)
        guard let panel = island, panel.isVisible else { return }
        overIsland = false
        islandAnimation += 1
        let animation = islandAnimation
        islandClosing = true
        if !animated {
            panel.orderOut(nil)
            islandClosing = false
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.16 : 0
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self, weak panel] in
            guard let self, self.islandAnimation == animation else { return }
            panel?.orderOut(nil)
            self.islandClosing = false
        }
    }

    private func closePanels() { openWork?.cancel(); fullPanel?.orderOut(nil); hideIsland(animated: false) }
    private func dismissOutsideClick() {
        let point = NSEvent.mouseLocation
        if anchorRect()?.contains(point) == true { return }
        if fullPanel?.isVisible == true, fullPanel?.frame.contains(point) == true { return }
        if island?.isVisible == true, island?.frame.contains(point) == true { return }
        closePanels()
    }
}
