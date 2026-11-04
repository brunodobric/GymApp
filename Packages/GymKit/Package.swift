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
        .library(name: "Stats", targets: ["Stats"]),
        .library(name: "Backup", targets: ["Backup"]),
        .library(name: "HealthSync", targets: ["HealthSync"]),
        .library(name: "Diagnostics", targets: ["Diagnostics"]),
        .library(name: "Demo", targets: ["Demo"]),
    ],
    targets: [
        .target(name: "Units"),
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
        .target(
            name: "Stats",
            dependencies: ["Models", "Catalog", "Training", "Units"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "Backup",
            dependencies: ["Models", "Catalog", "Units"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Veza iPhone ↔ Watch: snimke treninga, naredbe, kontekst za sat i logika treninga na satu.
        .target(
            name: "Connectivity",
            dependencies: ["Models", "Catalog", "Training", "Planning", "Units"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "HealthSync",
            dependencies: ["Models"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // MetricKit izvještaji spremljeni na uređaju (rušenja, zastoji, performanse).
        .target(name: "Diagnostics"),
        // Demo podaci za snimke zaslona (samo Debug).
        .target(
            name: "Demo",
            dependencies: ["Models", "Catalog", "Training", "Planning"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "DemoTests",
            dependencies: ["Demo", "Models", "Planning", "Stats", "Training", "Catalog"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "UnitsTests", dependencies: ["Units"]),
        .testTarget(name: "DiagnosticsTests", dependencies: ["Diagnostics"]),
        .testTarget(
            name: "ConnectivityTests",
            dependencies: ["Connectivity", "Models", "Catalog", "Training", "Planning", "Units"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
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
            name: "StatsTests",
            dependencies: ["Stats", "Training", "Models", "Catalog"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "BackupTests",
            dependencies: ["Backup", "Models", "Catalog", "Units"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "HealthSyncTests",
            dependencies: ["HealthSync", "Models"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "ModelsTests",
            dependencies: ["Models", "Units", "Catalog"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
