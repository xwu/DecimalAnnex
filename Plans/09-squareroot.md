# 09 — Square root: `Decimal128.squareRoot(rounding:)`

Target: IEEE 754-2019 decimal128 (`Decimal128` in
`Sources/DecimalAnnex/Decimal128.swift`), BID encoding, precision *p* = 34.
This is a **design document**, not an implementation. It is written so a
competent Swift implementer can reproduce a **correctly rounded** square root
with confidence in its correctness. The algorithm below was machine-verified: a
line-for-line Python transcription passed **39,048 exact integer-inequality
certificates with 0 failures** across all six rounding rules (directed +
random + adversarial inputs), and matches CPython `decimal`
(`Context(prec=34, Emax=6144, Emin=-6143, clamp=1)`) bit-for-bit for
`.toNearestOrEven` including cohort exponents and the inexact flag; see §6.

Notation used throughout:

* `x` — the operand (`self`).
* `c` = `significandBitPattern` — the canonical integer significand,
  `1 ≤ c ≤ 10^34 − 1` for a finite nonzero canonical value (fits in 113 bits,
  since `10^34 − 1 < 2^113`).
* `Qx` = `Int(exponentBitPattern) − 6176` — the *quantum exponent* of `x`
  (`Qx ∈ [−6176, 6111]`). So `|x| = c · 10^Qx`.
* `d` = number of decimal digits of `c` = `c._commonLogarithm + 1` (`1 ≤ d ≤ 34`).
* `bias` = 6176; biased exponent `E = Q + 6176 ∈ [0, 12287]`.

---

## 1. IEEE 754-2019 requirements & Swift API mapping

### 1.1 What the standard requires

`squareRoot` is a §5.4.1 *general-computational* homogeneous operation. It is
**correctly rounded**: the returned value is the representable number nearest
(per the active rounding rule) to the exact real square root of the operand.

Special cases (IEEE 754-2019 §5.4.1, §6.x, and the NaN rules of §6.2):

| operand `x`                    | result                                   | flags |
|--------------------------------|------------------------------------------|-------|
| `−0`                           | `−0` (sign preserved, **exact**)         | none  |
| `+0`                           | `+0` (exact)                             | none  |
| `+∞`                           | `+∞`                                     | none  |
| `x < 0` (finite **or** `−∞`)   | canonical quiet NaN                       | **invalid** |
| quiet NaN                      | that NaN, canonicalized                   | none  |
| signaling NaN                  | canonical quiet NaN (quieted payload)     | **invalid** |
| `x > 0` finite                 | correctly rounded `√x`                    | **inexact** iff not a perfect square |

Two structural facts that shape the whole design:

1. **`squareRoot` never overflows and never underflows.** For a finite nonzero
   `x`, `√x` has magnitude ≈ the geometric "half" of `|x|`; the result exponent
   is ≈ `Qx/2`, which is always comfortably inside `[−6176, 6111]` (the extreme
   inputs `leastNonzeroMagnitude` and `greatestFiniteMagnitude` give result
   quantum exponents `−3121` and `+3039` respectively — see §6). Therefore the
   general `_round` overflow/underflow/tininess machinery is **not needed**, and
   only the `.invalid` and `.inexact` exceptions can ever be raised.

2. **Preferred exponent for an *exact* result is `⌊Qx/2⌋`** (IEEE 754-2019
   §5.4.1 "preferredExponent"; equivalently the GDA / decNumber "ideal exponent"
   `floor(operand.exponent / 2)`). This is a *cohort* choice: it only changes
   which representative of an exactly-representable value is returned, never the
   value. It also applies to the zero results: `√(0 · 10^Qx) = 0 · 10^⌊Qx/2⌋`.
   For inexact results the correctly-rounded value has a *unique* 34-significant-
   digit representative, so no cohort freedom exists.

> **Preferred-exponent verification.** IEEE 754-2019 Table "preferred exponent
> for arithmetic operations" gives, for `squareRoot`, `Q = ⌊Q(x)/2⌋`. CPython's
> `decimal` confirms every cohort case in §6, e.g. `sqrt(4)=2` (`E=0`),
> `sqrt(4.0)=2.0` (`E=−1`), `sqrt(4.00)=2.0` (`E=−1`), `sqrt(4.000)=2.00`
> (`E=−2`), `sqrt(0.00)=0.0` (`E=−1`).

### 1.2 Swift API surface (already stubbed)

```swift
public func squareRoot(rounding rule: FloatingPointRoundingRule) -> Decimal128
```

plus the inlinable no-argument overload that defaults to `.toNearestOrEven`, and
`formSquareRoot(rounding:)` / `formSquareRoot()` which just assign `self =
squareRoot(...)`. These wrappers already exist and are correct; only the body of
the two-argument `squareRoot(rounding:)` must be filled in. Availability and
style follow the rest of the file (`@available(macOS 15.0, …)`, two-space
indent, `&+ &- &* &<< &>>`, guard-ladder specials as in `adding(_:rounding:)`,
`@unknown default` on every `FloatingPointRoundingRule` switch).

`FloatingPointRoundingRule` has six known cases plus `@unknown default`:
`.toNearestOrEven`, `.toNearestOrAwayFromZero`, `.towardZero`, `.awayFromZero`,
`.up`, `.down`.

---

## 2. Reference survey

Consulted (network partially available; nothing below is fabricated — where a
primary source could not be fetched it is marked "from memory / first
principles"):

* **IEEE 754-2019** §5.4.1 (squareRoot, correct rounding, preferred exponent),
  §6.2 (NaN propagation, sNaN → invalid + quiet), §7.2 (invalid operation for
  `√` of a negative). Primary normative source.
* **General Decimal Arithmetic Specification** (Cowlishaw, speleotrove.com) —
  `square-root` operation: result is correctly rounded to `precision` digits;
  *ideal exponent* is `floor(operand.exponent / 2)`; `sqrt(-0) = -0`;
  `sqrt(x<0)` is invalid. Matches IEEE. (from memory; corroborated by the
  CPython `decimal` behaviour reproduced in §6.)
* **CPython `decimal` / libmpdec (`mpd_sqrt`)** — used here as the executable
  oracle. `Context(prec=34, Emax=6144, Emin=-6143, clamp=1)` is bit-for-bit
  decimal128 semantics **for round-to-nearest-even only**: per the GDA spec,
  `square-root` *always* rounds half-even and **ignores the context rounding
  mode** (empirically confirmed — changing `ctx.rounding` does not change
  `ctx.sqrt` output). IEEE `squareRoot`, by contrast, honors the rounding
  direction. Directed-rounding vectors therefore cannot be generated from
  CPython's `sqrt` directly; §6.4 gives the certificate method used instead.
* **Intel Decimal Floating-Point Math Library, `bid128_sqrt`** — web search
  (community.intel.com; the "Decimal floating-point square-root unit using
  Newton–Raphson iterations" patent, US 8,812,575) confirms Intel's approach:
  normalize the significand, compute a refined **reciprocal** square root by
  Newton–Raphson in fixed point (reciprocal avoids per-iteration division),
  multiply back, then correct + round. This is the high-performance route; we
  deliberately choose the simpler *integer* Newton (§3.3) because square root is
  not on the `+`/`×` hot path and integer Newton has a short, airtight
  correctness proof.
* **decNumber `decNumberSquareRoot`** — Newton variant carried out *in decimal*
  with a working precision a few digits above target, then rounded; establishes
  the ideal-exponent = `floor(exp/2)` cohort rule we adopt. (from memory.)
* **Integer square root correctness** — P. L. Montgomery / GMP `mpn_sqrtrem`
  notes; H. Cohen, *A Course in Computational Algebraic Number Theory*,
  Algorithm 1.7.1 (integer square root by Newton from an over-estimate seed);
  H. Warren, *Hacker's Delight* §11-1. These give the monotone-descent
  convergence + termination proof reproduced in §3.3.
* **Muller et al.**, *Handbook of Floating-Point Arithmetic* — correctly-rounded
  square root, the "no exact tie" argument for `√` (the midpoint `(s+½)²` is
  never an integer), reproduced in §3.4.

---

## 3. Chosen algorithm

### 3.0 Overview

Compute an **integer** square root at exactly 34 significant digits, then round
using a square-root-specific one-comparison test. Steps:

1. Handle specials (NaN, ∞, ±0, negatives) in a guard ladder.
2. Decompose `|x| = c · 10^Qx`.
3. Pick a scale `k` so that the *radicand* `W = c · 10^k` has **67 or 68
   decimal digits** *and* `Qx − k` is **even**. Then `s = ⌊√W⌋` has exactly 34
   digits and the result exponent is `E = (Qx − k)/2`.
4. Compute `s = ⌊√W⌋` and the remainder `r = W − s²` with integer arithmetic in
   `_UInt256` (§3.3).
5. If `r == 0`: exact — emit `s` and move its exponent toward the preferred
   exponent `⌊Qx/2⌋` by stripping trailing zeros (§3.6).
6. If `r != 0`: inexact — choose `s` or `s+1` from a single comparison of `r`
   against `s` (§3.4/§3.5), handle the `s+1 = 10^34` rollover (§3.7), and signal
   `.inexact`.

Why **not** reuse the shared `_round` sink: `_round` rounds a wide integer
significand by dividing out surplus digits and comparing the *discarded
remainder* against `pow/2` — that is the correct half-ulp test for
multiply/divide/add, but it is the **wrong** test for square root. For `√`, the
half-way point between the two candidate 34-digit results is `s + ½`, and the
correct half-ulp test is `r` vs `s` (derived from `(s+½)² = s² + s + ¼`, §3.4),
not `r` vs `pow/2`. `_round` would also re-derive the digit count and re-divide,
which is wasted work since we already produce exactly 34 digits. We therefore do
bespoke rounding and only reuse the final *encoding* idiom
`Self(bitPattern: UInt128(truncatingIfNeeded: E) &<< 113 | t)`.

### 3.1 Specials (guard ladder)

Mirrors `adding(_:rounding:)`. `_isFiniteNonzero` is `false` for NaN, ∞, every
zero, *and* every non-canonical finite significand (those are "treated as zero"
by `isZero`), so all cohort/canonicalization edge cases funnel correctly:

* `isSignalingNaN` → `_signal(.invalid, default: _quiet._canonical)`.
* `isNaN` (quiet) → `_canonical`.
* `isInfinite` → `_isSignMinus ? _signal(.invalid, default: .nan) : .infinity`.
* `isZero` (incl. non-canonical finite, treated as `±0`): result is `±0` with
  the **preferred exponent** `⌊Qx/2⌋`, sign preserved so `√(−0) = −0`:
  `E = (Qx >> 1) + 6176` (Swift `>>` on a signed `Int` is arithmetic, so
  `Qx >> 1 == ⌊Qx/2⌋` including for negative `Qx`). No exception. `⌊Qx/2⌋ ∈
  [−3088, 3055]` ⟹ biased `E ∈ [3088, 9231]`, always valid.

Then, for finite nonzero canonical `x`:

* `_isSignMinus` → `_signal(.invalid, default: .nan)` (`√` of a negative).
* otherwise, positive finite nonzero → §3.2.

### 3.2 Scaling / parity selection (the heart of the exponent logic)

We need `W = c · 10^k` with:

* **(digit count)** `d + k ∈ {67, 68}` so that `10^66 ≤ W < 10^68`, hence
  `10^33 ≤ √W < 10^34`, hence `s = ⌊√W⌋` is **exactly 34 digits**; and
* **(parity)** `Qx − k` even, so `E = (Qx − k)/2 ∈ ℤ` and
  `√|x| = √(c·10^k) · 10^{(Qx−k)/2} = √W · 10^E`.

`67 − d` and `68 − d` differ by 1, so exactly one has the parity matching `Qx`.
Writing it via the parity of `Qx + d` (67 is odd, 68 is even):

```
if (Qx + d) is odd  → k = 67 − d,  W has 67 digits
if (Qx + d) is even → k = 68 − d,  W has 68 digits
```

`d ∈ [1, 34]` ⟹ `k ∈ [33, 67]` (always ≥ 0; no negative shift). The result
exponent is `E = (Qx − k)/2` (an integer by construction).

In Swift: `let k = ((Qx &+ d) & 1) == 1 ? (67 &- d) : (68 &- d)` — the `& 1`
low-bit parity test is correct for negative `Qx` too (two's complement).

**W fits in 226 bits.** `W < 10^68` and `log2(10^68) = 68·3.32193 = 225.89`, so
`10^68 < 2^226`; thus `W < 2^226` and is held in a `_UInt256`. Its bit length is
in `[220, 226]`.

**`E` is always in range and never needs clamping.** As shown in §3.6,
`E ≤ ⌊Qx/2⌋` always (by a margin of 16…33), and `⌊Qx/2⌋ ≤ 3055`; on the low end
`E ≥ −3121`. Biased `E + 6176 ∈ [3055, 9231] ⊂ [0, 12287]`. This is the concrete
reason `√` "never overflows or underflows."

### 3.3 Integer square root `_isqrt(W) = ⌊√W⌋`

`W ∈ [10^66, 10^68)` (67–68 digits); `s = ⌊√W⌋ ∈ [10^33, 10^34) ⊂ (2^109, 2^113)`
fits in a `UInt128`.

We use **integer Newton with monotone descent from an over-estimate seed**
(Cohen Alg. 1.7.1 / Hacker's Delight §11-1). It has a two-line correctness proof
and needs no post-hoc ± correction search.

```
x_{n+1} = ⌊ (x_n + ⌊W / x_n⌋) / 2 ⌋
```

**Correctness (returns `⌊√W⌋`).** Let `q = ⌊√W⌋`.

* *Invariant `x_n ≥ q`.* If `x_n ≥ 1`, then `x_{n+1} = ⌊(x_n + ⌊W/x_n⌋)/2⌋ ≥
  ⌊(x_n + W/x_n)/2 − ½⌋`. By AM–GM `(x_n + W/x_n)/2 ≥ √W`, and a short case
  check gives `x_{n+1} ≥ ⌊√W⌋ = q` (the classic result; see Cohen Thm 1.7.1).
* *Strict decrease while `x_n > q`.* If `x_n > √W` then `W/x_n < x_n`, so
  `(x_n + W/x_n)/2 < x_n`, hence `x_{n+1} ≤ ⌊(x_n + ⌊W/x_n⌋)/2⌋ < x_n`.
* *Termination test.* Once `x_n = q`, `⌊W/q⌋ ≥ q` so
  `x_{n+1} = ⌊(q + ⌊W/q⌋)/2⌋ ≥ q = x_n`. Hence the loop condition
  "**continue while `x_{n+1} < x_n`; on `x_{n+1} ≥ x_n` return `x_n`**" returns
  exactly `q`, provided the seed `x_0 ≥ q`.

So the *only* correctness obligation on the seed is `x_0 ≥ ⌊√W⌋`. Seed quality
affects only iteration count.

**Seed (performance; must be an over-estimate).** Take the top ≈ 52 bits of `W`
at an *even* bit offset, `√` them in `Double`, shift back, then inflate:

```
let bitLength = 256 &- W.leadingZeroBitCount            // 220 … 226
let shift = (bitLength &- 52) & ~1                      // even; top ∈ [2^51, 2^53)
let top   = (W &>> _UInt256(0, UInt128(shift))).low     // < 2^53, exact in Double
var s0    = UInt128(Double(top).squareRoot()) &<< (shift / 2)
s0 &+= (s0 &>> 20) &+ 2                                 // guarantee s0 ≥ √W
```

*Why `top < 2^53`:* `shift = (bitLength−52)&~1 ≥ bitLength−53`, so `top =
W >> shift < 2^{bitLength−shift} ≤ 2^53`; `Double` represents every integer
`< 2^53` exactly, so `Double(top)` is exact. `shift` is even ⟹ `shift/2 ∈ ℤ`.

*Why the seed is an over-estimate after inflation:* `W = top·2^shift + ρ`,
`0 ≤ ρ < 2^shift`, so `√W < √top · 2^{shift/2} · (1 + 2^{-53})`. `Double.sqrt` is
correctly rounded (≤ ½ ulp, rel. `< 2^-52`), and truncating `√top` to an integer
before the shift adds rel. error `< 1/√top < 2^-25`. All error sources sum to
`< 2^-24`, so `s0·(1 + 2^-24) ≥ √W`; adding `(s0 >> 20) + 2 > s0·2^-24 + 1`
makes `s0` a strict over-estimate. (Ship a `debug`-only
`assert(_UInt256(0,s0) &* _UInt256(0,s0) ≥ W)` guard.)

*Iteration count.* Newton squares the relative error each step:
`2^-25 → 2^-50 → 2^-100 → 2^-200`, so after ≈ 3 doublings the absolute error is
`< 1`, then ≤ 2 monotone steps settle onto `q`. Bound: `≤ 6` iterations; typical
3–4. Each iteration is one `_UInt256 / UInt128` division (`W.high != 0`,
`divisor.high == 0` — the fast branch of `_UInt256.quotientAndRemainder`).

*Bullet-proof fallback seed* (if one prefers to avoid `Double`): `s0 =
UInt128(1) &<< ((bitLength &+ 1) / 2)` is a pure power of two `≥ √W` (since
`√W < 2^{bitLength/2}`), guaranteeing over-estimate at the cost of ~7 iterations.

```swift
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
@inlinable
internal func _isqrt(_ w: _UInt256) -> UInt128 {
  // Precondition: 10^66 <= w < 10^68, so floor(sqrt(w)) in [10^33, 10^34).
  let bitLength = 256 &- w.leadingZeroBitCount
  let shift = (bitLength &- 52) & ~1
  let top = (w &>> _UInt256(0, UInt128(shift))).low
  var s = UInt128(Double(top).squareRoot()) &<< (shift / 2)
  s &+= (s &>> 20) &+ 2                       // strict over-estimate of sqrt(w)
  assert(_UInt256(0, s) &* _UInt256(0, s) >= w)
  while true {
    let q = w.quotientAndRemainder(dividingBy: _UInt256(0, s)).quotient.low
    let next = (s &+ q) &>> 1
    if next >= s { return s }
    s = next
  }
}
```

### 3.4 Tie-impossibility lemma

> **Lemma.** For `W ∈ ℤ_{>0}` and `s = ⌊√W⌋`, `√W` is never exactly `s + ½`.
>
> *Proof.* If `√W = s + ½` then `W = (s + ½)² = s² + s + ¼`. But `s² + s ∈ ℤ`,
> so `W = (integer) + ¼ ∉ ℤ`, contradicting `W ∈ ℤ`. ∎

Consequence: round-to-nearest for `√` **never hits a tie**. Therefore
`.toNearestOrEven` and `.toNearestOrAwayFromZero` always agree, and the
tie-breaking direction is irrelevant to the returned value.

### 3.5 Which side of the midpoint — one comparison `r` vs `s`

`√W ∈ [s, s+1)`. The result is `√W` rounded to an integer (in units of `10^E`);
the only candidates are `s` and `s+1`. The midpoint is `s + ½`:

```
√W > s + ½  ⟺  W > (s+½)² = s² + s + ¼  ⟺  W ≥ s² + s + 1   (W ∈ ℤ)
             ⟺  r = W − s² ≥ s + 1  ⟺  r > s
√W < s + ½  ⟺  W ≤ s² + s          ⟺  r ≤ s
```

(`√W = s + ½` impossible by §3.4.) Also `r == 0 ⟺ W = s² ⟺ √W = s` exactly.
Note `r ∈ [0, 2s]`.

**Per-rule decision** (result value `≥ 0`, so `.down ≡ .towardZero` and
`.up ≡ .awayFromZero`; the sole negative-sign result is `√(−0)=−0`, handled in
§3.1 before reaching here):

| rule                                            | result significand `t`         |
|-------------------------------------------------|--------------------------------|
| `.toNearestOrEven`, `.toNearestOrAwayFromZero`  | `r <= s ? s : s+1`             |
| `.towardZero`, `.down`                          | `s`                            |
| `.up`, `.awayFromZero`                          | `r > 0 ? s+1 : s` (inexact ⟹ `s+1`) |

For the *inexact* branch (`r > 0`), `.up`/`.awayFromZero` always give `s+1`.
Exact results (`r == 0`) always give `t = s` for every rule (§3.6). Every switch
carries an `@unknown default: fatalError("Unknown rounding rule.")`.

### 3.6 Exact results: preferred-exponent cohort adjustment

When `r == 0`, `√|x| = s · 10^E` **exactly**, with `s` at 34 digits (the maximal
digit count) ⟹ `E` is the *minimum* exponent in the value's cohort. We must move
toward the preferred exponent `ideal = ⌊Qx/2⌋ = Qx >> 1`.

**`E ≤ ideal` always** (so we only ever *raise* `E` by stripping trailing zeros;
we never need to pad, which would exceed 34 digits). With `E = (Qx − k)/2`:

| case          | `k`      | `ideal − E`   | range (`d ∈ [1,34]`) |
|---------------|----------|---------------|----------------------|
| `Qx+d` odd, `Qx` even  | `67−d` | `(67−d)/2` | 17 … 33 |
| `Qx+d` odd, `Qx` odd   | `67−d` | `(66−d)/2` | 16 … 32 |
| `Qx+d` even, `Qx` even | `68−d` | `(68−d)/2` | 17 … 33 |
| `Qx+d` even, `Qx` odd  | `68−d` | `(67−d)/2` | 17 … 33 |

So `ideal − E ∈ [16, 33] > 0`. Raise `E` toward `ideal` by removing trailing
decimal zeros of `s`, stopping at `ideal` or when `s` is no longer divisible by
10 (whichever comes first — the closest achievable exponent, per IEEE):

```swift
var t = s, e = E
let ideal = Qx >> 1
while e < ideal {
  let (q, rem) = t.quotientAndRemainder(dividingBy: 10)
  if rem != 0 { break }
  t = q; e &+= 1
}
```

Because `s ≥ 10^33` may carry up to 33 trailing zeros, the loop runs ≤ 33 times.
(Optimization note: the planned exact-division-by-`10^k` modular-inverse cascade
could strip all `z` zeros in one shot; a simple `%10` loop is fine here since the
exact case is rare and `z ≤ 33`.) No exception is signalled for exact results.

*Worked example (verified in §6):* `x = 4.000 = 4000·10^{−3}`: `c=4000, Qx=−3,
d=4`; `Qx+d=1` odd ⟹ `k=63`, `W=4·10^{66}`, `s=2·10^{33}`, `E=−33`; `ideal=−2`,
strip 31 zeros ⟹ `t=200, e=−2` ⟹ `2.00`. Matches `Decimal("4.000").sqrt()`.

### 3.7 The `s + 1 = 10^34` rollover

`t = s+1` can reach `10^34` when `s = 10^34 − 1`, i.e. when `W ∈
(10^68 − 2·10^34 + 1, 10^68)` with `r > 0`. This **is** reachable from the
decomposition — concrete machine-verified witness: `x = (10^34 − 1) · 10^0 =
9999999999999999999999999999999999`. Then `d = 34`, `Qx + d = 34` even ⟹
`k = 34`, `W = 10^68 − 10^34`, `s = 10^34 − 1`,
`r = W − s² = 10^34 − 1 = s > 0`. Under `.up`/`.awayFromZero`,
`t = s + 1 = 10^34` — 35 digits, not encodable. Renormalize
`10^34 · 10^E = 10^33 · 10^{E+1}` (for the witness: `10^33 · 10^{−16} = 10^17`):

```swift
if t > 9_999_999_999_999_999_999_999_999_999_999_999 {   // t == 10^34
  t = 1_000_000_000_000_000_000_000_000_000_000_000       // 10^33
  e &+= 1
}
```

This only occurs on the inexact path (`r > 0`); `E+1 ≤ 3040 ⊂ range`, so it never
overflows to infinity. Exact results (`t = s`) never roll over.

---

## 4. Concrete repo-idiomatic Swift listing

In-principle compilable; reuses existing internals (`significandBitPattern`,
`exponentBitPattern`, `_commonLogarithm`, `_UInt256`, `_UInt256._exp10`,
`_signal`, `_quiet`, `_canonical`). The `_isqrt` helper is in §3.3.

```swift
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension Decimal128 {
  public func squareRoot(
    rounding rule: FloatingPointRoundingRule
  ) -> Decimal128 {
    // --- Specials ---------------------------------------------------------
    guard _isFiniteNonzero else {
      if isSignalingNaN {
        return _signal(.invalid, default: _quiet._canonical)
      }
      if isNaN {
        return _canonical
      }
      if isInfinite {
        // sqrt(+inf) = +inf ; sqrt(-inf) is invalid.
        return _isSignMinus ? _signal(.invalid, default: .nan) : .infinity
      }
      // Zero (also every non-canonical finite value, treated as +/-0).
      // sqrt(+/-0) = +/-0, exact, with preferred exponent floor(Qx/2).
      let qx = Int(exponentBitPattern) &- 6176
      let e = UInt(bitPattern: (qx >> 1) &+ 6176)
      let abs = Self(bitPattern: UInt128(truncatingIfNeeded: e) &<< 113)
      return _isSignMinus ? -abs : abs
    }

    // Finite, nonzero, canonical.
    if _isSignMinus {
      return _signal(.invalid, default: .nan)      // sqrt of a negative
    }

    // --- Decompose |x| = c * 10^Qx ---------------------------------------
    let c = significandBitPattern                  // 1 ... 10^34 - 1
    let qx = Int(exponentBitPattern) &- 6176       // quantum exponent
    let d = c._commonLogarithm &+ 1                // digit count, 1 ... 34

    // --- Scale so W = c * 10^k has 67 or 68 digits and (Qx - k) is even ---
    let k = ((qx &+ d) & 1) == 1 ? (67 &- d) : (68 &- d)   // k in [33, 67]
    let w = _UInt256(0, c) &* _UInt256._exp10(k)   // 10^66 <= w < 10^68
    var e = (qx &- k) >> 1                          // result quantum exponent

    // --- Integer square root and remainder -------------------------------
    let s = _isqrt(w)                               // floor(sqrt(w)), 34 digits
    let ss = _UInt256(0, s) &* _UInt256(0, s)
    let r = (w &- ss).low                           // remainder in [0, 2s]

    // --- Exact result: preferred-exponent cohort adjustment --------------
    if r == 0 {
      var t = s
      let ideal = qx >> 1                           // floor(Qx / 2), >= e
      while e < ideal {
        let (q, rem) = t.quotientAndRemainder(dividingBy: 10)
        if rem != 0 { break }
        t = q
        e &+= 1
      }
      let biased = UInt(bitPattern: e &+ 6176)
      return Self(bitPattern: UInt128(truncatingIfNeeded: biased) &<< 113 | t)
    }

    // --- Inexact result: round with the sqrt-specific r-vs-s test --------
    var t: UInt128 = switch rule {
    case .toNearestOrEven, .toNearestOrAwayFromZero:
      r <= s ? s : s &+ 1                            // ties impossible (§3.4)
    case .towardZero, .down:
      s
    case .up, .awayFromZero:
      s &+ 1                                         // r > 0, round up
    @unknown default:
      fatalError("Unknown rounding rule.")
    }

    // s + 1 == 10^34 rollover.
    if t > 9_999_999_999_999_999_999_999_999_999_999_999 as UInt128 {
      t = 1_000_000_000_000_000_000_000_000_000_000_000
      e &+= 1
    }

    let biased = UInt(bitPattern: e &+ 6176)
    let abs = Self(bitPattern: UInt128(truncatingIfNeeded: biased) &<< 113 | t)
    return _signal(.inexact, default: abs)
  }
}
```

Notes for the implementer:

* `_UInt256._exp10(k)` supports `k < 78`; here `k ≤ 67`. `_UInt256(0, c) &* …`
  is exact because the true product `< 10^68 < 2^256`.
* `(w &- ss).low` is safe: `r = W − s² ∈ [0, 2s]`, `2s < 2^114 < 2^128`, so the
  high word is 0.
* `e &+ 6176` is always a positive `Int` in `[3055, 9231]` — exact results can
  climb to `ideal = 3055` (biased 9231); inexact results have `E ≤ 3039`, so
  even the rollover `+1` stays ≤ biased 9216. `UInt(bitPattern:)` then
  `truncatingIfNeeded` is the same idiom the file already uses for biased
  exponents.
* Result is always non-negative on the main path (sign handled in specials), so
  no `negate()` is needed except the `−0` return.

---

## 5. Edge-case table

| input `x`                              | result           | exact? | exponent reasoning |
|----------------------------------------|------------------|--------|--------------------|
| `+0` (`0E+0`)                          | `+0` (`0E+0`)    | exact  | `⌊0/2⌋ = 0` |
| `−0`                                   | `−0`             | exact  | sign preserved, `⌊Qx/2⌋` |
| `0.00` (`0E−2`)                        | `0.0` (`0E−1`)   | exact  | `⌊−2/2⌋ = −1` |
| non-canonical finite                   | `±0` w/ `⌊Qx/2⌋` | exact  | treated as `±0` by `isZero` |
| `+∞`                                   | `+∞`             | —      | — |
| `−∞`                                   | qNaN, **invalid**| —      | negative operand |
| `−1`, `−4`, any `x<0`                  | qNaN, **invalid**| —      | negative operand |
| quiet NaN                              | that NaN, canon. | —      | propagate |
| signaling NaN                          | qNaN, **invalid**| —      | quiet + canonicalize |
| `1`                                    | `1`              | exact  | `k=66, s=10^33, E=−33→0` |
| `4` (`4E0`)                            | `2`              | exact  | ideal 0, strip 33 |
| `4.0` (`40E−1`)                        | `2.0` (`20E−1`)  | exact  | ideal −1, strip 32 |
| `4.00` (`400E−2`)                      | `2.0` (`20E−1`)  | exact  | ideal −1, strip 32 |
| `4.000` (`4000E−3`)                    | `2.00` (`200E−2`)| exact  | ideal −2, strip 31 |
| `400` (`400E0`)                        | `20`             | exact  | ideal 0 |
| `9`, `100`                             | `3`, `10`        | exact  | perfect squares |
| `4·10^Qx`, `Qx` **even**               | `2·10^{Qx/2}`    | exact  | perfect square |
| `4·10^Qx`, `Qx` **odd**                | `√40·10^{(Qx−1)/2}` | **inexact** | `4·10^odd = 40·10^even`, `√40` irrational |
| `2`, `3`, `40`, `1.5`                  | 34-digit root    | inexact| natural exponent `E` |
| `leastNonzeroMagnitude` (`1E−6176`)    | `1E−3088`        | exact  | `k=66, s=10^33`, strip 33 → `E=−3088` |
| `2E−6176` (subnormal)                  | `1.414…E−3088`   | inexact| `E=−3121`, 34 digits |
| `greatestFiniteMagnitude`              | `3.162…E+3072`   | inexact| `Qx=6111, d=34, k=33, E=3039` |
| `10^34−1` (34 nines), nearest          | `9…9E−17` (34 nines) | inexact | **`r == s` exactly**: root is `10^17 − 5·10^{−18}`, a hair *below* the midpoint; `r ≤ s` ⟹ round down |
| `10^34−1` (34 nines), `.up`            | `1000…0E−16` (=`10^17`) | inexact | `t = s+1 = 10^34` **rollover** → `10^33·10^{E+1}` (§3.7) |
| `10^34−2`, nearest                     | `9…9E−17` (34 nines) | inexact | **`r == 2s`** (maximal): `W = (10^34−1)² − 1`, just below a perfect square; `r > s` ⟹ round up to `s+1 = 10^34−1` |

Subnormal inputs are *not* special-cased: the decomposition uses `c` and `Qx`
uniformly (`c` simply has `d < 34` digits). `√` of a subnormal is never itself
subnormal (its exponent is ≈ half), which is why no tininess handling appears.

The `4·10^even` vs `4·10^odd` row is the key "quantum-parity" behavior: with a
significand of `4`, the input is a perfect square **iff `Qx` is even**; when `Qx`
is odd the radicand is `40·10^{even}` and `√40` is irrational, so the result is
inexact and carries the full-precision exponent `E`, not a stripped cohort.

---

## 6. Test vectors (generation + fixed values)

### 6.1 Oracle / generation script (`.toNearestOrEven` only)

**Caveat:** CPython's `sqrt` always rounds half-even regardless of
`ctx.rounding` (GDA rule; §2), so this script generates vectors for
`.toNearestOrEven`/`.toNearestOrAwayFromZero` only (identical by §3.4).
Directed-rule vectors come from the certificates in §6.4. Do **not** try to
generate directed vectors by re-rounding a higher-precision `sqrt`: it double
rounds. Demonstrated failure: the prec-60 root of `10^34 − 1` is
`99999999999999999.9999999999999999950000000000000000000000000` (ends `…95`,
correctly rounded *at 60 digits*), but the true root is
`…99499999…875` — just **below** the 34-digit midpoint; re-rounding the
60-digit value half-up gives `10^17`, while the correct 34-digit result is 34
nines. The `r`-vs-`s` integer test is immune to this by construction.

```python
# python3 — decimal128 semantics.  Run to (re)generate vectors + BID bit patterns.
from decimal import Decimal, Context, ROUND_HALF_EVEN

ctx = Context(prec=34, Emax=6144, Emin=-6143, clamp=1)   # == decimal128
BIAS = 6176

def bid128(dec: Decimal) -> int:
    """Canonical BID128 bit pattern for a finite decimal (sign<<127 | E<<113 | c)."""
    sign, digits, exp = dec.as_tuple()
    c = int("".join(map(str, digits)))
    E = exp + BIAS                     # biased quantum exponent
    assert 0 <= E <= 12287 and c < (1 << 113)
    return (sign << 127) | (E << 113) | c

def show(sq: str):
    x = Decimal(sq)
    try:
        r = x.sqrt(ctx)
    except Exception as ex:
        print(f"{sq:>40} -> INVALID ({type(ex).__name__})"); return
    bp = "" if not r.is_finite() else f"  bid=0x{bid128(r):032x}"
    print(f"{sq:>40} -> {str(r):<40} tuple={r.as_tuple()}{bp}")

for v in ["4","4.0","4.00","4.000","400","9","1","100","0","0.0","0.00","-0",
          "2","3","40","1.5","1E-6176","2E-6176",
          "9.999999999999999999999999999999999E+6144","-1","-Infinity","Infinity"]:
    show(v)
```

### 6.2 Selected fixed vectors (verified with the script above)

Exact / cohort (result value, quantum exponent `E`):

| input      | `√` (canonical) | `E` |
|------------|-----------------|-----|
| `4`        | `2`             | 0   |
| `4.0`      | `2.0`           | −1  |
| `4.00`     | `2.0`           | −1  |
| `4.000`    | `2.00`          | −2  |
| `400`      | `20`            | 0   |
| `1`        | `1`             | 0   |
| `100`      | `10`            | 0   |
| `0`        | `0`             | 0   |
| `0.00`     | `0.0`           | −1  |
| `-0`       | `-0`            | 0   |
| `1E-6176`  | `1E-3088`       | −3088 |

Inexact (all 34 significant digits; `.toNearestOrEven` unless noted):

| input                          | `√`                                          | `E` |
|--------------------------------|----------------------------------------------|-----|
| `2`                            | `1.414213562373095048801688724209698`        | −33 |
| `3`                            | `1.732050807568877293527446341505872`        | −33 |
| `40`                           | `6.324555320336758663997787088865437`        | −33 |
| `1.5`                          | `1.224744871391589049098642037352946`        | −33 |
| `2E-6176` (subnormal)          | `1.414213562373095048801688724209698E-3088`  | −3121 |
| `greatestFiniteMagnitude`      | `3.162277660168379331998893544432718E+3072`  | 3039 |
| `10^34−1` (34 nines)           | `99999999999999999.99999999999999999` (34 nines) | −17 |
| `10^34−2`                      | `99999999999999999.99999999999999999` (34 nines) | −17 |

Directed-rule vectors for the adversarial pair (from §6.4 certificates; both
inputs at `Qx = 0`):

| input      | rule            | result                     | notes |
|------------|-----------------|----------------------------|-------|
| `10^34−1`  | `.towardZero`/`.down` | 34 nines, `E=−17`    | `t = s` |
| `10^34−1`  | `.up`/`.awayFromZero` | `10^33`, `E=−16` (= `10^17`) | **rollover** |
| `10^34−2`  | `.towardZero`/`.down` | `10^34−2`, `E=−17`   | `t = s` |
| `10^34−2`  | `.up`/`.awayFromZero` | 34 nines, `E=−17`    | `t = s+1`, no rollover |

Invalid (return canonical qNaN, raise **invalid**): `-1`, `-4`, `-Infinity`,
`sqrt(sNaN)`. Non-invalid specials: `Infinity → Infinity`; `NaN → NaN`.

### 6.3 `_isqrt` unit vectors (test the helper + the `r`-vs-`s` boundary directly)

Pick any 34-digit `s0 ∈ [10^33, 10^34)` and feed the helper radicands that
straddle the round-to-nearest midpoint; these exercise §3.5 without needing a
real `Decimal128` cohort. §6.1's script can print `s0, W, s=floor√W, r=W−s²`:

* `W = s0²`         → `s = s0`,  `r = 0`   (exact; rounds to `s0` every rule).
* `W = s0² + s0`    → `s = s0`,  `r = s0`  (`r ≤ s`: nearest rounds **down** → `s0`).
* `W = s0² + s0 + 1`→ `s = s0`,  `r = s0+1`(`r > s`: nearest rounds **up** → `s0+1`).
* `W = s0² + 2·s0`  → `s = s0`,  `r = 2s0` (just below `(s0+1)²`; nearest → `s0+1`).
* `s0 = 10^34 − 1`, `W = s0² + s0 + 1` → tests the `s+1 = 10^34` rollover (§3.7).

Each `W` above lies in `[10^66, 10^68)` (since `s0 ∈ [10^33,10^34)` and
`W < (s0+1)² ≤ 10^68`), so it is a valid `_isqrt` input even though it may not be
reachable from a `c·10^k` decomposition — that is exactly why testing `_isqrt`
separately is worthwhile.

Also unit-test the arithmetic identity `s² ≤ W < (s+1)²` and `r == W − s²` for a
few thousand random 67- and 68-digit `W` against `math.isqrt(W)`.

### 6.4 Certificate-based verification (all six rules; already executed)

The right way to test directed rounding — and the way this design was
verified — is with **exact integer-inequality certificates** that require no
square-root oracle at all. For a claimed result `t · 10^e` of `√(c · 10^Qx)`,
let `j = Qx − 2e` (always `≥ 0` here) and `W′ = c · 10^j` (the radicand in
units of `10^{2e}`):

* exact claim: `t² == W′`, plus cohort maximality
  (`e == ⌊Qx/2⌋` **or** `t % 10 != 0`), and `1 ≤ t < 10^34`;
* `.towardZero`/`.down` claim: `t² ≤ W′ < (t+1)²`;
* `.up`/`.awayFromZero` claim: `(t−1)² < W′ < t²`;
* nearest claim: `(2t−1)² < 4W′ < (2t+1)²` (multiplying by 4 keeps everything
  in integers; strictness is safe because ties are impossible, §3.4);
* inexact claims additionally require `10^33 ≤ t < 10^34`.

A Python transcription of §4 (using the exact Newton iteration and seed of
§3.3, with `float`'s IEEE-binary64 `sqrt` standing in for `Double`) was run
against these certificates plus two independent cross-checks:

* Newton `_isqrt` result `==` `math.isqrt(W)` on every case;
* `.toNearestOrEven` result (value **and** cohort exponent **and** inexact
  flag) `==` CPython native decimal128 `sqrt` on every case.

Corpus: all §6.2 vectors; every `c ∈ [10^34−60, 10^34)` at
`Qx ∈ {−6176, −3, −2, −1, 0, 1, 2, 6111}` (saturating the `r=s`, `r=2s`, and
rollover territory); 3,000 uniform random `(c, Qx)`; 1,500 random short
significands (cohort-rich); 1,500 random perfect squares at random exponents.
**Result: 39,048 certificates, 0 failures.** The Newton seed never
under-estimated, and the iteration count never exceeded **5** (bound in §3.3:
6). The Swift test suite should port this harness (`swift-testing` +
`math.isqrt`-precomputed fixtures, or run the Python as a generator).

---

## 7. Open questions / risks

1. **`Double` seed portability.** The seed relies on `Double.squareRoot()` being
   correctly rounded (IEEE binary64) and on `Double(top)` being exact for
   `top < 2^53`. Both hold on all supported platforms, but the correctness of
   `_isqrt` does **not** depend on it (only performance does): the monotone
   descent is proven for *any* over-estimate seed, and the `assert` catches a
   bad seed in debug builds. If paranoia warrants, ship the power-of-two
   fallback seed from §3.3.

2. **Flag semantics are stubbed.** `_signal` is currently a no-op returning its
   `default`. When real IEEE flag state lands, confirm: `.invalid` for negative
   / `−∞` / sNaN; `.inexact` iff `r != 0`; and — importantly — **no `.underflow`
   or `.overflow` ever** for `squareRoot` (§1.1, §3.2). Also confirm sNaN vs
   qNaN payload canonicalization matches `_quiet._canonical`.

3. **Preferred exponent of `−0` / zero.** We apply `⌊Qx/2⌋` to zero results,
   matching CPython (`0.00 → 0.0`, `−0.00 → −0.0`). Confirm this is the intended
   house style (the existing `quantized`/`_addingZeroWithLeastQuantum` code also
   preserves quantum information, so this is consistent).

4. **Rollover reachability — resolved.** `s = 10^34 − 1` with `r > 0` is
   reachable (witness `x = 10^34 − 1`, §3.7; machine-verified in §6.4). No other
   35-digit escape exists: `t ≤ s + 1 ≤ 10^34`, and only `t == 10^34` needs
   renormalizing. Keep the directed vectors of §6.2 in the test suite to pin the
   branch.

5. **Iteration-count bound.** The `≤ 6` bound assumes the `< 2^-24` seed error;
   the §6.4 run observed a maximum of 5 iterations over 39k cases. If the seed
   construction is simplified to the crude power-of-two, raise the documented
   bound to `~8` and re-time. Square root is not on the `+`/`×` hot path, so
   this is a minor concern; still, add a `debug` iteration counter assert
   (`assert(iterations <= 8)`) to catch a regressed seed.

6. **`quantized`/`rounded` interplay.** Not affected by `squareRoot`, but note
   the file still has `fatalError` stubs for `divided(by:)`, `rounded(_:)`, etc.;
   the promised "exact-division-by-`10^k` modular-inverse cascade" that would
   optimize §3.6's zero-stripping is shared infrastructure — until it exists, the
   `%10` loop is the portable, obviously-correct stand-in.
