import SwiftUI

struct AppRowView: View {
    let icon: Image
    let iconDimension: CGFloat
    let app: AppRecord
    let update: UpdateRecord?
    let releaseDate: Date
    let recentlyUpdatedDate: Date?
    let isUpdating: Bool
    let updateProgress: Double?
    let isUpdateFailed: Bool
    let isUpdatedPendingRefresh: Bool
    let isIgnored: Bool
    let onOpenFromIcon: () -> Void
    let onToggleIgnore: () -> Void
    let onUpdate: () -> Void
    let showsUninstallAction: Bool
    let isUninstallingHomebrewItem: Bool
    let onRequestUninstall: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: MenuPresentationMetrics.rowContentSpacing) {
            AppIconView(
                icon: icon,
                iconDimension: iconDimension,
                onOpen: onOpenFromIcon
            )

            AppMetadataView(
                title: app.displayName,
                versionLine: versionLine,
                releaseLine: releaseLine
            )

            Spacer(minLength: MenuPresentationMetrics.rowTrailingSpacerMinLength)

            AppActionsView(
                appDisplayName: app.displayName,
                hasUpdate: update != nil,
                isUpdating: isUpdating,
                updateProgress: updateProgress,
                isUpdateFailed: isUpdateFailed,
                isUpdatedPendingRefresh: isUpdatedPendingRefresh,
                isIgnored: isIgnored,
                showsUninstallAction: showsUninstallAction,
                isUninstallingHomebrewItem: isUninstallingHomebrewItem,
                onUpdate: onUpdate,
                onToggleIgnore: onToggleIgnore,
                onRequestUninstall: onRequestUninstall
            )
        }
        .padding(.vertical, MenuPresentationMetrics.rowVerticalPadding)
        .ignoredRowStyle(isIgnored: isIgnored)
        .compositingGroup()
        .clipped()
    }

    private var versionLine: String {
        if let update {
            return "\(update.localVersion.raw) -> \(update.remoteVersion.raw)"
        }
        return app.localVersion.raw.isEmpty ? "Unknown" : app.localVersion.raw
    }

    private var releaseLine: String {
        if let recentlyUpdatedDate {
            return "Updated on: \(formattedReleaseDate(recentlyUpdatedDate)) (\(relativeDayDescription(for: recentlyUpdatedDate)))"
        }
        return "Release: \(formattedReleaseDate(releaseDate)) (\(relativeDayDescription(for: releaseDate)))"
    }

    private func relativeDayDescription(for date: Date) -> String {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let startOfTarget = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: startOfTarget, to: startOfToday).day ?? 0

        if days <= 0 {
            return "today"
        }
        if days == 1 {
            return "yesterday"
        }
        return "\(days) days ago"
    }

    private func formattedReleaseDate(_ date: Date) -> String {
        AppRowView.releaseDateFormatter.string(from: date)
    }

    private static let releaseDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d MMM yyyy"
        return formatter
    }()
}

private struct AppIconView: View {
    let icon: Image
    let iconDimension: CGFloat
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            icon
                .resizable()
                .interpolation(.high)
                .frame(width: iconDimension, height: iconDimension)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: MenuPresentationMetrics.rowIconCornerRadius,
                        style: .continuous
                    )
                )
        }
        .buttonStyle(.plain)
        .help("Open App")
        .menuHoverable()
    }
}

private struct AppMetadataView: View {
    let title: String
    let versionLine: String
    let releaseLine: String

    var body: some View {
        VStack(alignment: .leading, spacing: MenuPresentationMetrics.rowMetadataSpacing) {
            Text(title)
                .font(.body.weight(.semibold))

            Text(versionLine)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(releaseLine)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct AppActionsView: View {
    let appDisplayName: String
    let hasUpdate: Bool
    let isUpdating: Bool
    let updateProgress: Double?
    let isUpdateFailed: Bool
    let isUpdatedPendingRefresh: Bool
    let isIgnored: Bool
    let showsUninstallAction: Bool
    let isUninstallingHomebrewItem: Bool
    let onUpdate: () -> Void
    let onToggleIgnore: () -> Void
    let onRequestUninstall: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            if showsUninstallAction {
                Button(action: onRequestUninstall) {
                    if isUninstallingHomebrewItem {
                        HomebrewUninstallActionGlyphView()
                    } else {
                        Image(systemName: "trash")
                    }
                }
                .menuDestructiveIconButtonStyle()
                .help("Uninstall \(appDisplayName)")
                .disabled(isUpdating || isUninstallingHomebrewItem)
            }

            IgnoreActionIconButton(
                isIgnored: isIgnored,
                onToggleIgnore: onToggleIgnore
            )
            .disabled(isUninstallingHomebrewItem)

            if hasUpdate {
                UpdateActionButton(
                    state: updateState,
                    onUpdate: onUpdate
                )
                .disabled(isUninstallingHomebrewItem)
            }
        }
    }

    private var updateState: UpdateActionButton.State {
        if isUpdateFailed {
            return .failed
        }
        if isUpdating {
            return .updating(progress: updateProgress)
        }
        if isUpdatedPendingRefresh {
            return .done
        }
        return .ready
    }
}
