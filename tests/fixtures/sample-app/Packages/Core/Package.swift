// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Core",
    platforms: [.iOS(.v18)],
    products: [.library(name: "Core", targets: ["Core"])],
    targets: [
        .target(
            name: "Core",
            swiftSettings: [.defaultIsolation(MainActor.self), .enableUpcomingFeature("ExistentialAny")]
        )
    ],
    swiftLanguageModes: [.v6]
)
