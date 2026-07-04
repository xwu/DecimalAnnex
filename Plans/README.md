# Decimal128 implementation plans

Design documents for completing and improving `Decimal128`, written so that a
human implementer can execute each one independently with confidence in its
correctness. No code in `Sources/` is modified by these documents; Swift
listings within them are illustrative but intended to be precise and
in-principle compilable, following the repository's existing idioms.

Two threads of work are covered:

1. **Adaptations** of algorithms from the `Foundation.Decimal` re-implementation
   in `xwu/swift-foundation` (branch `decimal-more-performance`), adjusted for
   the differences between the NSDecimal format (sign-magnitude, base-10 `Int8`
   exponent, 38-digit/128-bit significand, no infinities, no signed zero, no
   subnormals, no rounding-rule surface beyond `RoundingMode`) and IEEE 754-2019
   decimal128 (BID encoding, 34-digit significand, biased exponent 0…12287,
   full `FloatingPointRoundingRule` support, signaling/quiet NaNs with payloads,
   ±∞, subnormals, exception flags, preferred-exponent/cohort semantics).
2. **Completions** with no Foundation counterpart — `remainder`,
   `truncatingRemainder`, `addingProduct` (fused multiply-add), `squareRoot`,
   and the finite case of `quantized` — designed from IEEE 754-2019 and the
   published reference implementations (Intel IntelRDFPMathLib, IBM decNumber,
   mpdecimal).

## Documents

| Doc | Contents | Depends on |
| --- | --- | --- |
| [01-rounding-infrastructure](01-rounding-infrastructure.md) | Sticky-aware `_round`, exact-path overflow fix (bug), Granlund–Montgomery ÷10ᵏ, pow10 table, multiply fast path | — |
| [02-division](02-division.md) | `divided(by:rounding:)` via over-scale + full-width divide; preferred exponent for exact quotients | 01 |
| [03-rounding-and-scaling](03-rounding-and-scaling.md) | `rounded(_:)`, `quantized(by:rounding:)`, `init(sign:exponent:significand:)`, `BinaryInteger` conversions, `isTotallyOrdered` | 01 |
| [04-text](04-text.md) | `description` re-implementation, `LosslessStringConvertible` parser (ASCII-only by design) | 01 |
| [05-binary-fp-conversion](05-binary-fp-conversion.md) | `init(Double)` / `init?(exactly:)` exact multiword path; `Double(Decimal128)` bracketing | 01 |
| [06-cox-table-decimal128](06-cox-table-decimal128.md) | Analysis: extending the Cox power-of-ten table to `Decimal128`↔`Double` (range, entry width, saturation constants) | 05 |
| [07-remainder](07-remainder.md) | `remainder(dividingBy:)`, `truncatingRemainder(dividingBy:)` | 01, 02 |
| [08-fma](08-fma.md) | `addingProduct(_:_:rounding:)` | 01 |
| [09-squareroot](09-squareroot.md) | `squareRoot(rounding:)` | 01 |
| [10-testing](10-testing.md) | Test strategy, oracle fixtures (Python `decimal`), benchmarks | all |

## Ground rules

- **Toolchain**: the package manifest is swift-tools 5.9, but the sources
  require a Swift 6.0+ compiler (`UInt128`). Do **not** use Swift 6.2-only
  features that appear in the Foundation sources (`InlineArray` `[N of T]`,
  `Span`, `UTF8Span`, `MutableRawSpan`); use `static let` arrays and
  unsafe-buffer idioms instead.
- **Scope**: `Decimal128` is a standard-library-style type. String operations
  are ASCII-only; no locale awareness anywhere.
- **IEEE 754-2019 correctness is non-negotiable**: tininess detected before
  rounding; preferred exponents (cohort selection) honored for exact results;
  signed zeros per §6.3; sNaN → invalid with quieted canonical payload
  propagation; flags routed through the `_signal(_:default:)` scaffold.
- **Cohort-sensitive testing**: where preferred exponents matter, tests must
  compare `bitPattern`, not `==`.
