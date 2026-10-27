import AppKit
import SwiftUI

/// SwiftUI views can remain mounted while their menu-bar panel is ordered out.
/// Pause decorative timelines whenever their actual window is off screen.
struct VenusViewActivity: NSViewRepresentable {
    @Binding var isActive: Bool

    func makeNSView(context: Context) -> ActivityView {
        let view = ActivityView()
        view.onActivity = { isActive = $0 }
        return view
    }

    func updateNSView(_ view: ActivityView, context: Context) {
        view.onActivity = { isActive = $0 }
        view.refreshActivity()
    }

    final class ActivityView: NSView {
        var onActivity: ((Bool) -> Void)?
        private var observer: NSObjectProtocol?
        private var lastActivity: Bool?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            if let window {
                observer = NotificationCenter.default.addObserver(
                    forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
                ) { [weak self] _ in self?.refreshActivity() }
            }
            refreshActivity()
        }

        func refreshActivity() {
            let active = window.map { $0.isVisible && $0.occlusionState.contains(.visible) } ?? false
            guard active != lastActivity else { return }
            lastActivity = active
            DispatchQueue.main.async { [weak self] in self?.onActivity?(active) }
        }

        deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    }
}

struct VenusSoftPlaceholder: View {
    var width: CGFloat = 52
    var height: CGFloat = 5

    var body: some View {
        Capsule().fill(.white.opacity(0.13)).frame(width: width, height: height)
            .accessibilityLabel("Показник ще не отримано")
    }
}

/// A neutral activity indicator, never a percentage or an energy reading.
struct VenusLoadingOrb: View {
    let active: Bool
    var symbol = "bolt"
    var diameter: CGFloat = 88
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false
    private var moving: Bool { active && visible && !reduceMotion }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: !moving)) { context in
            let phase = moving ? context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3) / 3 : 0.15
            ZStack {
                Circle().fill(.black.opacity(0.14))
                Circle().stroke(.white.opacity(0.09), lineWidth: 0.8)
                Circle().stroke(.white.opacity(0.045), lineWidth: 0.6).padding(9)
                Circle().trim(from: 0, to: 0.23)
                    .stroke(LinearGradient(colors: [.clear, .white.opacity(active ? 0.85 : 0.25)], startPoint: .leading, endPoint: .trailing),
                            style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                    .rotationEffect(.degrees(phase * 360 - 90)).padding(1)
                Image(systemName: symbol).font(.system(size: 25, weight: .ultraLight))
                    .foregroundStyle(.white.opacity(active ? 0.8 : 0.4))
            }
        }
        .frame(width: diameter, height: diameter)
        .background(VenusViewActivity(isActive: $visible))
        .onDisappear { visible = false }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(active ? "Очікуємо відповідь станції" : "Підключення до станції")
    }
}

struct VenusButtonStyle: ButtonStyle {
    var primary = false
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        VenusButtonBody(configuration: configuration, primary: primary, compact: compact)
    }

    private struct VenusButtonBody: View {
        let configuration: Configuration
        let primary: Bool
        let compact: Bool
        @Environment(\.isEnabled) private var enabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var hovered = false

        var body: some View {
            configuration.label
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(primary ? Color.black : .white.opacity(0.9))
                .padding(.horizontal, compact ? 12 : 17)
                .frame(minHeight: compact ? 36 : 44)
                .modifier(SwiftfulUICardSurface(
                    backgroundColor: primary ? Color.white.opacity(hovered ? 1 : 0.92) : Color.white.opacity(hovered ? 0.14 : 0.075),
                    borderColor: .white.opacity(primary ? 0.5 : hovered ? 0.22 : 0.12), cornerRadius: compact ? 10 : 13))
                .contentShape(RoundedRectangle(cornerRadius: compact ? 10 : 13, style: .continuous))
                .modifier(SwiftfulUIPressFeedback(isPressed: configuration.isPressed))
                .opacity(enabled ? 1 : 0.35)
                .onHover { hovered = $0 }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: hovered)
        }
    }
}

struct VenusTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .font(.system(size: 14))
            .foregroundStyle(.white)
            .padding(.horizontal, 13)
            .frame(minHeight: 44)
            .modifier(SwiftfulUICardSurface(backgroundColor: .white.opacity(0.065), borderColor: .white.opacity(0.1), cornerRadius: 12))
    }
}
