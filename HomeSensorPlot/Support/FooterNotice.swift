import Foundation

/// Why the window footer is showing a message.
/// Exporter recovery must clear only an exporter failure — a store or export
/// error that happens to contain the word "Exporter" stays up.
enum FooterNotice: Equatable {
    case exporter(String)
    case other(String)

    var message: String {
        switch self {
        case .exporter(let message), .other(let message):
            return message
        }
    }

    var withoutExporterFailure: FooterNotice? {
        if case .exporter = self { return nil }
        return self
    }
}
