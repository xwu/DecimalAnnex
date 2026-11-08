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
        "DecimalCore",
        .product(name: "SwiftSyntax", package: "swift-syntax"),
        .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
        .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
        .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
        .product(name: "SwiftDiagnostics", package: "swift-syntax"),
      ]),
    .target(
      name: "DecimalAnnex",
      dependencies: ["DecimalCore", "DecimalMacros"]),
    .testTarget(
      name: "DecimalCoreTests",
      dependencies: ["DecimalCore"]),
    .testTarget(
      name: "DecimalMacrosTests",
      dependencies: [
        "DecimalMacros",
        .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax")
      ]),
  ]
)

if Context.environment["CORE_MODULE_ONLY"] == "true" {
  package.targets.removeAll { !$0.name.hasPrefix("DecimalCore") }
  package.products.removeAll { !$0.name.hasPrefix("DecimalCore") }
  package.dependencies.removeAll {
    switch $0.kind {
    case .sourceControl(_, "https://github.com/swiftlang/swift-syntax", _): true
    default: false
    }
  }
}
