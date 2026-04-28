import AppKit
import Foundation
import Observation

enum LookupOutcome<Value: Sendable>: Sendable {
    case completed(value: Value?)
    case transientFailure
}

struct HomebrewCommandResult: Sendable {
    let didComplete: Bool
    let output: String?

    init(didComplete: Bool, output: String? = nil) {
        self.didComplete = didComplete
        self.output = output
    }
}

struct UpdateStoreDependencies {
    var scanApplications: @Sendable ([URL]) async -> [AppRecord]
    var lookupAppStore: @Sendable (String, Version) async -> AppStoreLookupResult?
    var lookupAppStoreOutcome: @Sendable (String, Version) async -> LookupOutcome<AppStoreLookupResult>
    var lookupSparkle: @Sendable (URL, Version) async -> SparkleLookupResult?
    var lookupSparkleOutcome: @Sendable (URL, Version) async -> LookupOutcome<SparkleLookupResult>
    var fetchHomebrewIndex: @Sendable () async -> HomebrewCaskIndex
    var fetchHomebrewFormulaIndex: @Sendable () async -> HomebrewFormulaIndex
    var lookupHomebrew: @Sendable (HomebrewCaskIndex, String?, String, Version) async -> HomebrewLookupResult?
    var lookupHomebrewOutcome: @Sendable (HomebrewCaskIndex, String?, String, Version) async -> LookupOutcome<HomebrewLookupResult>
    var searchHomebrewCasks: @Sendable (HomebrewCaskIndex, String, Set<String>) async -> [HomebrewCaskDiscoveryItem]
    var searchHomebrewFormulae: @Sendable (HomebrewFormulaIndex, String, Set<String>) async -> [HomebrewCaskDiscoveryItem]
    var fetchHomebrewInventory: @Sendable () async -> [HomebrewManagedItem]
    var checkMasInstalled: @Sendable () async -> Bool
    var checkMasSignedIn: @Sendable () async -> Bool
    var checkHomebrewInstalled: @Sendable () async -> Bool
    var installMasUsingHomebrew: @Sendable () async -> Bool
    var runAppStoreUpgrade: @Sendable (Int) async -> Bool
    var runHomebrewUpgrade: @Sendable (String) async -> Bool
    var runHomebrewUpgradeWithEvents: @Sendable (String, @escaping @Sendable (HomebrewMaintenanceRunEvent) -> Void) async -> Bool
    var runHomebrewItemUpgrade: @Sendable (HomebrewManagedItemKind, String) async -> Bool
    var runHomebrewItemUpgradeWithEvents: @Sendable (HomebrewManagedItemKind, String, @escaping @Sendable (HomebrewMaintenanceRunEvent) -> Void) async -> Bool
    var runHomebrewCaskInstall: @Sendable (String) async -> Bool
    var runHomebrewCaskInstallWithEvents: @Sendable (String, @escaping @Sendable (HomebrewMaintenanceRunEvent) -> Void) async -> Bool
    var runHomebrewFormulaInstall: @Sendable (String) async -> Bool
    var runHomebrewFormulaInstallWithEvents: @Sendable (String, @escaping @Sendable (HomebrewMaintenanceRunEvent) -> Void) async -> Bool
    var runHomebrewCaskUninstall: @Sendable (String) async -> Bool
    var runHomebrewCaskUninstallWithOutput: @Sendable (String) async -> HomebrewCommandResult
    var runHomebrewMaintenanceCycle: @Sendable (@escaping @Sendable (HomebrewMaintenanceRunEvent) -> Void) async -> Bool
    var openExternalURL: @Sendable (URL) -> Void
    var openAppBundle: @Sendable (URL) -> Void

    init(
        scanApplications: @escaping @Sendable ([URL]) async -> [AppRecord],
        lookupAppStore: @escaping @Sendable (String, Version) async -> AppStoreLookupResult?,
        lookupAppStoreOutcome: (@Sendable (String, Version) async -> LookupOutcome<AppStoreLookupResult>)? = nil,
        lookupSparkle: @escaping @Sendable (URL, Version) async -> SparkleLookupResult?,
        lookupSparkleOutcome: (@Sendable (URL, Version) async -> LookupOutcome<SparkleLookupResult>)? = nil,
        fetchHomebrewIndex: @escaping @Sendable () async -> HomebrewCaskIndex,
        fetchHomebrewFormulaIndex: @escaping @Sendable () async -> HomebrewFormulaIndex = { .empty },
        lookupHomebrew: @escaping @Sendable (HomebrewCaskIndex, String?, String, Version) async -> HomebrewLookupResult?,
        lookupHomebrewOutcome: (@Sendable (HomebrewCaskIndex, String?, String, Version) async -> LookupOutcome<HomebrewLookupResult>)? = nil,
        searchHomebrewCasks: @escaping @Sendable (HomebrewCaskIndex, String, Set<String>) async -> [HomebrewCaskDiscoveryItem] = { _, _, _ in [] },
        searchHomebrewFormulae: @escaping @Sendable (HomebrewFormulaIndex, String, Set<String>) async -> [HomebrewCaskDiscoveryItem] = { _, _, _ in [] },
        fetchHomebrewInventory: @escaping @Sendable () async -> [HomebrewManagedItem],
        checkMasInstalled: @escaping @Sendable () async -> Bool = { false },
        checkMasSignedIn: @escaping @Sendable () async -> Bool = { false },
        checkHomebrewInstalled: @escaping @Sendable () async -> Bool = { false },
        installMasUsingHomebrew: @escaping @Sendable () async -> Bool = { false },
        runAppStoreUpgrade: @escaping @Sendable (Int) async -> Bool = { _ in false },
        runHomebrewUpgrade: @escaping @Sendable (String) async -> Bool,
        runHomebrewUpgradeWithEvents: (@Sendable (String, @escaping @Sendable (HomebrewMaintenanceRunEvent) -> Void) async -> Bool)? = nil,
        runHomebrewItemUpgrade: @escaping @Sendable (HomebrewManagedItemKind, String) async -> Bool,
        runHomebrewItemUpgradeWithEvents: (@Sendable (HomebrewManagedItemKind, String, @escaping @Sendable (HomebrewMaintenanceRunEvent) -> Void) async -> Bool)? = nil,
        runHomebrewCaskInstall: @escaping @Sendable (String) async -> Bool = { _ in false },
        runHomebrewCaskInstallWithEvents: (@Sendable (String, @escaping @Sendable (HomebrewMaintenanceRunEvent) -> Void) async -> Bool)? = nil,
        runHomebrewFormulaInstall: @escaping @Sendable (String) async -> Bool = { _ in false },
        runHomebrewFormulaInstallWithEvents: (@Sendable (String, @escaping @Sendable (HomebrewMaintenanceRunEvent) -> Void) async -> Bool)? = nil,
        runHomebrewCaskUninstall: @escaping @Sendable (String) async -> Bool = { _ in false },
        runHomebrewCaskUninstallWithOutput: (@Sendable (String) async -> HomebrewCommandResult)? = nil,
        runHomebrewMaintenanceCycle: @escaping @Sendable () async -> Bool,
        runHomebrewMaintenanceCycleWithEvents: (@Sendable (@escaping @Sendable (HomebrewMaintenanceRunEvent) -> Void) async -> Bool)? = nil,
        openExternalURL: @escaping @Sendable (URL) -> Void = { _ in },
        openAppBundle: @escaping @Sendable (URL) -> Void = { _ in }
    ) {
        self.scanApplications = scanApplications
        self.lookupAppStore = lookupAppStore
        self.lookupAppStoreOutcome = lookupAppStoreOutcome ?? { bundleIdentifier, localVersion in
            .completed(value: await lookupAppStore(bundleIdentifier, localVersion))
        }
        self.lookupSparkle = lookupSparkle
        self.lookupSparkleOutcome = lookupSparkleOutcome ?? { feedURL, localVersion in
            .completed(value: await lookupSparkle(feedURL, localVersion))
        }
        self.fetchHomebrewIndex = fetchHomebrewIndex
        self.fetchHomebrewFormulaIndex = fetchHomebrewFormulaIndex
        self.lookupHomebrew = lookupHomebrew
        self.lookupHomebrewOutcome = lookupHomebrewOutcome ?? { index, bundleIdentifier, appBundleName, localVersion in
            .completed(value: await lookupHomebrew(index, bundleIdentifier, appBundleName, localVersion))
        }
        self.searchHomebrewCasks = searchHomebrewCasks
        self.searchHomebrewFormulae = searchHomebrewFormulae
        self.fetchHomebrewInventory = fetchHomebrewInventory
        self.checkMasInstalled = checkMasInstalled
        self.checkMasSignedIn = checkMasSignedIn
        self.checkHomebrewInstalled = checkHomebrewInstalled
        self.installMasUsingHomebrew = installMasUsingHomebrew
        self.runAppStoreUpgrade = runAppStoreUpgrade
        self.runHomebrewUpgrade = runHomebrewUpgrade
        self.runHomebrewUpgradeWithEvents = runHomebrewUpgradeWithEvents ?? { token, _ in
            await runHomebrewUpgrade(token)
        }
        self.runHomebrewItemUpgrade = runHomebrewItemUpgrade
        self.runHomebrewItemUpgradeWithEvents = runHomebrewItemUpgradeWithEvents ?? { kind, token, _ in
            await runHomebrewItemUpgrade(kind, token)
        }
        self.runHomebrewCaskInstall = runHomebrewCaskInstall
        self.runHomebrewCaskInstallWithEvents = runHomebrewCaskInstallWithEvents ?? { token, _ in
            await runHomebrewCaskInstall(token)
        }
        self.runHomebrewFormulaInstall = runHomebrewFormulaInstall
        self.runHomebrewFormulaInstallWithEvents = runHomebrewFormulaInstallWithEvents ?? { token, _ in
            await runHomebrewFormulaInstall(token)
        }
        self.runHomebrewCaskUninstall = runHomebrewCaskUninstall
        self.runHomebrewCaskUninstallWithOutput = runHomebrewCaskUninstallWithOutput ?? { token in
            HomebrewCommandResult(didComplete: await runHomebrewCaskUninstall(token))
        }
        self.runHomebrewMaintenanceCycle = runHomebrewMaintenanceCycleWithEvents ?? { _ in
            await runHomebrewMaintenanceCycle()
        }
        self.openExternalURL = openExternalURL
        self.openAppBundle = openAppBundle
    }

    static let homebrewMaintenanceCommandSequence: [[String]] = [
        ["update"],
        ["upgrade"],
        ["upgrade", "--cask", "--greedy"],
        ["autoremove"],
        ["cleanup"]
    ]

    static let live: UpdateStoreDependencies = {
        let scanner = BundleScannerClient()
        let appStore = AppStoreLookupClient()
        let sparkle = SparkleAppcastClient()
        let homebrew = HomebrewCaskClient()
        let homebrewFormula = HomebrewFormulaClient()
        let homebrewInventory = HomebrewInventoryClient()

        return UpdateStoreDependencies(
            scanApplications: { directories in
                await scanner.scanApplications(in: directories)
            },
            lookupAppStore: { bundleIdentifier, localVersion in
                await appStore.lookup(bundleIdentifier: bundleIdentifier, localVersion: localVersion)
            },
            lookupAppStoreOutcome: { bundleIdentifier, localVersion in
                await appStore.lookupOutcome(bundleIdentifier: bundleIdentifier, localVersion: localVersion)
            },
            lookupSparkle: { feedURL, localVersion in
                await sparkle.lookup(feedURL: feedURL, localVersion: localVersion)
            },
            lookupSparkleOutcome: { feedURL, localVersion in
                await sparkle.lookupOutcome(feedURL: feedURL, localVersion: localVersion)
            },
            fetchHomebrewIndex: {
                await homebrew.fetchIndex()
            },
            fetchHomebrewFormulaIndex: {
                await homebrewFormula.fetchIndex()
            },
            lookupHomebrew: { index, bundleIdentifier, appBundleName, localVersion in
                await homebrew.lookupUpdate(
                    bundleIdentifier: bundleIdentifier,
                    appBundleName: appBundleName,
                    localVersion: localVersion,
                    in: index
                )
            },
            lookupHomebrewOutcome: { index, bundleIdentifier, appBundleName, localVersion in
                .completed(value: await homebrew.lookupUpdate(
                    bundleIdentifier: bundleIdentifier,
                    appBundleName: appBundleName,
                    localVersion: localVersion,
                    in: index
                ))
            },
            searchHomebrewCasks: { index, query, excludingTokens in
                await homebrew.searchCasks(
                    query: query,
                    in: index,
                    excludingTokens: excludingTokens
                )
            },
            searchHomebrewFormulae: { index, query, excludingTokens in
                await homebrewFormula.searchFormulae(
                    query: query,
                    in: index,
                    excludingTokens: excludingTokens
                )
            },
            fetchHomebrewInventory: {
                await homebrewInventory.fetchInventory()
            },
            checkMasInstalled: {
                await Self.checkMasInstalled()
            },
            checkMasSignedIn: {
                await Self.checkMasSignedIn()
            },
            checkHomebrewInstalled: {
                await Self.checkHomebrewInstalled()
            },
            installMasUsingHomebrew: {
                await Self.installMasUsingHomebrew()
            },
            runAppStoreUpgrade: { itemID in
                await Self.runAppStoreUpgrade(itemID: itemID)
            },
            runHomebrewUpgrade: { token in
                await Self.runHomebrewUpgrade(token: token)
            },
            runHomebrewUpgradeWithEvents: { token, onEvent in
                await Self.runHomebrewUpgrade(token: token, onEvent: onEvent)
            },
            runHomebrewItemUpgrade: { kind, token in
                await Self.runHomebrewItemUpgrade(kind: kind, token: token)
            },
            runHomebrewItemUpgradeWithEvents: { kind, token, onEvent in
                await Self.runHomebrewItemUpgrade(kind: kind, token: token, onEvent: onEvent)
            },
            runHomebrewCaskInstall: { token in
                await Self.runHomebrewCaskInstall(token: token)
            },
            runHomebrewCaskInstallWithEvents: { token, onEvent in
                await Self.runHomebrewCaskInstall(token: token, onEvent: onEvent)
            },
            runHomebrewFormulaInstall: { token in
                await Self.runHomebrewFormulaInstall(token: token)
            },
            runHomebrewFormulaInstallWithEvents: { token, onEvent in
                await Self.runHomebrewFormulaInstall(token: token, onEvent: onEvent)
            },
            runHomebrewCaskUninstall: { token in
                await Self.runHomebrewCaskUninstall(token: token)
            },
            runHomebrewCaskUninstallWithOutput: { token in
                await Self.runHomebrewCaskUninstallWithOutput(token: token)
            },
            runHomebrewMaintenanceCycle: {
                await Self.runHomebrewMaintenanceCycle()
            },
            runHomebrewMaintenanceCycleWithEvents: { onEvent in
                await Self.runHomebrewMaintenanceCycle(onEvent: onEvent)
            },
            openExternalURL: { url in
                NSWorkspace.shared.open(url)
            },
            openAppBundle: { bundleURL in
                NSWorkspace.shared.openApplication(at: bundleURL, configuration: .init())
            }
        )
    }()

    private static func checkMasInstalled() async -> Bool {
        await runMasCommand(["version"])
    }

    private static func checkMasSignedIn() async -> Bool {
        // `mas account` is removed in newer mas; `mas outdated` works across supported versions
        // and succeeds when mas can communicate with the App Store.
        await runMasCommand(["outdated"])
    }

    private static func checkHomebrewInstalled() async -> Bool {
        await runBrewCommand(["--version"])
    }

    private static func installMasUsingHomebrew() async -> Bool {
        await runBrewCommand(["install", "mas"])
    }

    private static func runAppStoreUpgrade(itemID: Int) async -> Bool {
        await runMasCommand(["upgrade", String(itemID)])
    }

    private static func runHomebrewUpgrade(token: String) async -> Bool {
        guard SecurityPolicy.isValidHomebrewToken(token) else { return false }
        return await runBrewCommand(["upgrade", "--cask", token])
    }

    private static func runHomebrewUpgrade(
        token: String,
        onEvent: @escaping @Sendable (HomebrewMaintenanceRunEvent) -> Void
    ) async -> Bool {
        guard SecurityPolicy.isValidHomebrewToken(token) else { return false }
        let command = ["upgrade", "--cask", token]
        onEvent(.commandStarted(command))
        let didComplete = await runBrewCommand(command) { line in
            onEvent(.outputLine(command: command, line: line))
        }
        onEvent(.commandFinished(command: command, success: didComplete))
        return didComplete
    }

    private static func runHomebrewItemUpgrade(kind: HomebrewManagedItemKind, token: String) async -> Bool {
        await runHomebrewItemUpgrade(kind: kind, token: token, onEvent: { _ in })
    }

    private static func runHomebrewItemUpgrade(
        kind: HomebrewManagedItemKind,
        token: String,
        onEvent: @escaping @Sendable (HomebrewMaintenanceRunEvent) -> Void
    ) async -> Bool {
        guard SecurityPolicy.isValidHomebrewToken(token) else { return false }
        let command: [String]
        switch kind {
        case .formula:
            command = ["upgrade", token]
        case .cask:
            command = ["upgrade", "--cask", token]
        }

        onEvent(.commandStarted(command))
        let didComplete = await runBrewCommand(command) { line in
            onEvent(.outputLine(command: command, line: line))
        }
        onEvent(.commandFinished(command: command, success: didComplete))
        return didComplete
    }

    private static func runHomebrewCaskInstall(token: String) async -> Bool {
        await runHomebrewCaskInstall(token: token, onEvent: { _ in })
    }

    private static func runHomebrewCaskInstall(
        token: String,
        onEvent: @escaping @Sendable (HomebrewMaintenanceRunEvent) -> Void
    ) async -> Bool {
        guard SecurityPolicy.isValidHomebrewToken(token) else { return false }
        let command = ["install", "--cask", token]
        onEvent(.commandStarted(command))
        let didComplete = await runBrewCommand(command) { line in
            onEvent(.outputLine(command: command, line: line))
        }
        onEvent(.commandFinished(command: command, success: didComplete))
        return didComplete
    }

    private static func runHomebrewFormulaInstall(token: String) async -> Bool {
        await runHomebrewFormulaInstall(token: token, onEvent: { _ in })
    }

    private static func runHomebrewFormulaInstall(
        token: String,
        onEvent: @escaping @Sendable (HomebrewMaintenanceRunEvent) -> Void
    ) async -> Bool {
        guard SecurityPolicy.isValidHomebrewToken(token) else { return false }
        let command = ["install", token]
        onEvent(.commandStarted(command))
        let didComplete = await runBrewCommand(command) { line in
            onEvent(.outputLine(command: command, line: line))
        }
        onEvent(.commandFinished(command: command, success: didComplete))
        return didComplete
    }

    private static func runHomebrewCaskUninstall(token: String) async -> Bool {
        guard SecurityPolicy.isValidHomebrewToken(token) else { return false }
        return await runBrewCommand(["uninstall", "--cask", token])
    }

    private static func runHomebrewCaskUninstallWithOutput(token: String) async -> HomebrewCommandResult {
        guard SecurityPolicy.isValidHomebrewToken(token) else {
            return HomebrewCommandResult(didComplete: false, output: "Blocked unsafe Homebrew token.")
        }
        let outputCollector = CommandOutputCollector()
        let didComplete = await runBrewCommand(["uninstall", "--cask", token]) { line in
            outputCollector.append(line)
        }
        return HomebrewCommandResult(
            didComplete: didComplete,
            output: outputCollector.normalizedOutput()
        )
    }

    private static func runHomebrewMaintenanceCycle() async -> Bool {
        await runHomebrewMaintenanceCycle(onEvent: { _ in })
    }

    private static func runHomebrewMaintenanceCycle(
        onEvent: @escaping @Sendable (HomebrewMaintenanceRunEvent) -> Void
    ) async -> Bool {
        for command in homebrewMaintenanceCommandSequence {
            onEvent(.commandStarted(command))
            let success = await runBrewCommand(command) { line in
                onEvent(.outputLine(command: command, line: line))
            }
            onEvent(.commandFinished(command: command, success: success))
            if !success {
                return false
            }
        }
        return true
    }

    private static func runBrewCommand(_ arguments: [String]) async -> Bool {
        await runBrewCommand(arguments, onOutputLine: { _ in })
    }

    private static func runBrewCommand(
        _ arguments: [String],
        onOutputLine: @escaping @Sendable (String) -> Void
    ) async -> Bool {
        guard let brewExecutableURL = SecurityPolicy.resolvedBrewExecutableURL() else {
            return false
        }
        return await runCommand(
            executableURL: brewExecutableURL,
            arguments: arguments,
            onOutputLine: onOutputLine
        )
    }

    private static func runMasCommand(_ arguments: [String]) async -> Bool {
        guard let masExecutableURL = SecurityPolicy.resolvedMasExecutableURL() else {
            return false
        }
        return await runCommand(
            executableURL: masExecutableURL,
            arguments: arguments,
            onOutputLine: { _ in }
        )
    }

    private static func runCommand(
        executableURL: URL,
        arguments: [String],
        onOutputLine: @escaping @Sendable (String) -> Void
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            let lineCollector = ProcessLineCollector(onOutputLine: onOutputLine)

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty { return }
                lineCollector.append(data)
            }
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty { return }
                lineCollector.append(data)
            }

            process.terminationHandler = { process in
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                let remainingStdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let remainingStderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                lineCollector.append(remainingStdout)
                lineCollector.append(remainingStderr)
                lineCollector.flush()
                continuation.resume(returning: process.terminationStatus == 0)
            }

            do {
                try process.run()
            } catch {
                continuation.resume(returning: false)
            }
        }
    }

}

private final class ProcessLineCollector: @unchecked Sendable {
    private let onOutputLine: @Sendable (String) -> Void
    private let lock = NSLock()
    private var buffered = Data()

    init(onOutputLine: @escaping @Sendable (String) -> Void) {
        self.onOutputLine = onOutputLine
    }

    func append(_ data: Data) {
        guard !data.isEmpty else { return }

        lock.lock()
        buffered.append(data)

        while let newline = buffered.firstIndex(of: 0x0A) {
            let chunk = buffered[..<newline]
            buffered.removeSubrange(...newline)
            let line = String(data: chunk, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !line.isEmpty {
                onOutputLine(line)
            }
        }
        lock.unlock()
    }

    func flush() {
        lock.lock()
        defer { lock.unlock() }

        guard !buffered.isEmpty else { return }
        let line = String(data: buffered, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        buffered.removeAll(keepingCapacity: false)
        if !line.isEmpty {
            onOutputLine(line)
        }
    }
}

private final class CommandOutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []

    func append(_ line: String) {
        let normalizedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedLine.isEmpty else { return }

        lock.lock()
        lines.append(normalizedLine)
        lock.unlock()
    }

    func normalizedOutput() -> String? {
        lock.lock()
        let output = lines
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        lock.unlock()

        guard !output.isEmpty else { return nil }
        return String(output.prefix(600))
    }
}

private enum RefreshMode: Sendable {
    case full
    case lightweight

    var usesCachedValues: Bool {
        self == .lightweight
    }

    func merged(with other: RefreshMode) -> RefreshMode {
        if self == .full || other == .full {
            return .full
        }
        return .lightweight
    }
}

private struct TimedCacheEntry<Value: Sendable>: Sendable {
    let value: Value
    let fetchedAt: Date

    func isFresh(at now: Date, ttl: TimeInterval) -> Bool {
        now.timeIntervalSince(fetchedAt) <= ttl
    }
}

private struct AppStoreLookupCacheKey: Hashable {
    let bundleIdentifier: String
    let localVersion: Version
}

private struct SparkleLookupCacheKey: Hashable {
    let feedURL: String
    let localVersion: Version
}

private struct HomebrewLookupCacheKey: Hashable {
    let bundleIdentifier: String?
    let appBundleName: String
    let localVersion: Version
}

private struct RefreshCacheState {
    var homebrewIndex: TimedCacheEntry<HomebrewCaskIndex>?
    var homebrewFormulaIndex: TimedCacheEntry<HomebrewFormulaIndex>?
    var homebrewInventory: TimedCacheEntry<[HomebrewManagedItem]>?
    var appStoreLookup: [AppStoreLookupCacheKey: TimedCacheEntry<AppStoreLookupResult?>] = [:]
    var sparkleLookup: [SparkleLookupCacheKey: TimedCacheEntry<SparkleLookupResult?>] = [:]
    var homebrewLookup: [HomebrewLookupCacheKey: TimedCacheEntry<HomebrewLookupResult?>] = [:]

    mutating func pruneExpired(now: Date, ttl: TimeInterval) {
        appStoreLookup = appStoreLookup.filter { $0.value.isFresh(at: now, ttl: ttl) }
        sparkleLookup = sparkleLookup.filter { $0.value.isFresh(at: now, ttl: ttl) }
        homebrewLookup = homebrewLookup.filter { $0.value.isFresh(at: now, ttl: ttl) }
    }
}

@MainActor
@Observable
final class UpdateStore {
    private(set) var apps: [AppRecord] = []
    private(set) var updatesByAppID: [String: UpdateRecord] = [:]
    private(set) var recentlyUpdatedRecords: [RecentlyUpdatedRecord] = []
    private(set) var homebrewItems: [HomebrewManagedItem] = []
    private(set) var homebrewRecentlyUpdatedRecords: [HomebrewRecentlyUpdatedRecord] = []

    var ignoredAppIDs: Set<String> = [] {
        didSet {
            if !isHydratingPersistedSnapshot {
                recomputeDerivedState()
                schedulePersistSnapshot()
            }
        }
    }

    var ignoredHomebrewItemIDs: Set<String> = [] {
        didSet {
            if !isHydratingPersistedSnapshot {
                recomputeDerivedState()
                schedulePersistSnapshot()
            }
        }
    }

    var additionalDirectories: [URL] = [] {
        didSet {
            if !isHydratingPersistedSnapshot {
                schedulePersistSnapshot()
            }
        }
    }

    var selectedTab: MenuTab = .apps {
        didSet {
            if !isHydratingPersistedSnapshot {
                schedulePersistSnapshot()
            }
        }
    }

    var showInstalledAppsSection: Bool = true {
        didSet {
            if !isHydratingPersistedSnapshot {
                schedulePersistSnapshot()
            }
        }
    }

    var showRecentlyUpdatedAppsSection: Bool = true {
        didSet {
            if !isHydratingPersistedSnapshot {
                schedulePersistSnapshot()
            }
        }
    }

    var showIgnoredAppsSection: Bool = true {
        didSet {
            if !isHydratingPersistedSnapshot {
                schedulePersistSnapshot()
            }
        }
    }

    var showRecentlyUpdatedHomebrewSection: Bool = true {
        didSet {
            if !isHydratingPersistedSnapshot {
                schedulePersistSnapshot()
            }
        }
    }

    var showInstalledHomebrewSection: Bool = true {
        didSet {
            if !isHydratingPersistedSnapshot {
                schedulePersistSnapshot()
            }
        }
    }

    var showIgnoredHomebrewSection: Bool = true {
        didSet {
            if !isHydratingPersistedSnapshot {
                schedulePersistSnapshot()
            }
        }
    }

    var searchText: String = "" {
        didSet {
            recomputeDerivedState()
            refreshHomebrewDiscoverItems()
        }
    }
    var useMasForAppStoreUpdates: Bool = true {
        didSet {
            if !isHydratingPersistedSnapshot {
                schedulePersistSnapshot()
            }
        }
    }

    var autoRefreshEnabled: Bool = true {
        didSet {
            if isHydratingPersistedSnapshot { return }
            restartAutoRefreshLoop()
            schedulePersistSnapshot()
        }
    }

    var refreshIntervalMinutes: Int = 60 {
        didSet {
            if refreshIntervalMinutes < 5 { refreshIntervalMinutes = 5 }
            if refreshIntervalMinutes > 1_440 { refreshIntervalMinutes = 1_440 }
            if isHydratingPersistedSnapshot { return }
            restartAutoRefreshLoop()
            schedulePersistSnapshot()
        }
    }

    private(set) var isRefreshing: Bool = false
    private(set) var lastRefreshDate: Date?
    private(set) var refreshErrorMessage: String?
    private(set) var lastRefreshNoticeMessage: String?
    private(set) var isMasInstalled: Bool = false
    private(set) var isHomebrewInstalledForMasInstall: Bool = false
    private(set) var isCheckingMas: Bool = false
    private(set) var isTestingMas: Bool = false
    private(set) var isInstallingMas: Bool = false
    private(set) var masTestMessage: String?
    private(set) var masTestSucceeded: Bool?
    private(set) var isRunningHomebrewMaintenance: Bool = false
    private(set) var isHomebrewUpdateAllUpdatedPendingRefresh: Bool = false
    private(set) var appUpdatingIDs: Set<String> = []
    private(set) var appUpdatedPendingRefreshIDs: Set<String> = []
    private(set) var homebrewUpdatingItemIDs: Set<String> = []
    private(set) var homebrewUninstallingItemIDs: Set<String> = []
    private(set) var homebrewUpdatedPendingRefreshItemIDs: Set<String> = []
    private(set) var homebrewBatchProgressByItemID: [String: Double] = [:]
    private(set) var homebrewBatchFailedItemIDs: Set<String> = []
    private(set) var homebrewFallbackProgressByAppID: [String: Double] = [:]
    private(set) var homebrewFallbackFailedAppIDs: Set<String> = []
    private(set) var laggingHomebrewCaskTokens: Set<String> = []
    private(set) var homebrewDiscoverItems: [HomebrewCaskDiscoveryItem] = []
    private(set) var homebrewDiscoverInstallingTokens: Set<String> = []
    private(set) var homebrewDiscoverInstalledPendingRefreshTokens: Set<String> = []
    private(set) var homebrewDiscoverFailedTokens: Set<String> = []
    private(set) var homebrewDiscoverProgressByToken: [String: Double] = [:]
    private(set) var availableApps: [AppRecord] = []
    private(set) var installedApps: [AppRecord] = []
    private(set) var recentlyUpdatedApps: [AppRecord] = []
    private(set) var ignoredApps: [AppRecord] = []
    private(set) var displayedAvailableApps: [AppRecord] = []
    private(set) var displayedInstalledApps: [AppRecord] = []
    private(set) var displayedRecentlyUpdatedApps: [AppRecord] = []
    private(set) var displayedIgnoredApps: [AppRecord] = []
    private(set) var homebrewOutdatedItems: [HomebrewManagedItem] = []
    private(set) var homebrewRecentlyUpdatedItems: [HomebrewManagedItem] = []
    private(set) var homebrewInstalledItems: [HomebrewManagedItem] = []
    private(set) var homebrewIgnoredItems: [HomebrewManagedItem] = []
    private(set) var displayedHomebrewOutdatedItems: [HomebrewManagedItem] = []
    private(set) var displayedHomebrewRecentlyUpdatedItems: [HomebrewManagedItem] = []
    private(set) var displayedHomebrewInstalledItems: [HomebrewManagedItem] = []
    private(set) var displayedHomebrewIgnoredItems: [HomebrewManagedItem] = []

    @ObservationIgnored private let dependencies: UpdateStoreDependencies
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let nowProvider: @Sendable () -> Date
    @ObservationIgnored private let onSnapshotPersist: (@Sendable (Data) -> Void)?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var activeRefreshMode: RefreshMode?
    @ObservationIgnored private var queuedRefreshMode: RefreshMode?
    @ObservationIgnored private var homebrewDiscoverTask: Task<Void, Never>?
    @ObservationIgnored private var autoRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var persistSnapshotTask: Task<Void, Never>?
    @ObservationIgnored private var isPersistSnapshotDirty = false
    @ObservationIgnored private var lastPersistedSnapshotData: Data?
    @ObservationIgnored private var pendingExternalUpdateRefreshTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var iconCache: [String: NSImage] = [:]
    @ObservationIgnored private var homebrewIconCache: [String: NSImage] = [:]
    @ObservationIgnored private var appReleaseDateCache: [String: Date] = [:]
    @ObservationIgnored private var refreshCacheState = RefreshCacheState()
    @ObservationIgnored private var isHydratingPersistedSnapshot = false
    @ObservationIgnored private let externalUpdateRefreshDelaySeconds: [UInt64]
    @ObservationIgnored private var latestHomebrewIndex: HomebrewCaskIndex = .empty
    @ObservationIgnored private var latestHomebrewFormulaIndex: HomebrewFormulaIndex = .empty
    @ObservationIgnored private var homebrewDiscoveryInstalledCaskTokens: Set<String> = []
    @ObservationIgnored private var homebrewDiscoveryInstalledFormulaTokens: Set<String> = []

    private static let recentlyUpdatedRetention: TimeInterval = 14 * 24 * 60 * 60
    private static let recentlyUpdatedLimit = 40
    private static let defaultExternalUpdateRefreshDelaySeconds: [UInt64] = [5, 15, 30, 60]
    private static let refreshCacheTTL: TimeInterval = 15 * 60
    private static let snapshotPersistDebounceNanoseconds: UInt64 = 140_000_000

    init(
        dependencies: UpdateStoreDependencies = .live,
        defaults: UserDefaults = UserDefaults(suiteName: PersistenceKeys.suiteName) ?? .standard,
        externalUpdateRefreshDelaySeconds: [UInt64] = UpdateStore.defaultExternalUpdateRefreshDelaySeconds,
        nowProvider: @escaping @Sendable () -> Date = Date.init,
        onSnapshotPersist: (@Sendable (Data) -> Void)? = nil
    ) {
        self.dependencies = dependencies
        self.defaults = defaults
        self.externalUpdateRefreshDelaySeconds = externalUpdateRefreshDelaySeconds
        self.nowProvider = nowProvider
        self.onSnapshotPersist = onSnapshotPersist
        loadPersistedSnapshot()
        recomputeDerivedState()
    }

    deinit {
        MainActor.assumeIsolated {
            refreshTask?.cancel()
            homebrewDiscoverTask?.cancel()
            autoRefreshTask?.cancel()
            flushPendingPersistence()
            for task in pendingExternalUpdateRefreshTasks.values {
                task.cancel()
            }
        }
    }

    func startIfNeeded() {
        guard !hasStarted else { return }
        hasStarted = true
        refreshMasSetupStatus()
        restartAutoRefreshLoop()
        refreshNow()
    }

    func refreshMasSetupStatus() {
        guard !isCheckingMas else { return }

        isCheckingMas = true

        Task { [weak self] in
            guard let self else { return }
            async let masInstalledResult = self.dependencies.checkMasInstalled()
            async let homebrewInstalledResult = self.dependencies.checkHomebrewInstalled()
            let masInstalled = await masInstalledResult
            let homebrewInstalled = await homebrewInstalledResult

            self.isMasInstalled = masInstalled
            self.isHomebrewInstalledForMasInstall = homebrewInstalled
            self.isCheckingMas = false

            if !masInstalled {
                self.masTestSucceeded = nil
            }
        }
    }

    func testMasSetup() {
        guard !isTestingMas else { return }
        guard !isCheckingMas else { return }

        guard isMasInstalled else {
            masTestSucceeded = false
            masTestMessage = "mas is not installed yet. Tap Install mas to get started."
            return
        }

        isTestingMas = true
        masTestSucceeded = nil
        masTestMessage = nil

        Task { [weak self] in
            guard let self else { return }

            let isInstalledNow = await self.dependencies.checkMasInstalled()
            if !isInstalledNow {
                self.isMasInstalled = false
                self.isTestingMas = false
                self.masTestSucceeded = false
                self.masTestMessage = "mas was not found. Please install mas, then try again."
                return
            }

            let isSignedIn = await self.dependencies.checkMasSignedIn()
            self.isTestingMas = false

            if isSignedIn {
                self.masTestSucceeded = true
                self.masTestMessage = "Great news. mas is ready, and Baseline can help start App Store updates for you."
            } else {
                self.masTestSucceeded = false
                self.masTestMessage = "mas is installed, but it is not connected to your App Store account yet. Open the App Store, sign in, then test again."
            }
        }
    }

    func installMasWithHomebrew() {
        guard !isInstallingMas else { return }
        guard !isCheckingMas else { return }

        isInstallingMas = true
        masTestSucceeded = nil
        masTestMessage = "Installing mas. This may take a moment."

        Task { [weak self] in
            guard let self else { return }

            let hasHomebrew = await self.dependencies.checkHomebrewInstalled()
            self.isHomebrewInstalledForMasInstall = hasHomebrew

            guard hasHomebrew else {
                self.isInstallingMas = false
                self.masTestSucceeded = false
                self.masTestMessage = "Automatic install needs Homebrew. You can use the install guide instead."
                return
            }

            let didInstall = await self.dependencies.installMasUsingHomebrew()
            let isInstalledNow = await self.dependencies.checkMasInstalled()
            self.isInstallingMas = false
            self.isMasInstalled = isInstalledNow

            if didInstall && isInstalledNow {
                self.masTestSucceeded = true
                self.masTestMessage = "mas was installed successfully. You can now test it and use automatic App Store updates."
            } else {
                self.masTestSucceeded = false
                self.masTestMessage = "We could not install mas automatically. Please use the install guide and try again."
            }
        }
    }

    func refreshNow(lightweight: Bool = false) {
        requestRefresh(mode: lightweight ? .lightweight : .full)
    }

    func dismissRefreshError() {
        refreshErrorMessage = nil
    }

    func diagnosticsReport() -> BaselineDiagnosticsReport {
        BaselineDiagnosticsReport(
            generatedAt: nowProvider(),
            lastRefreshDate: lastRefreshDate,
            isRefreshing: isRefreshing,
            appCount: apps.count,
            availableAppCount: availableApps.count,
            installedAppCount: installedApps.count,
            ignoredAppCount: ignoredApps.count,
            recentlyUpdatedAppCount: recentlyUpdatedApps.count,
            homebrewItemCount: homebrewItems.count,
            homebrewOutdatedCount: homebrewOutdatedItems.count,
            homebrewInstalledCount: homebrewInstalledItems.count,
            homebrewIgnoredCount: homebrewIgnoredItems.count,
            homebrewRecentlyUpdatedCount: homebrewRecentlyUpdatedItems.count,
            updateSourceCounts: Dictionary(grouping: updatesByAppID.values, by: \.source)
                .mapValues(\.count),
            scanDirectories: scanDirectories,
            additionalDirectoryCount: additionalDirectories.count,
            autoRefreshEnabled: autoRefreshEnabled,
            refreshIntervalMinutes: refreshIntervalMinutes,
            useMasForAppStoreUpdates: useMasForAppStoreUpdates,
            isMasInstalled: isMasInstalled,
            isHomebrewInstalled: isHomebrewInstalledForMasInstall,
            lastRefreshMessage: refreshErrorMessage ?? lastRefreshNoticeMessage
        )
    }

    private func requestRefresh(mode: RefreshMode) {
        if isRefreshing {
            if mode == .lightweight {
                queuedRefreshMode = (queuedRefreshMode ?? .lightweight).merged(with: mode)
                return
            }
            refreshTask?.cancel()
            activeRefreshMode = nil
            queuedRefreshMode = nil
        }

        startRefresh(mode: mode)
    }

    private func startRefresh(mode: RefreshMode) {
        let directories = scanDirectories
        let dependencies = self.dependencies
        let cacheState = self.refreshCacheState
        let now = nowProvider()

        isRefreshing = true
        refreshErrorMessage = nil
        lastRefreshNoticeMessage = nil
        activeRefreshMode = mode

        refreshTask = Task {
            let result = await Self.computeRefresh(
                directories: directories,
                dependencies: dependencies,
                mode: mode,
                cacheState: cacheState,
                now: now
            )

            guard !Task.isCancelled else { return }
            self.applyRefreshResult(result)
            self.activeRefreshMode = nil

            if let queuedMode = self.queuedRefreshMode {
                self.queuedRefreshMode = nil
                self.startRefresh(mode: queuedMode)
            }
        }
    }

    private func applyRefreshResult(_ result: RefreshResult) {
        let previousAppsByID = Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0) })
        let previousUpdatesByID = updatesByAppID
        let currentAppsByID = Dictionary(uniqueKeysWithValues: result.apps.map { ($0.id, $0) })
        let previousHomebrewItemsByID = Dictionary(uniqueKeysWithValues: homebrewItems.map { ($0.id, $0) })
        let currentHomebrewItemsByID = Dictionary(uniqueKeysWithValues: result.homebrewItems.map { ($0.id, $0) })

        apps = result.apps
        updatesByAppID = result.updates
        homebrewItems = result.homebrewItems
        latestHomebrewIndex = result.homebrewIndex
        latestHomebrewFormulaIndex = result.homebrewFormulaIndex
        refreshCacheState = result.cacheState
        let discoveryInstalledTokens = Self.discoveryInstalledHomebrewTokens(
            apps: result.apps,
            homebrewItems: result.homebrewItems,
            homebrewIndex: result.homebrewIndex
        )
        homebrewDiscoveryInstalledCaskTokens = discoveryInstalledTokens.caskTokens
        homebrewDiscoveryInstalledFormulaTokens = discoveryInstalledTokens.formulaTokens
        laggingHomebrewCaskTokens = result.laggingHomebrewCaskTokens
        recentlyUpdatedRecords = Self.mergeRecentlyUpdatedRecords(
            previousRecords: recentlyUpdatedRecords,
            previousAppsByID: previousAppsByID,
            previousUpdatesByID: previousUpdatesByID,
            currentAppsByID: currentAppsByID,
            currentUpdatesByID: result.updates,
            at: result.lastRefreshDate
        )
        homebrewRecentlyUpdatedRecords = Self.mergeRecentlyUpdatedHomebrewRecords(
            previousRecords: homebrewRecentlyUpdatedRecords,
            previousItemsByID: previousHomebrewItemsByID,
            currentItemsByID: currentHomebrewItemsByID,
            at: result.lastRefreshDate
        )
        homebrewRecentlyUpdatedRecords = Self.mergeInferredRecentlyUpdatedHomebrewRecords(
            previousRecords: homebrewRecentlyUpdatedRecords,
            inferredTransitions: result.inferredHomebrewRecentlyUpdatedTransitions,
            at: result.lastRefreshDate
        )
        lastRefreshDate = result.lastRefreshDate
        refreshErrorMessage = result.errorMessage
        lastRefreshNoticeMessage = result.noticeMessage
        isRefreshing = false
        appUpdatedPendingRefreshIDs.removeAll()
        homebrewUpdatedPendingRefreshItemIDs.removeAll()
        homebrewBatchProgressByItemID.removeAll()
        homebrewBatchFailedItemIDs.removeAll()
        homebrewFallbackProgressByAppID.removeAll()
        homebrewFallbackFailedAppIDs.removeAll()
        homebrewDiscoverInstallingTokens.removeAll()
        homebrewDiscoverInstalledPendingRefreshTokens.removeAll()
        homebrewDiscoverProgressByToken.removeAll()
        homebrewDiscoverFailedTokens.removeAll()
        isHomebrewUpdateAllUpdatedPendingRefresh = false
        pruneIconCache()
        recomputeDerivedState()
        refreshHomebrewDiscoverItems()
        schedulePersistSnapshot()
    }

    func update(for app: AppRecord) -> UpdateRecord? {
        updatesByAppID[app.id]
    }

    func toggleIgnored(for app: AppRecord) {
        if ignoredAppIDs.contains(app.id) {
            ignoredAppIDs.remove(app.id)
        } else {
            ignoredAppIDs.insert(app.id)
        }
    }

    func toggleIgnored(for item: HomebrewManagedItem) {
        if ignoredHomebrewItemIDs.contains(item.id) {
            ignoredHomebrewItemIDs.remove(item.id)
        } else {
            ignoredHomebrewItemIDs.insert(item.id)
        }
    }

    func openApp(_ app: AppRecord) {
        launchAppBundle(for: app)
    }

    func canOpenHomebrewItem(_ item: HomebrewManagedItem) -> Bool {
        guard item.kind == .cask else { return false }
        return matchingApp(for: item) != nil
    }

    func openHomebrewItem(_ item: HomebrewManagedItem) {
        guard item.kind == .cask, let app = matchingApp(for: item) else { return }
        launchAppBundle(for: app)
    }

    func canOpenHomebrewDiscoverItem(_ item: HomebrewCaskDiscoveryItem) -> Bool {
        guard let url = item.homepageURL else { return false }
        return SecurityPolicy.isAllowedExternalURL(url)
    }

    func openHomebrewDiscoverItem(_ item: HomebrewCaskDiscoveryItem) {
        guard let url = item.homepageURL else { return }
        _ = openExternalURLIfAllowed(
            url,
            blockedMessage: "Blocked an unsafe Homebrew page link."
        )
    }

    func performUpdate(for app: AppRecord) {
        guard let update = updatesByAppID[app.id] else {
            launchAppBundle(for: app)
            return
        }

        if useMasForAppStoreUpdates, update.source == .appStore, let appStoreItemID = update.appStoreItemID {
            guard !appUpdatingIDs.contains(app.id) else { return }
            appUpdatingIDs.insert(app.id)

            Task { [weak self] in
                guard let self else { return }
                defer { self.appUpdatingIDs.remove(app.id) }

                let didUpgrade = await self.dependencies.runAppStoreUpgrade(appStoreItemID)

                if didUpgrade {
                    self.appUpdatedPendingRefreshIDs.insert(app.id)
                    self.refreshNow()
                } else {
                    self.appUpdatedPendingRefreshIDs.remove(app.id)
                    self.routeExternalUpdate(for: app, update: update)
                }
            }
            return
        }

        if update.source == .homebrew, let token = update.homebrewToken {
            guard SecurityPolicy.isValidHomebrewToken(token) else {
                refreshErrorMessage = "Blocked unsafe Homebrew token for \(app.displayName)."
                return
            }

            if laggingHomebrewCaskTokens.contains(token.lowercased()) {
                routeExternalUpdate(for: app, update: update)
                return
            }

            if let item = matchingHomebrewItem(for: app), item.isOutdated {
                performHomebrewUpdate(for: item)
                return
            }

            guard !appUpdatingIDs.contains(app.id) else { return }
            homebrewFallbackFailedAppIDs.remove(app.id)
            homebrewFallbackProgressByAppID[app.id] = HomebrewMaintenanceProgressStage.queued.rawValue
            appUpdatingIDs.insert(app.id)

            Task { [weak self] in
                guard let self else { return }
                defer { self.appUpdatingIDs.remove(app.id) }
                let parser = HomebrewMaintenanceOutputParser(knownTokens: [token.lowercased()])
                let didUpgrade = await self.dependencies.runHomebrewUpgradeWithEvents(token) { event in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.applyHomebrewFallbackEvent(event, parser: parser, appID: app.id)
                    }
                }
                var postRefreshErrorMessage: String?

                if !didUpgrade {
                    self.markHomebrewFallbackFailed(appID: app.id)
                    postRefreshErrorMessage = "Homebrew update failed for \(app.displayName)."
                    self.appUpdatedPendingRefreshIDs.remove(app.id)
                } else {
                    self.markHomebrewFallbackCompleted(appID: app.id)
                    self.appUpdatedPendingRefreshIDs.insert(app.id)
                }

                self.refreshNow()
                if let postRefreshErrorMessage {
                    await self.setPostRefreshErrorMessage(postRefreshErrorMessage)
                }
            }
            return
        }

        routeExternalUpdate(for: app, update: update)
    }

    private func routeExternalUpdate(for app: AppRecord, update: UpdateRecord) {
        if let url = update.updateURL {
            if openExternalURLIfAllowed(
                url,
                blockedMessage: "Blocked an unsafe update link for \(app.displayName)."
            ) {
                schedulePostExternalUpdateRefresh(for: app.id)
            } else {
                launchAppBundle(for: app)
                schedulePostExternalUpdateRefresh(for: app.id)
            }
        } else {
            launchAppBundle(for: app)
            schedulePostExternalUpdateRefresh(for: app.id)
        }
    }

    func performHomebrewUpdate(for item: HomebrewManagedItem) {
        guard item.isOutdated else { return }
        guard !homebrewUpdatingItemIDs.contains(item.id) else { return }
        guard !homebrewUninstallingItemIDs.contains(item.id) else { return }
        guard SecurityPolicy.isValidHomebrewToken(item.token) else {
            refreshErrorMessage = "Blocked unsafe Homebrew token for \(item.name)."
            return
        }

        if item.kind == .cask,
           laggingHomebrewCaskTokens.contains(item.token.lowercased()),
           let app = matchingApp(for: item),
           let update = updatesByAppID[app.id],
           update.source == .homebrew {
            routeExternalUpdate(for: app, update: update)
            return
        }

        homebrewBatchFailedItemIDs.remove(item.id)
        homebrewBatchProgressByItemID[item.id] = HomebrewMaintenanceProgressStage.queued.rawValue
        homebrewUpdatingItemIDs.insert(item.id)
        if let appID = matchingApp(for: item)?.id {
            homebrewFallbackFailedAppIDs.remove(appID)
            homebrewFallbackProgressByAppID.removeValue(forKey: appID)
        }

        Task { [weak self] in
            guard let self else { return }
            defer { self.homebrewUpdatingItemIDs.remove(item.id) }

            let parser = HomebrewMaintenanceOutputParser(knownTokens: [item.token.lowercased()])
            let affectedItemsByToken = [item.token.lowercased(): [item]]
            let didUpgrade = await self.dependencies.runHomebrewItemUpgradeWithEvents(item.kind, item.token) { event in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.applyHomebrewMaintenanceEvent(
                        event,
                        parser: parser,
                        affectedItemsByToken: affectedItemsByToken
                    )
                }
            }
            var postRefreshErrorMessage: String?
            if !didUpgrade {
                postRefreshErrorMessage = "Homebrew update failed for \(item.name)."
                self.homebrewUpdatedPendingRefreshItemIDs.remove(item.id)
                self.homebrewBatchFailedItemIDs.insert(item.id)
                self.homebrewBatchProgressByItemID[item.id] = HomebrewMaintenanceProgressStage.completed.rawValue
                if let appID = self.matchingApp(for: item)?.id {
                    self.markHomebrewFallbackFailed(appID: appID)
                }
            } else {
                self.homebrewBatchProgressByItemID[item.id] = HomebrewMaintenanceProgressStage.completed.rawValue
                self.homebrewBatchFailedItemIDs.remove(item.id)
                self.homebrewUpdatedPendingRefreshItemIDs.insert(item.id)
                if let appID = self.matchingApp(for: item)?.id {
                    self.markHomebrewFallbackCompleted(appID: appID)
                }
            }
            self.refreshNow()
            if let postRefreshErrorMessage {
                await self.setPostRefreshErrorMessage(postRefreshErrorMessage)
            }
        }
    }

    func performHomebrewInstall(for item: HomebrewCaskDiscoveryItem) {
        guard SecurityPolicy.isValidHomebrewToken(item.token) else {
            refreshErrorMessage = "Blocked unsafe Homebrew token for \(item.displayName)."
            return
        }

        let itemID = item.id
        guard !homebrewDiscoverInstallingTokens.contains(itemID) else { return }

        homebrewDiscoverFailedTokens.remove(itemID)
        homebrewDiscoverInstalledPendingRefreshTokens.remove(itemID)
        homebrewDiscoverProgressByToken[itemID] = HomebrewMaintenanceProgressStage.queued.rawValue
        homebrewDiscoverInstallingTokens.insert(itemID)

        Task { [weak self] in
            guard let self else { return }
            defer { self.homebrewDiscoverInstallingTokens.remove(itemID) }

            let hasHomebrew = await self.dependencies.checkHomebrewInstalled()
            self.isHomebrewInstalledForMasInstall = hasHomebrew
            guard hasHomebrew else {
                self.markHomebrewDiscoverInstallFailed(itemID: itemID)
                self.refreshErrorMessage = "Homebrew is not installed. Install Homebrew to add \(item.displayName)."
                return
            }

            let parser = HomebrewMaintenanceOutputParser(knownTokens: [item.token.lowercased()])
            let didInstall: Bool
            switch item.kind {
            case .cask:
                didInstall = await self.dependencies.runHomebrewCaskInstallWithEvents(item.token) { event in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.applyHomebrewDiscoverInstallEvent(
                            event,
                            parser: parser,
                            itemID: itemID,
                            token: item.token.lowercased()
                        )
                    }
                }
            case .formula:
                didInstall = await self.dependencies.runHomebrewFormulaInstallWithEvents(item.token) { event in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.applyHomebrewDiscoverInstallEvent(
                            event,
                            parser: parser,
                            itemID: itemID,
                            token: item.token.lowercased()
                        )
                    }
                }
            }

            if didInstall {
                self.markHomebrewDiscoverInstallCompleted(itemID: itemID)
                self.refreshNow()
            } else {
                self.markHomebrewDiscoverInstallFailed(itemID: itemID)
                self.refreshErrorMessage = "Homebrew install failed for \(item.displayName)."
            }
        }
    }

    func isInstallingHomebrewDiscoverItem(_ item: HomebrewCaskDiscoveryItem) -> Bool {
        homebrewDiscoverInstallingTokens.contains(item.id)
    }

    func homebrewDiscoverInstallProgress(for item: HomebrewCaskDiscoveryItem) -> Double? {
        homebrewDiscoverProgressByToken[item.id]
    }

    func isHomebrewDiscoverItemInstallFailed(_ item: HomebrewCaskDiscoveryItem) -> Bool {
        homebrewDiscoverFailedTokens.contains(item.id)
    }

    func isHomebrewDiscoverItemInstalledPendingRefresh(_ item: HomebrewCaskDiscoveryItem) -> Bool {
        homebrewDiscoverInstalledPendingRefreshTokens.contains(item.id)
    }

    private func applyHomebrewDiscoverInstallEvent(
        _ event: HomebrewMaintenanceRunEvent,
        parser: HomebrewMaintenanceOutputParser,
        itemID: String,
        token: String
    ) {
        switch event {
        case .commandStarted(let command):
            guard let stage = commandStartStage(for: command) else { return }
            advanceHomebrewDiscoverInstallProgress(itemID: itemID, to: stage.rawValue)
        case .outputLine(let command, let line):
            let events = parser.parse(line: line, command: command)
            guard !events.isEmpty else { return }
            for progressEvent in events where progressEvent.token == token {
                switch progressEvent.kind {
                case .progress(let progress):
                    advanceHomebrewDiscoverInstallProgress(itemID: itemID, to: progress)
                case .completed:
                    markHomebrewDiscoverInstallCompleted(itemID: itemID)
                case .failed:
                    markHomebrewDiscoverInstallFailed(itemID: itemID)
                }
            }
        case .commandFinished(let command, let success):
            guard success, let stage = commandFinishStage(for: command) else { return }
            advanceHomebrewDiscoverInstallProgress(itemID: itemID, to: stage.rawValue)
        }
    }

    private func advanceHomebrewDiscoverInstallProgress(itemID: String, to progress: Double) {
        guard !homebrewDiscoverFailedTokens.contains(itemID) else { return }
        let clamped = min(max(progress, 0), 1)
        let current = homebrewDiscoverProgressByToken[itemID] ?? 0
        if shouldInjectDownloadFloorForInstall(current: current, target: clamped) {
            homebrewDiscoverProgressByToken[itemID] = max(
                current,
                HomebrewMaintenanceProgressStage.downloading.rawValue
            )
            scheduleDiscoverInstallProgressAdvance(for: itemID)
            return
        }
        homebrewDiscoverProgressByToken[itemID] = max(current, clamped)
    }

    private func markHomebrewDiscoverInstallCompleted(itemID: String) {
        homebrewDiscoverFailedTokens.remove(itemID)
        homebrewDiscoverProgressByToken[itemID] = HomebrewMaintenanceProgressStage.completed.rawValue
        homebrewDiscoverInstalledPendingRefreshTokens.insert(itemID)
    }

    private func markHomebrewDiscoverInstallFailed(itemID: String) {
        homebrewDiscoverFailedTokens.insert(itemID)
        homebrewDiscoverProgressByToken[itemID] = HomebrewMaintenanceProgressStage.completed.rawValue
        homebrewDiscoverInstalledPendingRefreshTokens.remove(itemID)
    }

    private func scheduleDiscoverInstallProgressAdvance(for itemID: String) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 140_000_000)
            guard let self else { return }
            guard !self.homebrewDiscoverFailedTokens.contains(itemID) else { return }
            self.advanceHomebrewDiscoverInstallProgress(
                itemID: itemID,
                to: HomebrewMaintenanceProgressStage.installing.rawValue
            )
        }
    }

    func performHomebrewUninstall(for item: HomebrewManagedItem) {
        guard item.kind == .cask else { return }
        guard !homebrewUninstallingItemIDs.contains(item.id) else { return }
        guard !homebrewUpdatingItemIDs.contains(item.id) else { return }
        guard SecurityPolicy.isValidHomebrewToken(item.token) else {
            refreshErrorMessage = "Blocked unsafe Homebrew token for \(item.name)."
            return
        }

        homebrewUninstallingItemIDs.insert(item.id)

        Task { [weak self] in
            guard let self else { return }
            defer { self.homebrewUninstallingItemIDs.remove(item.id) }

            let result = await self.dependencies.runHomebrewCaskUninstallWithOutput(item.token)
            if !result.didComplete {
                self.refreshNow()
                await self.setPostRefreshErrorMessage(
                    self.homebrewUninstallFailureMessage(for: item, output: result.output)
                )
                return
            }
            self.refreshNow()
        }
    }

    func performHomebrewUninstall(for app: AppRecord) {
        guard let item = uninstallableHomebrewItem(for: app) else { return }
        performHomebrewUninstall(for: item)
    }

    private func homebrewUninstallFailureMessage(for item: HomebrewManagedItem, output: String?) -> String {
        let prefix = "Homebrew uninstall failed for \(item.name)."
        guard let output, !output.isEmpty else { return prefix }
        return "\(prefix)\n\n\(output)"
    }

    func performHomebrewUpdateAll() {
        guard !isRunningHomebrewMaintenance else { return }

        let affectedItems = homebrewOutdatedItems
        let affectedItemIDs = Set(affectedItems.map(\.id))
        let affectedItemsByToken = Dictionary(grouping: affectedItems) { $0.token.lowercased() }

        homebrewBatchFailedItemIDs.subtract(affectedItemIDs)
        for itemID in affectedItemIDs {
            homebrewUpdatingItemIDs.insert(itemID)
            homebrewUpdatedPendingRefreshItemIDs.remove(itemID)
            homebrewBatchProgressByItemID[itemID] = max(
                homebrewBatchProgressByItemID[itemID] ?? 0,
                HomebrewMaintenanceProgressStage.queued.rawValue
            )
        }

        isRunningHomebrewMaintenance = true
        isHomebrewUpdateAllUpdatedPendingRefresh = false
        refreshErrorMessage = nil

        Task { [weak self] in
            guard let self else { return }
            let parser = HomebrewMaintenanceOutputParser(knownTokens: Set(affectedItemsByToken.keys))
            let didComplete = await self.dependencies.runHomebrewMaintenanceCycle { event in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.applyHomebrewMaintenanceEvent(
                        event,
                        parser: parser,
                        affectedItemsByToken: affectedItemsByToken
                    )
                }
            }
            self.isRunningHomebrewMaintenance = false
            var postRefreshErrorMessage: String?

            if !didComplete {
                postRefreshErrorMessage = "Homebrew maintenance cycle failed."
                self.isHomebrewUpdateAllUpdatedPendingRefresh = false
                let unresolvedIDs = self.homebrewUpdatingItemIDs.intersection(affectedItemIDs)
                self.homebrewBatchFailedItemIDs.formUnion(unresolvedIDs)
                self.homebrewUpdatedPendingRefreshItemIDs.subtract(unresolvedIDs)
                for itemID in unresolvedIDs {
                    self.homebrewBatchProgressByItemID[itemID] = HomebrewMaintenanceProgressStage.completed.rawValue
                }
                self.homebrewUpdatingItemIDs.subtract(unresolvedIDs)
            } else {
                let succeededItemIDs = affectedItemIDs.subtracting(self.homebrewBatchFailedItemIDs)
                for itemID in succeededItemIDs {
                    self.homebrewBatchProgressByItemID[itemID] = HomebrewMaintenanceProgressStage.completed.rawValue
                }
                self.homebrewUpdatingItemIDs.subtract(succeededItemIDs)
                self.homebrewUpdatedPendingRefreshItemIDs.formUnion(succeededItemIDs)
                self.isHomebrewUpdateAllUpdatedPendingRefresh = true
            }

            self.refreshNow()
            if let postRefreshErrorMessage {
                await self.setPostRefreshErrorMessage(postRefreshErrorMessage)
            }
        }
    }

    private func applyHomebrewMaintenanceEvent(
        _ event: HomebrewMaintenanceRunEvent,
        parser: HomebrewMaintenanceOutputParser,
        affectedItemsByToken: [String: [HomebrewManagedItem]]
    ) {
        switch event {
        case .commandStarted(let command):
            guard let stage = commandStartStage(for: command) else { return }
            let itemIDs = targetItemIDs(for: command, in: affectedItemsByToken)
            advanceHomebrewBatchProgress(for: itemIDs, to: stage.rawValue)
        case .outputLine(let command, let line):
            let progressEvents = parser.parse(line: line, command: command)
            guard !progressEvents.isEmpty else { return }

            for progressEvent in progressEvents {
                let itemIDs = resolveHomebrewItemIDs(
                    token: progressEvent.token,
                    kindHint: progressEvent.kindHint,
                    affectedItemsByToken: affectedItemsByToken
                )
                guard !itemIDs.isEmpty else { continue }

                switch progressEvent.kind {
                case .progress(let progress):
                    advanceHomebrewBatchProgress(for: itemIDs, to: progress)
                case .completed:
                    markHomebrewBatchCompleted(itemIDs)
                case .failed:
                    markHomebrewBatchFailed(itemIDs)
                }
            }
        case .commandFinished(let command, let success):
            guard success, let stage = commandFinishStage(for: command) else { return }
            let itemIDs = targetItemIDs(for: command, in: affectedItemsByToken)
            advanceHomebrewBatchProgress(for: itemIDs, to: stage.rawValue)
        }
    }

    private func commandStartStage(for command: [String]) -> HomebrewMaintenanceProgressStage? {
        let normalized = command.map { $0.lowercased() }
        guard let first = normalized.first else { return nil }

        switch first {
        case "update":
            return .queued
        case "upgrade":
            return .queued
        case "install":
            return .queued
        case "autoremove", "cleanup":
            return .finalizing
        default:
            return nil
        }
    }

    private func commandFinishStage(for command: [String]) -> HomebrewMaintenanceProgressStage? {
        let normalized = command.map { $0.lowercased() }
        guard let first = normalized.first else { return nil }

        switch first {
        case "upgrade":
            return .finalizing
        case "install":
            return .finalizing
        case "cleanup":
            return .completed
        default:
            return nil
        }
    }

    private func targetItemIDs(
        for command: [String],
        in affectedItemsByToken: [String: [HomebrewManagedItem]]
    ) -> Set<String> {
        let normalized = command.map { $0.lowercased() }
        guard let first = normalized.first else { return [] }
        let allItems = affectedItemsByToken.values.flatMap { $0 }

        switch first {
        case "upgrade":
            if normalized.contains("--cask") || normalized.contains("--casks") {
                return Set(allItems.filter { $0.kind == .cask }.map(\.id))
            }
            return Set(allItems.filter { $0.kind == .formula }.map(\.id))
        default:
            return Set(allItems.map(\.id))
        }
    }

    private func resolveHomebrewItemIDs(
        token: String,
        kindHint: HomebrewManagedItemKind?,
        affectedItemsByToken: [String: [HomebrewManagedItem]]
    ) -> Set<String> {
        let normalizedToken = token.lowercased()
        guard let matchingItems = affectedItemsByToken[normalizedToken] else { return [] }

        if let kindHint {
            let filtered = matchingItems.filter { $0.kind == kindHint }
            if !filtered.isEmpty {
                return Set(filtered.map(\.id))
            }
        }

        return Set(matchingItems.map(\.id))
    }

    private func advanceHomebrewBatchProgress(for itemIDs: Set<String>, to progress: Double) {
        let clamped = min(max(progress, 0), 1)
        for itemID in itemIDs {
            guard !homebrewBatchFailedItemIDs.contains(itemID) else { continue }
            let current = homebrewBatchProgressByItemID[itemID] ?? 0
            if shouldInjectDownloadFloorForInstall(current: current, target: clamped) {
                let floor = max(current, HomebrewMaintenanceProgressStage.downloading.rawValue)
                homebrewBatchProgressByItemID[itemID] = floor
                homebrewUpdatingItemIDs.insert(itemID)
                scheduleInstallProgressAdvance(for: itemID)
                continue
            }

            let next = max(current, clamped)
            homebrewBatchProgressByItemID[itemID] = next
            if next < HomebrewMaintenanceProgressStage.completed.rawValue {
                homebrewUpdatingItemIDs.insert(itemID)
            }
        }
    }

    private func markHomebrewBatchCompleted(_ itemIDs: Set<String>) {
        for itemID in itemIDs {
            homebrewBatchFailedItemIDs.remove(itemID)
            homebrewBatchProgressByItemID[itemID] = HomebrewMaintenanceProgressStage.completed.rawValue
            homebrewUpdatingItemIDs.remove(itemID)
            homebrewUpdatedPendingRefreshItemIDs.insert(itemID)
        }
    }

    private func markHomebrewBatchFailed(_ itemIDs: Set<String>) {
        for itemID in itemIDs {
            homebrewBatchFailedItemIDs.insert(itemID)
            homebrewBatchProgressByItemID[itemID] = HomebrewMaintenanceProgressStage.completed.rawValue
            homebrewUpdatingItemIDs.remove(itemID)
            homebrewUpdatedPendingRefreshItemIDs.remove(itemID)
        }
    }

    private func applyHomebrewFallbackEvent(
        _ event: HomebrewMaintenanceRunEvent,
        parser: HomebrewMaintenanceOutputParser,
        appID: String
    ) {
        switch event {
        case .commandStarted(let command):
            guard let stage = commandStartStage(for: command) else { return }
            advanceHomebrewFallbackProgress(for: appID, to: stage.rawValue)
        case .outputLine(let command, let line):
            let progressEvents = parser.parse(line: line, command: command)
            guard !progressEvents.isEmpty else { return }

            for progressEvent in progressEvents {
                switch progressEvent.kind {
                case .progress(let progress):
                    advanceHomebrewFallbackProgress(for: appID, to: progress)
                case .completed:
                    markHomebrewFallbackCompleted(appID: appID)
                case .failed:
                    markHomebrewFallbackFailed(appID: appID)
                }
            }
        case .commandFinished(let command, let success):
            guard success, let stage = commandFinishStage(for: command) else { return }
            advanceHomebrewFallbackProgress(for: appID, to: stage.rawValue)
        }
    }

    private func advanceHomebrewFallbackProgress(for appID: String, to progress: Double) {
        guard !homebrewFallbackFailedAppIDs.contains(appID) else { return }
        let clamped = min(max(progress, 0), 1)
        let current = homebrewFallbackProgressByAppID[appID] ?? 0
        if shouldInjectDownloadFloorForInstall(current: current, target: clamped) {
            homebrewFallbackProgressByAppID[appID] = max(current, HomebrewMaintenanceProgressStage.downloading.rawValue)
            scheduleFallbackInstallProgressAdvance(for: appID)
            return
        }
        homebrewFallbackProgressByAppID[appID] = max(current, clamped)
    }

    private func markHomebrewFallbackCompleted(appID: String) {
        homebrewFallbackFailedAppIDs.remove(appID)
        homebrewFallbackProgressByAppID[appID] = HomebrewMaintenanceProgressStage.completed.rawValue
    }

    private func markHomebrewFallbackFailed(appID: String) {
        homebrewFallbackFailedAppIDs.insert(appID)
        homebrewFallbackProgressByAppID[appID] = HomebrewMaintenanceProgressStage.completed.rawValue
    }

    private func shouldInjectDownloadFloorForInstall(current: Double, target: Double) -> Bool {
        let install = HomebrewMaintenanceProgressStage.installing.rawValue
        let download = HomebrewMaintenanceProgressStage.downloading.rawValue
        return target >= install && current < download
    }

    private func scheduleInstallProgressAdvance(for itemID: String) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 140_000_000)
            guard let self else { return }
            guard !self.homebrewBatchFailedItemIDs.contains(itemID) else { return }
            self.advanceHomebrewBatchProgress(
                for: [itemID],
                to: HomebrewMaintenanceProgressStage.installing.rawValue
            )
        }
    }

    private func scheduleFallbackInstallProgressAdvance(for appID: String) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 140_000_000)
            guard let self else { return }
            guard !self.homebrewFallbackFailedAppIDs.contains(appID) else { return }
            self.advanceHomebrewFallbackProgress(
                for: appID,
                to: HomebrewMaintenanceProgressStage.installing.rawValue
            )
        }
    }

    func isUpdatingHomebrewItem(_ item: HomebrewManagedItem) -> Bool {
        homebrewUpdatingItemIDs.contains(item.id)
    }

    func homebrewUpdateProgress(for item: HomebrewManagedItem) -> Double? {
        homebrewBatchProgressByItemID[item.id]
    }

    func isHomebrewItemUpdateFailed(_ item: HomebrewManagedItem) -> Bool {
        homebrewBatchFailedItemIDs.contains(item.id)
    }

    func isUninstallingHomebrewItem(_ item: HomebrewManagedItem) -> Bool {
        homebrewUninstallingItemIDs.contains(item.id)
    }

    func isUninstallingHomebrewItem(for app: AppRecord) -> Bool {
        guard let item = uninstallableHomebrewItem(for: app) else { return false }
        return homebrewUninstallingItemIDs.contains(item.id)
    }

    func isUpdatingApp(_ app: AppRecord) -> Bool {
        if appUpdatingIDs.contains(app.id) {
            return true
        }
        if let item = matchingHomebrewItem(for: app) {
            return homebrewUpdatingItemIDs.contains(item.id)
        }
        return false
    }

    func appUpdateProgress(for app: AppRecord) -> Double? {
        if let item = matchingHomebrewItem(for: app),
           let progress = homebrewBatchProgressByItemID[item.id] {
            return progress
        }
        return homebrewFallbackProgressByAppID[app.id]
    }

    func isAppUpdateFailed(_ app: AppRecord) -> Bool {
        if let item = matchingHomebrewItem(for: app),
           homebrewBatchFailedItemIDs.contains(item.id) {
            return true
        }
        return homebrewFallbackFailedAppIDs.contains(app.id)
    }

    func isAppUpdatedPendingRefresh(_ app: AppRecord) -> Bool {
        if let item = matchingHomebrewItem(for: app),
           homebrewUpdatedPendingRefreshItemIDs.contains(item.id) {
            return true
        }
        return appUpdatedPendingRefreshIDs.contains(app.id)
    }

    func isHomebrewItemUpdatedPendingRefresh(_ item: HomebrewManagedItem) -> Bool {
        homebrewUpdatedPendingRefreshItemIDs.contains(item.id)
    }

    private func launchAppBundle(for app: AppRecord) {
        dependencies.openAppBundle(app.bundleURL)
    }

    @discardableResult
    private func openExternalURLIfAllowed(_ url: URL, blockedMessage: String) -> Bool {
        guard SecurityPolicy.isAllowedExternalURL(url) else {
            refreshErrorMessage = blockedMessage
            return false
        }
        dependencies.openExternalURL(url)
        return true
    }

    func uninstallableHomebrewItem(for app: AppRecord) -> HomebrewManagedItem? {
        guard let item = matchingHomebrewItem(for: app), item.kind == .cask else {
            return nil
        }
        return item
    }

    func icon(for app: AppRecord) -> NSImage {
        appIcon(for: app)
    }

    private func appIcon(for app: AppRecord) -> NSImage {
        if let cached = iconCache[app.id] {
            return cached
        }

        let icon = NSWorkspace.shared.icon(forFile: app.bundleURL.path)
        icon.size = NSSize(
            width: MenuPresentationMetrics.rowIconSize,
            height: MenuPresentationMetrics.rowIconSize
        )
        iconCache[app.id] = icon
        return icon
    }

    func icon(for item: HomebrewManagedItem) -> NSImage {
        if let cached = homebrewIconCache[item.id] {
            return cached
        }

        let baseIcon: NSImage
        if item.kind == .cask, let app = matchingApp(for: item) {
            baseIcon = appIcon(for: app)
        } else {
            baseIcon = fallbackIcon(for: item.kind)
        }

        let resolvedIcon = (baseIcon.copy() as? NSImage) ?? baseIcon
        resolvedIcon.size = NSSize(
            width: MenuPresentationMetrics.rowIconSize,
            height: MenuPresentationMetrics.rowIconSize
        )
        homebrewIconCache[item.id] = resolvedIcon
        return resolvedIcon
    }

    func icon(for item: HomebrewCaskDiscoveryItem) -> NSImage {
        fallbackIcon(for: item.kind)
    }

    func releaseDate(for app: AppRecord) -> Date {
        if let update = updatesByAppID[app.id],
           update.source == .homebrew,
           let item = matchingHomebrewItem(for: app) {
            return releaseDate(for: item)
        }

        if let updateDate = sanitizedDisplayReleaseDate(updatesByAppID[app.id]?.releaseDate) {
            return updateDate
        }
        if let cached = sanitizedDisplayReleaseDate(appReleaseDateCache[app.id]) {
            return cached
        }

        let resourceValues = try? app.bundleURL.resourceValues(
            forKeys: [.contentModificationDateKey, .creationDateKey]
        )
        let resolvedDate = sanitizedDisplayReleaseDate(resourceValues?.contentModificationDate)
            ?? sanitizedDisplayReleaseDate(resourceValues?.creationDate)
            ?? lastRefreshDate
            ?? Date()
        appReleaseDateCache[app.id] = resolvedDate
        return resolvedDate
    }

    func releaseDate(for item: HomebrewManagedItem) -> Date {
        sanitizedDisplayReleaseDate(item.releaseDate) ?? lastRefreshDate ?? Date()
    }

    func recentlyUpdatedDate(for app: AppRecord) -> Date? {
        recentlyUpdatedRecords.first(where: { $0.appID == app.id })?.updatedAt
    }

    func recentlyUpdatedDate(for item: HomebrewManagedItem) -> Date? {
        homebrewRecentlyUpdatedRecords.first(where: { $0.itemID == item.id })?.updatedAt
    }

    func addDirectory(_ directory: URL) {
        let candidate = directory.standardizedFileURL
        guard candidate.path.hasPrefix("/") else { return }
        guard !additionalDirectories.contains(candidate) else { return }
        additionalDirectories.append(candidate)
    }

    func removeDirectory(_ directory: URL) {
        additionalDirectories.removeAll { $0.standardizedFileURL == directory.standardizedFileURL }
    }

    func chooseAndAddDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Add"

        if panel.runModal() == .OK, let chosen = panel.urls.first {
            addDirectory(chosen)
        }
    }

    var menuBarTitle: String {
        if isRefreshing { return "…" }
        return "\(availableApps.count)"
    }

    var menuBarSymbol: String {
        if isRefreshing { return "arrow.triangle.2.circlepath" }
        if availableApps.isEmpty { return "checkmark.circle" }
        return "arrow.down.circle"
    }

    var displayedHomebrewDiscoverItems: [HomebrewCaskDiscoveryItem] {
        homebrewDiscoverItems
    }

    var isHomebrewDiscoverySearchActive: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var scanDirectories: [URL] {
        let defaultDirectories = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications", isDirectory: true)
        ]

        var seen: Set<String> = []
        var directories: [URL] = []

        for directory in (defaultDirectories + additionalDirectories) {
            let path = directory.standardizedFileURL.path
            if seen.insert(path).inserted {
                directories.append(directory.standardizedFileURL)
            }
        }

        return directories
    }

    private func sortedAppsByName(_ unsorted: [AppRecord]) -> [AppRecord] {
        unsorted.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    private func sortedOutdatedApps(_ unsorted: [AppRecord]) -> [AppRecord] {
        unsorted.sorted { lhs, rhs in
            let leftDate = updatesByAppID[lhs.id]?.releaseDate
                ?? updatesByAppID[lhs.id]?.checkedAt
                ?? .distantPast
            let rightDate = updatesByAppID[rhs.id]?.releaseDate
                ?? updatesByAppID[rhs.id]?.checkedAt
                ?? .distantPast

            if leftDate != rightDate {
                return leftDate > rightDate
            }

            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    private func filterBySearch(_ input: [AppRecord]) -> [AppRecord] {
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return input }

        return input.filter { app in
            app.displayName.localizedCaseInsensitiveContains(term)
                || (app.bundleIdentifier?.localizedCaseInsensitiveContains(term) ?? false)
        }
    }

    private func sortedOutdatedHomebrewItems(_ unsorted: [HomebrewManagedItem]) -> [HomebrewManagedItem] {
        unsorted.sorted { lhs, rhs in
            let leftDate = lhs.releaseDate ?? .distantPast
            let rightDate = rhs.releaseDate ?? .distantPast

            if leftDate != rightDate {
                return leftDate > rightDate
            }

            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func sortedInstalledHomebrewItems(_ unsorted: [HomebrewManagedItem]) -> [HomebrewManagedItem] {
        unsorted.sorted { lhs, rhs in
            if lhs.kind != rhs.kind {
                return lhs.kind.rawValue < rhs.kind.rawValue
            }

            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func filterHomebrewBySearch(_ input: [HomebrewManagedItem]) -> [HomebrewManagedItem] {
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return input }

        return input.filter { item in
            item.name.localizedCaseInsensitiveContains(term)
                || item.token.localizedCaseInsensitiveContains(term)
                || item.installedVersion.raw.localizedCaseInsensitiveContains(term)
                || (item.latestVersion?.raw.localizedCaseInsensitiveContains(term) ?? false)
        }
    }

    private func recomputeDerivedState() {
        availableApps = sortedOutdatedApps(
            apps.filter { updatesByAppID[$0.id] != nil && !ignoredAppIDs.contains($0.id) }
        )
        installedApps = sortedAppsByName(
            apps.filter { updatesByAppID[$0.id] == nil && !ignoredAppIDs.contains($0.id) }
        )
        ignoredApps = sortedAppsByName(
            apps.filter { ignoredAppIDs.contains($0.id) }
        )

        let appByID = Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0) })
        recentlyUpdatedApps = recentlyUpdatedRecords
            .sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
            .compactMap { record in
                guard updatesByAppID[record.appID] == nil else { return nil }
                guard !ignoredAppIDs.contains(record.appID) else { return nil }
                return appByID[record.appID]
            }

        homebrewOutdatedItems = sortedOutdatedHomebrewItems(
            homebrewItems.filter { $0.isOutdated && !ignoredHomebrewItemIDs.contains($0.id) }
        )
        homebrewInstalledItems = sortedInstalledHomebrewItems(
            homebrewItems.filter { !$0.isOutdated && !ignoredHomebrewItemIDs.contains($0.id) }
        )
        homebrewIgnoredItems = sortedInstalledHomebrewItems(
            homebrewItems.filter { ignoredHomebrewItemIDs.contains($0.id) }
        )

        let itemByID = Dictionary(uniqueKeysWithValues: homebrewItems.map { ($0.id, $0) })
        homebrewRecentlyUpdatedItems = homebrewRecentlyUpdatedRecords
            .sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
            .compactMap { record in
                guard let item = itemByID[record.itemID] else { return nil }
                guard !item.isOutdated else { return nil }
                guard !ignoredHomebrewItemIDs.contains(item.id) else { return nil }
                return item
            }

        displayedAvailableApps = filterBySearch(availableApps)
        displayedInstalledApps = filterBySearch(installedApps)
        displayedRecentlyUpdatedApps = filterBySearch(recentlyUpdatedApps)
        displayedIgnoredApps = filterBySearch(ignoredApps)
        displayedHomebrewOutdatedItems = filterHomebrewBySearch(homebrewOutdatedItems)
        displayedHomebrewRecentlyUpdatedItems = filterHomebrewBySearch(homebrewRecentlyUpdatedItems)
        displayedHomebrewInstalledItems = filterHomebrewBySearch(homebrewInstalledItems)
        displayedHomebrewIgnoredItems = filterHomebrewBySearch(homebrewIgnoredItems)
    }

    private func refreshHomebrewDiscoverItems() {
        homebrewDiscoverTask?.cancel()

        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else {
            homebrewDiscoverItems = []
            return
        }

        let dependencies = self.dependencies
        let caskIndex = latestHomebrewIndex
        let formulaIndex = latestHomebrewFormulaIndex
        let excludedCaskTokens = homebrewDiscoveryInstalledCaskTokens
        let excludedFormulaTokens = homebrewDiscoveryInstalledFormulaTokens

        homebrewDiscoverTask = Task { [weak self] in
            guard let self else { return }
            async let caskItemsResult = dependencies.searchHomebrewCasks(caskIndex, term, excludedCaskTokens)
            async let formulaItemsResult = dependencies.searchHomebrewFormulae(formulaIndex, term, excludedFormulaTokens)
            let caskItems = await caskItemsResult
            let formulaItems = await formulaItemsResult
            let items = (caskItems + formulaItems).sorted { lhs, rhs in
                if lhs.kind != rhs.kind {
                    return lhs.kind.rawValue < rhs.kind.rawValue
                }

                let nameComparison = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
                if nameComparison != .orderedSame {
                    return nameComparison == .orderedAscending
                }

                return lhs.token.localizedCaseInsensitiveCompare(rhs.token) == .orderedAscending
            }
            guard !Task.isCancelled else { return }
            self.homebrewDiscoverItems = items
        }
    }

    private func restartAutoRefreshLoop() {
        autoRefreshTask?.cancel()
        guard autoRefreshEnabled else { return }

        autoRefreshTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                let interval = UInt64(max(5, self.refreshIntervalMinutes)) * 60 * 1_000_000_000
                try? await Task.sleep(nanoseconds: interval)
                if Task.isCancelled { return }
                self.refreshNow(lightweight: true)
            }
        }
    }

    private func loadPersistedSnapshot() {
        isHydratingPersistedSnapshot = true
        defer { isHydratingPersistedSnapshot = false }

        if let data = defaults.data(forKey: PersistenceKeys.snapshot),
           let snapshot = try? JSONDecoder().decode(PersistedSnapshot.self, from: data) {
            lastPersistedSnapshotData = data
            apps = snapshot.apps
            ignoredAppIDs = Set(snapshot.ignoredIDs)
            ignoredHomebrewItemIDs = Set(snapshot.ignoredHomebrewItemIDs)
            additionalDirectories = snapshot.additionalDirectories
            selectedTab = snapshot.selectedTab
            showInstalledAppsSection = snapshot.showInstalledAppsSection
            showRecentlyUpdatedAppsSection = snapshot.showRecentlyUpdatedAppsSection
            showIgnoredAppsSection = snapshot.showIgnoredAppsSection
            showRecentlyUpdatedHomebrewSection = snapshot.showRecentlyUpdatedHomebrewSection
            showInstalledHomebrewSection = snapshot.showInstalledHomebrewSection
            showIgnoredHomebrewSection = snapshot.showIgnoredHomebrewSection
            autoRefreshEnabled = snapshot.autoRefreshEnabled
            refreshIntervalMinutes = snapshot.refreshIntervalMinutes
            useMasForAppStoreUpdates = snapshot.useMasForAppStoreUpdates
            lastRefreshDate = snapshot.lastRefreshDate
            recentlyUpdatedRecords = snapshot.recentlyUpdated
            homebrewItems = snapshot.homebrewItems
            homebrewRecentlyUpdatedRecords = snapshot.homebrewRecentlyUpdated

            var updates: [String: UpdateRecord] = [:]
            for update in snapshot.updates {
                updates[update.appID] = update
            }
            updatesByAppID = updates
        }

        if let records = loadPersistedRecentlyUpdatedRecords() {
            recentlyUpdatedRecords = records
        }
        if let records = loadPersistedRecentlyUpdatedHomebrewRecords() {
            homebrewRecentlyUpdatedRecords = records
        }

        homebrewDiscoveryInstalledCaskTokens = Set(
            homebrewItems
                .filter { $0.kind == .cask }
                .map { $0.token.lowercased() }
        )
        homebrewDiscoveryInstalledFormulaTokens = Set(
            homebrewItems
                .filter { $0.kind == .formula }
                .map { $0.token.lowercased() }
        )
    }

    private func schedulePersistSnapshot() {
        guard !isHydratingPersistedSnapshot else { return }
        isPersistSnapshotDirty = true
        guard persistSnapshotTask == nil else { return }

        persistSnapshotTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.persistSnapshotTask = nil }

            while self.isPersistSnapshotDirty {
                self.isPersistSnapshotDirty = false
                do {
                    try await Task.sleep(nanoseconds: Self.snapshotPersistDebounceNanoseconds)
                } catch {
                    return
                }
                if self.isPersistSnapshotDirty {
                    continue
                }
                self.persistSnapshotNowIfNeeded()
            }
        }
    }

    private func persistSnapshotNowIfNeeded() {
        let canonicalApps = apps.sorted { lhs, rhs in
            lhs.id < rhs.id
        }
        let canonicalUpdates = updatesByAppID.values.sorted { lhs, rhs in
            lhs.appID < rhs.appID
        }
        let canonicalRecentlyUpdatedRecords = recentlyUpdatedRecords.sorted { lhs, rhs in
            lhs.appID < rhs.appID
        }
        let canonicalHomebrewItems = homebrewItems.sorted { lhs, rhs in
            lhs.id < rhs.id
        }
        let canonicalHomebrewRecentlyUpdatedRecords = homebrewRecentlyUpdatedRecords.sorted { lhs, rhs in
            lhs.itemID < rhs.itemID
        }
        let canonicalIgnoredAppIDs = ignoredAppIDs.sorted()
        let canonicalIgnoredHomebrewItemIDs = ignoredHomebrewItemIDs.sorted()
        let canonicalAdditionalDirectories = additionalDirectories.sorted { lhs, rhs in
            lhs.path < rhs.path
        }

        let snapshot = PersistedSnapshot(
            apps: canonicalApps,
            updates: canonicalUpdates,
            recentlyUpdated: canonicalRecentlyUpdatedRecords,
            homebrewItems: canonicalHomebrewItems,
            homebrewRecentlyUpdated: canonicalHomebrewRecentlyUpdatedRecords,
            ignoredIDs: canonicalIgnoredAppIDs,
            ignoredHomebrewItemIDs: canonicalIgnoredHomebrewItemIDs,
            additionalDirectories: canonicalAdditionalDirectories,
            selectedTab: selectedTab,
            showInstalledAppsSection: showInstalledAppsSection,
            showRecentlyUpdatedAppsSection: showRecentlyUpdatedAppsSection,
            showIgnoredAppsSection: showIgnoredAppsSection,
            showRecentlyUpdatedHomebrewSection: showRecentlyUpdatedHomebrewSection,
            showInstalledHomebrewSection: showInstalledHomebrewSection,
            showIgnoredHomebrewSection: showIgnoredHomebrewSection,
            autoRefreshEnabled: autoRefreshEnabled,
            refreshIntervalMinutes: refreshIntervalMinutes,
            useMasForAppStoreUpdates: useMasForAppStoreUpdates,
            lastRefreshDate: lastRefreshDate
        )

        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        if data == lastPersistedSnapshotData {
            return
        }
        defaults.set(data, forKey: PersistenceKeys.snapshot)
        lastPersistedSnapshotData = data
        onSnapshotPersist?(data)
        persistRecentlyUpdatedRecords()
        persistRecentlyUpdatedHomebrewRecords()
    }

    private func loadPersistedRecentlyUpdatedRecords() -> [RecentlyUpdatedRecord]? {
        guard let data = defaults.data(forKey: PersistenceKeys.recentlyUpdatedRecords) else {
            return nil
        }
        return try? JSONDecoder().decode([RecentlyUpdatedRecord].self, from: data)
    }

    private func loadPersistedRecentlyUpdatedHomebrewRecords() -> [HomebrewRecentlyUpdatedRecord]? {
        guard let data = defaults.data(forKey: PersistenceKeys.homebrewRecentlyUpdatedRecords) else {
            return nil
        }
        return try? JSONDecoder().decode([HomebrewRecentlyUpdatedRecord].self, from: data)
    }

    private func persistRecentlyUpdatedRecords() {
        guard let data = try? JSONEncoder().encode(recentlyUpdatedRecords) else { return }
        defaults.set(data, forKey: PersistenceKeys.recentlyUpdatedRecords)
    }

    private func persistRecentlyUpdatedHomebrewRecords() {
        guard let data = try? JSONEncoder().encode(homebrewRecentlyUpdatedRecords) else { return }
        defaults.set(data, forKey: PersistenceKeys.homebrewRecentlyUpdatedRecords)
    }

    private func flushPendingPersistence() {
        let hadPendingTask = persistSnapshotTask != nil
        let wasDirty = isPersistSnapshotDirty
        persistSnapshotTask?.cancel()
        persistSnapshotTask = nil
        isPersistSnapshotDirty = false
        guard hadPendingTask || wasDirty else { return }
        persistSnapshotNowIfNeeded()
    }

    func flushPendingPersistenceForTesting() {
        flushPendingPersistence()
    }

    private func schedulePostExternalUpdateRefresh(for appID: String) {
        pendingExternalUpdateRefreshTasks[appID]?.cancel()

        let delays = externalUpdateRefreshDelaySeconds
        pendingExternalUpdateRefreshTasks[appID] = Task { [weak self] in
            guard let self else { return }
            defer { self.pendingExternalUpdateRefreshTasks[appID] = nil }

            for delaySeconds in delays {
                if Task.isCancelled { return }
                if delaySeconds > 0 {
                    try? await Task.sleep(nanoseconds: delaySeconds * 1_000_000_000)
                }
                if Task.isCancelled { return }
                if self.updatesByAppID[appID] == nil { return }
                if self.isRefreshing { continue }

                self.refreshNow(lightweight: true)
            }
        }
    }

    private func setPostRefreshErrorMessage(_ message: String) async {
        let timeout = Date().addingTimeInterval(2.0)
        while isRefreshing && Date() < timeout {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        refreshErrorMessage = message
    }

    private func pruneIconCache() {
        let validIDs = Set(apps.map(\.id))
        iconCache = iconCache.filter { validIDs.contains($0.key) }
        appReleaseDateCache = appReleaseDateCache.filter { validIDs.contains($0.key) }

        let validHomebrewIDs = Set(homebrewItems.map(\.id))
        homebrewIconCache = homebrewIconCache.filter { validHomebrewIDs.contains($0.key) }
    }

    private func fallbackIcon(for kind: HomebrewManagedItemKind) -> NSImage {
        let symbolName = kind == .formula ? "terminal" : "shippingbox"
        if let placeholder = placeholderIcon(symbolName: symbolName) {
            return placeholder
        }
        return NSWorkspace.shared.icon(for: .application)
    }

    private func placeholderIcon(symbolName: String) -> NSImage? {
        guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) else {
            return nil
        }

        let sizeValue = MenuPresentationMetrics.rowIconSize
        let placeholderSizeValue = sizeValue * MenuPresentationMetrics.homebrewPlaceholderBoxScale
        let glyphSizeValue = placeholderSizeValue * MenuPresentationMetrics.homebrewPlaceholderGlyphScale
        let canvasSize = NSSize(width: sizeValue, height: sizeValue)
        let symbolConfig = NSImage.SymbolConfiguration(
            pointSize: glyphSizeValue,
            weight: .medium
        )
        let configuredSymbol = symbol.withSymbolConfiguration(symbolConfig) ?? symbol
        let colorConfig = NSImage.SymbolConfiguration(
            hierarchicalColor: NSColor.labelColor.withAlphaComponent(MenuPresentationMetrics.homebrewPlaceholderGlyphAlpha)
        )
        let tintedSymbol = configuredSymbol.withSymbolConfiguration(colorConfig) ?? configuredSymbol

        let image = NSImage(size: canvasSize)
        image.lockFocus()

        let backgroundRect = NSRect(
            x: (canvasSize.width - placeholderSizeValue) * 0.5,
            y: (canvasSize.height - placeholderSizeValue) * 0.5,
            width: placeholderSizeValue,
            height: placeholderSizeValue
        )
        let backgroundPath = NSBezierPath(
            roundedRect: backgroundRect,
            xRadius: MenuPresentationMetrics.rowIconCornerRadius * MenuPresentationMetrics.homebrewPlaceholderBoxScale,
            yRadius: MenuPresentationMetrics.rowIconCornerRadius * MenuPresentationMetrics.homebrewPlaceholderBoxScale
        )
        NSColor.tertiaryLabelColor.withAlphaComponent(0.18).setFill()
        backgroundPath.fill()

        let glyphRect = NSRect(
            x: (canvasSize.width - glyphSizeValue) * 0.5,
            y: (canvasSize.height - glyphSizeValue) * 0.5,
            width: glyphSizeValue,
            height: glyphSizeValue
        )
        tintedSymbol.draw(
            in: glyphRect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: nil
        )

        image.unlockFocus()
        return image
    }

    private func matchingApp(for item: HomebrewManagedItem) -> AppRecord? {
        for app in apps {
            if updatesByAppID[app.id]?.homebrewToken?.lowercased() == item.token.lowercased() {
                return app
            }
        }

        let normalizedToken = normalizedHomebrewToken(item.token)
        return apps.first { app in
            let filename = app.bundleURL.deletingPathExtension().lastPathComponent
            let normalizedName = normalizedHomebrewToken(filename)
            return normalizedName == normalizedToken
        }
    }

    private func matchingHomebrewItem(for app: AppRecord) -> HomebrewManagedItem? {
        guard
            let update = updatesByAppID[app.id],
            update.source == .homebrew
        else {
            return nil
        }

        if let token = update.homebrewToken?.lowercased(),
           let byToken = homebrewItems.first(where: { $0.token.lowercased() == token }) {
            return byToken
        }

        let normalizedAppName = normalizedHomebrewToken(
            app.bundleURL.deletingPathExtension().lastPathComponent
        )
        return homebrewItems.first { item in
            normalizedHomebrewToken(item.token) == normalizedAppName
        }
    }

    private func normalizedHomebrewToken(_ raw: String) -> String {
        raw
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .joined(separator: "-")
    }

    private func sanitizedDisplayReleaseDate(_ date: Date?) -> Date? {
        guard let date else { return nil }
        return date >= minimumPlausibleDisplayReleaseDate ? date : nil
    }

    private var minimumPlausibleDisplayReleaseDate: Date {
        Date(timeIntervalSince1970: 946_684_800) // 2000-01-01T00:00:00Z
    }

    private static func mergeRecentlyUpdatedRecords(
        previousRecords: [RecentlyUpdatedRecord],
        previousAppsByID: [String: AppRecord],
        previousUpdatesByID: [String: UpdateRecord],
        currentAppsByID: [String: AppRecord],
        currentUpdatesByID: [String: UpdateRecord],
        at date: Date
    ) -> [RecentlyUpdatedRecord] {
        var recordsByID = Dictionary(uniqueKeysWithValues: previousRecords.map { ($0.appID, $0) })

        for (appID, previousUpdate) in previousUpdatesByID {
            guard currentUpdatesByID[appID] == nil else { continue }
            guard let currentApp = currentAppsByID[appID] else { continue }
            guard !currentApp.localVersion.isEmpty else { continue }
            guard currentApp.localVersion >= previousUpdate.remoteVersion else { continue }

            let priorVersion = previousAppsByID[appID]?.localVersion ?? previousUpdate.localVersion
            guard currentApp.localVersion > priorVersion || currentApp.localVersion >= previousUpdate.remoteVersion else {
                continue
            }

            recordsByID[appID] = RecentlyUpdatedRecord(
                appID: appID,
                displayName: currentApp.displayName,
                fromVersion: priorVersion,
                toVersion: currentApp.localVersion,
                updatedAt: date
            )
        }

        let retained = recordsByID.values.filter { record in
            if let app = currentAppsByID[record.appID] {
                guard currentUpdatesByID[record.appID] == nil else { return false }
                guard app.localVersion >= record.toVersion else { return false }
            }
            return date.timeIntervalSince(record.updatedAt) <= recentlyUpdatedRetention
        }

        return retained
            .sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
            .prefix(recentlyUpdatedLimit)
            .map { $0 }
    }

    private static func mergeRecentlyUpdatedHomebrewRecords(
        previousRecords: [HomebrewRecentlyUpdatedRecord],
        previousItemsByID: [String: HomebrewManagedItem],
        currentItemsByID: [String: HomebrewManagedItem],
        at date: Date
    ) -> [HomebrewRecentlyUpdatedRecord] {
        var recordsByID = Dictionary(uniqueKeysWithValues: previousRecords.map { ($0.itemID, $0) })

        for (itemID, previousItem) in previousItemsByID {
            guard previousItem.isOutdated else { continue }
            guard let currentItem = currentItemsByID[itemID] else { continue }
            guard !currentItem.isOutdated else { continue }
            guard !currentItem.installedVersion.isEmpty else { continue }

            let didVersionAdvance = currentItem.installedVersion > previousItem.installedVersion
            let satisfiedPriorTargetVersion = previousItem.latestVersion.map {
                currentItem.installedVersion >= $0
            } ?? false
            guard didVersionAdvance || satisfiedPriorTargetVersion else { continue }

            recordsByID[itemID] = HomebrewRecentlyUpdatedRecord(
                itemID: itemID,
                token: currentItem.token,
                kind: currentItem.kind,
                displayName: currentItem.name,
                fromVersion: previousItem.installedVersion,
                toVersion: currentItem.installedVersion,
                updatedAt: date
            )
        }

        let retained = recordsByID.values.filter { record in
            if let item = currentItemsByID[record.itemID] {
                guard !item.isOutdated else { return false }
                guard item.installedVersion >= record.toVersion else { return false }
            }
            return date.timeIntervalSince(record.updatedAt) <= recentlyUpdatedRetention
        }

        return retained
            .sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
            .prefix(recentlyUpdatedLimit)
            .map { $0 }
    }

    private static func mergeInferredRecentlyUpdatedHomebrewRecords(
        previousRecords: [HomebrewRecentlyUpdatedRecord],
        inferredTransitions: [InferredHomebrewRecentlyUpdatedTransition],
        at date: Date
    ) -> [HomebrewRecentlyUpdatedRecord] {
        guard !inferredTransitions.isEmpty else { return previousRecords }

        var recordsByID = Dictionary(uniqueKeysWithValues: previousRecords.map { ($0.itemID, $0) })

        for transition in inferredTransitions {
            if let existing = recordsByID[transition.itemID], existing.toVersion >= transition.toVersion {
                continue
            }

            recordsByID[transition.itemID] = HomebrewRecentlyUpdatedRecord(
                itemID: transition.itemID,
                token: transition.token,
                kind: transition.kind,
                displayName: transition.displayName,
                fromVersion: transition.fromVersion,
                toVersion: transition.toVersion,
                updatedAt: date
            )
        }

        return recordsByID.values
            .sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
            .prefix(recentlyUpdatedLimit)
            .map { $0 }
    }

    private static func computeRefresh(
        directories: [URL],
        dependencies: UpdateStoreDependencies,
        mode: RefreshMode,
        cacheState: RefreshCacheState,
        now: Date
    ) async -> RefreshResult {
        var cacheState = cacheState
        let shouldUseCache = mode.usesCachedValues
        let cacheTTL = refreshCacheTTL

        cacheState.pruneExpired(now: now, ttl: cacheTTL)

        let canUseCachedHomebrewIndex = shouldUseCache
            && (cacheState.homebrewIndex?.isFresh(at: now, ttl: cacheTTL) ?? false)
        let canUseCachedHomebrewFormulaIndex = shouldUseCache
            && (cacheState.homebrewFormulaIndex?.isFresh(at: now, ttl: cacheTTL) ?? false)
        let canUseCachedHomebrewInventory = shouldUseCache
            && (cacheState.homebrewInventory?.isFresh(at: now, ttl: cacheTTL) ?? false)
        let cachedHomebrewIndexEntry = canUseCachedHomebrewIndex ? cacheState.homebrewIndex : nil
        let cachedHomebrewFormulaIndexEntry = canUseCachedHomebrewFormulaIndex ? cacheState.homebrewFormulaIndex : nil
        let cachedHomebrewInventoryEntry = canUseCachedHomebrewInventory ? cacheState.homebrewInventory : nil

        async let appsResult = dependencies.scanApplications(directories)
        async let homebrewIndexEntryResult: TimedCacheEntry<HomebrewCaskIndex> = {
            if let cachedHomebrewIndexEntry {
                return cachedHomebrewIndexEntry
            }
            let fetched = await dependencies.fetchHomebrewIndex()
            return TimedCacheEntry(value: fetched, fetchedAt: now)
        }()
        async let homebrewFormulaIndexEntryResult: TimedCacheEntry<HomebrewFormulaIndex> = {
            if let cachedHomebrewFormulaIndexEntry {
                return cachedHomebrewFormulaIndexEntry
            }
            let fetched = await dependencies.fetchHomebrewFormulaIndex()
            return TimedCacheEntry(value: fetched, fetchedAt: now)
        }()
        async let homebrewInventoryEntryResult: TimedCacheEntry<[HomebrewManagedItem]> = {
            if let cachedHomebrewInventoryEntry {
                return cachedHomebrewInventoryEntry
            }
            let fetched = await dependencies.fetchHomebrewInventory()
            return TimedCacheEntry(value: fetched, fetchedAt: now)
        }()

        let apps = await appsResult
        let homebrewIndexEntry = await homebrewIndexEntryResult
        let homebrewFormulaIndexEntry = await homebrewFormulaIndexEntryResult
        let homebrewInventoryEntry = await homebrewInventoryEntryResult
        let homebrewIndex = homebrewIndexEntry.value
        let homebrewFormulaIndex = homebrewFormulaIndexEntry.value
        let homebrewInventory = homebrewInventoryEntry.value

        cacheState.homebrewIndex = homebrewIndexEntry
        cacheState.homebrewFormulaIndex = homebrewFormulaIndexEntry
        cacheState.homebrewInventory = homebrewInventoryEntry
        if !canUseCachedHomebrewIndex {
            cacheState.homebrewLookup.removeAll()
        }

        var appStoreLookupMemo: [AppStoreLookupCacheKey: LookupOutcome<AppStoreLookupResult>] = [:]
        var sparkleLookupMemo: [SparkleLookupCacheKey: LookupOutcome<SparkleLookupResult>] = [:]
        var homebrewLookupMemo: [HomebrewLookupCacheKey: LookupOutcome<HomebrewLookupResult>] = [:]

        var updates: [String: UpdateRecord] = [:]
        var transientLookupFailureCount = 0

        func cachedAppStoreLookup(
            bundleIdentifier: String,
            localVersion: Version
        ) async -> LookupOutcome<AppStoreLookupResult> {
            let key = AppStoreLookupCacheKey(
                bundleIdentifier: bundleIdentifier.lowercased(),
                localVersion: localVersion
            )
            if let memoized = appStoreLookupMemo[key] {
                return memoized
            }

            if shouldUseCache,
               let cached = cacheState.appStoreLookup[key],
               cached.isFresh(at: now, ttl: cacheTTL) {
                let cachedOutcome = LookupOutcome<AppStoreLookupResult>.completed(value: cached.value)
                appStoreLookupMemo[key] = cachedOutcome
                return cachedOutcome
            }

            let fetchedOutcome = await dependencies.lookupAppStoreOutcome(bundleIdentifier, localVersion)
            switch fetchedOutcome {
            case .completed(let value):
                cacheState.appStoreLookup[key] = TimedCacheEntry(value: value, fetchedAt: now)
            case .transientFailure:
                transientLookupFailureCount += 1
                if let cached = cacheState.appStoreLookup[key] {
                    let cachedOutcome = LookupOutcome<AppStoreLookupResult>.completed(value: cached.value)
                    appStoreLookupMemo[key] = cachedOutcome
                    return cachedOutcome
                }
            }
            appStoreLookupMemo[key] = fetchedOutcome
            return fetchedOutcome
        }

        func cachedSparkleLookup(
            feedURL: URL,
            localVersion: Version
        ) async -> LookupOutcome<SparkleLookupResult> {
            let key = SparkleLookupCacheKey(
                feedURL: feedURL.absoluteString,
                localVersion: localVersion
            )
            if let memoized = sparkleLookupMemo[key] {
                return memoized
            }

            if shouldUseCache,
               let cached = cacheState.sparkleLookup[key],
               cached.isFresh(at: now, ttl: cacheTTL) {
                let cachedOutcome = LookupOutcome<SparkleLookupResult>.completed(value: cached.value)
                sparkleLookupMemo[key] = cachedOutcome
                return cachedOutcome
            }

            let fetchedOutcome = await dependencies.lookupSparkleOutcome(feedURL, localVersion)
            switch fetchedOutcome {
            case .completed(let value):
                cacheState.sparkleLookup[key] = TimedCacheEntry(value: value, fetchedAt: now)
            case .transientFailure:
                transientLookupFailureCount += 1
                if let cached = cacheState.sparkleLookup[key] {
                    let cachedOutcome = LookupOutcome<SparkleLookupResult>.completed(value: cached.value)
                    sparkleLookupMemo[key] = cachedOutcome
                    return cachedOutcome
                }
            }
            sparkleLookupMemo[key] = fetchedOutcome
            return fetchedOutcome
        }

        func cachedHomebrewLookup(
            bundleIdentifier: String?,
            appBundleName: String,
            localVersion: Version
        ) async -> LookupOutcome<HomebrewLookupResult> {
            let key = HomebrewLookupCacheKey(
                bundleIdentifier: bundleIdentifier?.lowercased(),
                appBundleName: appBundleName.lowercased(),
                localVersion: localVersion
            )
            if let memoized = homebrewLookupMemo[key] {
                return memoized
            }

            if shouldUseCache,
               let cached = cacheState.homebrewLookup[key],
               cached.isFresh(at: now, ttl: cacheTTL) {
                let cachedOutcome = LookupOutcome<HomebrewLookupResult>.completed(value: cached.value)
                homebrewLookupMemo[key] = cachedOutcome
                return cachedOutcome
            }

            let fetchedOutcome = await dependencies.lookupHomebrewOutcome(
                homebrewIndex,
                bundleIdentifier,
                appBundleName,
                localVersion
            )
            switch fetchedOutcome {
            case .completed(let value):
                cacheState.homebrewLookup[key] = TimedCacheEntry(value: value, fetchedAt: now)
            case .transientFailure:
                transientLookupFailureCount += 1
                if let cached = cacheState.homebrewLookup[key] {
                    let cachedOutcome = LookupOutcome<HomebrewLookupResult>.completed(value: cached.value)
                    homebrewLookupMemo[key] = cachedOutcome
                    return cachedOutcome
                }
            }
            homebrewLookupMemo[key] = fetchedOutcome
            return fetchedOutcome
        }

        for app in apps {
            if Task.isCancelled {
                break
            }

            if let bundleIdentifier = app.bundleIdentifier,
               case .completed(let appStoreUpdate?) = await cachedAppStoreLookup(
                   bundleIdentifier: bundleIdentifier,
                   localVersion: app.localVersion
               ) {
                updates[app.id] = UpdateRecord(
                    appID: app.id,
                    source: .appStore,
                    supportLevel: .supported,
                    localVersion: app.localVersion,
                    remoteVersion: appStoreUpdate.remoteVersion,
                    updateURL: SecurityPolicy.sanitizeExternalURL(appStoreUpdate.updateURL),
                    appStoreItemID: appStoreUpdate.appStoreItemID,
                    homebrewToken: nil,
                    releaseNotesURL: nil,
                    releaseNotesSummary: appStoreUpdate.releaseNotesSummary,
                    releaseDate: appStoreUpdate.releaseDate,
                    checkedAt: now
                )
                continue
            }

            if let feedURL = app.sparkleFeedURL,
               case .completed(let sparkleUpdate?) = await cachedSparkleLookup(
                   feedURL: feedURL,
                   localVersion: app.localVersion
               ) {
                updates[app.id] = UpdateRecord(
                    appID: app.id,
                    source: .sparkle,
                    supportLevel: .limited,
                    localVersion: app.localVersion,
                    remoteVersion: sparkleUpdate.remoteVersion,
                    updateURL: SecurityPolicy.sanitizeExternalURL(sparkleUpdate.updateURL),
                    homebrewToken: nil,
                    releaseNotesURL: SecurityPolicy.sanitizeExternalURL(sparkleUpdate.releaseNotesURL),
                    releaseNotesSummary: nil,
                    releaseDate: sparkleUpdate.releaseDate,
                    checkedAt: now
                )
                continue
            }

            let appBundleName = app.bundleURL.lastPathComponent
            if case .completed(let homebrewUpdate?) = await cachedHomebrewLookup(
                bundleIdentifier: app.bundleIdentifier,
                appBundleName: appBundleName,
                localVersion: app.localVersion
            ) {
                guard SecurityPolicy.isValidHomebrewToken(homebrewUpdate.token) else {
                    continue
                }

                updates[app.id] = UpdateRecord(
                    appID: app.id,
                    source: .homebrew,
                    supportLevel: .limited,
                    localVersion: app.localVersion,
                    remoteVersion: homebrewUpdate.remoteVersion,
                    updateURL: nil,
                    appStoreItemID: nil,
                    homebrewToken: homebrewUpdate.token,
                    releaseNotesURL: nil,
                    releaseNotesSummary: "Token: \(homebrewUpdate.token)",
                    releaseDate: nil,
                    checkedAt: now
                )
            }
        }

        let laggingHomebrewCaskTokens = detectLaggingHomebrewCaskTokens(
            inventory: homebrewInventory,
            with: updates
        )

        let reconciledHomebrewInventory = reconcileHomebrewInventory(
            homebrewInventory,
            with: updates
        )
        let installedAppVersionsByHomebrewToken = homebrewInstalledAppVersionsByToken(
            from: apps,
            homebrewIndex: homebrewIndex
        )
        let sanitizedHomebrewInventory = sanitizeStaleOutdatedHomebrewInventory(
            reconciledHomebrewInventory,
            installedAppVersionsByHomebrewToken: installedAppVersionsByHomebrewToken
        )

        return RefreshResult(
            apps: apps,
            updates: updates,
            homebrewIndex: homebrewIndex,
            homebrewFormulaIndex: homebrewFormulaIndex,
            homebrewItems: sanitizedHomebrewInventory.items,
            laggingHomebrewCaskTokens: laggingHomebrewCaskTokens,
            inferredHomebrewRecentlyUpdatedTransitions: sanitizedHomebrewInventory.inferredRecentlyUpdatedTransitions,
            lastRefreshDate: now,
            errorMessage: nil,
            noticeMessage: transientLookupFailureCount > 0
                ? "Some update checks could not be reached. Baseline kept available cached results where possible."
                : nil,
            cacheState: cacheState
        )
    }

    private static func homebrewUpdateVersionsByToken(
        with updates: [String: UpdateRecord]
    ) -> [String: Version] {
        updates.values.reduce(into: [String: Version]()) { result, update in
            guard update.source == .homebrew else { return }
            guard let token = update.homebrewToken?.lowercased(), !token.isEmpty else { return }

            let remoteVersion = update.remoteVersion
            if let existing = result[token] {
                result[token] = max(existing, remoteVersion)
            } else {
                result[token] = remoteVersion
            }
        }
    }

    private static func detectLaggingHomebrewCaskTokens(
        inventory: [HomebrewManagedItem],
        with updates: [String: UpdateRecord]
    ) -> Set<String> {
        let homebrewUpdatesByToken = homebrewUpdateVersionsByToken(with: updates)
        guard !homebrewUpdatesByToken.isEmpty else {
            return []
        }

        var laggingTokens: Set<String> = []
        for item in inventory {
            guard item.kind == .cask else { continue }
            let token = item.token.lowercased()
            guard let remoteVersion = homebrewUpdatesByToken[token] else { continue }
            guard remoteVersion > item.installedVersion else { continue }
            guard !item.isOutdated else { continue }
            laggingTokens.insert(token)
        }

        return laggingTokens
    }

    private static func reconcileHomebrewInventory(
        _ inventory: [HomebrewManagedItem],
        with updates: [String: UpdateRecord]
    ) -> [HomebrewManagedItem] {
        let homebrewUpdatesByToken = homebrewUpdateVersionsByToken(with: updates)

        guard !homebrewUpdatesByToken.isEmpty else {
            return inventory
        }

        return inventory.map { item in
            guard item.kind == .cask else { return item }
            guard let remoteVersion = homebrewUpdatesByToken[item.token.lowercased()] else { return item }
            guard remoteVersion > item.installedVersion else { return item }

            let reconciledLatestVersion = item.latestVersion.map { max($0, remoteVersion) } ?? remoteVersion

            return HomebrewManagedItem(
                token: item.token,
                name: item.name,
                kind: item.kind,
                installedVersion: item.installedVersion,
                latestVersion: reconciledLatestVersion,
                isOutdated: true,
                releaseDate: item.releaseDate
            )
        }
    }

    private static func homebrewInstalledAppVersionsByToken(
        from apps: [AppRecord],
        homebrewIndex: HomebrewCaskIndex
    ) -> [String: Version] {
        var versionsByToken: [String: Version] = [:]

        for app in apps {
            guard !app.localVersion.isEmpty else { continue }

            let token: String?
            if let bundleIdentifier = app.bundleIdentifier?.lowercased(),
               let entry = homebrewIndex.byBundleIdentifier[bundleIdentifier] {
                token = entry.token
            } else {
                let appBundleName = normalizedAppBundleName(app.bundleURL.lastPathComponent)
                if let entries = homebrewIndex.byAppBundleName[appBundleName], !entries.isEmpty {
                    token = preferredHomebrewEntry(from: entries)?.token
                } else {
                    token = nil
                }
            }

            guard let token else { continue }
            let key = token.lowercased()
            if let existingVersion = versionsByToken[key] {
                versionsByToken[key] = max(existingVersion, app.localVersion)
            } else {
                versionsByToken[key] = app.localVersion
            }
        }

        return versionsByToken
    }

    private static func discoveryInstalledHomebrewTokens(
        apps: [AppRecord],
        homebrewItems: [HomebrewManagedItem],
        homebrewIndex: HomebrewCaskIndex
    ) -> (caskTokens: Set<String>, formulaTokens: Set<String>) {
        var caskTokens = Set(
            homebrewItems
                .filter { $0.kind == .cask }
                .map { $0.token.lowercased() }
        )
        let formulaTokens = Set(
            homebrewItems
                .filter { $0.kind == .formula }
                .map { $0.token.lowercased() }
        )
        let inferred = homebrewInstalledAppVersionsByToken(
            from: apps,
            homebrewIndex: homebrewIndex
        )
        caskTokens.formUnion(inferred.keys)
        return (caskTokens, formulaTokens)
    }

    private static func normalizedAppBundleName(_ raw: String) -> String {
        let filename = URL(fileURLWithPath: raw).lastPathComponent.lowercased()
        if filename.hasSuffix(".app") {
            return filename
        }
        return "\(filename).app"
    }

    private static func preferredHomebrewEntry(from entries: [HomebrewCaskEntry]) -> HomebrewCaskEntry? {
        entries.max { lhs, rhs in
            if lhs.version != rhs.version {
                return lhs.version < rhs.version
            }
            return lhs.token.localizedCaseInsensitiveCompare(rhs.token) == .orderedDescending
        }
    }

    private static func sanitizeStaleOutdatedHomebrewInventory(
        _ inventory: [HomebrewManagedItem],
        installedAppVersionsByHomebrewToken: [String: Version]
    ) -> SanitizedHomebrewInventory {
        var inferredTransitions: [InferredHomebrewRecentlyUpdatedTransition] = []
        let items = inventory.map { item in
            guard item.kind == .cask else { return item }
            guard item.isOutdated else { return item }
            guard let latestVersion = item.latestVersion else { return item }
            guard let installedAppVersion = installedAppVersionsByHomebrewToken[item.token.lowercased()] else {
                return item
            }
            guard installedAppVersion >= latestVersion else { return item }

            inferredTransitions.append(
                InferredHomebrewRecentlyUpdatedTransition(
                    itemID: item.id,
                    token: item.token,
                    kind: item.kind,
                    displayName: item.name,
                    fromVersion: item.installedVersion,
                    toVersion: installedAppVersion
                )
            )

            return HomebrewManagedItem(
                token: item.token,
                name: item.name,
                kind: item.kind,
                installedVersion: installedAppVersion,
                latestVersion: nil,
                isOutdated: false,
                releaseDate: item.releaseDate
            )
        }
        return SanitizedHomebrewInventory(
            items: items,
            inferredRecentlyUpdatedTransitions: inferredTransitions
        )
    }

}

private struct RefreshResult {
    let apps: [AppRecord]
    let updates: [String: UpdateRecord]
    let homebrewIndex: HomebrewCaskIndex
    let homebrewFormulaIndex: HomebrewFormulaIndex
    let homebrewItems: [HomebrewManagedItem]
    let laggingHomebrewCaskTokens: Set<String>
    let inferredHomebrewRecentlyUpdatedTransitions: [InferredHomebrewRecentlyUpdatedTransition]
    let lastRefreshDate: Date
    let errorMessage: String?
    let noticeMessage: String?
    let cacheState: RefreshCacheState
}

private struct SanitizedHomebrewInventory {
    let items: [HomebrewManagedItem]
    let inferredRecentlyUpdatedTransitions: [InferredHomebrewRecentlyUpdatedTransition]
}

private struct InferredHomebrewRecentlyUpdatedTransition {
    let itemID: String
    let token: String
    let kind: HomebrewManagedItemKind
    let displayName: String
    let fromVersion: Version
    let toVersion: Version
}
