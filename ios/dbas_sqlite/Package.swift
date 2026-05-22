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
  dependencies: [],
  targets: [
    .target(
      name: "dbas_sqlite",
      dependencies: ["dbas_sqlite_native"],
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
