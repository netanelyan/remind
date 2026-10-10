import Foundation

/// Actions the widget asks the app to perform by opening a `remind://` URL.
///
/// Widget buttons that run code in place (`Button(intent:)`) need App Intents metadata that only
/// Xcode's build generates, so under xtool they silently do nothing. Links always work: iOS opens
/// the app, and the app does the work and confirms it.
public enum WidgetLink: Equatable, Sendable {
    case open
    case complete(UUID)
    case toggleGrouping

    public var url: URL {
        switch self {
        case .open: URL(string: "remind://open")!
        case .complete(let id): URL(string: "remind://complete/\(id.uuidString)")!
        case .toggleGrouping: URL(string: "remind://toggle-grouping")!
        }
    }

    public init?(url: URL) {
        guard url.scheme == "remind" else { return nil }
        switch url.host() {
        case "open": self = .open
        case "toggle-grouping": self = .toggleGrouping
        case "complete":
            guard let id = UUID(uuidString: url.lastPathComponent) else { return nil }
            self = .complete(id)
        default: return nil
        }
    }
}
