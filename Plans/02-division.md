# 02 — Division

Implements `divided(by:rounding:)` (currently `fatalError`). Adapted from the
Foundation rewrite's `_divideReportingInexact`
(`Decimal+Math.swift:518-565`), which replaces long division with:
*over-scale the dividend, one 256÷128 full-width divide, remainder becomes the
sticky bit*. Requires doc 01 (sticky-aware `_round`, exact-division cascade).

## 2.1 Special cases (guard ladder, mirroring `multiplied(by:rounding:)`)

Result sign is always `isSignMinus = lhs._isSignMinus != rhs._isSignMinus`
(applies to NaN-free paths):

| lhs \ rhs | sNaN | qNaN | ±∞ | ±0 | finite≠0 |
| --- | --- | --- | --- | --- | --- |
| **sNaN** | invalid, quiet lhs | invalid, quiet lhs | invalid, quiet lhs | invalid, quiet lhs | invalid, quiet lhs |
| **qNaN** | invalid, quiet rhs | lhs canonical | lhs canonical | lhs canonical | lhs canonical |
| **±∞** | invalid, quiet rhs | rhs canonical | **invalid, NaN** | ±∞ | ±∞ |
| **±0** | invalid, quiet rhs | rhs canonical | ±0 † | **invalid, NaN** | ±0 † |
| **finite≠0** | invalid, quiet rhs | rhs canonical | ±0 † | **divisionByZero, ±∞** | main path |

† zero results carry the preferred exponent: biased
`e = clamp(E₁ − E₂ + 6176, 0…12287)` (IEEE 754-2019 preferred quantum for
division is `Q(x) − Q(y)`), i.e.
`Self(bitPattern: UInt128(truncatingIfNeeded: e) &<< 113)` negated as needed.
`x/0` must go through `_signal(.divisionByZero, default:)` — the first use of
that flag; confirm `_DecimalException` plumbing accepts it.

Follow the exact sNaN/qNaN precedence order used by `adding`
(Decimal128.swift:954-967): lhs sNaN, rhs sNaN, lhs NaN, rhs NaN, then
infinities, then zeros.

## 2.2 Main path

```swift
let c1 = lhs.significandBitPattern
let c2 = rhs.significandBitPattern
let e1 = Int(lhs.exponentBitPattern)
let e2 = Int(rhs.exponentBitPattern)

// Fast path: dividing by a power of ten is exact apart from cohort selection.
if c2 == 1 {
  return ._round(isSignMinus, e1 &- e2 &+ 6176, (0, c1), rule)
}

// Scale the dividend to fill 128 bits so the quotient carries full precision.
// Underestimate of decimal headroom: 1233/4096 ≈ log10(2). One conditional
// top-up brings the estimate to exact.
var shift = ((c1 | 1).leadingZeroBitCount &* 1233) &>> 12
var scaled = c1 &* UInt128._exp10(shift)
if scaled <= (UInt128.max / 10) {
  shift &+= 1
  scaled &*= 10
}
// Widen by 10^38 into a 256-bit dividend; quotient gains ≥ 38 more digits.
let (hi, lo) = scaled.multipliedFullWidth(by: UInt128._exp10(38))
let (q1, r1) = hi.quotientAndRemainder(dividingBy: c2)
let (q2, r2) = c2.dividingFullWidth((r1, lo))

return ._round(
  isSignMinus,
  e1 &- e2 &+ 6176 &- shift &- 38,
  (q1, q2),
  sticky: r2 != 0,
  rule)
```

Why this is correctly rounded: the exact quotient is
`(q₁·2¹²⁸ + q₂ + r₂/c₂) · 10^(e₁−e₂−shift−38)` with `0 ≤ r₂ < c₂`, so the
fractional part is strictly below one unit of `q₂`'s last place — precisely
the sticky invariant of doc 01. The quotient `(q1, q2)` has at least
`34 + 38 − 34 = 38` digits beyond the eventual precision... more precisely:
`scaled ≥ ⌊2¹²⁸/10⌋+1 > 10³⁷`, so `scaled·10³⁸/c₂ > 10⁷⁵/10³⁴ = 10⁴¹`
guaranteeing ≥ 42 significant digits before `_round` strips to 34 — ample
separation between the rounding position and the sticky fraction.

Overflow of `q1` in `hi.quotientAndRemainder(dividingBy: c2)`: impossible —
`hi < c₂ · 2¹²⁸ / …`? Verify: `hi ≤ scaled·10³⁸ / 2¹²⁸ < 2¹²⁸`, and
`q1 = hi / c2` needs `hi/c2 < 2¹²⁸` ⟸ always. (`dividingFullWidth`
precondition `r1 < c2` holds by construction.)

## 2.3 Preferred exponent for exact quotients

Foundation compacts all trailing zeros (NSDecimal has no cohorts). IEEE
754-2019 §5.2 requires: *if the result is exact, select the cohort member
whose exponent is closest to the preferred exponent* `Q(x) − Q(y)`.

The main path over-scales by `shift + 38`, so an exact quotient (e.g. `10/2`)
emerges from `_round` with dozens of trailing zeros and an exponent far below
preferred. Post-process **only when the division was exact**
(`r2 == 0` **and** `_round` stripped exactly — detect by having `_round`
return exactness, or recompute: result is exact iff `sticky == false` and the
re-multiplied check passes; simplest correct scheme: after `_round`, if
`r2 == 0`, strip trailing zeros from the *result*):

```swift
// result: Decimal128 from _round; preferred: Int = e1 - e2 + 6176
if r2 == 0 {
  var c = result.significandBitPattern
  var e = Int(result.exponentBitPattern)
  // Only an exact division can produce rem == 0 in _round's stripping;
  // if it didn't, c already ends in a nonzero digit and the loop exits
  // immediately, so re-checking exactness here is unnecessary. (Convince
  // yourself: _round with sticky == false and rem != 0 rounds, possibly
  // leaving a trailing zero after increment — e.g. …9 + 1 = …0. So DO
  // detect exactness properly: extend _round to report it, or gate on
  // `_signal` having recorded no inexact flag once flags are real. Until
  // then, recompute: exact ⟺ result * rhs == lhs is NOT valid (rounding);
  // the robust interim gate is to return (result, inexact) from an
  // internal _divideCore and only strip when !inexact.)
  // CORRECTED by machine verification (Plans/verification/verify_plans.py):
  // the strip bound is min(preferred, 12287), NOT preferred alone. When the
  // preferred exponent exceeds the format maximum (e.g. exact
  // 5×10^6124 / 10^-6175-style cases; concretely (c=5, E=12300)/(c=1, E=6177))
  // an unbounded strip walks the exponent past 12287, undoing _round's
  // regrow clamp and producing an unencodable result. IEEE selects the
  // cohort member closest to preferred AMONG THOSE THAT EXIST.
  while e < min(preferred, 12287), c != 0, c % 10 == 0 {
    c /= 10
    e += 1
  }
  // Batch with the doc-01 cascade (÷10^16, ÷10^8, …) instead of the
  // digit-at-a-time loop shown here for clarity.
  return Decimal128(
    sign: isSignMinus ? .minus : .plus,
    exponentBitPattern: UInt(e),
    significandBitPattern: c)
}
```

**Design decision to make explicit in code review**: the clean structure is an
internal `_divideCore(...) -> (result: Decimal128, inexact: Bool)` (typed
Foundation-style tuple return) wrapped by the public API — inexactness is
needed both for the preferred-exponent gate and, later, for flag signaling.
This mirrors Foundation's `_xxxReportingInexact` naming and keeps `_round` as
the single rounding sink.

Worked example (`10/2`, both canonical): `x = 1×10^1` (c=1, E=6177),
`y = 2×10^0` (c=2, E=6176). Preferred biased exponent `= 6177`. Cohort of `5`:
exponents ≤ 6176 (c=5, E=6176 up to c=5·10³³, E=6143). Closest to preferred
is `E = 6176, c = 5`. The unstripped result would be `5·10³³ × 10^(…)` — the
strip loop must stop at `E = 6176` because `c = 5` is no longer divisible by
ten (preferred `6177` remains unreachable — that is correct and expected).

- [ ] Tests must pin `((10 as Decimal128) / 2).bitPattern == (6176 << 113 | 5)`
      and similar cohort-level vectors (Python `decimal` preserves these
      semantics — `Decimal(10)/Decimal(2) == Decimal('5')` with exponent 0 —
      and can generate fixtures; see doc 10).

## 2.4 Subnormals, underflow, overflow

All handled by `_round` (tininess before rounding, doc 01 audits). Division
reaches deeper exponents than `*` (biased `e` down to
`0 − 12287 + 6176 − 39 − 38 ≈ −6188`); confirm `_round`'s tiny path accepts
`biasedExponent` in `[−6188 − 34, 12287 + …]` without `Int` trouble (it takes
`Int`; fine) and that the `e < −68` early exit covers the extreme.

## 2.5 Edge-case tests (beyond §2.3)

- `1/3`, `2/3` under all five rounding rules (last-digit parity).
- `1/(10³⁴−1)`, `(10³⁴−1)/(10³⁴−2)` — quotients with long carry chains.
- `x / 10ᵏ` fast path incl. `k` pushing into subnormals and below.
- `leastNonzeroMagnitude / 2` (underflow to zero per rule),
  `leastNonzeroMagnitude / 0.5` (exact, no underflow),
  `greatestFiniteMagnitude / 0.5` (overflow per rule).
- Signed-zero sign through every special-case cell of the §2.1 table.
- Oracle sweep: random (c, E) pairs × rules against Python `decimal` (doc 10).

## 2.6 Verification executed

A Python transcription of §2.2 + §2.3 (with doc 01's generalized tininess
ladder and the §2.3 strip bound) matches mpdecimal (prec 34, Emin −6143,
Emax 6144, clamp 1) on **9,002 division checks** — value, cohort exponent,
and {inexact, overflow, underflow} flags — across all six rounding modes with
structured-random operands, plus the §2.3 cohort pins. Run
`python3 Plans/verification/verify_plans.py`. The harness caught two real
design errors now folded back into these documents (doc 01 §1.1 note, §2.3
strip bound) — treat it as a living artifact: re-run after any algorithm
change, and port its vectors to the Swift test suite (doc 10).
