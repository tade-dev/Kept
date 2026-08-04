import Foundation

/// Finder-style library orientations.
enum LibraryViewMode: String, CaseIterable, Identifiable {
    case icons
    case list
    case gallery

    var id: String { rawValue }

    var label: String {
        switch self {
        case .icons: "Icons"
        case .list: "List"
        case .gallery: "Gallery"
        }
    }

    var systemImage: String {
        switch self {
        case .icons: "square.grid.2x2"
        case .list: "list.bullet"
        case .gallery: "rectangle.split.1x2"
        }
    }
}
