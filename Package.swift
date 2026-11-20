// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "Snapmark", platforms: [.macOS(.v14)], products: [.executable(name: "Snapmark", targets: ["Snapmark"])], targets: [.executableTarget(name: "Snapmark"), .testTarget(name: "SnapmarkTests", dependencies: ["Snapmark"])], swiftLanguageModes: [.v5])
