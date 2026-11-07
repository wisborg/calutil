// swift-tools-version: 6.0
import Foundation
import PackageDescription

// The Info.plist is embedded into the executable so macOS knows why calutil asks
// for Calendar access. Without it, a command-line tool using EventKit is refused
// (or killed) by the privacy system.
let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let infoPlist = "\(packageRoot)/Sources/calutil/Info.plist"

let package = Package(
    name: "calutil",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "calutil", targets: ["calutil"]),
    ],
    targets: [
        // Everything that does not touch EventKit: argument parsing, templates,
        // date handling, iCalendar output. Kept separate so it can be unit tested.
        .target(name: "CalUtilCore"),
        .executableTarget(
            name: "calutil",
            dependencies: ["CalUtilCore"],
            exclude: ["Info.plist"],
            linkerSettings: [
                .linkedFramework("EventKit"),
                .linkedFramework("MapKit"),
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", infoPlist,
                ]),
            ]
        ),
        .testTarget(name: "CalUtilCoreTests", dependencies: ["CalUtilCore"]),
    ]
)
