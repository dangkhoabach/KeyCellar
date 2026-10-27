// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DKBSecretCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DKBSecretCore", targets: ["DKBSecretCore"])
    ],
    dependencies: [
        // The only third-party dependency this app has.
        // Package.resolved is committed so the reviewed revision is the one
        // every build uses.
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0")
    ],
    targets: [
        .target(name: "DKBSecretCore", dependencies: [.product(name: "GRDB", package: "GRDB.swift")]),
        .testTarget(name: "DKBSecretCoreTests", dependencies: ["DKBSecretCore"]),
    ]
)
