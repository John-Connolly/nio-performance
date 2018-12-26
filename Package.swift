// swift-tools-version:4.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "redis",
    products: [
        .library(name: "redis", targets: ["redis"]),
    ],
    dependencies: [
        //.package(url: "https://github.com/apple/swift-nio.git", .exact("1.9.0")) // 4x slower
        .package(url: "https://github.com/apple/swift-nio.git", .exact("1.8.0"))
    ],
    targets: [
        .target(name: "Dev", dependencies: ["redis"]),
        .target(name: "redis", dependencies: ["NIO"]),
        .testTarget(name: "redisTests", dependencies: ["redis"]),
    ]
)
