// Adapted from SwiftfulUI by Swiftful Thinking, LLC (MIT, copyright 2022).
// Sources and full permission notice: THIRD_PARTY_NOTICES.md.
import SwiftUI

/// SwiftfulUI's pressed scale/opacity/brightness primitive, adapted to a modifier
/// so VenusBar keeps the original native Button and its keyboard/accessibility actions.
struct SwiftfulUIPressFeedback: ViewModifier {
    let isPressed: Bool
    var scale: CGFloat = 0.98
    var opacity: Double = 0.72
    var brightness: Double = 0
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let pressed = isPressed && enabled
        return content
            .scaleEffect(pressed && !reduceMotion ? scale : 1)
            .opacity(pressed ? opacity : 1)
            .brightness(pressed ? brightness : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: pressed)
    }
}

/// SwiftfulUI's background/border/fill geometry, with bounded corner radii.
struct SwiftfulUICardSurface: ViewModifier {
    let backgroundColor: Color
    var borderColor: Color = .white.opacity(0.08)
    var borderWidth: CGFloat = 0.6
    var cornerRadius: CGFloat = 13

    func body(content: Content) -> some View {
        content
            .background(Color.white.opacity(0.0001))
            .padding(-borderWidth)
            .background(RoundedRectangle(cornerRadius: max(0, cornerRadius - borderWidth / 2), style: .continuous).fill(backgroundColor))
            .padding(borderWidth)
            .background(RoundedRectangle(cornerRadius: max(0, cornerRadius), style: .continuous).fill(borderColor))
    }
}
