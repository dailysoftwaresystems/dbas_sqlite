// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "dbas_sqlite",
  platforms: [
    .iOS("16.0")
  ],
  products: [
    .library(name: "dbas-sqlite", targets: ["dbas_sqlite"])
  ],
  dependencies: [
    .package(name: "FlutterFramework", path: "../FlutterFramework")
  ],
  targets: [
    .target(
      name: "dbas_sqlite",
      dependencies: [
        .product(name: "FlutterFramework", package: "FlutterFramework"),
        "dbas_sqlite_native"
      ],
      resources: [
        .process("PrivacyInfo.xcprivacy")
      ],
      linkerSettings: [
        .linkedLibrary("c++"),
        .unsafeFlags(["-all_load"])
      ]
    ),
    .binaryTarget(
      name: "dbas_sqlite_native",
      path: "dbas_sqlite.xcframework"
    )
  ]
)
