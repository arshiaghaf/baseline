import AppKit
import SwiftUI

private struct PointingHandCursorModifier: ViewModifier {
    let isEnabled: Bool
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                guard isEnabled else {
                    if isHovering {
                        NSCursor.pop()
                        isHovering = false
                    }
                    return
                }

                if hovering {
                    guard !isHovering else { return }
                    NSCursor.pointingHand.push()
                    isHovering = true
                } else if isHovering {
                    NSCursor.pop()
                    isHovering = false
                }
            }
            .onDisappear {
                guard isHovering else { return }
                NSCursor.pop()
                isHovering = false
            }
    }
}

private struct MenuHoverModifier: ViewModifier {
    let isEnabled: Bool
    let scale: CGFloat
    let brightness: Double
    let shadowOpacity: Double
    let shadowRadius: CGFloat
    let shadowYOffset: CGFloat
    let animation: Animation
    @State private var isHovering = false

    private var isHoverActive: Bool {
        isEnabled && isHovering
    }

    func body(content: Content) -> some View {
        content
            .menuPointingHandCursor(isEnabled: isEnabled)
            .onHover { hovering in
                guard isEnabled else {
                    isHovering = false
                    return
                }
                isHovering = hovering
            }
            .onChange(of: isEnabled) { _, enabled in
                if !enabled {
                    isHovering = false
                }
            }
            .scaleEffect(isHoverActive ? scale : 1.0)
            .offset(y: isHoverActive ? -0.5 : 0)
            .brightness(isHoverActive ? brightness : 0)
            .shadow(
                color: .black.opacity(isHoverActive ? shadowOpacity : 0),
                radius: isHoverActive ? shadowRadius : 0,
                x: 0,
                y: isHoverActive ? shadowYOffset : 0
            )
            .animation(animation, value: isHoverActive)
    }
}

extension View {
    func menuPointingHandCursor(isEnabled: Bool = true) -> some View {
        modifier(PointingHandCursorModifier(isEnabled: isEnabled))
    }

    func menuHoverable(
        isEnabled: Bool = true,
        scale: CGFloat = 1.03,
        brightness: Double = 0.04,
        shadowOpacity: Double = 0.22,
        shadowRadius: CGFloat = 8,
        shadowYOffset: CGFloat = 2,
        animation: Animation = .spring(response: 0.18, dampingFraction: 0.88)
    ) -> some View {
        modifier(
            MenuHoverModifier(
                isEnabled: isEnabled,
                scale: scale,
                brightness: brightness,
                shadowOpacity: shadowOpacity,
                shadowRadius: shadowRadius,
                shadowYOffset: shadowYOffset,
                animation: animation
            )
        )
    }
}
