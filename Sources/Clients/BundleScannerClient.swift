import Foundation

actor BundleScannerClient {
    private let fileManager = FileManager.default
    private var metadataCacheByPath: [String: CachedMetadata] = [:]

    private struct CachedMetadata {
        let signature: AppBundleSignature
        let record: AppRecord
    }

    private struct AppBundleSignature: Equatable {
        let infoPlistModificationDate: Date?
        let infoPlistFileSize: Int?
        let bundleModificationDate: Date?
        let hasAppStoreReceipt: Bool
    }

    func scanApplications(in directories: [URL]) async -> [AppRecord] {
        let resolvedDirectories = directories.map { $0.standardizedFileURL }
        var recordsByPath: [String: AppRecord] = [:]
        var scannedAppPaths: Set<String> = []

        for directory in resolvedDirectories {
            guard directory.path.hasPrefix("/") else { continue }
            guard fileManager.fileExists(atPath: directory.path) else { continue }

            let options: FileManager.DirectoryEnumerationOptions = [
                .skipsHiddenFiles,
                .producesRelativePathURLs,
                .skipsPackageDescendants
            ]

            guard let enumerator = fileManager.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey, .nameKey],
                options: options
            ) else {
                continue
            }

            while let candidateURL = enumerator.nextObject() as? URL {
                if candidateURL.pathExtension.caseInsensitiveCompare("app") != .orderedSame {
                    continue
                }

                let standardizedURL = candidateURL.standardizedFileURL
                scannedAppPaths.insert(standardizedURL.path)

                if let record = makeRecord(for: standardizedURL) {
                    recordsByPath[record.id] = record
                }
            }
        }

        if !metadataCacheByPath.isEmpty {
            metadataCacheByPath = metadataCacheByPath.filter { scannedAppPaths.contains($0.key) }
        }

        return recordsByPath.values.sorted { lhs, rhs in
            lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    private func makeRecord(for appURL: URL) -> AppRecord? {
        let signature = appBundleSignature(for: appURL)
        if let signature,
           let cached = metadataCacheByPath[appURL.path],
           cached.signature == signature {
            return cached.record
        }

        let info = (NSDictionary(
            contentsOf: appURL
                .appendingPathComponent("Contents")
                .appendingPathComponent("Info.plist")
        ) as? [String: Any]) ?? [:]
        let displayName = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? appURL.deletingPathExtension().lastPathComponent

        let bundleIdentifier = info["CFBundleIdentifier"] as? String
        let shortVersion = (info["CFBundleShortVersionString"] as? String)
            ?? (info["CFBundleVersion"] as? String)

        let sparkleFeedURL = (info["SUFeedURL"] as? String)
            .flatMap(URL.init(string:))
            .flatMap { url in
                SecurityPolicy.isAllowedFeedURL(url) ? url : nil
            }
        let hasAppStoreReceipt = signature?.hasAppStoreReceipt ?? fileManager.fileExists(
            atPath: appURL
                .appendingPathComponent("Contents")
                .appendingPathComponent("_MASReceipt")
                .appendingPathComponent("receipt")
                .path
        )

        let sourceHint: UpdateSource
        if hasAppStoreReceipt {
            sourceHint = .appStore
        } else if sparkleFeedURL != nil {
            sourceHint = .sparkle
        } else {
            sourceHint = .unknown
        }

        let record = AppRecord(
            bundleURL: appURL,
            displayName: displayName,
            bundleIdentifier: bundleIdentifier,
            localVersion: Version(shortVersion),
            sourceHint: sourceHint,
            sparkleFeedURL: sparkleFeedURL
        )

        if let signature {
            metadataCacheByPath[appURL.path] = CachedMetadata(
                signature: signature,
                record: record
            )
        } else {
            metadataCacheByPath.removeValue(forKey: appURL.path)
        }

        return record
    }

    private func appBundleSignature(for appURL: URL) -> AppBundleSignature? {
        let infoPlistURL = appURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("Info.plist")
        let appStoreReceiptURL = appURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("_MASReceipt")
            .appendingPathComponent("receipt")

        let infoPlistValues = try? infoPlistURL.resourceValues(
            forKeys: [.contentModificationDateKey, .fileSizeKey]
        )
        let bundleValues = try? appURL.resourceValues(
            forKeys: [.contentModificationDateKey]
        )
        let hasAppStoreReceipt = fileManager.fileExists(atPath: appStoreReceiptURL.path)

        guard
            infoPlistValues?.contentModificationDate != nil
                || infoPlistValues?.fileSize != nil
                || bundleValues?.contentModificationDate != nil
        else {
            return nil
        }

        return AppBundleSignature(
            infoPlistModificationDate: infoPlistValues?.contentModificationDate,
            infoPlistFileSize: infoPlistValues?.fileSize,
            bundleModificationDate: bundleValues?.contentModificationDate,
            hasAppStoreReceipt: hasAppStoreReceipt
        )
    }
}
