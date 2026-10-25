// swift-tools-version: 6.4

import PackageDescription

let package = Package(
  name: "DecimalAnnex",
  products: [
    .library(
      name: "DecimalCore",
      targets: ["DecimalCore"]),
    .library(
      name: "DecimalAnnex",
      targets: ["DecimalAnnex"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-numerics", from: "1.0.0"),
  ],
  targets: [
    .target(
      name: "DecimalCore",
      dependencies: [
        .product(name: "Numerics", package: "swift-numerics"),
      ],
      swiftSettings: [
          .strictMemorySafety(),
      ]),
    .target(
      name: "DecimalAnnex",
      dependencies: ["DecimalCore"]),
    .testTarget(
      name: "DecimalCoreTests",
      dependencies: ["DecimalCore"]),
  ]
)

