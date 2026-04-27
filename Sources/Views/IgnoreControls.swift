import SwiftUI

struct IgnoreActionIconButton: View {
    let isIgnored: Bool
    let onToggleIgnore: () -> Void

    var body: some View {
        Button(action: onToggleIgnore) {
            Image(systemName: isIgnored ? "eye.slash" : "eye")
        }
        .menuSecondaryIconButtonStyle()
        .help(isIgnored ? "Unignore" : "Ignore")
        .accessibilityLabel(isIgnored ? "Unignore" : "Ignore")
    }
}

private struct IgnoredRowModifier: ViewModifier {
    let isIgnored: Bool

    func body(content: Content) -> some View {
        content
            .background {
                if isIgnored {
                    RoundedRectangle(
                        cornerRadius: 12,
                        style: .continuous
                    )
                    .fill(.secondary.opacity(0.18))
                    .overlay {
                        RoundedRectangle(
                            cornerRadius: 12,
                            style: .continuous
                        )
                        .stroke(.secondary.opacity(0.28), lineWidth: 1)
                    }
                }
            }
            .saturation(isIgnored ? 0.45 : 1.0)
            .opacity(isIgnored ? 0.9 : 1.0)
    }
}

extension View {
    func ignoredRowStyle(isIgnored: Bool) -> some View {
        modifier(IgnoredRowModifier(isIgnored: isIgnored))
    }
}
