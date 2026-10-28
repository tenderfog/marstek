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
            .accessibilityLabel(VL("Показник ще не отримано", "No reading received yet"))
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
        .accessibilityLabel(active ? VL("Очікуємо відповідь станції", "Waiting for the station") : VL("Підключення до станції", "Connect to the station"))
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

struct VenusDisclosure<Content: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    private let destructive: Bool
    private let content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(_ title: String, isExpanded: Binding<Bool>, destructive: Bool = false, @ViewBuilder content: () -> Content) {
        self.title = title
        _isExpanded = isExpanded
        self.destructive = destructive
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 12) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0)).accessibilityHidden(true)
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    .foregroundStyle(destructive ? VenusVisuals.supplying : .white.opacity(0.9))
            }
            .buttonStyle(VenusButtonStyle())
            .accessibilityValue(isExpanded ? VL("Розгорнуто", "Expanded") : VL("Згорнуто", "Collapsed"))
            if isExpanded { content.frame(maxWidth: .infinity, alignment: .leading) }
        }
    }
}

/// Keep the overflow hint outside the viewport so it never hides a form control.
struct VenusVerticalScroll<Content: View>: View {
    private let content: Content
    @Namespace private var coordinateSpace
    @State private var contentFrame = CGRect.zero
    private let hintHeight: CGFloat = 24

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        GeometryReader { available in
            let overflowing = VenusScrollMetrics.overflows(contentHeight: contentFrame.height, availableHeight: available.size.height)
            let viewportHeight = available.size.height - (overflowing ? hintHeight : 0)
            let moreBelow = overflowing && VenusScrollMetrics.hasMoreBelow(contentBottom: contentFrame.maxY, viewportHeight: viewportHeight)
            VStack(spacing: 0) {
                ScrollView(.vertical) {
                    content.frame(maxWidth: .infinity, alignment: .leading)
                        .background(GeometryReader { geometry in
                            Color.clear.preference(key: VenusScrollContentFrame.self,
                                                   value: [coordinateSpace: geometry.frame(in: .named(coordinateSpace))])
                        })
                }
                .coordinateSpace(name: coordinateSpace)
                .scrollIndicators(.visible)
                .onPreferenceChange(VenusScrollContentFrame.self) { frames in
                    if let frame = frames[coordinateSpace] { contentFrame = frame }
                }
                if overflowing {
                    HStack(spacing: 5) {
                        Text(VL("Прокрути вниз", "Scroll for more"))
                        Image(systemName: "chevron.down").fontWeight(.semibold)
                    }
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity).frame(height: hintHeight)
                    .opacity(moreBelow ? 1 : 0).accessibilityHidden(!moreBelow)
                }
            }
        }
    }
}

private struct VenusScrollContentFrame: PreferenceKey {
    static var defaultValue: [Namespace.ID: CGRect] = [:]
    static func reduce(value: inout [Namespace.ID: CGRect], nextValue: () -> [Namespace.ID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

enum VenusScrollMetrics {
    static func overflows(contentHeight: CGFloat, availableHeight: CGFloat) -> Bool {
        availableHeight > 0 && contentHeight > availableHeight + 1
    }

    static func hasMoreBelow(contentBottom: CGFloat, viewportHeight: CGFloat) -> Bool {
        viewportHeight > 0 && contentBottom > viewportHeight + 1
    }

    static func selfCheck() throws {
        struct Invalid: Error {}
        guard !overflows(contentHeight: 100, availableHeight: 100),
              !overflows(contentHeight: 100, availableHeight: 0),
              !overflows(contentHeight: 100.5, availableHeight: 100),
              overflows(contentHeight: 102, availableHeight: 100),
              hasMoreBelow(contentBottom: 110, viewportHeight: 100),
              !hasMoreBelow(contentBottom: 100, viewportHeight: 100),
              !hasMoreBelow(contentBottom: -20, viewportHeight: 100) else { throw Invalid() }
    }
}
