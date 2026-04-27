import Darwin
import Foundation

enum SecurityPolicy {
    static let appStoreLookupMaxBytes = 1 * 1024 * 1024
    static let sparkleAppcastMaxBytes = 2 * 1024 * 1024
    static let homebrewIndexMaxBytes = 25 * 1024 * 1024

    private static let homebrewTokenSegmentRegex = try! NSRegularExpression(
        pattern: "^[a-z0-9][a-z0-9+._@-]{0,127}$"
    )

    static func sanitizeExternalURL(_ url: URL?) -> URL? {
        guard let url else { return nil }
        return isAllowedExternalURL(url) ? url : nil
    }

    static func isAllowedExternalURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" else { return false }
        guard let host = url.host, !host.isEmpty else { return false }
        return true
    }

    static func isAllowedFeedURL(_ url: URL) -> Bool {
        guard isAllowedExternalURL(url) else { return false }
        guard let host = url.host?.lowercased(), !host.isEmpty else { return false }

        if host == "localhost" || host.hasSuffix(".localhost") {
            return false
        }

        if let ipv4 = parseIPv4(host) {
            return !isDisallowedIPv4(ipv4)
        }

        if let ipv6 = parseIPv6(host) {
            return !isDisallowedIPv6(ipv6)
        }

        return true
    }

    static func isValidHomebrewToken(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed == token else { return false }

        let segments = token
            .split(separator: "/", omittingEmptySubsequences: false)
            .map(String.init)
        guard segments.count == 1 || segments.count == 3 else { return false }

        return segments.allSatisfy(isValidHomebrewTokenSegment)
    }

    private static func isValidHomebrewTokenSegment(_ segment: String) -> Bool {
        guard !segment.isEmpty else { return false }
        let range = NSRange(location: 0, length: segment.utf16.count)
        return homebrewTokenSegmentRegex.firstMatch(in: segment, options: [], range: range) != nil
    }

    static func resolveExecutableURL(
        candidates: [String],
        fileManager: FileManager = .default
    ) -> URL? {
        for candidate in candidates {
            guard candidate.hasPrefix("/") else { continue }
            let url = URL(fileURLWithPath: candidate)
            guard url.lastPathComponent != "env" else { continue }

            var isDirectory = ObjCBool(false)
            guard fileManager.fileExists(atPath: candidate, isDirectory: &isDirectory) else { continue }
            guard !isDirectory.boolValue else { continue }
            guard fileManager.isExecutableFile(atPath: candidate) else { continue }

            return url
        }
        return nil
    }

    static func resolvedBrewExecutableURL(fileManager: FileManager = .default) -> URL? {
        resolveExecutableURL(
            candidates: [
                "/opt/homebrew/bin/brew",
                "/usr/local/bin/brew"
            ],
            fileManager: fileManager
        )
    }

    static func resolvedMasExecutableURL(fileManager: FileManager = .default) -> URL? {
        resolveExecutableURL(
            candidates: [
                "/opt/homebrew/bin/mas",
                "/usr/local/bin/mas"
            ],
            fileManager: fileManager
        )
    }

    private static func parseIPv4(_ host: String) -> [UInt8]? {
        var addr = in_addr()
        let parseResult = host.withCString { pointer in
            inet_pton(AF_INET, pointer, &addr)
        }
        guard parseResult == 1 else { return nil }

        let value = UInt32(bigEndian: addr.s_addr)
        return [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF)
        ]
    }

    private static func parseIPv6(_ host: String) -> [UInt8]? {
        var addr = in6_addr()
        let parseResult = host.withCString { pointer in
            inet_pton(AF_INET6, pointer, &addr)
        }
        guard parseResult == 1 else { return nil }

        return withUnsafeBytes(of: &addr) { rawBuffer in
            Array(rawBuffer)
        }
    }

    private static func isDisallowedIPv4(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 4 else { return false }

        let first = bytes[0]
        let second = bytes[1]

        if first == 10 { return true }
        if first == 127 { return true }
        if first == 169 && second == 254 { return true }
        if first == 192 && second == 168 { return true }
        if first == 172 && (16...31).contains(second) { return true }

        return false
    }

    private static func isDisallowedIPv6(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 16 else { return false }

        let isLoopback = bytes[0..<15].allSatisfy { $0 == 0 } && bytes[15] == 1
        if isLoopback { return true }

        let isLinkLocal = bytes[0] == 0xFE && (bytes[1] & 0xC0) == 0x80
        if isLinkLocal { return true }

        let isUniqueLocal = (bytes[0] & 0xFE) == 0xFC
        if isUniqueLocal { return true }

        return false
    }
}
