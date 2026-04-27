import Foundation

enum HomebrewMaintenanceRunEvent: Sendable, Equatable {
    case commandStarted([String])
    case outputLine(command: [String], line: String)
    case commandFinished(command: [String], success: Bool)
}

enum HomebrewMaintenanceProgressStage: Double, Sendable, Equatable {
    case queued = 0.0
    case downloading = 0.78
    case installing = 0.83
    case finalizing = 0.92
    case completed = 1.0
}

struct HomebrewMaintenanceProgressEvent: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case progress(Double)
        case completed
        case failed
    }

    let token: String
    let kindHint: HomebrewManagedItemKind?
    let kind: Kind
}

struct HomebrewMaintenanceOutputParser {
    private let knownTokens: Set<String>

    init(knownTokens: Set<String>) {
        self.knownTokens = Set(knownTokens.map { $0.lowercased() })
    }

    func parse(line: String, command: [String]) -> [HomebrewMaintenanceProgressEvent] {
        let normalizedLine = line.lowercased()
        let matchedTokens = extractTokens(in: normalizedLine)
        guard !matchedTokens.isEmpty else { return [] }

        let kindHint = kindHint(for: command)

        if isFailureLine(normalizedLine) {
            return matchedTokens.map {
                HomebrewMaintenanceProgressEvent(
                    token: $0,
                    kindHint: kindHint,
                    kind: .failed
                )
            }
        }

        if isCompletionLine(normalizedLine) {
            return matchedTokens.map {
                HomebrewMaintenanceProgressEvent(
                    token: $0,
                    kindHint: kindHint,
                    kind: .completed
                )
            }
        }

        guard let progressStage = progressStage(for: normalizedLine) else {
            return []
        }

        return matchedTokens.map {
            HomebrewMaintenanceProgressEvent(
                token: $0,
                kindHint: kindHint,
                kind: .progress(progressStage.rawValue)
            )
        }
    }

    private func kindHint(for command: [String]) -> HomebrewManagedItemKind? {
        let lowercasedCommand = command.map { $0.lowercased() }
        guard lowercasedCommand.first == "upgrade" else {
            return nil
        }
        if lowercasedCommand.contains("--cask") || lowercasedCommand.contains("--casks") {
            return .cask
        }
        return .formula
    }

    private func progressStage(for line: String) -> HomebrewMaintenanceProgressStage? {
        if matchesAny(in: line, terms: ["fetching", "downloading"]) {
            return .downloading
        }
        if matchesAny(in: line, terms: ["pouring", "installing", "upgrading", "extracting", "linking"]) {
            return .installing
        }
        if matchesAny(in: line, terms: ["purging files", "cleanup", "cleaning"]) {
            return .finalizing
        }
        if matchesAny(in: line, terms: ["queued", "queue", "starting"]) {
            return .queued
        }
        return nil
    }

    private func isCompletionLine(_ line: String) -> Bool {
        matchesAny(
            in: line,
            terms: [
                "is up-to-date",
                "already installed",
                "was successfully installed",
                "purging files for version",
                "🍺"
            ]
        )
    }

    private func isFailureLine(_ line: String) -> Bool {
        matchesAny(
            in: line,
            terms: [
                "error:",
                "failed",
                "failed!",
                "failed to"
            ]
        )
    }

    private func matchesAny(in line: String, terms: [String]) -> Bool {
        terms.contains { line.contains($0) }
    }

    private func extractTokens(in line: String) -> [String] {
        knownTokens
            .filter { containsToken($0, in: line) }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count {
                    return lhs.count > rhs.count
                }
                return lhs < rhs
            }
    }

    private func containsToken(_ token: String, in line: String) -> Bool {
        guard !token.isEmpty else { return false }

        var searchRange = line.startIndex..<line.endIndex
        while let range = line.range(of: token, options: [], range: searchRange) {
            let hasValidLeftBoundary: Bool
            if range.lowerBound == line.startIndex {
                hasValidLeftBoundary = true
            } else {
                let previous = line[line.index(before: range.lowerBound)]
                hasValidLeftBoundary = isBoundaryCharacter(previous)
            }

            var hasValidRightBoundary: Bool
            if range.upperBound == line.endIndex {
                hasValidRightBoundary = true
            } else {
                let next = line[range.upperBound]
                hasValidRightBoundary = isBoundaryCharacter(next)
                if !hasValidRightBoundary, next == "-" {
                    let following = line.index(after: range.upperBound)
                    if following < line.endIndex, line[following] == "-" {
                        hasValidRightBoundary = true
                    }
                }
            }

            if hasValidLeftBoundary && hasValidRightBoundary {
                return true
            }

            searchRange = range.upperBound..<line.endIndex
        }

        return false
    }

    private func isBoundaryCharacter(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first else {
            return true
        }
        if CharacterSet.alphanumerics.contains(scalar) {
            return false
        }
        return !("@".contains(character) || "+".contains(character) || "-".contains(character) || "_".contains(character) || ".".contains(character))
    }
}
