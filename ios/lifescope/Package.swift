// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "lifescope",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        .library(name: "lifescope", targets: ["lifescope"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "lifescope",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
