# 05 — Binary floating-point conversions

Fills the stubs `init?<T: BinaryFloatingPoint>(exactly:)`,
`init<T: BinaryFloatingPoint>(_:)` (Decimal128.swift:1386-1406) and the TODO
"Conversion from `Decimal128` to binary integer or floating point" (:1408).
New file suggested: `Sources/DecimalAnnex/Decimal128+BinaryFloatingPoint.swift`.

**Semantics decision (differs from Foundation deliberately)**: Foundation's
`Decimal(Double)` produces the *shortest decimal that round-trips*
(`_cox_shortest`, `Decimal+FloatingPointConversion.swift:1031-1066`) — so
`Decimal(0.1) == 0.1` exactly. For an IEEE type, `init(_: Double)` is
`convertFormat` and must be **correctly rounded to 34 digits**:
`Decimal128(0.1) == 0.1000000000000000055511151231257827` (the exact binary
value rounded), and `Decimal128(exactly: 0.1) == nil` is *wrong* — 0.1's exact
expansion has 55 significant digits, `exactly` returns nil — correct; but
`Decimal128(exactly: 0.5) == 0.5` (exact). Every finite `Double` fits
`Decimal128`'s exponent range, so overflow/underflow cannot occur; only
34-digit precision rounding.

## 5.1 `init(_ source: Double)` — exact multiword path (recommended first)

Two implementation strategies exist; **implement the exact path first**, and
treat the Cox-table fast path as a later optimization gated on doc 06's
proof work:

- The Cox `_table` (128-bit entries) is proven for 19-digit outputs from
  64-bit inputs. 34-digit outputs leave ~13 bits of error margin
  (doc 06 §6.4) — not acceptable without new proof.
- The exact path is straightforward to verify and conversion is not a hot
  path for this type.

Algorithm. Decompose `|source| = m × 2^e` with
`m = source.significandBitPattern | implicitBit ≤ 2⁵³−1` (subnormals: no
implicit bit), `e = source.exponentBitPattern`-derived unbiased exponent of
the *integer* `m` (i.e. `e = source.exponent − 52`, range `[−1074, 971]`).

- **`e ≥ 0`**: value = `m << e`, an exact integer of ≤ 1024 bits.
- **`e < 0`**: value = `m / 2^|e|` = `(m × 5^|e|) / 10^|e|` — an exact integer
  `N = m × 5^|e|` (≤ 53 + ⌈1074·log₂5⌉ ≈ 2547 bits) scaled by `10^−|e|`.

Both cases reduce to: *exact big integer `N` (≤ 2547 bits) times `10^k`
(k = 0 or −|e|), round to 34 digits*. Multiword machinery — a stack-allocated
`withUnsafeTemporaryAllocation(of: UInt64.self, capacity: 40)` limb buffer and
three primitive loops (no allocation, no generics):

```swift
// 1. multiply-accumulate by a UInt64 (builds m × 5^|e| in ≤ ⌈|e|/27⌉ passes
//    of ×5^27, the largest power of 5 in UInt64 — table _uint64_pow5 from
//    Foundation FPC:727-756):
func mulSmall(_ limbs: inout Buffer, _ count: inout Int, by x: UInt64)
// 2. left-shift by e bits (for the e ≥ 0 case):
func shiftLeft(_ limbs: inout Buffer, _ count: inout Int, by bits: Int)
// 3. divide by 10^19 returning the 19-digit remainder (Granlund–Montgomery
//    per-limb; or plain 128÷64 hardware divides — off hot path):
func divmod1e19(_ limbs: inout Buffer, _ count: inout Int) -> UInt64
```

Reduction to 34 digits: repeatedly `divmod1e19` collecting low-digit chunks
into `sticky` until ≤ 2 limbs ≥ … — concretely: compute the total decimal
digit count `D` (first via bit count estimate `(bits×1233)>>12`, corrected by
comparison), let `drop = max(0, D − 35)`; remove `drop` digits (chunks of 19,
then a final `10^(drop mod 19)` division), ORing every removed digit's
nonzero-ness into `sticky`; the surviving ≤ 35-digit value fits `UInt128`.
Then hand to the doc 01 sink exactly as the string parser does (doc 04 §4.2
option (a)): keep 35 digits, let `_round` strip the last with `sticky`:

```swift
let abs = Decimal128._round(
  false, 6176 + k + drop, (0, top35), sticky: sticky, .toNearestOrEven)
self = source.sign == .minus ? -abs : abs
```

Specials first: NaN → `.nan` (payload not preserved — Double payloads don't
map meaningfully onto decimal payloads; sNaN → `_signal(.invalid, …)`),
±∞ → ±∞, ±0 → ±0 with exponent 6176 (preferred exponent for conversions
is 0... IEEE says preferred exponent Q = 0 for convertFromInt; for
convertFormat of zero follow Double semantic emptiness — use 6176).

`init(_ source: T)` for generic `BinaryFloatingPoint`: `Float16`/`Float`
convert exactly to `Double` (strictly wider format), so
`self.init(Double(source))` after a `T.significandBitCount <= 52 &&
T.exponentBitCount <= 11` gate; larger formats (`Float80`) need the multiword
path parameterized on the significand width — the limb loops above already
are; only the decomposition line changes. Recommended: implement generic over
`(significandBitPattern as UInt64, exponent)` with a precondition, punting
`Float80` explicitly (`fatalError("unsupported format")` documented) until
needed.

## 5.2 `init?(exactly source: Double)`

Same computation; return `nil` if the reduction dropped any nonzero digit or
`_round` reports inexact (structure the shared core as
`static func _convert(_ m: UInt64, _ e: Int) -> (Decimal128, inexact: Bool)`).
Exactness shortcut worth implementing (avoids the big path for the common
case): if `e ≥ 0 && m << e` has ≤ 34 digits (`e ≤ 60` suffices as a guard) or
`e < 0 && |e| ≤ 48 && m × 5^|e| ≤ 10³⁴−1`, the value is exactly
representable and computable in `UInt128`/`_UInt256` directly.

## 5.3 `Double(_ x: Decimal128)` — bracketing via the existing Cox table

Direction: 34-digit `c × 10^q` → correctly rounded `Double`, ties-to-even.
Adapt Foundation `__doubleValue`/`_parseWide`
(`Decimal+FloatingPointConversion.swift:957-1027, 1138-1155`) — the ported
128-bit `_table` and `_cox_parse` are *sufficient and proven* for this
direction's 19-digit sub-steps; the range problems are handled by
pre-saturation (all constants from doc 06 §6.3):

1. Specials: NaN → `Double.nan` (quiet; sNaN → invalid + nan), ±∞, ±0.
2. Saturate: `|x| > 1.797693134862315807937289714053034e308` (34-digit floor
   of the RN overflow boundary 2¹⁰²⁴−2⁹⁷⁰; strict compare is exact because
   the boundary itself is not 34-digit representable, doc 06 §6.3) →
   ±∞ with overflow-inexact. `|x| < 2.470328229206232720882843964341106e−324`
   (34-digit floor of 2⁻¹⁰⁷⁵) → ±0 with underflow-inexact — **for
   round-to-nearest**; this API has no rounding parameter, so RN constants
   suffice (document that a future `init(_:rounding:)` needs the
   direction-aware constants from doc 06).
3. In-range: truncate `c` to 19 digits: `(d, r) = c._quotientAndRemainder
   (dividingBy1e: D − 19)` where `D = digit count`; let `p = q + (D − 19)`.
   Convert `d·10^p` via ported `_cox_parse` → candidate `lo`; convert
   `(d+1)·10^p` → candidate `hi`. If `lo == hi`, done (any value between two
   representable brackets rounds identically) — *unless* `r == 0`, where
   `d·10^p` is the exact value and `_cox_parse`'s own result is already
   correct. If `lo != hi`, the true value straddles a rounding boundary:
   decide by exact comparison of `c·10^q` against the Double midpoint between
   `lo` and `hi` using the ported `_Wide` bigint — **enlarged**: Foundation's
   4×UInt128 (512-bit) `_Wide` suffices for `5^|p|` with `|p| ≤ ~167`;
   here `|p| ≤ 342` needs `5^342 ≈ 2⁷⁹⁵` × `c ≤ 2¹¹³` → **1024-bit** (8
   limbs). Port `_Wide` (FPC:888-953) with limbs parameterized; its three
   operations (multiply by 5^k chunks, shift, compare) generalize
   mechanically.
4. Subnormal results: `_cox_parse` rounds at the fixed 54-bit position;
   for results below `2⁻¹⁰²²` the rounding position is coarser. Foundation
   never hits this (its range is normal-only, doc 06 §6.1). Port the
   fixed-position variant Foundation already contains for its `k < −128`
   re-rounding (`_cox_uscale(…, s)` with explicit shift, FPC:1113-1128):
   compute the result's binary exponent from the scaled product's magnitude,
   set the rounding position accordingly, and apply the same
   guard+sticky rounding. This is the one genuinely new code path in this
   direction; test it against every power of ten in
   `[1e−324, 1e−308]` and random subnormal-landing values (doc 10).
5. `Float(x)`/`Float16(x)`: `Float(Double(x))` double-rounds incorrectly in
   principle — for these narrow targets, correct rounding via
   `Double(x)`-then-narrow fails only when `Double(x)` lands exactly on a
   Float-rounding boundary and the sticky information was lost. Handle later
   (or document as known-lossy); the protocol only requires
   `init(_: Decimal128)` on `Double` extensions we choose to provide.

## 5.4 `Int`/`BinaryInteger` from `Decimal128` (same TODO comment)

`Int(x)` truncates toward zero, traps on NaN/∞/overflow (match stdlib
`Int(_: Double)` semantics); `Int(exactly:)` returns nil in those cases.
Implementation: `rounded(.towardZero)` (doc 03) then scale-out:
`c × 10^(E−6176)` with `E ≥ 6176` guaranteed after rounding-to-integral;
overflow-check `10^k` multiply into the target width via
`multipliedReportingOverflow`. Generic over `FixedWidthInteger`.

## 5.5 Tests

- Round-trip: for random Doubles, `Double(Decimal128(d)) == d` (34 > 17
  digits, always exact round-trip — *prove in doc as a one-liner*: the
  conversion `d → Decimal128` has relative error < 10⁻³³ ≪ half-ulp of
  Double ⟹ nearest Double to the image is `d`).
- Known vectors: `0.1`, `0.5`, `Double.pi`, `1e308`, `5e-324`,
  `Double.leastNormalMagnitude ± ulp`, and the SR-13837 consecutive-Double
  table (Foundation `DecimalTests.swift:1011-1032`) — expected values from
  Python `decimal.Decimal(float)` (exact) + `.quantize`/context rounding
  (doc 10 generator).
- Ties: decimal values exactly midway between Doubles
  (e.g. Foundation's `Decimal128("10746007285463371481088")` →
  `0x1.23456789abcdfp+73.nextUp` vector, DecimalTests:1252) and the
  bracketing-path `lo != hi` fixtures.
- Saturation boundaries: `±1.797693134862315807937289714053034e308`
  (largest finite result) vs. `.nextUp` in decimal (→ ∞);
  `2.470328229206232720882843964341106e−324` (→ 0) vs. `.nextUp` (→
  `5e−324`).
