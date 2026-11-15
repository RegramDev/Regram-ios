// swift-tools-version: 5.9
import PackageDescription

let package = Package(name: "RGAdFilter", platforms: [.macOS(.v12), .iOS(.v15)], products: [.library(name: "RGAdFilter", targets: ["RGAdFilter"])], targets: [.target(name: "RGAdFilter", path: "Sources"), .testTarget(name: "RGAdFilterTests", dependencies: ["RGAdFilter"], path: "Tests")])
