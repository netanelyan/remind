import Foundation

/// Locates the App Group container shared by the app and the widget.
///
/// xtool registers bundle and group IDs under a per-account prefix: the app becomes
/// `XTL-<id>.com.example.HelloApp` and the group declared as `group.com.example.HelloApp`
/// becomes `group.XTL-<id>.com.example.HelloApp`. The prefix isn't known at build time,
/// so the group ID is derived from the running bundle's (already rewritten) identifier.
public enum SharedContainer {
    static let widgetSuffix = ".HelloWidget"

    public static var appGroupID: String {
        var base = Bundle.main.bundleIdentifier ?? "com.example.HelloApp"
        if base.hasSuffix(widgetSuffix) {
            base.removeLast(widgetSuffix.count)
        }
        return "group." + base
    }

    /// The shared directory, or nil if the App Group entitlement didn't make it into the signature.
    public static var groupDirectory: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    public static var isAvailable: Bool { groupDirectory != nil }

    /// Falls back to the process's own Documents folder so the app still works without the group;
    /// the widget just won't see the app's data in that case.
    public static var directory: URL {
        groupDirectory ?? URL.documentsDirectory
    }
}
