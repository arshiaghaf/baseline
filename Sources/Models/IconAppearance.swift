import AppKit
import SwiftUI

enum IconAppearance: String, Sendable {
    case light
    case dark

    init(colorScheme: ColorScheme) {
        switch colorScheme {
        case .dark:
            self = .dark
        default:
            self = .light
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .light:
            NSAppearance(named: .aqua)
        case .dark:
            NSAppearance(named: .darkAqua)
        }
    }
}
