import AppKit
import SwiftUI

struct SettingsView: View {
    @Bindable var store: UpdateStore
    @Environment(\.openURL) private var openURL
    @State private var showsMasInstallPrompt = false
    @State private var diagnosticsCopyMessage: String?

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            ScrollView {
                VStack(spacing: 12) {
                    SettingsHeaderCard(
                        isRefreshing: store.isRefreshing,
                        lastRefreshDate: store.lastRefreshDate,
                        onRefresh: { store.refreshNow() }
                    )

                    SettingsSectionVisibilityCard(
                        showInstalledAppsSection: $store.showInstalledAppsSection,
                        showRecentlyUpdatedAppsSection: $store.showRecentlyUpdatedAppsSection,
                        showIgnoredAppsSection: $store.showIgnoredAppsSection,
                        showRecentlyUpdatedHomebrewSection: $store.showRecentlyUpdatedHomebrewSection,
                        showInstalledHomebrewSection: $store.showInstalledHomebrewSection,
                        showIgnoredHomebrewSection: $store.showIgnoredHomebrewSection
                    )

                    SettingsMasSetupCard(
                        useMasForAppStoreUpdates: $store.useMasForAppStoreUpdates,
                        isMasInstalled: store.isMasInstalled,
                        isHomebrewInstalledForMasInstall: store.isHomebrewInstalledForMasInstall,
                        isCheckingMas: store.isCheckingMas,
                        isTestingMas: store.isTestingMas,
                        isInstallingMas: store.isInstallingMas,
                        masTestMessage: store.masTestMessage,
                        messageColor: messageColor,
                        onCheckAgain: store.refreshMasSetupStatus,
                        onTest: store.testMasSetup,
                        onInstall: {
                            store.refreshMasSetupStatus()
                            showsMasInstallPrompt = true
                        }
                    )

                    SettingsOptionalToolsCard(
                        isMasInstalled: store.isMasInstalled,
                        isHomebrewInstalled: store.isHomebrewInstalledForMasInstall,
                        useMasForAppStoreUpdates: store.useMasForAppStoreUpdates
                    )

                    SettingsDirectoriesCard(
                        scanDirectories: store.scanDirectories,
                        additionalDirectories: store.additionalDirectories,
                        onAddDirectory: store.chooseAndAddDirectory,
                        onRemoveDirectory: store.removeDirectory(_:)
                    )

                    SettingsRefreshIntervalCard(
                        refreshIntervalMinutes: $store.refreshIntervalMinutes,
                        autoRefreshEnabled: $store.autoRefreshEnabled
                    )

                    SettingsDiagnosticsCard(
                        copyMessage: diagnosticsCopyMessage,
                        onCopy: copyDiagnosticsReport
                    )
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(12)
            }
        }
        .onAppear {
            store.refreshMasSetupStatus()
        }
        .onChange(of: store.useMasForAppStoreUpdates) { _, newValue in
            if newValue && !store.isMasInstalled {
                showsMasInstallPrompt = true
            }
        }
        .sheet(isPresented: $showsMasInstallPrompt) {
            SettingsMasInstallSheet(
                isInstallingMas: store.isInstallingMas,
                isHomebrewInstalledForMasInstall: store.isHomebrewInstalledForMasInstall,
                onInstallAutomatically: store.installMasWithHomebrew,
                onOpenGuide: {
                    if let url = URL(string: "https://formulae.brew.sh/formula/mas") {
                        openURL(url)
                    }
                },
                onClose: { showsMasInstallPrompt = false }
            )
        }
    }

    private func copyDiagnosticsReport() {
        let report = store.diagnosticsReport().render()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(report, forType: .string)
        diagnosticsCopyMessage = "Diagnostics copied. Review before sharing."
    }

    private var messageColor: Color {
        if store.masTestSucceeded == true {
            return .green
        }
        if store.masTestSucceeded == false {
            return .orange
        }
        return .secondary
    }
}

private struct SettingsOptionalToolsCard: View {
    let isMasInstalled: Bool
    let isHomebrewInstalled: Bool
    let useMasForAppStoreUpdates: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Readiness")
                    .font(.headline)
                Text("Baseline works without optional tools, but direct update actions improve when they are available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SettingsReadinessRow(
                title: "Homebrew",
                value: isHomebrewInstalled ? "Available" : "Not detected",
                isReady: isHomebrewInstalled,
                detail: isHomebrewInstalled
                    ? "Homebrew cask and formula actions can run locally."
                    : "Baseline will use external Homebrew pages for install or update actions."
            )

            SettingsReadinessRow(
                title: "mas",
                value: isMasInstalled ? "Available" : "Not detected",
                isReady: isMasInstalled,
                detail: isMasInstalled && useMasForAppStoreUpdates
                    ? "App Store updates can start through mas when an item ID is available."
                    : "App Store updates fall back to opening the App Store page."
            )
        }
        .menuCardStyle()
    }
}

private struct SettingsReadinessRow: View {
    let title: String
    let value: String
    let isReady: Bool
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(isReady ? Color.green : Color.gray)
                .frame(width: 10, height: 10)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 1) {
                HStack {
                    Text(title)
                        .font(.callout.weight(.semibold))
                    Text(value)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
    }
}

private struct SettingsDiagnosticsCard: View {
    let copyMessage: String?
    let onCopy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Diagnostics")
                        .font(.headline)
                    Text("Copy a local report with counts, tool status, scan paths, and the latest non-sensitive refresh message.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Copy Report", action: onCopy)
                    .menuSecondaryButtonStyle()
                    .controlSize(.small)
            }

            if let copyMessage {
                Text(copyMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .menuCardStyle()
    }
}

private struct SettingsHeaderCard: View {
    let isRefreshing: Bool
    let lastRefreshDate: Date?
    let onRefresh: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Baseline Settings")
                    .font(.headline)
                Text("Customize menu sections, scan paths, and refresh behavior.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let lastRefreshDate {
                    Text("Last refresh \(lastRefreshDate.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .padding(.top, 2)
            }

            Button("Refresh Now", action: onRefresh)
                .menuUpdateButtonStyle()
                .controlSize(.small)
                .disabled(isRefreshing)
        }
        .menuCardStyle()
    }
}

private struct SettingsSectionVisibilityCard: View {
    @Binding var showInstalledAppsSection: Bool
    @Binding var showRecentlyUpdatedAppsSection: Bool
    @Binding var showIgnoredAppsSection: Bool
    @Binding var showRecentlyUpdatedHomebrewSection: Bool
    @Binding var showInstalledHomebrewSection: Bool
    @Binding var showIgnoredHomebrewSection: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Visible Sections")
                .font(.headline)

            SettingsToggleGroup(title: "Apps") {
                Text("Available is always shown.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 2)

                SettingsCheckboxRow(
                    title: "Installed",
                    subtitle: "Apps without currently available updates.",
                    isOn: $showInstalledAppsSection
                )
                SettingsCheckboxRow(
                    title: "Recently Updated",
                    subtitle: "Apps updated recently and no longer outdated.",
                    isOn: $showRecentlyUpdatedAppsSection
                )
                SettingsCheckboxRow(
                    title: "Ignored",
                    subtitle: "Apps explicitly ignored in the menu.",
                    isOn: $showIgnoredAppsSection
                )
            }

            Divider()

            SettingsToggleGroup(title: "Homebrew") {
                Text("Outdated is always shown.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 2)

                SettingsCheckboxRow(
                    title: "Recently Updated",
                    subtitle: "Homebrew items updated recently.",
                    isOn: $showRecentlyUpdatedHomebrewSection
                )
                SettingsCheckboxRow(
                    title: "Installed",
                    subtitle: "Installed formulas and casks without available updates.",
                    isOn: $showInstalledHomebrewSection
                )
                SettingsCheckboxRow(
                    title: "Ignored",
                    subtitle: "Formulas and casks explicitly ignored in the menu.",
                    isOn: $showIgnoredHomebrewSection
                )
            }
        }
        .menuCardStyle()
    }
}

private struct SettingsMasSetupCard: View {
    @Binding var useMasForAppStoreUpdates: Bool

    let isMasInstalled: Bool
    let isHomebrewInstalledForMasInstall: Bool
    let isCheckingMas: Bool
    let isTestingMas: Bool
    let isInstallingMas: Bool
    let masTestMessage: String?
    let messageColor: Color

    let onCheckAgain: () -> Void
    let onTest: () -> Void
    let onInstall: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("App Store Update Helper")
                .font(.headline)

            Toggle("Use mas for App Store updates", isOn: $useMasForAppStoreUpdates)
                .toggleStyle(.checkbox)

            Text("With mas installed, Baseline can start App Store updates for you automatically, so you don't have to open the App Store and update manually.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Circle()
                    .fill(isMasInstalled ? Color.green : Color.gray)
                    .frame(width: 10, height: 10)

                Text(isMasInstalled ? "mas is installed" : "mas is not installed yet")
                    .font(.callout)

                if isCheckingMas {
                    ProgressView()
                        .controlSize(.small)
                }

                Spacer()

                Button("Check Again", action: onCheckAgain)
                    .menuSecondaryButtonStyle()
                    .controlSize(.small)
                    .disabled(isCheckingMas || isInstallingMas)
            }

            HStack(spacing: 8) {
                Button(isTestingMas ? "Testing mas..." : "Test mas", action: onTest)
                    .menuUpdateButtonStyle()
                    .controlSize(.small)
                    .disabled(!isMasInstalled || isTestingMas || isCheckingMas || isInstallingMas)

                if !isMasInstalled {
                    Button("Install mas", action: onInstall)
                        .menuSecondaryButtonStyle()
                        .controlSize(.small)
                        .disabled(isInstallingMas)
                }
            }

            if let masTestMessage {
                Text(masTestMessage)
                    .font(.caption)
                    .foregroundStyle(messageColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !isHomebrewInstalledForMasInstall {
                Text("Automatic install requires Homebrew.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .menuCardStyle()
    }
}

private struct SettingsDirectoriesCard: View {
    let scanDirectories: [URL]
    let additionalDirectories: [URL]
    let onAddDirectory: () -> Void
    let onRemoveDirectory: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("App Directories")
                        .font(.headline)
                    Text("Baseline scans default and custom app locations.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Add Directory", action: onAddDirectory)
                    .menuSecondaryButtonStyle()
                    .controlSize(.small)
            }

            List {
                ForEach(scanDirectories, id: \.path) { directory in
                    HStack(spacing: 8) {
                        Text(directory.path)
                            .font(.caption)
                            .textSelection(.enabled)
                        Spacer(minLength: 8)
                        if canRemove(directory) {
                            Button("Remove") {
                                onRemoveDirectory(directory)
                            }
                            .menuSecondaryButtonStyle(controlSize: .mini)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .frame(minHeight: 160, maxHeight: 190)
            .scrollContentBackground(.hidden)
            .listStyle(.inset)
            .menuListContainerStyle()
        }
        .menuCardStyle()
    }

    private func canRemove(_ directory: URL) -> Bool {
        additionalDirectories.contains { $0.standardizedFileURL == directory.standardizedFileURL }
    }
}

private struct SettingsRefreshIntervalCard: View {
    @Binding var refreshIntervalMinutes: Int
    @Binding var autoRefreshEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Refresh Interval")
                        .font(.headline)
                    Text("Background refresh cadence in minutes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Stepper(value: $refreshIntervalMinutes, in: 5...1_440) {
                    Text("\(refreshIntervalMinutes) min")
                        .font(.body)
                        .monospacedDigit()
                }
                .frame(width: 180)
                .disabled(!autoRefreshEnabled)
            }

            Toggle("Enable automatic background refresh", isOn: $autoRefreshEnabled)
                .toggleStyle(.checkbox)

            Text("Baseline checks Apple, Sparkle feeds, and Homebrew endpoints when refreshing for updates.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !autoRefreshEnabled {
                Text("Automatic checks are off. Use Refresh Now when you want to fetch updates.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .menuCardStyle()
    }
}

private struct SettingsMasInstallSheet: View {
    let isInstallingMas: Bool
    let isHomebrewInstalledForMasInstall: Bool
    let onInstallAutomatically: () -> Void
    let onOpenGuide: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Install mas")
                .font(.title3.weight(.semibold))

            Text("mas is a trusted command-line helper for the Mac App Store. It helps Baseline start App Store updates for you in one click.")
                .font(.callout)

            if isHomebrewInstalledForMasInstall {
                Text("Automatic install is available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Automatic install needs Homebrew. You can still use the install guide.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button(isInstallingMas ? "Installing..." : "Install automatically", action: onInstallAutomatically)
                    .menuHoverable(isEnabled: isHomebrewInstalledForMasInstall && !isInstallingMas)
                    .disabled(!isHomebrewInstalledForMasInstall || isInstallingMas)

                Button("Open install guide", action: onOpenGuide)
                    .menuHoverable()

                Spacer()

                Button("Not now", action: onClose)
                    .menuHoverable()
            }
        }
        .padding()
        .frame(width: 520)
    }
}

private struct SettingsToggleGroup<Content: View>: View {
    let title: String
    let content: () -> Content

    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            content()
        }
    }
}

private struct SettingsCheckboxRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.callout)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.checkbox)
    }
}
