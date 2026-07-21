// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "BilidownNative",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "BilidownNative", targets: ["BilidownNative"])
    ],
    targets: [
        .executableTarget(
            name: "BilidownNative",
            path: ".",
            exclude: ["Package.swift"]
        )
    ]
)
