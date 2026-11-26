// swift-tools-version: 6.4

import PackageDescription

let package = Package(
  name: "Benchmarks",
  platforms: [
    .macOS(.v26),
  ],
  dependencies: [
    // Macros aren't benchmarked, so disable the default trait that adds them.
    .package(name: "DecimalAnnex", path: "..", traits: []),
    .package(url: "https://github.com/ordo-one/benchmark", from: "1.36.0"),
  ],
  targets: [
    .executableTarget(
      name: "DecimalBenchmarks",
      dependencies: [
        .product(name: "DecimalCore", package: "DecimalAnnex"),
        .product(name: "Benchmark", package: "benchmark"),
      ],
      path: "Benchmarks/DecimalBenchmarks",
      plugins: [
        .plugin(name: "BenchmarkPlugin", package: "benchmark"),
      ]),
  ]
)
