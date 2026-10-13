import Foundation

/// Actions the widget asks the app to perform by opening a `remind://` URL.
///
/// `add` always goes through the app, since widgets can't take typed text. `complete` and
/// `toggleGrouping` are a fallback: the widget normally runs them in place with App Intents
/// (see WidgetIntents.swift), which only works when the bundle has Xcode-generated metadata.
public enum WidgetLink: Equatable, Sendable {
    case open
    /// Opens the app's quick-add pop-up.
    case add
    case complete(UUID)
    case toggleGrouping

    public var url: URL {
        switch self {
        case .open: URL(string: "remind://open")!
        case .add: URL(string: "remind://add")!
        case .complete(let id): URL(string: "remind://complete/\(id.uuidString)")!
        case .toggleGrouping: URL(string: "remind://toggle-grouping")!
        }
    }

    public init?(url: URL) {
        guard url.scheme == "remind" else { return nil }
        switch url.host() {
        case "open": self = .open
        case "add": self = .add
        case "toggle-grouping": self = .toggleGrouping
        case "complete":
            guard let id = UUID(uuidString: url.lastPathComponent) else { return nil }
            self = .complete(id)
        default: return nil
        }
    }
}
