import Benchmark
import DecimalCore
import Foundation

/// A small seeded generator, so that every run with the same toolchain sees the
/// same operands.
struct SplitMix64: RandomNumberGenerator {
  var state: UInt64
  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z &>> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z &>> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z &>> 31)
  }
}

/// The number of operands in a pool, large enough that branch predictors can't
/// learn the sequence of operands.
let poolSize = 65536

/// The number of operations in a benchmark iteration.
///
/// Each iteration processes the next `batchSize` operands of the pool, so the
/// reported wall clock and instruction count of an iteration are for
/// `batchSize` operations. Short iterations keep the median robust against
/// preemption on machines that aren't otherwise idle.
let batchSize = 4096

@inline(always)
func measure(_ benchmark: Benchmark, _ body: (Int) -> Void) {
  for j in benchmark.scaledIterations {
    // Benchmark closures are called once per iteration, so the batch is chosen
    // by the iteration count.
    let start =
      (benchmark.currentIteration + j) % (poolSize / batchSize) * batchSize
    for i in start..<start + batchSize { body(i) }
  }
}

/// Returns the digits of a random coefficient with the given number of digits.
func coefficient(digits: Int, _ rng: inout SplitMix64) -> String {
  var result = String(UInt64.random(in: 1..<10, using: &rng))
  for _ in 1..<digits {
    result.append(String(UInt64.random(in: 0..<10, using: &rng)))
  }
  return result
}

/// Returns an "everyday" operand: a value with two decimal places and 1 to 8
/// digits, negative half of the time.
func everydayText(_ rng: inout SplitMix64) -> String {
  var digits = coefficient(digits: .random(in: 1...8, using: &rng), &rng)
  while digits.count < 3 { digits = "0" + digits }
  let split = digits.index(digits.endIndex, offsetBy: -2)
  let sign = Bool.random(using: &rng) ? "-" : ""
  return sign + digits[..<split] + "." + digits[split...]
}

/// Returns a "wide" operand: a value with 1 to 34 significant digits and an
/// exponent from -30 through 10, negative half of the time.
func wideText(_ rng: inout SplitMix64) -> String {
  let digits = coefficient(digits: .random(in: 1...34, using: &rng), &rng)
  let exponent = Int.random(in: -30...10, using: &rng)
  let sign = Bool.random(using: &rng) ? "-" : ""
  return sign + digits + "E" + String(exponent)
}

struct Pool {
  let text: [String]
  let a: [Decimal128]
  let b: [Decimal128]
  let c: [Decimal128]
  let foundationA: [Foundation.Decimal]
  let foundationB: [Foundation.Decimal]

  init(
    seed: UInt64,
    withFoundation: Bool = false,
    _ make: (inout SplitMix64) -> String
  ) {
    var rng = SplitMix64(state: seed)
    let textA = (0..<poolSize).map { _ in make(&rng) }
    let textB = (0..<poolSize).map { _ in make(&rng) }
    let textC = (0..<poolSize).map { _ in make(&rng) }
    text = textA
    a = textA.map { Decimal128($0)! }
    b = textB.map { Decimal128($0)! }
    c = textC.map { Decimal128($0)! }
    foundationA = withFoundation ? textA.map { Decimal(string: $0)! } : []
    foundationB = withFoundation ? textB.map { Decimal(string: $0)! } : []
  }
}

let benchmarks: @Sendable () -> Void = {
  let configuration = Benchmark.Configuration(
    metrics: [.wallClock, .instructions, .mallocCountTotal],
    timeUnits: .nanoseconds,
    units: [.instructions: .count],
    maxDuration: .seconds(2))

  let everyday = Pool(seed: 0x00DE_C1A1, withFoundation: true, everydayText)
  let wide = Pool(seed: 0x0000_1DE5, wideText)

  // The cost of the loop and of passing an operand to `blackHole` alone.
  Benchmark("Loop overhead", configuration: configuration) { benchmark in
    let a = everyday.a
    measure(benchmark) { i in blackHole(a[i]) }
  }

  // The operations in the README table, over both pools.
  for (suffix, pool) in [("", everyday), (" (wide)", wide)] {
    Benchmark("Add\(suffix)", configuration: configuration) { benchmark in
      let (a, b) = (pool.a, pool.b)
      measure(benchmark) { i in blackHole(a[i] + b[i]) }
    }
    Benchmark("Subtract\(suffix)", configuration: configuration) { benchmark in
      let (a, b) = (pool.a, pool.b)
      measure(benchmark) { i in blackHole(a[i] - b[i]) }
    }
    Benchmark("Multiply\(suffix)", configuration: configuration) { benchmark in
      let (a, b) = (pool.a, pool.b)
      measure(benchmark) { i in blackHole(a[i] * b[i]) }
    }
    Benchmark("Divide\(suffix)", configuration: configuration) { benchmark in
      let (a, b) = (pool.a, pool.b)
      measure(benchmark) { i in blackHole(a[i] / b[i]) }
    }
    Benchmark(
      "Fused multiply-add\(suffix)", configuration: configuration
    ) { benchmark in
      let (a, b, c) = (pool.a, pool.b, pool.c)
      measure(benchmark) { i in blackHole(c[i].addingProduct(a[i], b[i])) }
    }
    Benchmark(
      "Round to integer, ties to even\(suffix)", configuration: configuration
    ) { benchmark in
      let a = pool.a
      measure(benchmark) { i in blackHole(a[i].rounded(.toNearestOrEven)) }
    }
    Benchmark(
      "Convert text to decimal\(suffix)", configuration: configuration
    ) { benchmark in
      let text = pool.text
      measure(benchmark) { i in blackHole(Decimal128(text[i])) }
    }
    Benchmark(
      "Convert decimal to text\(suffix)", configuration: configuration
    ) { benchmark in
      let a = pool.a
      measure(benchmark) { i in blackHole(a[i].description) }
    }
  }

  // The same operations on `Foundation.Decimal`, over the everyday pool.
  Benchmark("Foundation add", configuration: configuration) { benchmark in
    let (a, b) = (everyday.foundationA, everyday.foundationB)
    measure(benchmark) { i in blackHole(a[i] + b[i]) }
  }
  Benchmark("Foundation subtract", configuration: configuration) { benchmark in
    let (a, b) = (everyday.foundationA, everyday.foundationB)
    measure(benchmark) { i in blackHole(a[i] - b[i]) }
  }
  Benchmark("Foundation multiply", configuration: configuration) { benchmark in
    let (a, b) = (everyday.foundationA, everyday.foundationB)
    measure(benchmark) { i in blackHole(a[i] * b[i]) }
  }
  Benchmark("Foundation divide", configuration: configuration) { benchmark in
    let (a, b) = (everyday.foundationA, everyday.foundationB)
    measure(benchmark) { i in blackHole(a[i] / b[i]) }
  }
  Benchmark(
    "Foundation round to integer, ties to even", configuration: configuration
  ) { benchmark in
    let a = everyday.foundationA
    measure(benchmark) { i in
      var source = a[i]
      var result = Decimal()
      NSDecimalRound(&result, &source, 0, .bankers)
      blackHole(result)
    }
  }
  Benchmark(
    "Foundation convert text to decimal", configuration: configuration
  ) { benchmark in
    let text = everyday.text
    measure(benchmark) { i in blackHole(Decimal(string: text[i])) }
  }
  Benchmark(
    "Foundation convert decimal to text", configuration: configuration
  ) { benchmark in
    let a = everyday.foundationA
    measure(benchmark) { i in blackHole(a[i].description) }
  }

  // Other operations, over the everyday pool.
  let products = zip(everyday.a, everyday.b).map { $0 * $1 }
  let cent = Decimal128("0.01")!
  let magnitudes = everyday.a.map(\.magnitude)
  let doubles = everyday.a.map { Double(nearest: $0) }
  let integers = everyday.a.map { Int($0) }

  Benchmark("Equal", configuration: configuration) { benchmark in
    let (a, b) = (everyday.a, everyday.b)
    measure(benchmark) { i in blackHole(a[i] == b[i]) }
  }
  Benchmark("Less than", configuration: configuration) { benchmark in
    let (a, b) = (everyday.a, everyday.b)
    measure(benchmark) { i in blackHole(a[i] < b[i]) }
  }
  Benchmark(
    "Quantize product to 0.01", configuration: configuration
  ) { benchmark in
    measure(benchmark) { i in blackHole(products[i].quantized(by: cent)) }
  }
  Benchmark("Square root", configuration: configuration) { benchmark in
    measure(benchmark) { i in blackHole(magnitudes[i].squareRoot()) }
  }
  Benchmark("Remainder", configuration: configuration) { benchmark in
    let (a, b) = (everyday.a, everyday.b)
    measure(benchmark) { i in blackHole(a[i].remainder(dividingBy: b[i])) }
  }
  Benchmark(
    "Truncating remainder", configuration: configuration
  ) { benchmark in
    let (a, b) = (everyday.a, everyday.b)
    measure(benchmark) { i in
      blackHole(a[i].truncatingRemainder(dividingBy: b[i]))
    }
  }
  Benchmark(
    "Convert decimal to Int", configuration: configuration
  ) { benchmark in
    let a = everyday.a
    measure(benchmark) { i in blackHole(Int(a[i])) }
  }
  Benchmark(
    "Convert Int to decimal", configuration: configuration
  ) { benchmark in
    measure(benchmark) { i in blackHole(Decimal128(integers[i])) }
  }
  Benchmark(
    "Convert decimal to Double", configuration: configuration
  ) { benchmark in
    let a = everyday.a
    measure(benchmark) { i in blackHole(Double(nearest: a[i])) }
  }
  Benchmark(
    "Convert Double to decimal, shortest", configuration: configuration
  ) { benchmark in
    measure(benchmark) { i in blackHole(Decimal128(shortest: doubles[i])) }
  }
}
