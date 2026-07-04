# 03 — Round-to-integral, quantize, scaleB, integer conversions, total order

Foundation's key structural insight (its `_roundReportingInexact`,
`Decimal+Math.swift:826-864`): *round-to-integral, quantize, and re-scaling
are all "re-round the significand at a target exponent"*. Everything in this
document reduces to divide-by-10ᵏ (doc 01 G-M helpers) plus a rounding
predicate, or multiply-by-10ᵏ plus a range check.

## 3.1 `rounded(_ rule:)` — replace stub at Decimal128.swift:1524

Semantics: IEEE `roundToIntegral{...}` per rule; Swift's `rounded` does *not*
signal inexact (that would be `roundToIntegralExact` — expose later as an
internal `_roundedExact` if flags become real).

```swift
public func rounded(_ rule: FloatingPointRoundingRule) -> Decimal128 {
  guard _isFiniteNonzero else {
    if isSignalingNaN { return _signal(.invalid, default: _quiet._canonical) }
    if isNaN { return _canonical }
    if isInfinite { return self }
    // Zero: preferred exponent max(Q(x), 0) → clamp E up to 6176.
    let e = max(exponentBitPattern, 6176)
    let abs = Self(bitPattern: UInt128(truncatingIfNeeded: e) &<< 113)
    return _isSignMinus ? -abs : abs
  }
  let e = exponentBitPattern
  guard e < 6176 else { return self }          // already integral
  let c = significandBitPattern
  let shift = Int(6176 &- e)
  guard shift <= 34 else {
    // |x| < 1 and even the highest digit is below the units place:
    // result is 0 or ±1 depending only on direction (no ties possible when
    // shift == 35+? — careful: shift == 34 with c == 5·10³³ IS a tie at 0.5;
    // hence the guard is shift > 34, where |x| < 10³⁴·10^−35 < 1/10 … no:
    // c < 10³⁴, value < 10^(34−35) = 0.1 — below any tie. Direction only.)
    let up: Bool = switch rule {
    case .awayFromZero: true
    case .down: _isSignMinus
    case .up: !_isSignMinus
    case .toNearestOrEven, .toNearestOrAwayFromZero, .towardZero: false
    @unknown default: fatalError("Unknown rounding rule.")
    }
    let abs = Self(bitPattern: (6176 as UInt128) &<< 113 | (up ? 1 : 0))
    return _isSignMinus ? -abs : abs
  }
  let (quo, rem) = c._quotientAndRemainder(dividingBy1e: shift)  // doc 01
  if rem == 0 { return Self(sign: sign, exponentBitPattern: 6176,
                            significandBitPattern: quo) }
  let pow = UInt128._exp10(shift)
  let nextAway: Bool = switch rule {         // same predicate family as _round
  case .awayFromZero: true
  case .down: _isSignMinus
  case .toNearestOrAwayFromZero: rem >= (pow &>> 1)
  case .toNearestOrEven:
    (quo & 1) == 0 ? rem > (pow &>> 1) : rem >= (pow &>> 1)
  case .towardZero: false
  case .up: !_isSignMinus
  @unknown default: fatalError("Unknown rounding rule.")
  }
  // quo + 1 ≤ 10³⁴ − 1? quo < 10³⁴/10^1 always (shift ≥ 1), so no carry
  // out of the 34-digit range is possible: quo ≤ 10³³ − 1 … verify: c ≤
  // 10³⁴−1, shift ≥ 1 ⇒ quo ≤ 10³³−1 ⇒ quo+1 ≤ 10³³ ✓ never overflows.
  return Self(sign: sign, exponentBitPattern: 6176,
              significandBitPattern: nextAway ? quo &+ 1 : quo)
}
```

Note the `shift == 34` case flows through the general path (it fits
`dividingBy1e` up to 38) — only `shift > 34` takes the direction-only branch,
and the comment in the listing records the tie-at-0.5 reasoning for why the
boundary sits there. Existing wrapper `round(_ rule:)` (mutating) already
delegates.

## 3.2 `quantized(by:rounding:)` — complete the stub (Decimal128.swift:457-493)

> **Superseded by doc 07 §§1.3, 3.5, 4.3**, which carries the full design with
> a complete listing, proof that coarser-quantum rounding can never signal
> invalid, edge-case table (Q1–Q16), and oracle-verified vectors. The sketch
> below is retained as a summary; where they differ, doc 07 governs.

IEEE 754-2019 §5.3.2 `quantize(x, y)`: value of `x`, quantum of `y`. Never
overflows/underflows; signals **invalid** (returning NaN) when the result
can't hold 34 digits; signals inexact when the value changes.
Non-finite handling is already written up to the two `fatalError`s; the
remaining structure:

- `other.isZero` (lhs finite nonzero — falls into the first `fatalError`):
  per IEEE, quantize(finite, 0-with-quantum-Q) is *not* special — zero has a
  quantum like any value. So the stub's zero handling for *lhs* stays; there
  is nothing special about rhs zero at all. Delete the first `fatalError` by
  restructuring: only `guard _isFiniteNonzero` + NaN/∞ ladder are special.
- Finite main path (second `fatalError`):

```swift
let eTarget = other.exponentBitPattern
let e = exponentBitPattern
let c = significandBitPattern
if e >= eTarget {
  // Scale up: exact or invalid.
  let k = Int(e &- eTarget)
  // c·10^k must stay ≤ 10³⁴−1; k ≥ 35 always fails for c ≥ 1.
  guard k <= 33,
        c <= (9_999_999_999_999_999_999_999_999_999_999_999 as UInt128)
          / UInt128._exp10(k) else {
    return _signal(.invalid, default: .nan)
  }
  return Self(sign: sign, exponentBitPattern: eTarget,
              significandBitPattern: c &* UInt128._exp10(k))
} else {
  // Scale down with rounding; inexact iff digits are dropped.
  let k = Int(eTarget &- e)
  guard k <= 34 else {
    // Everything rounds away; value < ulp(target)... result is 0 or 1 unit
    // per rule (same direction-only predicate as §3.1 with tie
    // impossibility: k ≥ 35 ⇒ |x| < 10³⁴·10^(e−6176) ≤ 10^{−1}·quantum).
    …direction-only branch, result significand 0 or 1, exponent eTarget,
    _signal(.inexact, …)
  }
  let (quo, rem) = c._quotientAndRemainder(dividingBy1e: k)
  if rem == 0 { return Self(sign: sign, exponentBitPattern: eTarget,
                            significandBitPattern: quo) }
  …rounding predicate as §3.1; quo &+ 1 here CAN reach 10³⁴? No: k ≥ 1 ⇒
  quo ≤ 10³³ − 1 (same argument as §3.1) ✓;
  return _signal(.inexact, default: signed result)
}
```

Note `k == 34` in the scale-down arm: `quo == 0` always
(c < 10³⁴ = divisor), `rem == c ≠ 0`, ties possible at `c == 5·10³³` — the
general predicate handles it; do *not* divert to the direction-only branch.

- [ ] Cohort tests at bitPattern level: `quantize(1.234, 10⁰) == 1`,
      exponent of result equals `other`'s in every case incl. zeros
      (`quantize(±0·10^a, 10^b)` → `±0·10^b`).

## 3.3 `init(sign:exponent:significand:)` — scaleB (stub at :539)

Swift semantics (`FloatingPoint`): `value = (sign) × significand × 10^exponent`
(radix 10). IEEE scaleB semantics for specials: NaN propagates (quiet,
canonical, sNaN → invalid), ∞ propagates with `sign` applied, zero keeps
quantum shifted by `exponent` (clamped).

```swift
public init(sign: FloatingPointSign, exponent: Int, significand: Decimal128) {
  if significand.isSignalingNaN {
    self = _signal(.invalid, default: significand._quiet._canonical)
    // NOTE Swift convention: sign parameter is NOT applied to NaN.
    return
  }
  if significand.isNaN { self = significand._canonical; return }
  if significand.isInfinite {
    self = sign == .minus ? -.infinity : .infinity
    return
  }
  let isSignMinus = sign == .minus   // per Swift: sign REPLACES, xor? —
  // Swift stdlib doc: "a value whose sign is sign, exponent is …" for
  // binary types init(sign:exponent:significand:) MULTIPLIES:
  // result = sign⊙|significand| ⨯ … — actually stdlib semantics:
  // `(sign == .minus ? -1 : 1) * significand.magnitude * radix^exponent`?
  // VERIFY against the stdlib doc comment: the documented identity is
  //   Self(sign: .plus, exponent: x.exponent, significand: x.significand)
  //     == x  for finite x,
  // and significand's own sign participates via |significand|? The stdlib
  // implementation for Double uses: result = significand * 2^exponent then
  // copysign(sign). Decide and DOCUMENT: recommended semantics
  //   self = (significand.magnitude scaled by 10^exponent) with `sign`
  // which matches Double's behavior of combining… Double does NOT use
  // magnitude; it computes significand * 2^exp and then applies sign only
  // through the documented identity where significand ≥ 0. Follow Double:
  //   scaled = significand scaled; then self = sign == .minus ? -scaled.magnitude
  //            : scaled.magnitude  — NO. Resolve by reading
  // swift stdlib FloatingPointTypes.swift.gyb: `self = Self(sign)(…)`.
  // ACTION ITEM for implementer: mirror Double exactly; add tests vs Double
  // analogues (e.g. init(sign: .minus, exponent: 2, significand: -3) — Double
  // gives -300? or +300?).
  let e = Int(significand.exponentBitPattern) &+ exponent
  // Clamp guards: e can exceed Int bounds only if caller passes Int.max-ish
  // exponents — saturate before feeding _round (values beyond ±20k are
  // unconditional overflow/underflow anyway):
  let eClamped = min(max(e, -40_000), 40_000)
  let abs = Decimal128._round(
    false, eClamped, (0, significand.significandBitPattern),
    .toNearestOrEven)
  self = isSignMinus ? -abs : abs
}
```

The clamp trick avoids `Int` overflow while preserving over/underflow
signaling; `_round` (doc 01) does the rest, including subnormal results and
the regrow fix for high exponents with small significands (this initializer
is exactly the operation that manufactures those cohort members).

**Open item deliberately surfaced**: the stdlib's exact sign-combination
semantics for negative `significand` must be pinned by test against `Double`
before implementation (the listing's long comment). This is a
5-minute empirical check that changes one line.

## 3.4 Integer conversions

- `init<T: BinaryInteger>(_ source: T)` (stub at :1352): fast path
  `source.magnitude ≤ 10³⁴−1` → exact, `E = 6176` (this is today's
  `init(integerLiteral:)` body — after this lands, the literal init and
  `init?(exactly:)` both delegate here / to the core below and their
  `fatalError`s disappear).
  General path (Foundation's `_convert(from:)` shape, `Decimal+Math.swift:869-944`):
  reduce `magnitude` by `quotientAndRemainder(dividingBy: 10^38-as-T)` chunks
  (generic `T` arithmetic — fine off the hot path) until the leading chunk
  fits `UInt128`; keep the top ≤ 34 digits, fold every dropped digit into
  `sticky`, count dropped digits into the exponent, and finish with
  sticky-aware `_round(_, 6176 + dropped, (0, top), sticky:, .toNearestOrEven)`.
- `init?<T: BinaryInteger>(exactly:)` (fatalError at :1326): run the same
  reduction; return `nil` if any dropped digit was nonzero *after* absorbing
  trailing zeros: equivalently, strip trailing decimal zeros from `magnitude`
  first (cheap: `while m % 10 == 0`… bounded by 6111 iterations — batch by
  10^19 using T division), then require the residue ≤ 10³⁴−1 and zeros ≤ 6111.
- `ExpressibleByIntegerLiteral` (fatalError at :735): delegate to
  `init(_ source: Int128)`; inexact literals round to nearest-even like
  `Double`'s behavior for over-precise literals. (`Int128` covers 39 digits;
  values needing more use `init(_: some BinaryInteger)` or strings.)

## 3.5 `isTotallyOrdered(belowOrEqualTo:)` (stub at :1425)

IEEE 754-2019 §5.10 totalOrder for decimal — the BID adaptation of
Foundation's `Decimal+Conformances.swift:368` (which only handles NSDecimal's
no-cohort world; the decimal128 version must order *within* cohorts):

Ordering key (ascending): −qNaN < −sNaN < −∞ < negative finite
(by value; ties → **larger** exponent first) < −0 < +0 < positive finite
(by value; ties → smaller exponent first) < +∞ < +sNaN < +qNaN;
NaNs of same sign/kind order by payload (ascending for +, descending for −).
Zeros: −0 < +0; among same-signed zeros, order by exponent like other
same-valued cohorts.

Implementation sketch — avoid case explosion via the standard trick: map each
operand to a signed-magnitude *total-order key* and compare keys:

```swift
internal var _totalOrderKey: UInt128 {
  // Canonicalize (noncanonical → canonical zero/inf/nan form) first, then:
  // For finite x: key = (biasedExponent << 113 | significand) is NOT
  // monotone across cohorts (1×10^1 vs 10×10^0 must tie-break by exponent
  // AFTER value). Instead normalize the cohort to its LOWEST exponent
  // representation? No — totalOrder distinguishes cohort members. Correct
  // approach: compare values first (existing `<` logic without signaling),
  // then exponents. A single key is only possible if value-then-exponent
  // collapses to a monotone integer — it does not in BID. Use the two-stage
  // comparison instead of a key.
}
```

Two-stage comparison (recommended; the "key" idea above is recorded to
explain why it was rejected):

1. Handle NaNs (four combinations of sign×{s,q}, payload comparison on
   canonicalized payloads).
2. Different signs (treat zeros as signed): `lhs._isSignMinus && !rhs…` → true.
3. Same sign, both finite: if values differ (reuse `<`'s magnitude comparison
   *without* `_signal` — factor the finite comparison core out of
   `Comparable.<` into `_isMagnitudeLess(than:)`), order by value adjusted
   for sign; if values are equal (`==` core), compare
   `exponentBitPattern` — for positive operands smaller-or-equal exponent
   ⇒ totally-below-or-equal; inverted for negative.
4. Infinities per the key line above.

- [ ] Test with the cohort pair from `testEquatable`
      (`1.0×10¹ vs 10×10⁰` bit patterns), ±0 pairs, NaN payload pairs,
      and cross-check the full ordering axioms (total, antisymmetric,
      transitive) on a randomized canonical sample.

## 3.6 Preferred exponents summary (for review against IEEE Table in §5.2 / §5.3)

| Operation | Preferred Q (exact results) |
| --- | --- |
| rounded / roundToIntegral | max(Q(x), 0) |
| quantize | Q(y) — mandatory, not just preferred |
| scaleB | Q(x) + n |
| convertFromInt | 0 |
| division (doc 02) | Q(x) − Q(y) |
| remainder (doc 07) | min(Q(x), Q(y)) |
| fma (doc 08) | min(Q(x)+Q(y), Q(z)) |
| squareRoot (doc 09) | ⌊Q(x)/2⌋ |
