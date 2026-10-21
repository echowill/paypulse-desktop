// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PayPulse",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "PayPulse", targets: ["PayPulse"])],
    targets: [
        .target(name: "PayPulseCore"),
        .executableTarget(name: "PayPulse", dependencies: ["PayPulseCore"]),
        .executableTarget(name: "SalaryEngineChecks", dependencies: ["PayPulseCore"], path: "Tests/PayPulseCoreTests")
    ]
)
