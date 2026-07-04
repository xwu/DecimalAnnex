# 04 — Text: `description` re-implementation and string parsing

Scope note (project decision): `Decimal128` is a standard-library-style type —
**ASCII only, no locale awareness**. The Foundation parser's grapheme-aware
separator matching and `locale:` parameter are explicitly *not* ported.
New file suggested: `Sources/DecimalAnnex/Decimal128+Text.swift` (move the
existing `CustomStringConvertible`/`LosslessStringConvertible` extensions
there).

## 4.1 `description` — replace the "TODO: Re-implement" finite path

The output grammar is already pinned by tests and must not change
(`testPi`, `testDescription`, `testAddition`):

- Plain form when `0 ≤ decimalPointIndex < min(count, 16)`:
  `3.141592653589793238462643383279502`, `-1.` (trailing dot marks integral
  values), `12.` from `testAddition` (`"…description + "0"` pattern relies on
  a trailing dot after integral sums? — no: `(x + y).description + "0"` vs
  `Double.description`: `Double(2).description == "2.0"`, decimal gives
  `"2."`, `+ "0"` → `"2.0"` ✓ trailing dot confirmed).
- Leading-zero form for exponents in `[−4, 0)`: `0.05`, `-0.0001…`.
- Scientific otherwise: `-1.0e+2`, `-1e+2`, `9.99…e+6144` (exponent always
  signed, no zero padding).
- Zeros print `"0."`/`"-0."` — quantum information is currently **dropped**
  (existing `TODO: Decide if we want to preserve quantum`; see §4.3).
- Non-finite: `"inf"/"-inf"/"nan"/"-nan"`; NaN payloads are not printed
  (sNaN prints as plain `nan` after invalid — existing behavior).

Re-implementation (Foundation `Decimal.swift:203-285` adapted):

1. Add a 100-entry two-digit ASCII table and write-from-buffer-end digit
   generators:

```swift
internal let _asciiDigits: [(UInt8, UInt8)] = [
  (48, 48), (48, 49), /* "00", "01", … generated, 100 entries */ (57, 57)
]

extension UInt64 {
  // Writes self's digits ending at `end`, returns index of first digit.
  internal func _ascii(
    into buffer: UnsafeMutableBufferPointer<UInt8>, endingAt end: Int
  ) -> Int { /* two digits per iteration via _asciiDigits */ }
}
extension UInt128 {
  internal func _ascii(
    into buffer: UnsafeMutableBufferPointer<UInt8>, endingAt end: Int
  ) -> Int {
    // ≤ UInt64.max: delegate. Else split via
    // _quotientAndRemainder(dividingBy1e: 19) (doc 01), write low 19 digits
    // zero-padded, then recurse on the (≤ UInt64-sized after two splits)
    // quotient. c < 10³⁴ ⇒ at most one split needed here.
  }
}
```

2. Rewrite the `description` body to: compute digit count via
   `_commonLogarithm + 1` (no `String(UInt128)` allocation, no intermediate
   copy), branch into the three grammar forms, and fill one
   `String(unsafeUninitializedCapacity: 42)` buffer writing digits directly at
   their final positions (compute the decimal-point split from digit count and
   exponent *before* generating digits, so no post-hoc shifting is needed —
   this is the main structural improvement over the current implementation,
   which generates into a `String` then re-copies).
   Capacity stays 42 = sign(1) + digits(34) + point(1) + `e±`(2) + exp(4).

3. Micro-benchmark before/after (doc 10 benchmark target): expect the win to
   come from removing the `String(UInt128)` round-trip (which itself divides
   by 10 repeatedly through generic paths).

## 4.2 `LosslessStringConvertible.init?(_:)` — replace stub

Adapted from Foundation `__decimal` (`Decimal.swift:376-622`), simplified to
ASCII and extended to the IEEE grammar. Accepted grammar (case-insensitive
keywords; `s` = optional `+`/`-`):

```
number   := s (digits [ '.' [digits] ] | '.' digits) [ ('e'|'E') s digits ]
          | s ('inf' | 'infinity')
          | s 'nan'
```

Whole-string match only (`Decimal128("3.14x") == nil`) — this is a
standard-library-style `LosslessStringConvertible`, not a scanner. NaN
payloads are not parsed (round-trip of payloads goes through
`init(nan:signaling:)`/`bitPattern`, matching `description` which never prints
them). Note `description` prints `"inf"` — `"infinity"` is accepted for
IEEE 5.12 conformity.

Core (single pass over `description.utf8`; generic over `StringProtocol` as
the existing stub declares):

- Digit accumulation: `UInt64` accumulator promoted to `UInt128` at 19 digits
  (Foundation's `consume` closure, `Decimal.swift:465-499`); once 34
  significant digits are held, the 35th becomes `round`, later nonzero digits
  OR into `sticky`, and each further pre-point digit increments the implied
  exponent. Leading zeros are value-free (don't count toward 34); fractional
  leading zeros decrement the exponent.
- Exponent field accumulates into `Int` with saturation at ±100_000 (beyond
  the ±(6144+34+6176) interesting window everything is
  overflow/underflow-to-zero; saturation avoids `Int` overflow on
  `"1e99999999999999999999"`).
- Finish: combine `round`/`sticky` → `sticky = (round != 0) || sticky` is
  **wrong** (destroys tie information). Feed
  `_round(isSignMinus, biasedExponent, (0, c34), sticky:, .toNearestOrEven)`
  — but `_round`'s sticky models a *sub-unit* excess while parsing holds a
  full extra digit (`round ∈ 0…9` at the unit boundary). Two clean options,
  pick one and document at the call site:
  (a) keep 35 digits in the intermediate (c ≤ 10³⁵−1 still fits UInt128) and
  let `_round` strip the final digit with `sticky` covering digits beyond the
  35th — recommended: zero special cases, reuses the sink verbatim;
  (b) extend `_round` to take `tail: (numerator, denominator)` like
  Foundation's `(round<<1|sticky, 20)` encoding — more general than needed.
- Zeros: all-zero digit strings produce ±0 with exponent from the fractional
  digit count / exponent field, clamped to [0, 12287] — IEEE
  `convertFromDecimalCharacter` preserves zero quantum (`"0.00"` →
  `0 × 10⁻²`, biased 6174). This gives zeros *richer* round-trips than
  `description` currently emits (see §4.3).
- Out-of-range exponents: nonzero digits with saturated positive exponent →
  `_round` overflow path (±∞ + flags); saturated negative → underflow to
  ±0/±leastNonzero per rule. This falls out of feeding `_round` extreme
  biased exponents; no bespoke code.

## 4.3 Round-trip guarantees and the zero-quantum TODO

Invariant to test (doc 10): for every canonical `x`,
`Decimal128(x.description)` is **value-equal and cohort-equal** (bitPattern)
to `x` — *except* zeros and NaN payloads today:

- NaN payloads: `description` prints none; round-trip preserves NaN-ness only.
  Acceptable; document.
- Zeros: `description` prints `"0."` for every member of the zero cohort
  (exponent dropped), so parse restores `0 × 10⁰` (biased 6176), not the
  original quantum. Two options: (a) accept value-level round-trip for zeros
  (document the asymmetry with `hasSameQuantum` caveat), or (b) resolve the
  existing TODO by printing zeros with quantum, e.g. `0e-2` / `0.00`.
  **Recommendation: (b) eventually, but as a separate, deliberately-visible
  change** since it alters pinned output; the parser in §4.2 already handles
  it. Until then the round-trip test special-cases zero to value equality.

## 4.4 Tests

- Grammar acceptance/rejection table: `""`, `"."`, `"e5"`, `"1e"`, `"+.5"`,
  `".5e+1"`, `"Infinity"`, `"-NAN"`, `"3.14x"` (nil), embedded NUL, huge
  digit strings (10⁵ digits of 9 → ±∞ path; 10⁵ zeros → exact zero).
- Rounding at the 34-digit boundary: `"…5"` tie cases (even/odd last kept
  digit), `"…50000…001"` (sticky breaks tie), all five rules via an internal
  `init?(_:rounding:)` if exposed, else `.toNearestOrEven` vectors only.
- Round-trip fuzz per §4.3 over random canonical bit patterns.
- Oracle: Python `decimal` string constructor at prec 34 (doc 10).
