# 01 — Rounding infrastructure

Shared groundwork that every subsequent document builds on. Four independent
changes plus one bug fix, all in `Sources/DecimalAnnex/Decimal128.swift` and
`Sources/DecimalAnnex/UInt128+Utilities.swift`.

## 1.1 Sticky-aware `_round`

`Decimal128._round(_:_:_:_:)` rounds an intermediate
`(high · 2¹²⁸ + low) · 10^(biasedExponent − 6176)` and today assumes that
intermediate is *exact*. Division (doc 02), FMA (doc 08), string parsing
(doc 04), and binary-FP conversion (doc 05) all produce intermediates that are
exact **except** for a known-nonzero fraction strictly below one unit of
`low`'s last place. Foundation's `_assemble` threads this through as a
`tail: (numerator, denominator)` exact fraction; for `Decimal128` a single
`Bool` suffices, because the callers never need to distinguish *how far* into
the unit the excess lies — only whether ties are broken and exactness is
destroyed.

**Signature** (add parameter; existing callers `adding`, `multiplied` pass
nothing):

```swift
@inlinable
@inline(__always)
internal static func _round(
  _ isSignMinus: Bool,
  _ biasedExponent: Int,
  _ significand: (high: UInt128, low: UInt128),
  sticky: Bool = false,
  _ rule: FloatingPointRoundingRule
) -> Decimal128
```

**Invariant given to callers**: when `sticky` is true, the true magnitude `V`
satisfies `I < V < I + 10^(biasedExponent − 6176)` where `I` is the value of
the intermediate. Consequences inside `_round`, where digit-stripping computes
`(quo, rem)` with divisor `pow = 10^n`:

- The *true* remainder is `rem + ε`, `0 < ε < 1`. Since `pow` is even and
  `rem` is an integer, `rem + ε > pow/2  ⟺  rem ≥ pow/2`, and
  `rem + ε == pow/2` is impossible. Exact ties therefore cannot occur when
  `sticky` is set.
- Every *exactness* test `rem == 0` becomes `rem == 0 && !sticky`.
- Every *tie* test changes as follows (shown for the main inexact branch;
  the tiny-path branch with its two-level `(rem, rem_)` remainder gets the
  same treatment with `sticky` as a third level ORed into `rem_`'s
  nonzero-ness):

```swift
// Before:
case .toNearestOrAwayFromZero:
  rem >= (pow &>> 1)
case .toNearestOrEven:
  (quo & 1) == 0 ? rem > (pow &>> 1) : rem >= (pow &>> 1)

// After:
case .toNearestOrAwayFromZero:
  rem >= (pow &>> 1)                       // unchanged: ε only breaks ties up
case .toNearestOrEven:
  (quo & 1) == 0
    ? (rem > (pow &>> 1) || (rem == (pow &>> 1) && sticky))
    : rem >= (pow &>> 1)
```

- In the *no-stripping* path (`pow == 1`, `rem == 0`), a set `sticky` means
  the result is inexact with the dropped fraction strictly below half an ulp:
  directed rules may still bump (`awayFromZero`, sign-matching `up`/`down`);
  the two to-nearest rules never do. This is exactly the "sub-half-ulp
  perturbation" branch `adding` already implements inline for far-apart
  operands (Decimal128.swift:1042-1087) — reuse its `nextAway`/`nextToward`
  switch structure.
- Tininess detection is *unchanged*: `sticky` adds strictly less than one unit
  of `low`'s lsb, and every tininess comparison in `_round` is against a
  power-of-ten bound `B`. `(hi, lo) < B ⟹ (hi, lo) + ε < B` requires that
  equality `(hi, lo) == B − 1 + ε < B` still classify the same way — it does,
  because the comparisons are strict `<` against `B` and `V < I + 1 unit ≤ B`
  whenever `I ≤ B − 1`. Re-verify each of the three range branches
  (`e < −34`, `e < −5`, `e < 33`) against this argument when implementing.

**Checklist for the implementer**

- [ ] Add the parameter with default `false`; confirm `adding`/`multiplied`
      compile unmodified and all existing tests pass.
- [ ] Audit all six `rule` switches inside `_round` (two inexact branches ×
      to-nearest cases, plus the `e < −68` far-underflow branch where `sticky`
      is irrelevant because the result is already below half of
      `leastNonzeroMagnitude` — confirm: with `sticky`, magnitude is still
      `< 1/2 · leastNonzeroMagnitude`? **No** — the guard is `e < −68`; the
      value including ε remains below the branch's precondition only because
      ε < 1 unit at exponent `e ≤ −69`, and the branch's bound has ≥ 34
      orders of magnitude of slack. Document this in a comment).
- [ ] Signal `.inexact`/`.underflowInexact` whenever `sticky` is set, even if
      `rem == 0`.

## 1.2 Bug fix: exact-path overflow with non-full significands

`_round` currently declares overflow whenever the stripped exponent exceeds
12287:

```swift
guard e <= 12287 else { /* signal overflow per rule */ }
```

This is wrong when `quo` has decimal headroom. Counterexample, reachable
today through `*`:

```
x = Decimal128(bitPattern: (12287 << 113) | 1)   // 1 × 10^6111
y = Decimal128(bitPattern: ( 6177 << 113) | 1)   // 1 × 10^1 (cohort member of 10)
x * y:  quo = 1 · 1 = 1,  e = 12287 + 6177 − 6176 = 12288 > 12287
```

The true product `10^6112` **is** representable — any cohort member
`c · 10^k = 10^6112` with `c ≤ 10³⁴−1`, `k ≤ 6111` works, e.g.
`c = 10, k = 6111` (biased 12287). The current code signals overflow and
returns ±∞ for a representable product. (Note the literal `10` is encoded as
`c = 10, E = 6176` and does *not* trigger the bug; the low-significand,
high-exponent cohort members that do can also arise as results of earlier
arithmetic, e.g. any exact division whose preferred exponent lands high, so
this is not merely a bit-pattern curiosity.)

**Fix** (mirrors `_assemble`'s regrow clause, Foundation `Decimal+Math.swift:1211`):
before the overflow guard, try to absorb the excess exponent into the
significand:

```swift
if e > 12287 {
  let k = e &- 12287
  // 10^34 − 1 has 34 digits; quo can absorb k more digits iff
  // quo * 10^k still has at most 34 digits.
  if k <= 33, quo <= (9_999_999_999_999_999_999_999_999_999_999_999 as UInt128)
      / UInt128._exp10(k) {
    quo &*= UInt128._exp10(k)
    e = 12287
  }
}
guard e <= 12287 else { /* existing overflow handling */ }
```

Apply in **both** the exact and inexact result paths after digit-stripping
(inexact case: the increment-and-carry step that can push
`quo` to `10³⁴` must run **before** the regrow, since regrowing first would
mask the `e &+= 1` carry interaction — work through the order carefully; the
safe sequence is: strip → round-increment/carry → regrow → overflow guard).

- [ ] Regression tests: `(1 × 10^6111) * 10` (exact, representable),
      `(1 × 10^6111) * (10^34 − 1)` (must genuinely overflow),
      the `+` analogue `(1 × 10^6111) + (1 × 10^6111)` → `2 × 10^6111` (fine)
      vs. sums whose stripped exponent exceeds 12287 with headroom.
      Compare `bitPattern` against Python-`decimal` oracle results (doc 10).

## 1.3 Granlund–Montgomery division by 10ᵏ

Port from Foundation `Decimal+Math.swift`:

1. `UInt128._quotientAndRemainder(dividingBy1e e: Int) -> (quotient: UInt128,
   remainder: UInt128)` (`Decimal+Math.swift:88-136`): for each `e ∈ 1…38` a
   hardcoded `(multiplier, shift)` pair computes
   `q = ((self >> e) * multiplier).high >> shift; r = self − q·10^e`.
   The existing one-off `_quotientAndRemainderDividingBy1e18` (see
   `UInt128+Utilities.swift:49-60`, citing Granlund & Montgomery 1994 thm 4.2)
   is the `e = 18` row of this table; absorb it.
2. `UInt128._quotientAndRemainder(fullWidth: (high: UInt128, low: UInt128),
   dividingBy1e e: Int)` (`Decimal+Math.swift:138-205`): one round of Knuth
   short division in base 2¹²⁸ using a second table of
   `(q1, r1)` where `2¹²⁸ = q1·10^e + r1` for `e ∈ 1…19`, splitting
   `e > 19` into two passes. This replaces the `pow.dividingFullWidth((hi, lo))`
   calls in `_round` — Swift's `UInt128.dividingFullWidth` is a software loop
   and this is the single largest performance lever for the existing hot path.
   Absorb `_UInt256._quotientAndRemainderDividingBy1e38` similarly.
3. Exact-division cascade `_quotientIfExactDividingBy10/100/10000/1e8/1e16`
   (`Decimal+Math.swift:210-262`): multiply by the modular inverse of the odd
   part of 10ᵏ mod 2¹²⁸, rotate right by k, range-check; returns `nil` unless
   exactly divisible. Needed by doc 02 (preferred-exponent normalization of
   exact quotients) and doc 09 (exact roots). Transcribe the constants, do not
   re-derive by hand; verify each against
   `python3 -c "print(pow(5**k, -1, 2**128))"`.

Table constants must be copied exactly and covered by an exhaustive unit test
(`for e in 1...38`, random dividends, compare against
`quotientAndRemainder(dividingBy: UInt128._exp10(e))`).

## 1.4 pow10 table

Replace the body of `UInt128._exp10(_:)` (UInt64 table + multiply,
`UInt128+Utilities.swift:21-46`) with a single `static let` array of 39
`UInt128` values (Foundation `Decimal+Math.swift:27-67` has the values;
transcribe as `UInt128(high << 64 | low)` literals or `_low/_high` pairs).
Keep the API; do the same for `_UInt256._exp10` up to 77 via composition.
(Swift 6.2 `InlineArray` is not available at this toolchain floor — a
`static let [UInt128]` global is acceptable; measure before doing anything
fancier.)

## 1.5 Multiply fast path

In `multiplied(by:rounding:)`: when both significands fit in 64 bits
(`significandBitPattern.leadingZeroBitCount >= 64` for both), compute
`UInt64.multipliedFullWidth` and zero-extend, skipping the 128×128 full-width
product (Foundation `Decimal+Math.swift:449-455`). Values ≤ 10¹⁹ cover most
real-world magnitudes.

## Verification

- Existing 9 XCTest cases stay green.
- New unit tests for 1.2 (bitPattern-level), 1.3 (exhaustive vs. stdlib), and
  a randomized `_round`-with-sticky harness: generate `(hi, lo, e, sticky)`
  tuples, compute the exact value with Python `decimal` at prec 34 plus an
  artificial `+ 10^(e−6176) · 1/7` when sticky, round under all five rules,
  compare bitPatterns (doc 10 has the fixture pipeline).
