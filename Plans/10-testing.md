# 10 — Testing, oracle fixtures, benchmarks

## 10.1 Oracle: Python `decimal` *is* IEEE decimal128

CPython's `decimal` (libmpdec) configured as

```python
import decimal
D128 = decimal.Context(
    prec=34, Emin=-6143, Emax=6144, clamp=1,
    rounding=decimal.ROUND_HALF_EVEN,
    traps=[])
```

implements IEEE 754-2019 decimal128 arithmetic including cohort/quantum
semantics (`Decimal.as_tuple()` exposes sign/digits/exponent — i.e. the
canonical BID triple), all five relevant rounding modes
(`ROUND_HALF_EVEN/HALF_UP/DOWN/CEILING/FLOOR` ↔ `toNearestOrEven/
toNearestOrAwayFromZero/towardZero/up/down`), flags
(`Inexact/Overflow/Underflow/InvalidOperation/DivisionByZero/Subnormal`
via `context.flags`), and the operations under test: `+ − × ÷`,
`quantize`, `to_integral_value`, `remainder_near`, `%`/`fmod`-style
`remainder`, `fma`, `sqrt`, `scaleb`, string I/O, and exact
`Decimal(float)` construction.

**Fixture pipeline** (checked into `Tests/DecimalAnnexTests/`):

- `Tests/generate_fixtures.py` — deterministic (seeded) generator that emits
  Swift source files (`Fixtures+Division.swift`, …) containing arrays of
  `(lhsBitPattern, rhsBitPattern, rule, expectedBitPattern, expectedFlags)`
  tuples as `UInt128` literals. Bit patterns are constructed from
  `as_tuple()` triples (digits → significand, exponent → biased exponent) —
  the generator must implement the BID packing itself (30 lines; test it
  against the repo's known constants like `pi`, `greatestFiniteMagnitude`).
- Committed fixtures stay < ~200 KB per operation (a few thousand vectors);
  the script header records seed + command line for regeneration.
- Distribution of random operands must be *structured*, not uniform bits:
  sample exponents from {min, min+1, …, −1, 0, …, max−1, max} × significands
  from {1, 5, 10^k, 10^k−1, 10³⁴−1, random 1–34-digit} plus sign, and
  include the specials (±0 at several quanta, ±∞, qNaN, sNaN with payloads).

## 10.2 Per-operation test plans

Each implementation doc carries its own edge-case list; the recurring
patterns, so they're written once:

- **Cohort/bitPattern assertions** wherever preferred exponents apply
  (docs 02, 03, 07, 08, 09): compare `bitPattern`, not `==`.
- **All-five-rules tables** for every rounding-sensitive operation, with
  operands straddling ties (`…5` exactly, `…5 + sticky`), both signs.
- **Tininess-before-rounding probes**: operands whose unrounded result is
  just below / at / just above `leastNormalMagnitude` where rounding pushes
  across the boundary (the classic "rounds up to smallest normal" case must
  still signal underflow-inexact... verify against IEEE §7.5 + oracle
  `Subnormal`/`Underflow` flags).
- **Exhaustive small sweeps**: `i ∘ j` for `i, j ∈ 1…255` for `÷` (and the
  existing `+`, `×` sweeps stay), checked against the oracle rather than
  against `Double` (removes the current tests' dependence on `Double`
  formatting quirks).
- **Round-trip properties**: description↔parse (doc 04 §4.3),
  `Double(Decimal128(d)) == d`, `Decimal128(exactly:)` nil-iff-inexact.

## 10.3 Flags testing (forward-looking)

`_signal` is currently a no-op scaffold. The fixtures already carry
`expectedFlags`, so when `_DecimalException` reporting becomes observable
(task for a future doc: thread-local flag accumulation or a
`withFloatingPointExceptions { }` scope), the same fixtures upgrade from
value-tests to value+flags-tests without regeneration. Until then the
generator still writes the flags column; the test harness ignores it.

## 10.4 Test target organization

Current: one file, XCTest, `guard #available(macOS 15…)` prologue per test.
Keep XCTest (repo convention; swift-testing migration is orthogonal and not
part of this work). New files per area:
`DivisionTests.swift`, `RoundingTests.swift` (rounded/quantized/scaleB),
`RemainderTests.swift`, `FMATests.swift`, `SquareRootTests.swift`,
`TextTests.swift`, `ConversionTests.swift`, `Fixtures+*.swift` (generated).
Hoist the availability guard into a shared
`func withDecimal128(_ body: () throws -> Void)` helper to cut the
boilerplate.

## 10.5 Benchmarks (optional, last)

Mirror Foundation's `Benchmarks/Benchmarks/Decimal/BenchmarkDecimal.swift`:
a separate `Benchmarks/` package (own `Package.swift`, dependency on
`package-benchmark` ~1.4, path dependency on the root package) so the library
manifest gains no dependencies. Benchmarks: `add`, `multiply`, `divide`,
`compare`, `hash`, `description`, `parse`, `initFromDouble`,
`doubleFromDecimal`, each in the
`benchmark.scaledIterations`/`blackHole` pattern with
`scalingFactor: .mega, maxDuration: .seconds(2)`. Fixed 16-value operand
array mixing magnitudes, signs, and NaN (Foundation's `:27-44` list adapted).
Purpose: catch regressions from docs 01–05 (especially the G-M replacement
of `dividingFullWidth` in `_round`, expected to be the headline win) — run
before/after each doc lands.

## 10.6 Toolchain / CI

No Swift toolchain is present in the development container.
Options, in order:

1. `curl -fsSL https://swiftlang.github.io/swiftly/swiftly-install.sh | bash`
   then `swiftly install 6.1` (Linux; respects the container's proxy).
2. Direct toolchain tarball from swift.org.
3. Fall back to CI / a local machine: fixtures and docs are all committed, so
   nothing blocks on the container.

`swift build && swift test` must be green after each doc's implementation
lands; the nine pre-existing tests are the regression floor.
