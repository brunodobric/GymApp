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
        .library(name: "Catalog", targets: ["Catalog"]),
        .library(name: "Models", targets: ["Models"]),
        .library(name: "Training", targets: ["Training"]),
        .library(name: "Planning", targets: ["Planning"]),
    ],
    targets: [
        .target(name: "Units"),
        .target(name: "Connectivity"),
        .target(name: "Catalog"),
        .target(
            name: "Models",
            dependencies: ["Units", "Catalog"],
            // SwiftData makro generira kod koji još nije u potpunosti prilagođen Swift 6 modu.
            // Isto kao u project.yml (SWIFT_VERSION 5.0).
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "Training",
            dependencies: ["Models", "Catalog", "Units"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "Planning",
            dependencies: ["Models", "Catalog", "Training", "Units"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "UnitsTests", dependencies: ["Units"]),
        .testTarget(name: "ConnectivityTests", dependencies: ["Connectivity"]),
        .testTarget(name: "CatalogTests", dependencies: ["Catalog"]),
        .testTarget(
            name: "TrainingTests",
            dependencies: ["Training", "Models", "Catalog"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "PlanningTests",
            dependencies: ["Planning", "Training", "Models", "Catalog"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "ModelsTests",
            dependencies: ["Models", "Units", "Catalog"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
