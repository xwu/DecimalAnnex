// swift-tools-version: 6.4

import PackageDescription
import CompilerPluginSupport

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
  traits: [
    "CompliantPayload",
    "ConsensusNaN",
    "Macros",
    .default(enabledTraits: ["Macros"]),
  ],
  dependencies: [
//  .package(url: "https://github.com/apple/swift-numerics", from: "1.0.0"),
    .package(url: "https://github.com/swiftlang/swift-syntax", from: "604.0.0"),
  ],
  targets: [
    .target(
      name: "DecimalCore",
      dependencies: [
//      .product(name: "RealModule", package: "swift-numerics"),
      ],
      swiftSettings: [
          .strictMemorySafety(),
      ]),
    .macro(
      name: "DecimalMacros",
      dependencies: [
        .target(name: "DecimalCore", condition: .when(traits: ["Macros"])),
        .product(
          name: "SwiftSyntax",
          package: "swift-syntax",
          condition: .when(traits: ["Macros"])),
        .product(
          name: "SwiftSyntaxBuilder",
          package: "swift-syntax",
          condition: .when(traits: ["Macros"])),
        .product(
          name: "SwiftSyntaxMacros",
          package: "swift-syntax",
          condition: .when(traits: ["Macros"])),
        .product(
          name: "SwiftCompilerPlugin",
          package: "swift-syntax",
          condition: .when(traits: ["Macros"])),
        .product(
          name: "SwiftDiagnostics",
          package: "swift-syntax",
          condition: .when(traits: ["Macros"])),
      ]),
    .target(
      name: "DecimalAnnex",
      dependencies: [
        "DecimalCore",
        .target(name: "DecimalMacros", condition: .when(traits: ["Macros"])),
      ]),
    .testTarget(
      name: "DecimalCoreTests",
      dependencies: ["DecimalCore"]),
    .testTarget(
      name: "DecimalMacrosTests",
      dependencies: [
        .target(name: "DecimalMacros", condition: .when(traits: ["Macros"])),
        .product(
          name: "SwiftSyntaxMacrosTestSupport",
          package: "swift-syntax",
          condition: .when(traits: ["Macros"])),
      ]),
  ]
)
