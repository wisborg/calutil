// swift-tools-version: 6.0
import Foundation
import PackageDescription

// The Info.plist is embedded into the executable so macOS knows why cal-add asks
// for Calendar access. Without it, a command-line tool using EventKit is refused
// (or killed) by the privacy system.
let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let infoPlist = "\(packageRoot)/Sources/cal-add/Info.plist"

let package = Package(
    name: "cal-add",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "cal-add", targets: ["cal-add"]),
    ],
    targets: [
        // Everything that does not touch EventKit: argument parsing, templates,
        // date handling, iCalendar output. Kept separate so it can be unit tested.
        .target(name: "CalAddCore"),
        .executableTarget(
            name: "cal-add",
            dependencies: ["CalAddCore"],
            exclude: ["Info.plist"],
            linkerSettings: [
                .linkedFramework("EventKit"),
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", infoPlist,
                ]),
            ]
        ),
        .testTarget(name: "CalAddCoreTests", dependencies: ["CalAddCore"]),
    ]
)
