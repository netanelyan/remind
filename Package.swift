// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "HelloApp",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        // The main app. xtool.yml's `product:` points here.
        .library(
            name: "HelloApp",
            targets: ["HelloApp"]
        ),
        // The WidgetKit extension, declared under `extensions:` in xtool.yml.
        .library(
            name: "HelloWidget",
            targets: ["HelloWidget"]
        ),
        // Only used by ci/project.yml, the Xcode build that generates the widget's App Intents metadata.
        .library(
            name: "ReminderKit",
            targets: ["ReminderKit"]
        ),
    ],
    targets: [
        // Shared between the app and the widget: models, storage, parsing, intents.
        .target(
            name: "ReminderKit"
        ),
        .target(
            name: "HelloApp",
            dependencies: ["ReminderKit"]
        ),
        .target(
            name: "HelloWidget",
            dependencies: ["ReminderKit"],
            linkerSettings: [
                // xtool links extensions with `-e _NSExtensionMain`, so nothing references the
                // widget's @main and Swift Build's dead-stripping removes all widget code.
                // Keep `_main` alive (NSExtensionMain finds the WidgetBundle through it).
                .unsafeFlags(["-Xlinker", "-u", "-Xlinker", "_main"]),
            ]
        ),
    ]
)
