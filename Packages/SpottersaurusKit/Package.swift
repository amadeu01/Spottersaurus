// swift-tools-version: 6.2
//
//  Package.swift
//  SpottersaurusKit
//
//  Shared local package for Spottersaurus: Model, Detection, Sync, Design.
//  Built and unit-tested on macOS via `swift test` (no device-only frameworks
//  in package code — HealthKit / CoreMotion live in the app targets).
//
import PackageDescription

let package = Package(
    name: "SpottersaurusKit",
    platforms: [
        .iOS(.v26),
        .watchOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(
            name: "SpottersaurusKit",
            targets: ["SpottersaurusKit"]
        ),
    ],
    targets: [
        .target(
            name: "SpottersaurusKit",
            path: "Sources/SpottersaurusKit"
        ),
        .testTarget(
            name: "SpottersaurusKitTests",
            dependencies: ["SpottersaurusKit"],
            path: "Tests/SpottersaurusKitTests"
        ),
    ]
)
