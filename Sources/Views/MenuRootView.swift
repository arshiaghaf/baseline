import AppKit
import SwiftUI

private enum MenuActionConfirmation: Identifiable {
    case uninstall(HomebrewManagedItem)
    case install(HomebrewCaskDiscoveryItem)

    var id: String {
        switch self {
        case .uninstall(let item):
            return "uninstall-\(item.id)"
        case .install(let item):
            return "install-\(item.id)"
        }
    }

    var title: String {
        switch self {
        case .uninstall(let item):
            return "Uninstall \(item.name)?"
        case .install(let item):
            return "Install \(item.displayName)?"
        }
    }

    var message: String {
        switch self {
        case .uninstall(let item):
            return "This will fully delete \(item.name) from your Mac. Do you want to proceed?"
        case .install(let item):
            return "This will run Homebrew and install \(item.displayName) (\(item.kind.displayName.lowercased()) \(item.token)) on your Mac."
        }
    }

    var actionTitle: String {
        switch self {
        case .uninstall(let item):
            return "Uninstall \(item.name)"
        case .install(let item):
            return "Install \(item.displayName)"
        }
    }

    var isDestructive: Bool {
        if case .uninstall = self {
            return true
        }
        return false
    }
}

struct MenuRootView: View {
    @Bindable var store: UpdateStore
    @Environment(\.openSettings) private var openSettings
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedTab: MenuTab
    @State private var renderedTab: MenuTab
    @State private var isSearchPresented = false
    @State private var collapsedAppSectionIDs: Set<String> = []
    @State private var collapsedHomebrewSectionIDs: Set<String> = []
    @State private var actionConfirmation: MenuActionConfirmation?
    @State private var selectedTabPersistenceTask: Task<Void, Never>?
    @State private var renderedTabUpdateTask: Task<Void, Never>?

    init(store: UpdateStore) {
        self.store = store
        _selectedTab = State(initialValue: store.selectedTab)
        _renderedTab = State(initialValue: store.selectedTab)
    }

    var body: some View {
        ZStack {
            GlassEffectContainer(spacing: 12) {
                VStack(spacing: 12) {
                    MenuHeaderCard(
                        isRefreshing: store.isRefreshing,
                        isRunningHomebrewMaintenance: store.isRunningHomebrewMaintenance,
                        lastRefreshDate: store.lastRefreshDate,
                        searchText: $store.searchText,
                        isSearchPresented: isSearchPresented,
                        onOpenSettings: openSettingsPanel,
                        onRefresh: refreshNow,
                        onToggleSearch: toggleSearch,
                        onCloseSearch: hideSearch
                    )

                    if let refreshErrorMessage = store.refreshErrorMessage {
                        MenuErrorCard(
                            message: refreshErrorMessage,
                            onDismiss: store.dismissRefreshError
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    MenuControlsCard(
                        selectedTab: $selectedTab
                    )

                    if renderedTab == .apps {
                        MenuContentCard(
                            sections: visibleAppSections,
                            collapsedSectionIDs: $collapsedAppSectionIDs,
                            ignoredAppIDs: store.ignoredAppIDs,
                            iconDimension: MenuPresentationMetrics.rowIconSize,
                            updateForApp: store.update(for:),
                            releaseDateForApp: store.releaseDate(for:),
                            recentlyUpdatedDateForApp: store.recentlyUpdatedDate(for:),
                            isUpdatingApp: store.isUpdatingApp(_:),
                            appUpdateProgress: store.appUpdateProgress(for:),
                            isAppUpdateFailed: store.isAppUpdateFailed(_:),
                            isAppUpdatedPendingRefresh: store.isAppUpdatedPendingRefresh(_:),
                            iconForApp: store.icon(for:),
                            onOpenFromIcon: store.openApp(_:),
                            onToggleIgnore: store.toggleIgnored(for:),
                            onUpdate: store.performUpdate(for:),
                            uninstallableHomebrewItemForApp: store.uninstallableHomebrewItem(for:),
                            isUninstallingHomebrewItemForApp: store.isUninstallingHomebrewItem(for:),
                            onRequestUninstallHomebrewItem: requestUninstallConfirmation(for:)
                        )
                    } else {
                        HomebrewContentCard(
                            showsDiscoverSection: store.isHomebrewDiscoverySearchActive,
                            discoverSectionTitle: sectionTitle(base: "Discover", count: store.displayedHomebrewDiscoverItems.count),
                            discoverItems: store.displayedHomebrewDiscoverItems,
                            sections: visibleHomebrewSections,
                            collapsedSectionIDs: $collapsedHomebrewSectionIDs,
                            ignoredHomebrewItemIDs: store.ignoredHomebrewItemIDs,
                            isRunningHomebrewMaintenance: store.isRunningHomebrewMaintenance,
                            isHomebrewUpdateAllUpdatedPendingRefresh: store.isHomebrewUpdateAllUpdatedPendingRefresh,
                            isUpdatingHomebrewItem: store.isUpdatingHomebrewItem(_:),
                            homebrewUpdateProgress: store.homebrewUpdateProgress(for:),
                            isHomebrewItemUpdateFailed: store.isHomebrewItemUpdateFailed(_:),
                            isUninstallingHomebrewItem: store.isUninstallingHomebrewItem(_:),
                            isHomebrewItemUpdatedPendingRefresh: store.isHomebrewItemUpdatedPendingRefresh(_:),
                            onUpdateAllHomebrew: updateAllHomebrew,
                            iconAppearance: IconAppearance(colorScheme: colorScheme),
                            iconForItem: store.icon(for:appearance:),
                            canOpenFromIcon: store.canOpenHomebrewItem(_:),
                            onOpenFromIcon: store.openHomebrewItem(_:),
                            releaseDateForItem: store.releaseDate(for:),
                            recentlyUpdatedDateForItem: store.recentlyUpdatedDate(for:),
                            onToggleIgnore: store.toggleIgnored(for:),
                            onUpdate: store.performHomebrewUpdate(for:),
                            onRequestUninstall: requestUninstallConfirmation(for:),
                            onRequestInstall: requestInstallConfirmation(for:),
                            iconForDiscoverItem: store.icon(for:appearance:),
                            canOpenDiscoverFromIcon: store.canOpenHomebrewDiscoverItem(_:),
                            onOpenDiscoverFromIcon: store.openHomebrewDiscoverItem(_:),
                            isInstallingDiscoverItem: store.isInstallingHomebrewDiscoverItem(_:),
                            discoverInstallProgress: store.homebrewDiscoverInstallProgress(for:),
                            isDiscoverInstallFailed: store.isHomebrewDiscoverItemInstallFailed(_:),
                            isDiscoverInstalledPendingRefresh: store.isHomebrewDiscoverItemInstalledPendingRefresh(_:)
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .disabled(actionConfirmation != nil)
            }
            .padding(12)

            if let confirmation = actionConfirmation {
                MenuActionConfirmationOverlay(
                    confirmation: confirmation,
                    onCancel: cancelActionConfirmation,
                    onConfirm: confirmAction
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.spring(response: 0.2, dampingFraction: 0.9), value: actionConfirmation?.id)
        .onAppear {
            selectedTab = store.selectedTab
            renderedTab = store.selectedTab
        }
        .onChange(of: selectedTab) { _, newTab in
            renderSelectedTabAfterControlUpdate(newTab)
            persistSelectedTabAfterPaint(newTab)
        }
        .onChange(of: store.selectedTab) { _, newTab in
            guard selectedTab != newTab else { return }
            selectedTab = newTab
        }
    }
}

private extension MenuRootView {
    var visibleAppSections: [MenuSection] {
        var sections: [MenuSection] = [
            MenuSection(
                id: "available",
                title: sectionTitle(base: "Available", count: store.displayedAvailableApps.count),
                apps: store.displayedAvailableApps
            )
        ]

        if store.showRecentlyUpdatedAppsSection {
            sections.append(
                MenuSection(
                    id: "recentlyUpdated",
                    title: "Recently Updated",
                    apps: store.displayedRecentlyUpdatedApps,
                    showsUpdatedOnDate: true
                )
            )
        }

        if store.showInstalledAppsSection {
            sections.append(
                MenuSection(
                    id: "installed",
                    title: sectionTitle(base: "Installed", count: store.displayedInstalledApps.count),
                    apps: store.displayedInstalledApps
                )
            )
        }

        if store.showIgnoredAppsSection {
            sections.append(
                MenuSection(
                    id: "ignored",
                    title: sectionTitle(base: "Ignored", count: store.displayedIgnoredApps.count),
                    apps: store.displayedIgnoredApps
                )
            )
        }

        return sections
    }

    var visibleHomebrewSections: [HomebrewSection] {
        var sections: [HomebrewSection] = [
            HomebrewSection(
                id: "outdated",
                title: sectionTitle(base: "Outdated", count: store.displayedHomebrewOutdatedItems.count),
                items: store.displayedHomebrewOutdatedItems,
                showsUpdateAllButton: true
            )
        ]

        if store.showRecentlyUpdatedHomebrewSection {
            sections.append(
                HomebrewSection(
                    id: "recentlyUpdated",
                    title: "Recently Updated",
                    items: store.displayedHomebrewRecentlyUpdatedItems,
                    showsUpdatedOnDate: true
                )
            )
        }

        if store.showInstalledHomebrewSection {
            sections.append(
                HomebrewSection(
                    id: "installed",
                    title: sectionTitle(base: "Installed", count: store.displayedHomebrewInstalledItems.count),
                    items: store.displayedHomebrewInstalledItems
                )
            )
        }

        if store.showIgnoredHomebrewSection {
            sections.append(
                HomebrewSection(
                    id: "ignored",
                    title: sectionTitle(base: "Ignored", count: store.displayedHomebrewIgnoredItems.count),
                    items: store.displayedHomebrewIgnoredItems
                )
            )
        }

        return sections
    }

    func openSettingsPanel() {
        openSettings()
    }

    func renderSelectedTabAfterControlUpdate(_ tab: MenuTab) {
        renderedTabUpdateTask?.cancel()
        renderedTabUpdateTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            guard renderedTab != tab else { return }

            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                renderedTab = tab
            }
        }
    }

    func persistSelectedTabAfterPaint(_ tab: MenuTab) {
        selectedTabPersistenceTask?.cancel()
        selectedTabPersistenceTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            guard store.selectedTab != tab else { return }
            store.selectedTab = tab
        }
    }

    func refreshNow() {
        store.refreshNow()
    }

    func toggleSearch() {
        withAnimation(searchControlAnimation) {
            if isSearchPresented {
                hideSearch()
            } else {
                isSearchPresented = true
            }
        }
    }

    func hideSearch() {
        guard isSearchPresented else { return }
        isSearchPresented = false
        store.searchText = ""
    }

    var searchControlAnimation: Animation {
        .spring(response: 0.26, dampingFraction: 0.9)
    }

    func updateAllHomebrew() {
        store.performHomebrewUpdateAll()
    }

    func requestUninstallConfirmation(for item: HomebrewManagedItem) {
        guard item.kind == .cask else { return }
        actionConfirmation = .uninstall(item)
    }

    func requestInstallConfirmation(for item: HomebrewCaskDiscoveryItem) {
        actionConfirmation = .install(item)
    }

    func cancelActionConfirmation() {
        actionConfirmation = nil
    }

    func confirmAction() {
        guard let confirmation = actionConfirmation else { return }
        actionConfirmation = nil

        switch confirmation {
        case .uninstall(let item):
            store.performHomebrewUninstall(for: item)
        case .install(let item):
            store.performHomebrewInstall(for: item)
        }
    }

    func sectionTitle(base: String, count: Int?) -> String {
        guard let count, count > 0 else { return base }
        return "\(base) (\(count))"
    }
}

private struct MenuActionConfirmationOverlay: View {
    let confirmation: MenuActionConfirmation
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.42)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .onTapGesture(perform: onCancel)

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(confirmation.title)
                        .font(.headline.weight(.semibold))

                    Text(confirmation.message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 8) {
                    if confirmation.isDestructive {
                        Button(action: onConfirm) {
                            Text(confirmation.actionTitle)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(MenuDestructiveTextButtonStyle())
                    } else {
                        Button(action: onConfirm) {
                            Text(confirmation.actionTitle)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(MenuPrimaryTextButtonStyle())
                    }

                    Button(action: onCancel) {
                        Text("Cancel")
                            .frame(maxWidth: .infinity)
                    }
                    .menuSecondaryButtonStyle(controlSize: .regular)
                    .keyboardShortcut(.cancelAction)
                }
            }
            .padding(16)
            .frame(width: 270)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.quaternary.opacity(0.35), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.28), radius: 20, y: 10)
        }
        .padding(12)
        .accessibilityElement(children: .contain)
    }
}

private struct MenuDestructiveTextButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let opacity = isEnabled ? (configuration.isPressed ? 0.78 : 1.0) : 0.45

        configuration.label
            .font(.caption.weight(.semibold))
            .foregroundStyle(.red.opacity(opacity))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(minHeight: 30)
            .background(
                RoundedRectangle(cornerRadius: MenuPresentationMetrics.actionButtonCornerRadius, style: .continuous)
                    .fill(Color.red.opacity(isEnabled ? 0.18 : 0.08))
            )
            .overlay {
                RoundedRectangle(cornerRadius: MenuPresentationMetrics.actionButtonCornerRadius, style: .continuous)
                    .stroke(Color.red.opacity(isEnabled ? 0.34 : 0.14), lineWidth: 1)
            }
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .menuHoverable(isEnabled: isEnabled)
    }
}

private struct MenuPrimaryTextButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let opacity = isEnabled ? (configuration.isPressed ? 0.78 : 1.0) : 0.45

        configuration.label
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(opacity))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(minHeight: 30)
            .background(
                RoundedRectangle(cornerRadius: MenuPresentationMetrics.actionButtonCornerRadius, style: .continuous)
                    .fill(Color.accentColor.opacity(opacity))
            )
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .menuHoverable(isEnabled: isEnabled)
    }
}

private struct MenuErrorCard: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("Action failed")
                    .font(.caption2.weight(.semibold))

                Text(compactMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .frame(width: 18, height: 18)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Dismiss")
            .headerCapsuleControlBackground()
            .menuHoverable()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.orange.opacity(0.24), lineWidth: 1)
        }
        .glassEffect()
    }

    private var compactMessage: String {
        message
            .replacingOccurrences(of: "\n\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
    }
}

private struct MenuHeaderCard: View {
    let isRefreshing: Bool
    let isRunningHomebrewMaintenance: Bool
    let lastRefreshDate: Date?
    @Binding var searchText: String
    let isSearchPresented: Bool
    let onOpenSettings: () -> Void
    let onRefresh: () -> Void
    let onToggleSearch: () -> Void
    let onCloseSearch: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Baseline")
                    .font(.headline)
                if let lastRefreshDate {
                    Text("Last refresh \(lastRefreshDate.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if isRefreshing || isRunningHomebrewMaintenance {
                ProgressView()
                    .controlSize(.small)
                    .padding(.trailing, 2)
            }

            HStack(spacing: 6) {
                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape")
                        .font(.caption.weight(.semibold))
                        .frame(
                            width: HeaderControlMetrics.collapsedWidth,
                            height: HeaderControlMetrics.controlHeight
                        )
                        .contentShape(Capsule(style: .continuous))
                }
                .help("Open Settings")
                .buttonStyle(.plain)
                .headerCapsuleControlBackground()
                .menuHoverable()

                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                        .frame(
                            width: HeaderControlMetrics.collapsedWidth,
                            height: HeaderControlMetrics.controlHeight
                        )
                        .contentShape(Capsule(style: .continuous))
                }
                .help("Refresh")
                .buttonStyle(.plain)
                .headerCapsuleControlBackground()
                .menuHoverable()

                HeaderExpandingSearchControl(
                    searchText: $searchText,
                    isSearchPresented: isSearchPresented,
                    onToggleSearch: onToggleSearch,
                    onCloseSearch: onCloseSearch
                )
            }
            .controlSize(.small)
        }
        .menuCardStyle()
    }
}

private struct HeaderExpandingSearchControl: View {
    @Binding var searchText: String
    let isSearchPresented: Bool
    let onToggleSearch: () -> Void
    let onCloseSearch: () -> Void
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onToggleSearch) {
                Image(systemName: "magnifyingglass")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .help(isSearchPresented ? "Hide Search" : "Show Search")
            .menuHoverable()

            if isSearchPresented {
                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                    .onExitCommand(perform: onCloseSearch)
                    .transition(.move(edge: .trailing).combined(with: .opacity))

                Button(action: onCloseSearch) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear and Hide Search")
                .menuHoverable()
                .transition(.opacity)
            }
        }
        .padding(.horizontal, isSearchPresented ? 8 : 5)
        .frame(
            width: isSearchPresented
                ? HeaderControlMetrics.expandedSearchWidth
                : HeaderControlMetrics.collapsedWidth,
            height: HeaderControlMetrics.controlHeight,
            alignment: .leading
        )
        .headerCapsuleControlBackground()
        .animation(.spring(response: 0.26, dampingFraction: 0.9), value: isSearchPresented)
        .onChange(of: isSearchPresented) { _, isPresented in
            if isPresented {
                DispatchQueue.main.async {
                    isSearchFocused = true
                }
            } else {
                isSearchFocused = false
            }
        }
    }
}

private enum HeaderControlMetrics {
    static let collapsedWidth: CGFloat = 26
    static let expandedSearchWidth: CGFloat = 170
    static let controlHeight: CGFloat = 26
}

private extension View {
    func headerCapsuleControlBackground() -> some View {
        self
            .background(
                Capsule(style: .continuous)
                    .fill(.quaternary.opacity(0.14))
            )
            .overlay {
                Capsule(style: .continuous)
                    .stroke(.quaternary.opacity(0.28), lineWidth: 1)
            }
    }
}

private struct MenuControlsCard: View {
    @Binding var selectedTab: MenuTab

    var body: some View {
        ModernMenuTabControl(selectedTab: $selectedTab)
        .menuCardStyle()
    }
}

private struct ModernMenuTabControl: View {
    @Binding var selectedTab: MenuTab
    @Namespace private var selectionNamespace

    var body: some View {
        HStack(spacing: 6) {
            ForEach(MenuTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(selectionAnimation) {
                        selectedTab = tab
                    }
                } label: {
                    Text(tab.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .background {
                    if selectedTab == tab {
                        Capsule(style: .continuous)
                            .fill(Color.accentColor.opacity(0.22))
                            .overlay {
                                Capsule(style: .continuous)
                                    .stroke(Color.accentColor.opacity(0.5), lineWidth: 1)
                            }
                            .shadow(
                                color: Color.accentColor.opacity(0.18),
                                radius: 5,
                                x: 0,
                                y: 1
                            )
                            .matchedGeometryEffect(id: "menu-tab-highlight", in: selectionNamespace)
                    }
                }
                .menuHoverable()
            }
        }
        .padding(4)
        .frame(maxWidth: .infinity)
        .background(
            Capsule(style: .continuous)
                .fill(.quaternary.opacity(0.1))
        )
        .overlay {
            Capsule(style: .continuous)
                .stroke(.quaternary.opacity(0.24), lineWidth: 1)
        }
    }

    private var selectionAnimation: Animation {
        .spring(response: 0.12, dampingFraction: 0.94)
    }
}

private struct MenuContentCard: View {
    let sections: [MenuSection]
    @Binding var collapsedSectionIDs: Set<String>
    let ignoredAppIDs: Set<String>
    let iconDimension: CGFloat
    let updateForApp: (AppRecord) -> UpdateRecord?
    let releaseDateForApp: (AppRecord) -> Date
    let recentlyUpdatedDateForApp: (AppRecord) -> Date?
    let isUpdatingApp: (AppRecord) -> Bool
    let appUpdateProgress: (AppRecord) -> Double?
    let isAppUpdateFailed: (AppRecord) -> Bool
    let isAppUpdatedPendingRefresh: (AppRecord) -> Bool
    let iconForApp: (AppRecord) -> NSImage
    let onOpenFromIcon: (AppRecord) -> Void
    let onToggleIgnore: (AppRecord) -> Void
    let onUpdate: (AppRecord) -> Void
    let uninstallableHomebrewItemForApp: (AppRecord) -> HomebrewManagedItem?
    let isUninstallingHomebrewItemForApp: (AppRecord) -> Bool
    let onRequestUninstallHomebrewItem: (HomebrewManagedItem) -> Void
    @State private var isShowingAllRecentlyUpdated = false
    private let recentlyUpdatedPreviewLimit = 5
    private let recentlyUpdatedExpandedLimit = 40

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(sections) { section in
                    let canCollapse = section.isCollapsible
                    let isExpanded = !canCollapse || !collapsedSectionIDs.contains(section.id)

                    CollapsibleSectionHeaderView(
                        title: section.title,
                        canCollapse: canCollapse,
                        isExpanded: isExpanded,
                        onToggleExpanded: { toggleSection(section.id) }
                    ) {
                        EmptyView()
                    }
                    .menuSectionHeaderStyle()

                    if isExpanded {
                        let visibleApps = Array(appsForCurrentState(in: section).enumerated())
                        if section.apps.isEmpty {
                            Text(section.emptyStateMessage)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 8)
                                .padding(.vertical, 6)
                                .transition(sectionContentTransition)
                        } else {
                            ForEach(visibleApps, id: \.element.id) { index, app in
                                let isShowMoreRow = showsBlurredShowMoreOverlay(in: section) && index == visibleApps.count - 1
                                appRow(for: app, in: section)
                                    .overlay(alignment: .bottom) {
                                        if isShowMoreRow {
                                            RecentlyUpdatedShowMoreOverlay(onShowMore: showAllRecentlyUpdated)
                                                .padding(.horizontal, 2)
                                                .transition(.opacity)
                                        }
                                    }
                                    .transition(sectionRowTransition)

                                if index < visibleApps.count - 1 {
                                    SubtleRowDivider()
                                }
                            }
                        }
                    }

                    if section.id != sections.last?.id {
                        SubtleSectionDivider()
                    }
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
        }
        .scrollIndicators(.hidden)
        .menuListContainerStyle()
    }

    private func appRow(for app: AppRecord, in section: MenuSection) -> some View {
        AppRowView(
            icon: Image(nsImage: iconForApp(app)),
            iconDimension: iconDimension,
            app: app,
            update: updateForApp(app),
            releaseDate: releaseDateForApp(app),
            recentlyUpdatedDate: section.showsUpdatedOnDate ? recentlyUpdatedDateForApp(app) : nil,
            isUpdating: isUpdatingApp(app),
            updateProgress: appUpdateProgress(app),
            isUpdateFailed: isAppUpdateFailed(app),
            isUpdatedPendingRefresh: isAppUpdatedPendingRefresh(app),
            isIgnored: ignoredAppIDs.contains(app.id),
            onOpenFromIcon: { onOpenFromIcon(app) },
            onToggleIgnore: { onToggleIgnore(app) },
            onUpdate: { onUpdate(app) },
            showsUninstallAction: uninstallableHomebrewItemForApp(app) != nil,
            isUninstallingHomebrewItem: isUninstallingHomebrewItemForApp(app),
            onRequestUninstall: { requestUninstall(for: app) }
        )
    }

    private func requestUninstall(for app: AppRecord) {
        guard let item = uninstallableHomebrewItemForApp(app), item.kind == .cask else { return }
        onRequestUninstallHomebrewItem(item)
    }

    private func isRecentlyUpdatedAppsSection(_ section: MenuSection) -> Bool {
        section.id == "recentlyUpdated" && section.showsUpdatedOnDate
    }

    private func showsBlurredShowMoreOverlay(in section: MenuSection) -> Bool {
        isRecentlyUpdatedAppsSection(section)
            && !isShowingAllRecentlyUpdated
            && section.apps.count > recentlyUpdatedPreviewLimit
    }

    private func appsForCurrentState(in section: MenuSection) -> [AppRecord] {
        guard isRecentlyUpdatedAppsSection(section) else { return section.apps }

        if isShowingAllRecentlyUpdated {
            return Array(section.apps.prefix(recentlyUpdatedExpandedLimit))
        }

        return Array(section.apps.prefix(recentlyUpdatedPreviewLimit))
    }

    private func showAllRecentlyUpdated() {
        withAnimation(showMoreAnimation) {
            isShowingAllRecentlyUpdated = true
        }
    }

    private var showMoreAnimation: Animation {
        .spring(response: 0.26, dampingFraction: 0.9)
    }

    private func toggleSection(_ sectionID: String) {
        withAnimation(sectionToggleAnimation) {
            if collapsedSectionIDs.contains(sectionID) {
                collapsedSectionIDs.remove(sectionID)
            } else {
                collapsedSectionIDs.insert(sectionID)
            }
        }
    }

    private var sectionToggleAnimation: Animation {
        .spring(response: 0.28, dampingFraction: 0.88)
    }

    private var sectionContentTransition: AnyTransition {
        .move(edge: .top).combined(with: .opacity)
    }

    private var sectionRowTransition: AnyTransition {
        .move(edge: .top).combined(with: .opacity)
    }

}

private struct HomebrewContentCard: View {
    let showsDiscoverSection: Bool
    let discoverSectionTitle: String
    let discoverItems: [HomebrewCaskDiscoveryItem]
    let sections: [HomebrewSection]
    @Binding var collapsedSectionIDs: Set<String>
    let ignoredHomebrewItemIDs: Set<String>
    let isRunningHomebrewMaintenance: Bool
    let isHomebrewUpdateAllUpdatedPendingRefresh: Bool
    let isUpdatingHomebrewItem: (HomebrewManagedItem) -> Bool
    let homebrewUpdateProgress: (HomebrewManagedItem) -> Double?
    let isHomebrewItemUpdateFailed: (HomebrewManagedItem) -> Bool
    let isUninstallingHomebrewItem: (HomebrewManagedItem) -> Bool
    let isHomebrewItemUpdatedPendingRefresh: (HomebrewManagedItem) -> Bool
    let onUpdateAllHomebrew: () -> Void
    let iconAppearance: IconAppearance
    let iconForItem: (HomebrewManagedItem, IconAppearance) -> NSImage
    let canOpenFromIcon: (HomebrewManagedItem) -> Bool
    let onOpenFromIcon: (HomebrewManagedItem) -> Void
    let releaseDateForItem: (HomebrewManagedItem) -> Date
    let recentlyUpdatedDateForItem: (HomebrewManagedItem) -> Date?
    let onToggleIgnore: (HomebrewManagedItem) -> Void
    let onUpdate: (HomebrewManagedItem) -> Void
    let onRequestUninstall: (HomebrewManagedItem) -> Void
    let onRequestInstall: (HomebrewCaskDiscoveryItem) -> Void
    let iconForDiscoverItem: (HomebrewCaskDiscoveryItem, IconAppearance) -> NSImage
    let canOpenDiscoverFromIcon: (HomebrewCaskDiscoveryItem) -> Bool
    let onOpenDiscoverFromIcon: (HomebrewCaskDiscoveryItem) -> Void
    let isInstallingDiscoverItem: (HomebrewCaskDiscoveryItem) -> Bool
    let discoverInstallProgress: (HomebrewCaskDiscoveryItem) -> Double?
    let isDiscoverInstallFailed: (HomebrewCaskDiscoveryItem) -> Bool
    let isDiscoverInstalledPendingRefresh: (HomebrewCaskDiscoveryItem) -> Bool

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if showsDiscoverSection {
                    CollapsibleSectionHeaderView(
                        title: discoverSectionTitle,
                        canCollapse: false,
                        isExpanded: true,
                        onToggleExpanded: {}
                    ) {
                        EmptyView()
                    }
                    .menuSectionHeaderStyle()

                    if discoverItems.isEmpty {
                        Text("No matching installable casks.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 8)
                            .padding(.vertical, 6)
                    } else {
                        ForEach(Array(discoverItems.enumerated()), id: \.element.id) { index, item in
                            HomebrewDiscoverRowView(
                                icon: Image(nsImage: iconForDiscoverItem(item, iconAppearance)),
                                item: item,
                                canOpenFromIcon: canOpenDiscoverFromIcon(item),
                                isInstalling: isInstallingDiscoverItem(item),
                                installProgress: discoverInstallProgress(item),
                                isInstallFailed: isDiscoverInstallFailed(item),
                                isInstalledPendingRefresh: isDiscoverInstalledPendingRefresh(item),
                                onOpenFromIcon: { onOpenDiscoverFromIcon(item) },
                                onRequestInstall: { requestInstall(for: item) }
                            )

                            if index < discoverItems.count - 1 {
                                SubtleRowDivider()
                            }
                        }
                    }

                    if !sections.isEmpty {
                        SubtleSectionDivider()
                    }
                }

                ForEach(sections) { section in
                    let canCollapse = section.isCollapsible
                    let isExpanded = !canCollapse || !collapsedSectionIDs.contains(section.id)

                    CollapsibleSectionHeaderView(
                        title: section.title,
                        canCollapse: canCollapse,
                        isExpanded: isExpanded,
                        onToggleExpanded: { toggleSection(section.id) }
                    ) {
                        if section.showsUpdateAllButton, section.items.count > 1 {
                            UpdateActionButton(
                                state: isRunningHomebrewMaintenance
                                    ? .updating(progress: nil)
                                    : (isHomebrewUpdateAllUpdatedPendingRefresh ? .done : .ready),
                                onUpdate: onUpdateAllHomebrew,
                                readyLabel: "Update All"
                            )
                        }
                    }
                    .menuSectionHeaderStyle()

                    if isExpanded {
                        let visibleItems = Array(section.items.enumerated())
                        if section.items.isEmpty {
                            Text(section.emptyStateMessage)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 8)
                                .padding(.vertical, 6)
                                .transition(sectionContentTransition)
                        } else {
                            ForEach(visibleItems, id: \.element.id) { index, item in
                                HomebrewRowView(
                                    icon: Image(nsImage: iconForItem(item, iconAppearance)),
                                    item: item,
                                    releaseDate: releaseDateForItem(item),
                                    recentlyUpdatedDate: section.showsUpdatedOnDate ? recentlyUpdatedDateForItem(item) : nil,
                                    canOpenFromIcon: canOpenFromIcon(item),
                                    isUpdating: isUpdatingHomebrewItem(item),
                                    updateProgress: homebrewUpdateProgress(item),
                                    isUpdateFailed: isHomebrewItemUpdateFailed(item),
                                    isUninstalling: isUninstallingHomebrewItem(item),
                                    isUpdatedPendingRefresh: isHomebrewItemUpdatedPendingRefresh(item),
                                    isIgnored: ignoredHomebrewItemIDs.contains(item.id),
                                    onOpenFromIcon: { onOpenFromIcon(item) },
                                    onToggleIgnore: { onToggleIgnore(item) },
                                    onUpdate: { onUpdate(item) },
                                    onRequestUninstall: { requestUninstall(for: item) }
                                )
                                .transition(sectionRowTransition)

                                if index < visibleItems.count - 1 {
                                    SubtleRowDivider()
                                }
                            }
                        }
                    }

                    if section.id != sections.last?.id {
                        SubtleSectionDivider()
                    }
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
        }
        .scrollIndicators(.hidden)
        .menuListContainerStyle()
    }

    private func requestUninstall(for item: HomebrewManagedItem) {
        guard item.kind == .cask else { return }
        onRequestUninstall(item)
    }

    private func requestInstall(for item: HomebrewCaskDiscoveryItem) {
        onRequestInstall(item)
    }

    private func toggleSection(_ sectionID: String) {
        withAnimation(sectionToggleAnimation) {
            if collapsedSectionIDs.contains(sectionID) {
                collapsedSectionIDs.remove(sectionID)
            } else {
                collapsedSectionIDs.insert(sectionID)
            }
        }
    }

    private var sectionToggleAnimation: Animation {
        .spring(response: 0.28, dampingFraction: 0.88)
    }

    private var sectionContentTransition: AnyTransition {
        .move(edge: .top).combined(with: .opacity)
    }

    private var sectionRowTransition: AnyTransition {
        .move(edge: .top).combined(with: .opacity)
    }

}

private struct RecentlyUpdatedShowMoreOverlay: View {
    let onShowMore: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            Rectangle()
                .fill(.clear)
                .background(.regularMaterial)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .clear, location: 0.72),
                            .init(color: .white.opacity(0.6), location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(maxWidth: .infinity)
                .frame(height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .allowsHitTesting(false)
                .frame(maxHeight: .infinity, alignment: .bottom)

            Button(action: onShowMore) {
                Text("Show more")
                    .font(.caption.weight(.semibold))
                    .frame(width: 108)
                    .padding(.vertical, 5)
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .menuHoverable()
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}

private struct HomebrewDiscoverRowView: View {
    let icon: Image
    let item: HomebrewCaskDiscoveryItem
    let canOpenFromIcon: Bool
    let isInstalling: Bool
    let installProgress: Double?
    let isInstallFailed: Bool
    let isInstalledPendingRefresh: Bool
    let onOpenFromIcon: () -> Void
    let onRequestInstall: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: MenuPresentationMetrics.rowContentSpacing) {
            iconView

            VStack(alignment: .leading, spacing: MenuPresentationMetrics.rowMetadataSpacing) {
                Text(item.displayName)
                    .font(.body.weight(.semibold))

                Text("\(item.kind.displayName): \(item.token)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(versionLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: MenuPresentationMetrics.rowTrailingSpacerMinLength)

            UpdateActionButton(
                state: installState,
                onUpdate: onRequestInstall,
                readyLabel: "Install"
            )
        }
        .padding(.vertical, MenuPresentationMetrics.rowVerticalPadding)
        .compositingGroup()
        .clipped()
    }

    @ViewBuilder
    private var iconView: some View {
        if canOpenFromIcon {
            Button(action: onOpenFromIcon) {
                rowIcon
            }
            .buttonStyle(.plain)
            .help("Open Homebrew Page")
            .menuHoverable()
        } else {
            rowIcon
        }
    }

    private var rowIcon: some View {
        icon
            .resizable()
            .interpolation(.high)
            .frame(
                width: MenuPresentationMetrics.rowIconSize,
                height: MenuPresentationMetrics.rowIconSize
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: MenuPresentationMetrics.rowIconCornerRadius,
                    style: .continuous
                )
            )
    }

    private var installState: UpdateActionButton.State {
        if isInstallFailed {
            return .failed
        }
        if isInstalling {
            return .updating(progress: installProgress)
        }
        if isInstalledPendingRefresh {
            return .done
        }
        return .ready
    }

    private var versionLine: String {
        let raw = item.version.raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let firstSegment = raw.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false).first else {
            return raw
        }
        return "Version: \(String(firstSegment))"
    }
}

private struct SubtleRowDivider: View {
    var body: some View {
        Rectangle()
            .fill(.quaternary.opacity(0.3))
            .frame(maxWidth: .infinity)
            .frame(height: 0.8)
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
    }
}

private struct SubtleSectionDivider: View {
    var body: some View {
        Rectangle()
            .fill(.quaternary.opacity(0.38))
            .frame(maxWidth: .infinity)
            .frame(height: 1.0)
            .padding(.vertical, 5)
    }
}

private struct CollapsibleSectionHeaderView<TrailingContent: View>: View {
    let title: String
    let canCollapse: Bool
    let isExpanded: Bool
    let onToggleExpanded: () -> Void
    @ViewBuilder let trailingContent: () -> TrailingContent

    var body: some View {
        HStack(spacing: 8) {
            if canCollapse {
                Button(action: onToggleExpanded) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .animation(.spring(response: 0.25, dampingFraction: 0.9), value: isExpanded)
                        Text(title)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .menuHoverable()
            } else {
                Text(title)
                    .padding(.leading, nonCollapsibleTitleInset)
            }

            Spacer()
            trailingContent()
        }
    }

    private var nonCollapsibleTitleInset: CGFloat {
        // Keep non-collapsible section titles aligned with titles that include a chevron glyph.
        14
    }
}

private struct HomebrewRowView: View {
    let icon: Image
    let item: HomebrewManagedItem
    let releaseDate: Date
    let recentlyUpdatedDate: Date?
    let canOpenFromIcon: Bool
    let isUpdating: Bool
    let updateProgress: Double?
    let isUpdateFailed: Bool
    let isUninstalling: Bool
    let isUpdatedPendingRefresh: Bool
    let isIgnored: Bool
    let onOpenFromIcon: () -> Void
    let onToggleIgnore: () -> Void
    let onUpdate: () -> Void
    let onRequestUninstall: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: MenuPresentationMetrics.rowContentSpacing) {
            iconView

            VStack(alignment: .leading, spacing: MenuPresentationMetrics.rowMetadataSpacing) {
                Text(item.name)
                    .font(.body.weight(.semibold))

                Text(versionLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(dateLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: MenuPresentationMetrics.rowTrailingSpacerMinLength)

            HStack(spacing: 7) {
                if item.kind == .cask {
                    Button(action: onRequestUninstall) {
                        if isUninstalling {
                            HomebrewUninstallActionGlyphView()
                        } else {
                            Image(systemName: "trash")
                        }
                    }
                    .menuDestructiveIconButtonStyle()
                    .help("Uninstall \(item.name)")
                    .disabled(isUpdating || isUninstalling)
                }

                IgnoreActionIconButton(
                    isIgnored: isIgnored,
                    onToggleIgnore: onToggleIgnore
                )
                .disabled(isUninstalling)

                if item.isOutdated {
                    UpdateActionButton(
                        state: homebrewUpdateState,
                        onUpdate: onUpdate
                    )
                    .disabled(isUninstalling)
                }
            }
        }
        .padding(.vertical, MenuPresentationMetrics.rowVerticalPadding)
        .ignoredRowStyle(isIgnored: isIgnored)
        .compositingGroup()
        .clipped()
    }

    @ViewBuilder
    private var iconView: some View {
        if canOpenFromIcon {
            Button(action: onOpenFromIcon) {
                rowIcon
            }
            .buttonStyle(.plain)
            .help("Open App")
            .menuHoverable(isEnabled: !isUninstalling)
            .disabled(isUninstalling)
        } else {
            rowIcon
        }
    }

    private var rowIcon: some View {
        icon
            .resizable()
            .interpolation(.high)
            .frame(
                width: MenuPresentationMetrics.rowIconSize,
                height: MenuPresentationMetrics.rowIconSize
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: MenuPresentationMetrics.rowIconCornerRadius,
                    style: .continuous
                )
            )
    }

    private var versionLine: String {
        if let latest = item.latestVersion {
            return "\(displayVersion(item.installedVersion)) -> \(displayVersion(latest))"
        }
        return displayVersion(item.installedVersion)
    }

    private func displayVersion(_ version: Version) -> String {
        guard item.kind == .cask else {
            return version.raw
        }
        let raw = version.raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let firstSegment = raw.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false).first else {
            return raw
        }
        return String(firstSegment)
    }

    private var dateLine: String {
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
        HomebrewRowView.releaseDateFormatter.string(from: date)
    }

    private static let releaseDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d MMM yyyy"
        return formatter
    }()

    private var homebrewUpdateState: UpdateActionButton.State {
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

struct HomebrewUninstallActionGlyphView: View {
    @State private var isAnimating = false

    var body: some View {
        Image(systemName: "trash")
            .scaleEffect(isAnimating ? 1.08 : 0.92)
            .opacity(isAnimating ? 1.0 : 0.75)
            .rotationEffect(.degrees(isAnimating ? 360 : 0))
            .onAppear {
                isAnimating = true
            }
            .animation(
                .linear(duration: 1.05).repeatForever(autoreverses: false),
                value: isAnimating
            )
            .animation(
                .easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                value: isAnimating
            )
    }
}

private struct MenuSection: Identifiable {
    let id: String
    let title: String
    let apps: [AppRecord]
    let showsUpdatedOnDate: Bool

    init(id: String? = nil, title: String, apps: [AppRecord], showsUpdatedOnDate: Bool = false) {
        self.id = id ?? title
        self.title = title
        self.apps = apps
        self.showsUpdatedOnDate = showsUpdatedOnDate
    }

    var isCollapsible: Bool {
        id != "available"
    }

    var emptyStateMessage: String {
        switch id {
        case "available":
            return "All your apps are up to date."
        case "recentlyUpdated":
            return "You haven't updated any apps recently."
        case "installed":
            return "No installed apps found."
        case "ignored":
            return "You haven't ignored any apps."
        default:
            return "No apps in this section."
        }
    }
}

private struct HomebrewSection: Identifiable {
    let id: String
    let title: String
    let items: [HomebrewManagedItem]
    let showsUpdatedOnDate: Bool
    let showsUpdateAllButton: Bool

    init(
        id: String? = nil,
        title: String,
        items: [HomebrewManagedItem],
        showsUpdatedOnDate: Bool = false,
        showsUpdateAllButton: Bool = false
    ) {
        self.id = id ?? title
        self.title = title
        self.items = items
        self.showsUpdatedOnDate = showsUpdatedOnDate
        self.showsUpdateAllButton = showsUpdateAllButton
    }

    var isCollapsible: Bool {
        id != "outdated"
    }

    var emptyStateMessage: String {
        switch id {
        case "outdated":
            return "All your Homebrew items are up to date."
        case "recentlyUpdated":
            return "You haven't updated any Homebrew items recently."
        case "installed":
            return "No installed Homebrew items found."
        case "ignored":
            return "You haven't ignored any Homebrew items."
        default:
            return "No items in this section."
        }
    }
}
