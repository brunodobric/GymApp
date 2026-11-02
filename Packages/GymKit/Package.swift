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
    ],
    targets: [
        .target(name: "Units"),
        .target(name: "Connectivity"),
        .testTarget(name: "UnitsTests", dependencies: ["Units"]),
        .testTarget(name: "ConnectivityTests", dependencies: ["Connectivity"]),
    ]
)
