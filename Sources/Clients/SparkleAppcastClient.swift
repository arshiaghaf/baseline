import Foundation

actor SparkleAppcastClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    static func secureXMLParser(data: Data) -> XMLParser {
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        return parser
    }

    func lookup(feedURL: URL, localVersion: Version) async -> SparkleLookupResult? {
        switch await lookupOutcome(feedURL: feedURL, localVersion: localVersion) {
        case .completed(let value):
            return value
        case .transientFailure:
            return nil
        }
    }

    func lookupOutcome(feedURL: URL, localVersion: Version) async -> LookupOutcome<SparkleLookupResult> {
        guard SecurityPolicy.isAllowedFeedURL(feedURL) else {
            return .completed(value: nil)
        }

        var request = URLRequest(url: feedURL)
        request.timeoutInterval = 8

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return .transientFailure
            }
            guard data.count <= SecurityPolicy.sparkleAppcastMaxBytes else {
                return .completed(value: nil)
            }

            return parseAppcastOutcome(data, localVersion: localVersion)
        } catch {
            return .transientFailure
        }
    }

    func parseAppcast(_ data: Data, localVersion: Version) -> SparkleLookupResult? {
        switch parseAppcastOutcome(data, localVersion: localVersion) {
        case .completed(let value):
            return value
        case .transientFailure:
            return nil
        }
    }

    private func parseAppcastOutcome(_ data: Data, localVersion: Version) -> LookupOutcome<SparkleLookupResult> {
        guard data.count <= SecurityPolicy.sparkleAppcastMaxBytes else {
            return .completed(value: nil)
        }

        let parser = AppcastParser(data: data)
        guard let items = parser.parse() else {
            return .transientFailure
        }
        guard !items.isEmpty else {
            return .completed(value: nil)
        }

        let bestItem = items
            .compactMap { item -> (item: AppcastItem, version: Version)? in
                let version = Version(item.shortVersionString ?? item.buildVersion)
                guard !version.isEmpty else { return nil }
                return (item, version)
            }
            .max { lhs, rhs in lhs.version < rhs.version }

        guard let bestItem else {
            return .completed(value: nil)
        }
        guard bestItem.version > localVersion else {
            return .completed(value: nil)
        }

        let updateURL = SecurityPolicy.sanitizeExternalURL(bestItem.item.enclosureURL)
        let releaseNotesURL = SecurityPolicy.sanitizeExternalURL(bestItem.item.releaseNotesURL)
        guard updateURL != nil || releaseNotesURL != nil else {
            return .completed(value: nil)
        }

        return .completed(value: SparkleLookupResult(
            remoteVersion: bestItem.version,
            updateURL: updateURL,
            releaseNotesURL: releaseNotesURL,
            releaseDate: bestItem.item.publicationDate
        ))
    }
}

private struct AppcastItem: Sendable {
    var shortVersionString: String?
    var buildVersion: String?
    var enclosureURL: URL?
    var releaseNotesURL: URL?
    var publicationDate: Date?
}

private final class AppcastParser: NSObject, XMLParserDelegate {
    private let parser: XMLParser
    private var items: [AppcastItem] = []
    private var currentItem: AppcastItem?
    private var currentElement: String?
    private var textBuffer = ""

    init(data: Data) {
        self.parser = SparkleAppcastClient.secureXMLParser(data: data)
        super.init()
        self.parser.delegate = self
    }

    func parse() -> [AppcastItem]? {
        guard parser.parse() else { return nil }
        return items
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        textBuffer = ""
        let element = qName ?? elementName
        currentElement = element

        if element == "item" {
            currentItem = AppcastItem()
        }

        guard currentItem != nil else { return }

        if element == "enclosure" {
            let shortVersion = attributeDict["sparkle:shortVersionString"]
                ?? attributeDict["shortVersionString"]
            let buildVersion = attributeDict["sparkle:version"]
                ?? attributeDict["version"]
            let enclosure = attributeDict["url"]
                .flatMap(URL.init(string:))
                .flatMap { SecurityPolicy.sanitizeExternalURL($0) }

            currentItem?.shortVersionString = shortVersion
            currentItem?.buildVersion = buildVersion
            currentItem?.enclosureURL = enclosure
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        textBuffer += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let element = qName ?? elementName
        let value = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)

        guard currentItem != nil else {
            textBuffer = ""
            currentElement = nil
            return
        }

        if element == "sparkle:releaseNotesLink" || element == "releaseNotesLink" {
            currentItem?.releaseNotesURL = URL(string: value).flatMap {
                SecurityPolicy.sanitizeExternalURL($0)
            }
        } else if element == "pubDate" {
            currentItem?.publicationDate = AppcastParser.rfc822.date(from: value)
        } else if element == "sparkle:shortVersionString" {
            currentItem?.shortVersionString = value
        } else if element == "sparkle:version" {
            currentItem?.buildVersion = value
        } else if element == "item", let item = currentItem {
            items.append(item)
            currentItem = nil
        }

        textBuffer = ""
        currentElement = nil
    }

    private static let rfc822: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter
    }()
}
