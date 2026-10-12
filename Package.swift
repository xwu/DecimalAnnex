// swift-tools-version: 6.4

import PackageDescription

let package = Package(
  name: "DecimalAnnex",
  products: [
    .library(
      name: "DecimalAnnex",
      targets: ["DecimalAnnex"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-numerics", from: "1.0.0"),
  ],
  targets: [
    .target(
      name: "DecimalAnnex",
      dependencies: [
        .product(name: "Numerics", package: "swift-numerics"),
      ],
      swiftSettings: [
          .strictMemorySafety(),
      ]),
    .testTarget(
      name: "DecimalAnnexTests",
      dependencies: ["DecimalAnnex"]),
  ]
)

