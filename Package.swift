// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Snapmark",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Snapmark", targets: ["Snapmark"])],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")
    ],
    targets: [
        .executableTarget(
            name: "Snapmark",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "SnapmarkTests", dependencies: ["Snapmark"])
    ],
    swiftLanguageModes: [.v5]
)
