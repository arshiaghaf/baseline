import SwiftUI

private struct MenuButtonSizing {
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let minHeight: CGFloat

    static func forControlSize(_ controlSize: ControlSize) -> MenuButtonSizing {
        switch controlSize {
        case .mini:
            return MenuButtonSizing(horizontalPadding: 10, verticalPadding: 3, minHeight: 22)
        case .small:
            return MenuButtonSizing(horizontalPadding: 13, verticalPadding: 4, minHeight: 26)
        case .regular:
            return MenuButtonSizing(horizontalPadding: 16, verticalPadding: 6, minHeight: 30)
        case .large:
            return MenuButtonSizing(horizontalPadding: 19, verticalPadding: 8, minHeight: 34)
        case .extraLarge:
            return MenuButtonSizing(horizontalPadding: 22, verticalPadding: 10, minHeight: 38)
        @unknown default:
            return MenuButtonSizing(horizontalPadding: 13, verticalPadding: 4, minHeight: 26)
        }
    }
}

private struct MenuUpdateButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    let controlSize: ControlSize

    func makeBody(configuration: Configuration) -> some View {
        let sizing = MenuButtonSizing.forControlSize(controlSize)
        let opacity = isEnabled ? (configuration.isPressed ? 0.78 : 1.0) : 0.45

        return configuration.label
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, sizing.horizontalPadding)
            .padding(.vertical, sizing.verticalPadding)
            .frame(minHeight: sizing.minHeight)
            .background(
                RoundedRectangle(
                    cornerRadius: MenuPresentationMetrics.actionButtonCornerRadius,
                    style: .continuous
                )
                .fill(Color.accentColor.opacity(opacity))
            )
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .menuHoverable(isEnabled: isEnabled)
    }
}

private struct MenuSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    let controlSize: ControlSize

    func makeBody(configuration: Configuration) -> some View {
        let sizing = MenuButtonSizing.forControlSize(controlSize)
        let fillOpacity = isEnabled ? (configuration.isPressed ? 0.2 : 0.12) : 0.06
        let strokeOpacity = isEnabled ? 0.14 : 0.06
        let foregroundOpacity = isEnabled ? 1.0 : 0.5

        return configuration.label
            .font(.caption)
            .foregroundStyle(.primary.opacity(foregroundOpacity))
            .padding(.horizontal, sizing.horizontalPadding)
            .padding(.vertical, sizing.verticalPadding)
            .frame(minHeight: sizing.minHeight)
            .background(
                RoundedRectangle(
                    cornerRadius: MenuPresentationMetrics.actionButtonCornerRadius,
                    style: .continuous
                )
                .fill(.primary.opacity(fillOpacity))
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: MenuPresentationMetrics.actionButtonCornerRadius,
                    style: .continuous
                )
                .stroke(.primary.opacity(strokeOpacity), lineWidth: 1)
            }
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .menuHoverable(isEnabled: isEnabled)
    }
}

private struct MenuDestructiveIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    let controlSize: ControlSize

    func makeBody(configuration: Configuration) -> some View {
        let sizing = MenuButtonSizing.forControlSize(controlSize)
        let opacity = isEnabled ? (configuration.isPressed ? 0.9 : 1.0) : 0.5
        let fillOpacity = isEnabled ? (configuration.isPressed ? 0.22 : 0.14) : 0.08
        let strokeOpacity = isEnabled ? 0.32 : 0.14
        let iconDimension = max(
            MenuPresentationMetrics.destructiveIconButtonDimension,
            sizing.minHeight
        )

        return configuration.label
            .font(.caption.weight(.semibold))
            .foregroundStyle(.red.opacity(opacity))
            .frame(width: iconDimension, height: iconDimension)
            .background(
                RoundedRectangle(
                    cornerRadius: MenuPresentationMetrics.actionButtonCornerRadius,
                    style: .continuous
                )
                .fill(Color.red.opacity(fillOpacity))
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: MenuPresentationMetrics.actionButtonCornerRadius,
                    style: .continuous
                )
                .stroke(Color.red.opacity(strokeOpacity), lineWidth: 1)
            }
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .menuHoverable(isEnabled: isEnabled)
    }
}

private struct MenuSecondaryIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    let controlSize: ControlSize

    func makeBody(configuration: Configuration) -> some View {
        let sizing = MenuButtonSizing.forControlSize(controlSize)
        let opacity = isEnabled ? (configuration.isPressed ? 0.9 : 1.0) : 0.5
        let fillOpacity = isEnabled ? (configuration.isPressed ? 0.2 : 0.12) : 0.06
        let strokeOpacity = isEnabled ? 0.16 : 0.08
        let iconDimension = max(
            MenuPresentationMetrics.destructiveIconButtonDimension,
            sizing.minHeight
        )

        return configuration.label
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary.opacity(opacity))
            .frame(width: iconDimension, height: iconDimension)
            .background(
                RoundedRectangle(
                    cornerRadius: MenuPresentationMetrics.actionButtonCornerRadius,
                    style: .continuous
                )
                .fill(.primary.opacity(fillOpacity))
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: MenuPresentationMetrics.actionButtonCornerRadius,
                    style: .continuous
                )
                .stroke(.primary.opacity(strokeOpacity), lineWidth: 1)
            }
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .menuHoverable(isEnabled: isEnabled)
    }
}

private struct MenuUpdateIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    let controlSize: ControlSize

    func makeBody(configuration: Configuration) -> some View {
        let sizing = MenuButtonSizing.forControlSize(controlSize)
        let opacity = isEnabled ? (configuration.isPressed ? 0.85 : 1.0) : 0.5
        let iconDimension = max(
            MenuPresentationMetrics.destructiveIconButtonDimension,
            sizing.minHeight
        )

        return configuration.label
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(opacity))
            .frame(width: iconDimension, height: iconDimension)
            .background(
                RoundedRectangle(
                    cornerRadius: MenuPresentationMetrics.actionButtonCornerRadius,
                    style: .continuous
                )
                .fill(Color.accentColor.opacity(opacity))
            )
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .menuHoverable(isEnabled: isEnabled)
    }
}

extension View {
    func menuUpdateButtonStyle(controlSize: ControlSize = .small) -> some View {
        self
            .buttonStyle(MenuUpdateButtonStyle(controlSize: controlSize))
    }

    func menuSecondaryButtonStyle(controlSize: ControlSize = .small) -> some View {
        self
            .buttonStyle(MenuSecondaryButtonStyle(controlSize: controlSize))
    }

    func menuDestructiveIconButtonStyle(controlSize: ControlSize = .small) -> some View {
        self
            .buttonStyle(MenuDestructiveIconButtonStyle(controlSize: controlSize))
    }

    func menuSecondaryIconButtonStyle(controlSize: ControlSize = .small) -> some View {
        self
            .buttonStyle(MenuSecondaryIconButtonStyle(controlSize: controlSize))
    }

    func menuUpdateIconButtonStyle(controlSize: ControlSize = .small) -> some View {
        self
            .buttonStyle(MenuUpdateIconButtonStyle(controlSize: controlSize))
    }
}
