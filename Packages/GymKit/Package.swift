// swift-tools-version: 6.0
import PackageDescription

// GymKit: logika koju dijele iPhone, iPad i Watch aplikacija.
// Moduli bez ovisnosti o sučelju, pokriveni unit testovima.
let package = Package(
    name: "GymKit",
    defaultLocalization: "hr",
    platforms: [
        .iOS(.v18),
        .watchOS(.v11),
        .macOS(.v15), // samo zato da `swift test` radi na Macu i CI-ju
    ],
    products: [
        .library(name: "Units", targets: ["Units"]),
        .library(name: "Connectivity", targets: ["Connectivity"]),
        .library(name: "Models", targets: ["Models"]),
    ],
    targets: [
        .target(name: "Units"),
        .target(name: "Connectivity"),
        .target(
            name: "Models",
            dependencies: ["Units"],
            // SwiftData makro generira kod koji još nije u potpunosti prilagođen Swift 6 modu.
            // Isto kao u project.yml (SWIFT_VERSION 5.0).
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "UnitsTests", dependencies: ["Units"]),
        .testTarget(name: "ConnectivityTests", dependencies: ["Connectivity"]),
        .testTarget(
            name: "ModelsTests",
            dependencies: ["Models", "Units"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
