import Foundation

enum FixtureLoader {
    static func data(named name: String, ext: String) throws -> Data {
        let bundle = Bundle(for: FixtureToken.self)
        guard let url = bundle.url(forResource: name, withExtension: ext) else {
            throw NSError(domain: "FixtureLoader", code: 1)
        }
        return try Data(contentsOf: url)
    }
}

private final class FixtureToken {}
