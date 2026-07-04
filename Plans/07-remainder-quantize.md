# 07 — Remainder, truncating remainder, and quantize

Target: `Sources/DecimalAnnex/Decimal128.swift` (IEEE 754-2019 decimal128, BID
encoding, `bitPattern: UInt128`, precision p = 34, biased exponent 0…12287,
bias 6176, quantum exponent Q ∈ [−6176, 6111]).

Status legend: ✅ verified numerically against the Python `decimal` oracle
(prec=34) · 🔬 proven below · ⚠️ open question / risk.

---

## 0. Summary of decisions

| Operation | Rounding param? | Signals | Result exponent (biased) | Core engine |
|---|---|---|---|---|
| `remainder(dividingBy:)` | **No** (always exact, ties-to-even integer *n*) | only `invalid` (∞÷·, ·÷0), *never* inexact/overflow/underflow | `min(e1, e2)` | shared `_remainder(_:nearest: true)` |
| `truncatingRemainder(dividingBy:)` | **No** (always exact, *n* = trunc) | only `invalid` | `min(e1, e2)` | shared `_remainder(_:nearest: false)` |
| `quantized(by:rounding:)` | **Yes** (`= .toNearestOrEven`) | `invalid` (can't fit 34 digits, or exactly-one-∞), `inexact` (value changed) — *never* overflow/underflow | `e2` (other's exponent) | direct scale up / G-M divide down |

Key structural choice: **the two remainders never touch `_round`.** Their
results are proven representable at the preferred exponent `min(e1, e2)`
(§3.1), so we build the result directly with
`Self(sign:exponentBitPattern:significandBitPattern:)`. This matches the IEEE
mandate that remainder is *always exact* — there is no rounding sink to invoke
and no `inexact`/`overflow`/`underflow` to signal. `quantize` does its own
fixed-target-exponent rounding (also not via `_round`, which chooses its own
exponent).

---

## 1. IEEE 754-2019 requirements & Swift API mapping

### 1.1 `remainder` — IEEE §5.3.1 `remainder(x, y)`

Definition: `r = x − y·n`, where `n` is the integer **nearest** the exact real
quotient `x/y`; when `x/y` is exactly halfway between two integers, `n` is the
**even** one. This is fully specified and independent of the ambient rounding
attribute, hence **always exact** and takes **no rounding parameter**.

- `|r| ≤ |y|/2`.
- Sign of a zero result equals the sign of `x`.
- Preferred exponent: `min(Q(x), Q(y))`.
- `x` infinite, or (`y` zero and `x` finite): signal `invalid`, return NaN.
- `y` infinite, `x` finite: `r = x` (no exception).
- Never signals `inexact`, `underflow`, or `overflow`.

Swift mapping: `FloatingPoint.remainder(dividingBy:)` / `formRemainder`. The
Swift protocol requirement has **no** rounding parameter — consistent with IEEE
exactness. `formRemainder` wrapper already exists and calls `remainder`.

> **⚠️ GDA divergence (✅ verified with Python 3.11 `decimal`).** The General
> Decimal Arithmetic spec — and therefore decNumber and Python's `decimal`
> module — signals *invalid operation* on `remainder`/`remainder-near` whenever
> the integer quotient would need more than p digits: e.g.
> `Context(prec=34).remainder_near(Decimal('1E100'), 7)` returns `NaN` and
> raises `InvalidOperation`, whereas IEEE 754-2019 defines the result (= `−3`,
> exactly, computed by §3.2's reduction). **IEEE has no such restriction**, and
> Swift's `FloatingPoint.remainder` semantics (like `Float`/`Double`, and like
> Intel's `bid128_rem`) is the IEEE one. This design follows IEEE.
> Consequence for testing: Python `decimal` is only a valid oracle when the
> quotient fits in 34 digits; beyond that the oracle must be exact integer
> arithmetic (§6's script implements both).

### 1.2 `truncatingRemainder` — C `fmod` semantics

Identical to §1.1 except `n = trunc(x/y)` (round toward zero). Consequences:

- `0 ≤ |r| < |y|`.
- Result sign = **sign of x** always (never flips).
- Same specials (∞÷·, ·÷0 → invalid NaN; finite ÷ ∞ → x).
- Same preferred exponent `min(Q(x), Q(y))`; always exact.

Swift mapping: `FloatingPoint.truncatingRemainder(dividingBy:)` /
`formTruncatingRemainder` (wrapper exists).

### 1.3 `quantize` — IEEE §5.3.2 `quantize(x, y)`

Result has the **exponent of `y`** and the numerical value of `x` rounded to
that quantum under `rule` (an operation where IEEE *does* allow a rounding
attribute, so `rounding rule = .toNearestOrEven` default is correct).

- If the correctly-rounded significand would exceed `10^34 − 1` (more than p
  digits) → signal **`invalid`**, return NaN. (NB: *invalid*, **not**
  *overflow*.)
- Signal `inexact` **iff** the value changed (i.e. digits were discarded with a
  nonzero remainder). Never `overflow`/`underflow`.
- `x` ∞ and `y` ∞ → `x` (sign preserved). Exactly one of `x`,`y` infinite →
  `invalid` NaN. NaN propagation as usual (sNaN → invalid + quiet; qNaN → quiet).
- Zero `x`: result is zero with `y`'s exponent and `x`'s sign (already handled
  by the existing stub). A *nonzero* `x` that rounds down to zero still yields
  a zero significand at `y`'s exponent, and signals `inexact`.

Swift mapping: there is no `FloatingPoint` protocol requirement; this is the
type's own `quantized(by:rounding:)`. The existing stub handles
sNaN/qNaN/∞/zero-`x`; §4.3 completes the finite path.

---

## 2. Reference-algorithm survey

(Network access from the sandbox is restricted; citations below are from first
principles and from the author's knowledge of the public implementations. Where
a specific claim could not be re-verified against a live source it is marked and
re-derived from scratch in §3. **No fabricated line-level citations.**)

The naïve method — compute `q = x/y`, then `r = x − y·round(q)` — **fails**:
`n = round(x/y)` can have up to ~12,300 decimal digits (e.g. `x = 9…9·10^6111`,
`y = 1·10^-6176`), which is not representable and cannot be materialised.

The standard family of correct algorithms (as used by Intel's
IntelRDFPMathLib `bid128_rem`/`bid128_fmod`, IBM/decNumber
`decNumberRemainder`/`decNumberRemainderNear`, and libmpdec
`mpd_rem`/`mpd_rem_near`) all reduce **incrementally** without ever forming `n`:

- Align on the finer quantum `g = 10^min(Q1,Q2)`. Both operands become integer
  multiples of `g`.
- The dividend's over-scaled significand `C = c1·10^Δ` (Δ = exponent gap) is
  reduced **mod c2** by chunked long division — folding ≤ K decimal digits per
  step through a wide (here 256-bit) intermediate — producing the *truncated*
  remainder directly.
- For the nearest variant, the **parity** of the (never-materialised) quotient
  `n` is tracked so the halfway tie can be broken to even; the final fix-up
  compares `2·r` against `y` and, if needed, replaces `r` by `r − y`
  (equivalently `n → n + 1`).

decNumber and mpdecimal additionally observe that the exact remainder always
fits in p digits at the preferred exponent — the crux we prove in §3.1.

This design follows that shared structure, specialised to decimal128 and to the
repo's existing 128/256-bit primitives.

---

## 3. Chosen algorithms with correctness arguments

Throughout, write the finite nonzero operands as
`x = (−1)^{s1}·c1·10^{Q1}`, `y = (−1)^{s2}·c2·10^{Q2}` with integer significands
`1 ≤ c1, c2 ≤ 10^34 − 1` and unbiased quantum exponents `Q1, Q2`. Biased
exponents are `e1 = Q1 + 6176 = exponentBitPattern`, `e2 = Q2 + 6176`. Because
the bias cancels in every difference, we use `e` and `Q` interchangeably in
gaps. Let `a = c1·10^{Q1} = |x|`, `b = c2·10^{Q2} = |y|`.

Sign reduction (both variants): `remainder(x, y) = sign(x) · remainder(a, b)`,
because `remainder(−x, y) = −remainder(x, y)` and `y`'s sign is irrelevant
(`n = round(x/y)` and `round` is odd). So we compute on magnitudes and reattach
`x`'s sign, with one wrinkle for nearest (the tie/flip can make
`remainder(a,b) < 0`, which flips the reported sign — see §3.3).

### 3.1 🔬 Representability lemma (THE crux)

> **Lemma.** For finite nonzero `x, y` the exact remainder `r` (truncating *or*
> nearest) is an integer multiple of `g = 10^{min(Q1,Q2)}` whose multiplier has
> magnitude `≤ 10^34 − 1`. Hence `r` is exactly representable as a `Decimal128`
> at the preferred exponent `min(Q1, Q2)`.

**Proof.**

*(i) r lies on the grid g.* Let `Qm = min(Q1,Q2)`. Both operands are integer
multiples of `10^{Qm}`: `x = c1·10^{Q1−Qm}·10^{Qm}` and `Q1 − Qm ≥ 0`, likewise
`y`. Since `r = x − n·y` with `n ∈ ℤ`, `r` is an integer multiple of `10^{Qm}`.
Write `r = m·10^{Qm}`, `m ∈ ℤ`.

*(ii) Magnitude bound `|r| ≤ |x|`* (holds for **both** variants). If `n = 0`
then `r = x`, so `|r| = |x|`. If `n ≠ 0`:
 - truncating: `n = trunc(a/b) ≠ 0 ⇒ a ≥ b ⇒ |r| < b ≤ a = |x|`;
 - nearest: `n ≠ 0 ⇒ |a/b| > 1/2` (a value with `|a/b| ≤ 1/2` rounds to the
   even integer 0), so `a > b/2 ≥ |r|` because `|r| ≤ b/2`.

 In every case `|r| ≤ |x| = a`.

*(iii) The other bound `|r| < |y|`* also holds for both variants
(`< b` truncating, `≤ b/2 < b` nearest).

*(iv) Multiplier fits.* Two cases on which operand owns the finer grid:
 - **Q1 ≤ Q2** (`Qm = Q1`): `m = r/10^{Q1}`, and by (ii)
   `|m| = |r|/10^{Q1} ≤ |x|/10^{Q1} = c1 ≤ 10^34 − 1`.
 - **Q2 < Q1** (`Qm = Q2`): `m = r/10^{Q2}`, and by (iii)
   `|m| = |r|/10^{Q2} < |y|/10^{Q2} = c2 ≤ 10^34 − 1`.

In both cases `|m| ≤ 10^34 − 1`, i.e. `m` is a valid p=34 significand at
exponent `Qm`. ∎

**Why the naïve `|r| < |y|` bound looked broken.** When `Q1 < Q2`, `|r| < |y|`
gives `|m| < c2·10^{Q2−Q1}`, which can be `~10^68`. The resolution is bound
**(ii)**: the remainder never exceeds the *dividend*, and it is the dividend `x`
that lives on the fine grid `10^{Q1}`, so `|r|/10^{Q1} ≤ c1 ≤ 10^34 − 1`. The
correct bound to use is whichever operand owns the finer grid: `|r| ≤ |x|` when
`x` is finer, `|r| < |y|` when `y` is finer. (Verified numerically in §6 across
random and adversarial `Q1 ≪ Q2` / `Q1 ≫ Q2` cases.)

Corollary used by the code: in the nearest "flip" branch the flipped magnitude
`bMul − rt` is the multiplier of the actual result, so by the lemma it is
`≤ 10^34 − 1 < 2^113` — and a flip can only occur when `2·rt ≥ bMul`, which
forces `bMul < 2^114`, i.e. `bMul` fits in 128 bits. The subtraction is
therefore a plain `UInt128` operation, never 256-bit. ✅ asserted across all §6
runs.

### 3.2 🔬 Chunked modular reduction (`C = c1·10^Δ mod c2`) and parity

Used when `Δ = Q1 − Q2 > 0` (dividend over-scaled; §3.4 Case B). We must obtain
`R_t = C mod c2 ∈ [0, c2)` and `p = n_t mod 2` where `n_t = ⌊C/c2⌋`, **without**
forming `C` or `n_t` (either can be thousands of digits: `Δ ≤ 12287`).

Pre-reduce once, then fold Δ in chunks of at most `K = 38` decimal digits
(Horner over base `10^s`), using only `UInt128.multipliedFullWidth` and
`UInt128.dividingFullWidth` — no `_UInt256` division needed:

```
(_, acc) ← c1 divmod c2        # pre-reduce: acc = c1 mod c2 < c2
d ← Δ                          # ≥ 1
q ← 0
while d > 0:
  s    ← min(d, 38)
  prod ← acc ×fullWidth 10^s   # (high, low), 128×128 → 256 bits
  (q, acc) ← c2.dividingFullWidth(prod)   # q, acc: UInt128; acc < c2
  d ← d − s
R_t ← acc ;  p ← q & 1         # q from the LAST iteration only
```

**Loop invariant (entering each iteration): `acc < c2`.** True after the
pre-reduction, and preserved because `dividingFullWidth` returns a remainder
`< c2`.

**No overflow / `dividingFullWidth` precondition.** 🔬
`Swift`'s `dividingFullWidth` requires the quotient to fit in 128 bits, i.e.
`prod.high < c2`. From the invariant, `prod = acc·10^s ≤ (c2 − 1)·10^38`, so

```
prod.high = ⌊prod / 2^128⌋ ≤ (c2 − 1)·10^38 / 2^128 < c2 · (10^38 / 2^128) < 0.3·c2 < c2
```

because `10^38 < 2^128` (`10^38 ≈ 2^126.2`). This is exactly why the chunk
size is 38: it is the largest `s` with `10^s < 2^128`, making the precondition
automatic. (With `s = 39` the bound fails.) The 256-bit product itself is
`< 2^113·2^127 = 2^240`, comfortably inside `multipliedFullWidth`'s range.
Iteration count: `⌈Δ/38⌉ ≤ ⌈12287/38⌉ = 324` — bounded, small, branch-free per
step. ✅ the precondition was asserted on every step across all §6 test runs.

**Correctness of `R_t`.** Modular Horner: the digits appended to `c1` are all
zero (the `10^Δ` tail), so `C mod c2 = ((…((c1 mod c2)·10^{s_1} mod c2)·10^{s_2}
mod c2)…)·10^{s_j} mod c2` with `Σ s_i = Δ`. Each loop step performs one such
multiply-reduce; the final `acc = C mod c2 = R_t`.

**Correctness of parity `p`.** 🔬 Long division in decimal chunks emits
`n_t = ⌊C/c2⌋ = q_0·10^{L_0} + Σ_i q_i·10^{L_i}`, where `q_0 = ⌊c1/c2⌋` is the
pre-reduction quotient, `q_i` is iteration `i`'s chunk quotient, and `L_i` is
the count of decimal places still unprocessed when that quotient is emitted
(`L_0 = Δ`; each loop step's `L_i` = the remaining `d` after it runs). This is
the division algorithm applied left-to-right: every step maintains
`C = (accumulated quotient)·10^{L}·c2 + acc·10^{L}` with `acc < c2`, hence at
`L = 0` the accumulated quotient is exactly `⌊C/c2⌋`.

Now reduce mod 2: every term except the last has `L_i ≥ 1`, and `10^{L_i}` is
**even**, contributing 0. The last iteration has `L = 0` (weight 1). Therefore

```
n_t mod 2 = q_last mod 2 = q_last & 1
```

Only the final chunk's quotient parity matters; earlier chunk quotients and the
pre-reduction quotient `⌊c1/c2⌋` (weight `10^Δ`, even since `Δ ≥ 1`) are
irrelevant — which is why the listing discards them. This is the decimal
analogue of "`n mod 2 = (n mod 10) mod 2` because 10 is even"; note it would be
**false** in an odd base. ✅ verified in §6 including engineered tie cases where
parity decides the result.

### 3.3 🔬 Nearest tie/flip fix-up

Given the truncated remainder `R_t ∈ [0, b)` (as a multiplier `rt` of `10^{Qm}`)
and parity `p = n_t & 1`:

- Compare `2·R_t` with `b`.
  - `2·R_t > b` → round up: `n = n_t + 1`, `remainder(a,b) = R_t − b < 0`.
  - `2·R_t < b` → keep: `remainder(a,b) = R_t ≥ 0`.
  - `2·R_t = b` (tie) → to even: flip iff `p == 1` (n_t odd → n_t+1 even).
- "Flip" ⇒ reported magnitude `= b − R_t` and reported sign `= ¬sign(x)`;
  otherwise magnitude `= R_t`, sign `= sign(x)`.

Ties (`2R_t = b`) require `c2` even and `R_t = b/2` exact — rare but real; the
parity machinery exists solely for these. Truncating never flips.

Zero-remainder sign: if `R_t = 0` (no flip possible, since `2·0 < b`), the
result is `±0` with the **sign of x** — both variants. Handle before the flip.

### 3.4 Case split for computing `rt`, `bMul`, and `p`

Let `Δ = Q1 − Q2 = e1 − e2` (biased exponents subtract identically).
`Qm = min(Q1,Q2)`, biased `eMin = min(e1,e2)`. Both the truncated remainder
`rt` and the divisor magnitude `bMul` (= `b/10^{Qm}`) are expressed as
multipliers of `10^{Qm}`; `bMul` is carried as a 256-bit pair
`(bHigh, bLow)` because case C can exceed 128 bits.

- **Case A, Δ = 0** (equal quanta; `Qm = Q1 = Q2`):
  `(n_t, rt) = c1.quotientAndRemainder(dividingBy: c2)` in plain 128-bit.
  `bMul = (0, c2)`, `p = n_t & 1`.

- **Case B, Δ > 0** (dividend coarser; `Qm = Q2`): `rt = c1·10^Δ mod c2` and
  `p` from the chunked reduction §3.2. `bMul = (0, c2)`. (`rt < c2 < 2^113`.)

- **Case C, Δ < 0** (divisor coarser; `k = −Δ ≥ 1`, `Qm = Q1`): the divisor on
  grid `10^{Q1}` is `bMul = c2·10^k`.
  - `k ≥ 35`: `bMul ≥ 10^35 > 2·(10^34 − 1) ≥ 2·c1`, so `n_t = 0`, `rt = c1`,
    and even the nearest variant can never flip (`2·rt < bMul`). **Early
    return `x` unchanged** — value, quantum (`Q1 = Qm` ✓), and sign are already
    right. This also caps `_exp10`'s argument at 34 in the next bullet.
  - `1 ≤ k ≤ 34`: `bMul = c2.multipliedFullWidth(by: 10^k)` (`≤ (10^34−1)·10^34
    < 2^226`, exact as a 256-bit pair). If `bHigh != 0 || c1 < bLow` then
    `(n_t, rt) = (0, c1)`; otherwise `bMul` fits in `bLow` and
    `(n_t, rt) = c1.quotientAndRemainder(dividingBy: bLow)` in 128-bit.
    `p = n_t & 1`.

Nearest fix-up on top (all cases): `twice = rt &<< 1` (fits: `rt < 2^113`);
`flip = bHigh == 0 && (twice > bLow || (twice == bLow && p))`; on flip the
magnitude is `bLow &- rt` and the sign toggles. The `bHigh == 0` conjunct is
correct because `twice < 2^114 ≤ bMul` whenever `bHigh != 0`.

In every branch, `rt ≤ 10^34 − 1` and (on flip) `bLow − rt ≤ 10^34 − 1` by
§3.1, so `Self(sign:exponentBitPattern:significandBitPattern:)` at `eMin`
encodes the exact result with no rounding and no signals.

### 3.5 quantize finite path (§4.3)

`Δ = Q2 − Q1 = e2 − e1` (target minus source).

- **Δ ≤ 0** (widen to a finer/equal quantum): value is exact; multiply
  `c = c1·10^{−Δ}`. Overflow test *first* (avoid UInt128 overflow): let
  `D = c1._commonLogarithm + 1` (number of digits). If `D + (−Δ) > 34` →
  `invalid`, NaN. Else `c = c1 · 10^{−Δ}` (fits, `< 2^113`), exact (no
  `inexact`). Result `(sign x, e2, c)`.

- **Δ > 0** (round to a coarser quantum): divide `c1` by `10^Δ` with remainder.
  - `Δ ≥ 35`: `10^Δ ≥ 10^35 > 2·c1` ⇒ `quo = 0`, `rem = c1 ≠ 0`, and `rem` is
    **strictly below half** of the (unrepresentable-in-table) `10^Δ`. So the
    to-nearest rules keep 0; only the directed-away rules (`up` on positive,
    `down` on negative, `awayFromZero`) produce 1. Handle with `pow`-free
    predicates (see listing) — avoids calling `_exp10(Δ)` for `Δ > 38`.
  - `1 ≤ Δ ≤ 34`: `pow = 10^Δ`,
    `(quo, rem) = c1.quotientAndRemainder(dividingBy: pow)` — or the planned
    Granlund–Montgomery helper `c1._quotientAndRemainder(dividingBy1e: Δ)` once
    it lands (drop-in, same contract). Round `quo` using `(rem, pow, rule,
    sign)` with the exact same predicate ladder as `_round`'s inexact branch
    (tie at `rem == pow &>> 1`; `pow` is even for `Δ ≥ 1`, so the half is
    exact). `inexact` iff `rem ≠ 0`. Result `(sign x, e2, quo')`.

  🔬 **Round-up cannot overflow the significand here**: `Δ ≥ 1` implies
  `quo = ⌊c1/10^Δ⌋ ≤ ⌊(10^34 − 1)/10⌋ = 10^33 − 1`, so `quo + 1 ≤ 10^33 <
  10^34`. Therefore the `invalid` (34-digit-overflow) check is needed **only in
  the Δ ≤ 0 branch** — quantize toward a *coarser* quantum never fails. (✅
  confirmed against the Python oracle: no `InvalidOperation` in 6000+ random
  Δ > 0 cases; matched on directed roundings too.)

quantize never routes through `_round` (which would pick its own exponent and
detect tininess); it writes the fixed target exponent `e2` directly, which is
also why it can never signal overflow/underflow.

---

## 4. Swift listings (repo-idiomatic, in-principle compilable)

Conventions used (matching the file): two-space indent; masking operators;
special-value guard ladder in the exact order of `adding(_:rounding:)` /
`multiplied(by:rounding:)`; results assembled by `bitPattern` composition
(`UInt128(truncatingIfNeeded: e) &<< 113 | c`) exactly as `_round` does, then
negated for minus sign. The three public stubs already exist (lines ~1459–1496
and ~457–493 in `Decimal128.swift`); the listings below replace their bodies.
`formRemainder` / `formTruncatingRemainder` wrappers already exist unchanged.

### 4.1 Shared engine `_remainder(dividingBy:nearest:)`

```swift
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension Decimal128 {
  /// Returns the exact remainder of this value divided by the given value,
  /// with the quotient rounded either to the nearest integer (ties to even)
  /// or toward zero.
  ///
  /// The result is always exact; no floating-point exception other than
  /// invalid operation is ever signaled. See design notes: the result is
  /// always representable at the preferred exponent `min(e1, e2)`.
  @inlinable
  internal func _remainder(
    dividingBy other: Decimal128, nearest: Bool
  ) -> Decimal128 {
    let lhs = self, rhs = other

    guard lhs._isFiniteNonzero && rhs._isFiniteNonzero else {
      if lhs.isSignalingNaN {
        return _signal(.invalid, default: lhs._quiet._canonical)
      }
      if rhs.isSignalingNaN {
        return _signal(.invalid, default: rhs._quiet._canonical)
      }

      if lhs.isNaN {
        return lhs._canonical
      }
      if rhs.isNaN {
        return rhs._canonical
      }

      if lhs.isInfinite {
        return _signal(.invalid, default: .nan)
      }
      if rhs.isInfinite {
        // The remainder of a finite value divided by infinity is the value
        // itself, unchanged.
        return lhs._canonical
      }

      if rhs.isZero {
        return _signal(.invalid, default: .nan)
      }
      // `lhs` is zero (or noncanonical and treated as zero); the result is a
      // zero with the sign of `lhs` at the preferred exponent min(e1, e2).
      let e = min(lhs.exponentBitPattern, rhs.exponentBitPattern)
      let abs = Self(bitPattern: UInt128(truncatingIfNeeded: e) &<< 113)
      return lhs._isSignMinus ? -abs : abs
    }

    let isSignMinus = lhs._isSignMinus
    let e1 = lhs.exponentBitPattern, e2 = rhs.exponentBitPattern
    let c1 = lhs.significandBitPattern, c2 = rhs.significandBitPattern

    // Compute the truncated remainder `rt` and the divisor magnitude
    // `(bHigh, bLow)`, both as multipliers of the preferred quantum
    // 10^(min(e1, e2) - 6176), along with the parity of the truncated
    // quotient (needed only to break ties when `nearest` is true).
    let rt: UInt128
    let isOddQuotient: Bool
    let bHigh: UInt128, bLow: UInt128
    if e1 == e2 {
      let (q, r) = c1.quotientAndRemainder(dividingBy: c2)
      (rt, isOddQuotient) = (r, (q & 1) == 1)
      (bHigh, bLow) = (0, c2)
    } else if e1 > e2 {
      // Chunked modular reduction of c1 * 10^(e1 - e2) mod c2, folding at
      // most 38 digits per step. The loop invariant `acc < c2` guarantees
      // that the full-width quotient fits in 128 bits, because
      // acc * 10^38 / 2^128 < acc < c2.
      var delta = Int(e1 &- e2)
      var q = 0 as UInt128
      var acc = c1 % c2
      repeat {
        let s = min(delta, 38)
        let prod = acc.multipliedFullWidth(by: UInt128._exp10(s))
        (q, acc) = c2.dividingFullWidth(prod)
        delta &-= s
      } while delta > 0
      // Only the parity of the last chunk quotient matters: every earlier
      // chunk (and the discarded `c1 / c2`) carries a factor of 10^k with
      // k >= 1, which is even.
      (rt, isOddQuotient) = (acc, (q & 1) == 1)
      (bHigh, bLow) = (0, c2)
    } else {
      let k = Int(e2 &- e1)
      guard k <= 34 else {
        // 2 * |lhs| < 10^35 <= |rhs| at this exponent gap, so the quotient
        // rounds to zero under both variants and the result is exactly
        // `lhs`, whose exponent is already min(e1, e2).
        return lhs
      }
      (bHigh, bLow) = c2.multipliedFullWidth(by: UInt128._exp10(k))
      if bHigh != 0 || c1 < bLow {
        (rt, isOddQuotient) = (c1, false)
      } else {
        // `bLow` holds the entire divisor magnitude here.
        let (q, r) = c1.quotientAndRemainder(dividingBy: bLow)
        (rt, isOddQuotient) = (r, (q & 1) == 1)
      }
    }

    let e = min(e1, e2)
    if nearest {
      // If twice the truncated remainder exceeds the divisor magnitude --
      // or equals it and the truncated quotient is odd -- then the nearest
      // (or even) quotient is one greater, and the remainder reverses sign.
      let twice = rt &<< 1  // No overflow: rt < 2^113.
      if bHigh == 0 && (twice > bLow || (twice == bLow && isOddQuotient)) {
        let abs = Self(
          bitPattern: UInt128(truncatingIfNeeded: e) &<< 113 | (bLow &- rt))
        return isSignMinus ? abs : -abs
      }
    }
    // Exact result (including a zero remainder, which takes the sign of
    // `lhs`); never signals inexact, underflow, or overflow.
    let abs = Self(bitPattern: UInt128(truncatingIfNeeded: e) &<< 113 | rt)
    return isSignMinus ? -abs : abs
  }
}
```

Implementation notes for the reviewer:

- `c2.dividingFullWidth(prod)` is the Swift standard library 256÷128 → 128
  primitive on `UInt128`; its precondition (quotient fits in 128 bits ⟺
  `prod.high < c2`) is discharged by the invariant proof in §3.2. The initial
  `acc = c1 % c2` (one 128-bit division) establishes it.
- The `repeat`–`while` is entered only when `delta ≥ 1`, which is guaranteed by
  the `e1 > e2` branch condition, so `q` is always the *last chunk* quotient.
- In the `nearest` flip, `bLow &- rt` cannot underflow: the flip condition
  implies `bHigh == 0 && rt < bLow` (since `2·rt ≥ bLow` and `rt < bLow` from
  `rt` being a remainder mod `bLow`, or `rt = c1 < bLow` in the small-dividend
  branch). The difference is ≤ 10^34 − 1 by the §3.1 lemma.
- The flip's sign line reads inverted on purpose: `isSignMinus ? abs : -abs`
  (the mathematical remainder is negative relative to `lhs`'s sign).
- Zero results fall through the last two lines with `rt == 0`, producing
  `±0 × 10^(min quantum)` with `lhs`'s sign — IEEE 754 §5.3.1's requirement.

### 4.2 Public wrappers

```swift
  /// Returns the remainder of this value divided by the given value.
  ///
  /// For two finite values `x` and `y`, the remainder `r` of dividing `x` by
  /// `y` satisfies `x == y * n + r`, where `n` is the integer nearest the
  /// exact quotient `x / y`; if `x / y` is exactly halfway between two
  /// integers, `n` is chosen to be even. The result is always exact, and
  /// `abs(r) <= abs(y) / 2`. A zero result has the sign of this value.
  ///
  /// This method implements the `remainder` operation defined by the IEEE 754
  /// specification. Because the remainder is always exact, this operation has
  /// no rounding rule parameter and never signals the inexact, underflow, or
  /// overflow exceptions.
  @inlinable
  public func remainder(dividingBy other: Decimal128) -> Decimal128 {
    _remainder(dividingBy: other, nearest: true)
  }

  /// Returns the remainder of this value divided by the given value using
  /// truncating division.
  ///
  /// For two finite values `x` and `y`, the remainder `r` of dividing `x` by
  /// `y` satisfies `x == y * n + r`, where `n` is `x / y` rounded toward
  /// zero. The result is always exact, has the same sign as this value, and
  /// `abs(r) < abs(y)`.
  @inlinable
  public func truncatingRemainder(
    dividingBy other: Decimal128
  ) -> Decimal128 {
    _remainder(dividingBy: other, nearest: false)
  }
```

(The mutating `formRemainder(dividingBy:)` / `formTruncatingRemainder(dividingBy:)`
forwarders already exist and need no change.)

### 4.3 `quantized(by:rounding:)` — completed

Only the two `fatalError("Not implemented")` sites change; the existing
special-value ladder is kept verbatim. The inner `fatalError` is unreachable
(once NaN, infinity have returned, a non-`_isFiniteNonzero` value must satisfy
`isZero`, which also covers noncanonical encodings), so the zero return becomes
unconditional:

```swift
  /// Returns this value rounded, using the given rounding rule, so that its
  /// quantum matches that of the given value.
  ///
  /// This method implements the `quantize` operation defined by the IEEE 754
  /// specification. If the rounded significand would require more than 34
  /// digits, the invalid operation exception is signaled and the result is
  /// NaN; this operation never signals overflow or underflow. The inexact
  /// exception is signaled if and only if the result differs in value from
  /// this value.
  public func quantized(
    by other: Decimal128,
    rounding rule: FloatingPointRoundingRule = .toNearestOrEven
  ) -> Decimal128 {
    guard _isFiniteNonzero else {
      if isSignalingNaN {
        return _signal(.invalid, default: _quiet._canonical)
      }
      if other.isSignalingNaN {
        return _signal(.invalid, default: other._quiet._canonical)
      }

      if isNaN {
        return _canonical
      }
      if other.isNaN {
        return other._canonical
      }

      if isInfinite {
        if other.isInfinite { return _isSignMinus ? -.infinity : .infinity }
        return _signal(.invalid, default: .nan)
      }
      if other.isInfinite {
        return _signal(.invalid, default: .nan)
      }

      // `self` is zero (or noncanonical and treated as zero); the result is
      // a zero with this value's sign and the other value's exponent.
      return Self(
        sign: sign,
        exponentBitPattern: other.exponentBitPattern,
        significandBitPattern: 0)
    }

    // `self` is finite and nonzero; `other` may still be non-finite.
    if other.isSignalingNaN {
      return _signal(.invalid, default: other._quiet._canonical)
    }
    if other.isNaN {
      return other._canonical
    }
    if other.isInfinite {
      return _signal(.invalid, default: .nan)
    }

    let isSignMinus = _isSignMinus
    let e1 = exponentBitPattern, e2 = other.exponentBitPattern
    let c1 = significandBitPattern

    guard e1 < e2 else {
      // Scaling to an equal or finer quantum is exact when the widened
      // significand fits in 34 digits, and invalid otherwise.
      let n = Int(e1 &- e2)
      guard c1._commonLogarithm &+ n < 34 else {
        return _signal(.invalid, default: .nan)
      }
      let abs = Self(
        bitPattern: UInt128(truncatingIfNeeded: e2) &<< 113
          | c1 &* UInt128._exp10(n))
      return isSignMinus ? -abs : abs
    }

    // Rounding to a coarser quantum: remove `n` decimal digits.
    let n = Int(e2 &- e1)
    guard n <= 34 else {
      // 2 * c1 < 10^35 <= 10^n: every digit is discarded and the true value
      // is strictly less than half of the target quantum in magnitude.
      let nextAway: Bool = switch rule {
      case .awayFromZero:
        true
      case .down:
        isSignMinus
      case .toNearestOrAwayFromZero:
        false
      case .toNearestOrEven:
        false
      case .towardZero:
        false
      case .up:
        !isSignMinus
      @unknown default:
        fatalError("Unknown rounding rule.")
      }
      let abs = Self(
        bitPattern: UInt128(truncatingIfNeeded: e2) &<< 113
          | (nextAway ? 1 : 0))
      return _signal(.inexact, default: isSignMinus ? -abs : abs)
    }

    let pow = UInt128._exp10(n)
    let (quo, rem) = c1.quotientAndRemainder(dividingBy: pow)
    if rem == 0 {
      // Exact result.
      let abs = Self(
        bitPattern: UInt128(truncatingIfNeeded: e2) &<< 113 | quo)
      return isSignMinus ? -abs : abs
    }

    // Inexact.
    let nextAway: Bool = switch rule {
    case .awayFromZero:
      true
    case .down:
      isSignMinus
    case .toNearestOrAwayFromZero:
      rem >= (pow &>> 1)
    case .toNearestOrEven:
      (quo & 1) == 0
        ? rem > (pow &>> 1)
        : rem >= (pow &>> 1)
    case .towardZero:
      false
    case .up:
      !isSignMinus
    @unknown default:
      fatalError("Unknown rounding rule.")
    }
    // `quo &+ 1` cannot reach 10^34: with n >= 1, quo <= 10^33 - 1, so a
    // quantization to a coarser quantum can never signal invalid.
    let abs = Self(
      bitPattern: UInt128(truncatingIfNeeded: e2) &<< 113
        | (nextAway ? quo &+ 1 : quo))
    return _signal(.inexact, default: isSignMinus ? -abs : abs)
  }
```

Implementation notes:

- `n = 0` (equal exponents) takes the `guard e1 < e2 else` branch with
  `_exp10(0) == 1`: the operand is returned unchanged (already canonical,
  because `_isFiniteNonzero` passed) — exact, no signals. This is important
  for the `x.quantized(by: x) == x` identity.
- The digit-count test `c1._commonLogarithm &+ n < 34` encodes
  `digits(c1) + n ≤ 34` (since `digits = floorLog10 + 1`), so `_exp10(n)` is
  called only with `n ≤ 33` there and the product `c1 &* _exp10(n) < 10^34 <
  2^113` cannot wrap.
- Both `nextAway` ladders are copies of `_round`'s inexact ladder (with
  `rem_ = 0`), so reviewers can diff them; `pow` is even whenever this ladder
  runs (`n ≥ 1`), making `pow &>> 1` the exact half.
- Once `UInt128._quotientAndRemainder(dividingBy1e:)` (Granlund–Montgomery)
  lands, the single `quotientAndRemainder(dividingBy: pow)` call can switch to
  it; the contract `(quo, rem)` is identical. Not a correctness matter.
- `quantum` interplay: after this returns a finite non-NaN result `z`,
  `z.hasSameQuantum(as: other)` is `true` by construction (`z`'s
  `exponentBitPattern` is written as `e2` in the bit pattern, and results are
  canonical because significands stay `≤ 10^34 − 1`). Tests should assert this
  at the `bitPattern` level, not with `==` (which ignores quantum): e.g.
  `x.quantized(by: y).bitPattern == expected.bitPattern`, distinguishing
  `1E+2` (biased 6178, significand 1) from `100E+0` (biased 6176,
  significand 100), which compare equal but must not be conflated.

---

## 5. Edge-case tables

### 5.1 `remainder` / `truncatingRemainder` (identical special handling)

| # | `x` | `y` | Result | Signals | Notes |
|---|---|---|---|---|---|
| R1 | sNaN | any | quiet(x)._canonical | invalid | x checked first |
| R2 | any (non-sNaN) | sNaN | quiet(y)._canonical | invalid | |
| R3 | qNaN | any | x._canonical | — | payload preserved, canonicalized |
| R4 | any | qNaN | y._canonical | — | |
| R5 | ±∞ | any finite/∞ | NaN | invalid | |
| R6 | finite | ±∞ | x (unchanged, canonicalized) | — | quantum of x preserved ✅ |
| R7 | finite (incl. 0) | ±0 | NaN | invalid | y-zero checked before x-zero |
| R8 | ±0 | finite ≠ 0 | ±0 with sign(x), exponent min(e1,e2) | — | ✅ `0E+5 rem 1E+2 → 0E+2` |
| R9 | x, y with result 0 | | ±0 with **sign(x)**, exponent min(e1,e2) | — | e.g. `−3 rem 3 → −0` ✅ |
| R10 | noncanonical finite | — | treated as zero (both sides) | — | via `_isFiniteNonzero`/`isZero` |
| R11 | subnormal-range result | | exact, **no underflow signal** | — | exact subnormals never signal |
| R12 | `k = e2 − e1 ≥ 35` | | result = x exactly | — | early return, both variants |
| R13 | tie `2rt == b`, n_t odd | | nearest: flip; trunc: keep rt | — | parity machinery |
| R14 | tie `2rt == b`, n_t even | | nearest: keep rt; trunc: keep | — | |
| R15 | Δ = e1 − e2 up to 12287 | | exact via ≤ 324 chunk steps | — | GDA/Python signals invalid here; IEEE (us) must not |

### 5.2 `quantized(by:rounding:)`

| # | `x` | `y` | Result | Signals | Notes |
|---|---|---|---|---|---|
| Q1 | sNaN | any | quiet(x)._canonical | invalid | existing stub |
| Q2 | non-sNaN | sNaN | quiet(y)._canonical | invalid | needed in **both** ladders (finite x too) |
| Q3 | qNaN | any | x._canonical | — | |
| Q4 | any | qNaN | y._canonical | — | |
| Q5 | ±∞ | ±∞ | x (±∞) | — | sign of x preserved |
| Q6 | ±∞ | finite | NaN | invalid | |
| Q7 | finite | ±∞ | NaN | invalid | |
| Q8 | ±0 | finite | ±0, exponent of y, sign of x | — | existing stub; y may be zero |
| Q9 | finite ≠ 0 | zero y (any sign) | normal quantize to y's exponent | per value | y's *sign* ignored; only its exponent matters |
| Q10 | e2 ≤ e1, fits ≤ 34 digits | | exact widened significand | — | never inexact |
| Q11 | e2 < e1, needs > 34 digits | | NaN | **invalid** (not overflow) | e.g. `(10^34−1)E0 by 1E−1` |
| Q12 | e2 > e1, rem = 0 | | exact | — | e.g. `100E−2 by 1E0 → 1E0` |
| Q13 | e2 > e1, rem ≠ 0 | | rounded per rule | inexact | round-up can never hit 10^34 (§3.5) |
| Q14 | e2 − e1 ≥ 35 | | 0 or 1 unit at e2 per rule | inexact | value strictly below half-quantum |
| Q15 | nonzero x rounds to 0 | | ±0 at e2, sign of x | inexact | e.g. `1E−10 by 1E0, .towardZero` |
| Q16 | x = y (same quantum) | | x unchanged | — | identity; `n = 0` path |

Rounding-rule mapping used by tests (Python ↔ Swift):
`ROUND_HALF_EVEN ↔ .toNearestOrEven`, `ROUND_HALF_UP ↔ .toNearestOrAwayFromZero`,
`ROUND_DOWN ↔ .towardZero`, `ROUND_UP ↔ .awayFromZero`,
`ROUND_FLOOR ↔ .down`, `ROUND_CEILING ↔ .up`.

---

## 6. Test vectors (generated with python3 `decimal` + exact integers)

Two artifacts, both runnable with stock Python ≥ 3.9:

1. **Property harness** (run during implementation): simulates the exact Swift
   algorithm of §4 in Python integers — including every no-overflow assertion
   (`dividingFullWidth` precondition, `2·rt` fit, flip-magnitude ≤ 10^34 − 1) —
   and checks it against (a) an exact-integer IEEE oracle on ~4,500 random +
   adversarial remainder cases (full exponent range, engineered chunked-tie
   cases where quotient parity decides the answer) and (b) Python `decimal`
   (prec = 34, `Emin=-6143, Emax=6144, clamp=1`) for `quantize` on ~6,000
   cases across all six rounding rules, comparing values, exponents, and the
   inexact/invalid flags. All checks pass. Core oracle mapping:
   `remainder(dividingBy:)` ↔ `Context.remainder_near` (where GDA defines it),
   `truncatingRemainder` ↔ `Context.remainder`, `quantized` ↔
   `Context.quantize`.

2. **Vector generator** (below, verbatim; regenerates everything printed after
   it). Finite canonical values encode as
   `sign << 127 | (Q + 6176) << 113 | c` — valid for all canonical
   significands since `10^34 − 1 < 2^113`; `+Inf = 0x78 << 120`,
   `qNaN = 0x7C << 120`, `sNaN = 0x7E << 120`.

```python
#!/usr/bin/env python3
"""Generate Decimal128 (BID) test vectors for remainder / truncatingRemainder /
quantized(by:rounding:).

Oracles:
  - remainder ops: exact integer arithmetic implementing IEEE 754-2019
    definitions (Python `decimal` follows GDA and signals invalid when the
    quotient needs > 34 digits, so it is only used as a cross-check when
    defined).
  - quantize: Python `decimal` with Context(prec=34, Emin=-6143, Emax=6144).

Encoding: canonical BID decimal128. For finite values with c <= 10^34-1 < 2^113:
  bits = sign<<127 | (Q+6176)<<113 | c
Specials: +inf 0x78<<120, qNaN 0x7C<<120, sNaN 0x7E<<120.
"""
from decimal import (Decimal, Context, InvalidOperation, Inexact,
                     ROUND_HALF_EVEN, ROUND_HALF_UP, ROUND_DOWN, ROUND_UP,
                     ROUND_FLOOR, ROUND_CEILING)

CMAX = 10**34 - 1

def bits(sign, c, q):
    assert 0 <= c <= CMAX and -6176 <= q <= 6111
    return (sign << 127) | ((q + 6176) << 113) | c

INF  = 0x78 << 120
QNAN = 0x7C << 120
SNAN = 0x7E << 120

def hx(v):
    return f"0x{v:032X}"

def parse(s):
    """'-123E-4' -> (sign, c, q); also 'Inf','-Inf','NaN','sNaN'."""
    if s in ('Inf', '+Inf'): return ('inf', 0)
    if s == '-Inf': return ('inf', 1)
    if s == 'NaN':  return ('nan', 0)
    if s == 'sNaN': return ('snan', 0)
    sign = 0
    if s.startswith('-'): sign, s = 1, s[1:]
    if 'E' in s:
        m, e = s.split('E')
    else:
        m, e = s, '0'
    return (sign, int(m), int(e))

def enc(t):
    if t[0] == 'inf':  return INF | (t[1] << 127)
    if t[0] == 'nan':  return QNAN
    if t[0] == 'snan': return SNAN
    return bits(*t)

# ---------------- IEEE remainder oracle (exact integers) ----------------
def ieee_rem(xt, yt, nearest):
    """Returns (result_bits, flags) for finite/special operands."""
    if xt[0] == 'snan': return QNAN, {'invalid'}   # payload details elided
    if yt[0] == 'snan': return QNAN, {'invalid'}
    if xt[0] == 'nan':  return QNAN, set()
    if yt[0] == 'nan':  return QNAN, set()
    if xt[0] == 'inf':  return QNAN, {'invalid'}
    if yt[0] == 'inf':  return enc(xt), set()
    s1, c1, q1 = xt
    s2, c2, q2 = yt
    if c2 == 0: return QNAN, {'invalid'}
    qm = min(q1, q2)
    if c1 == 0: return bits(s1, 0, qm), set()
    A, B = c1 * 10**(q1 - qm), c2 * 10**(q2 - qm)
    nt, rt = divmod(A, B)
    if nearest and (2*rt > B or (2*rt == B and nt & 1)):
        m, sign = B - rt, 1 - s1
    else:
        m, sign = rt, s1
    if m == 0: sign = s1
    assert m <= CMAX
    return bits(sign, m, qm), set()

# ---------------- quantize oracle (Python decimal) ----------------
RULES = {'toNearestOrEven': ROUND_HALF_EVEN,
         'toNearestOrAwayFromZero': ROUND_HALF_UP,
         'towardZero': ROUND_DOWN, 'awayFromZero': ROUND_UP,
         'down': ROUND_FLOOR, 'up': ROUND_CEILING}

def dec_of(t):
    if t[0] == 'inf': return Decimal('-Infinity') if t[1] else Decimal('Infinity')
    if t[0] in ('nan', 'snan'): return Decimal('NaN')
    s, c, q = t
    return Decimal((s, tuple(int(d) for d in str(c)), q))

def ieee_quantize(xt, yt, rule):
    if xt[0] == 'snan' or yt[0] == 'snan': return QNAN, {'invalid'}
    if xt[0] == 'nan' or yt[0] == 'nan':   return QNAN, set()
    if xt[0] == 'inf':
        if yt[0] == 'inf': return enc(xt), set()
        return QNAN, {'invalid'}
    if yt[0] == 'inf': return QNAN, {'invalid'}
    c = Context(prec=34, Emin=-6143, Emax=6144, clamp=1,
                rounding=RULES[rule])
    c.traps[InvalidOperation] = False
    c.clear_flags()
    r = c.quantize(dec_of(xt), dec_of(yt))
    if r.is_nan(): return QNAN, {'invalid'}
    t = r.as_tuple()
    m = int(''.join(map(str, t.digits)))
    flags = {'inexact'} if c.flags[Inexact] else set()
    return bits(t.sign, m, t.exponent), flags

# ---------------- vector definitions ----------------
REM = [
    # (x, y, comment)
    ('7', '2', 'tie: 3.5 -> n=4 even; nearest flips'),
    ('-7', '2', 'sign of x drives result sign'),
    ('150', '4', 'tie 37.5 -> n=38; nearest flips'),
    ('15E1', '4', 'same value via coarser quantum of x'),
    ('5', '10', 'tie 0.5 -> n=0 even; keep'),
    ('15', '10', '1.5 -> n=2; nearest flips'),
    ('25', '10', '2.5 -> n=2 even; keep'),
    ('6', '1E1', 'k=1 flip: 0.6 -> n=1'),
    ('1E100', '7', 'chunked reduction; GDA says invalid, IEEE says -3'),
    ('1E-6000', '3', 'tiny x: r = x'),
    ('9999999999999999999999999999999999E6111', '7E-6176',
     'maximal gap, ~12287 fold digits'),
    ('9999999999999999999999999999999999E6111', '1E-6176',
     'divisor one ulp-min: r = 0 at Q=-6176'),
    ('9999999999999999999999999999999999E-6000',
     '3000000000000000000000000000000001E67', 'tiny vs huge: r = x'),
    ('3', '3', 'exact zero, sign +'),
    ('-3', '3', 'exact zero keeps sign of x'),
    ('-3E5', '3E1', 'zero at min exponent'),
    ('3E-6176', '2E-6176', 'subnormal ops: 1.5 -> n=2; exact, no underflow'),
    ('0E5', '1E2', 'zero dividend: exponent min(5,2)'),
    ('-0E-5', '1E2', 'zero dividend keeps sign, exponent min(-5,2)'),
    ('100E-2', 'Inf', 'y infinite: x unchanged (quantum kept)'),
    ('0E5', '-Inf', 'zero dividend, y infinite'),
    ('1', '0E0', 'division by zero: invalid NaN'),
    ('Inf', '2', 'infinite dividend: invalid NaN'),
    ('1E6111', '9999999999999999999999999999999999E-6176',
     'huge gap, 34-digit divisor'),
]

QNT = [
    # (x, y, rule, comment)
    ('25E-1', '1E0', 'toNearestOrEven', '2.5 -> 2'),
    ('25E-1', '1E0', 'toNearestOrAwayFromZero', '2.5 -> 3'),
    ('35E-1', '1E0', 'toNearestOrEven', '3.5 -> 4'),
    ('-25E-1', '1E0', 'down', '-2.5 -> -3 (floor)'),
    ('-25E-1', '1E0', 'towardZero', '-2.5 -> -2'),
    ('217E0', '1E1', 'toNearestOrEven', '21.7 -> 22, inexact'),
    ('100E-2', '1E0', 'toNearestOrEven', 'exact rescale 1.00 -> 1'),
    ('123E0', '1E0', 'toNearestOrEven', 'same quantum: identity'),
    ('1E2', '1E0', 'toNearestOrEven', 'exact widen 1E2 -> 100'),
    ('1E0', '1E-33', 'toNearestOrEven', 'widen to 34 digits: exact'),
    ('1E0', '1E-34', 'toNearestOrEven', 'widen to 35 digits: invalid'),
    ('9999999999999999999999999999999999E0', '1E-1', 'toNearestOrEven',
     'widen max significand: invalid'),
    ('9999999999999999999999999999999999E0', '1E1', 'toNearestOrEven',
     'round up at cap: quo 10^33-1 -> 10^33, fits'),
    ('5E33', '1E34', 'toNearestOrEven', 'tie, quo 0 even: -> 0, inexact'),
    ('5E33', '1E34', 'toNearestOrAwayFromZero', 'tie -> 1E34'),
    ('1E0', '1E100', 'toNearestOrEven', 'discard all, below half -> 0'),
    ('1E0', '1E100', 'up', 'discard all, ceiling -> 1E100'),
    ('-1E0', '1E100', 'down', 'discard all, floor -> -1E100'),
    ('-1E0', '1E100', 'up', 'ceiling toward zero -> -0E100'),
    ('1E-10', '1E0', 'towardZero', 'nonzero -> zero significand, inexact'),
    ('-5E-1', '1E0', 'toNearestOrEven', '-0.5 -> -0, sign kept'),
    ('0E5', '1E-3', 'toNearestOrEven', 'zero x: zero at y quantum'),
    ('123E0', '0E2', 'toNearestOrEven', 'y zero: only its exponent matters'),
    ('Inf', 'Inf', 'toNearestOrEven', 'both infinite: x'),
    ('-Inf', 'Inf', 'toNearestOrEven', 'sign preserved'),
    ('Inf', '1E0', 'toNearestOrEven', 'one infinite: invalid'),
    ('1E0', 'Inf', 'toNearestOrEven', 'one infinite: invalid'),
]

def fmt(t):
    if t[0] == 'inf': return '-Inf' if t[1] else '+Inf'
    if t[0] == 'nan': return 'NaN'
    if t[0] == 'snan': return 'sNaN'
    s, c, q = t
    return f"{'-' if s else ''}{c}E{q:+d}"

def human(b):
    if b == QNAN: return 'NaN'
    if b & (0xF << 123) == INF & (0xF << 123):
        pass
    if b == INF: return '+Inf'
    if b == INF | (1 << 127): return '-Inf'
    sign = b >> 127
    q = ((b >> 113) & 0x3FFF) - 6176
    c = b & ((1 << 113) - 1)
    return f"{'-' if sign else ''}{c}E{q:+d}"

print("#### remainder / truncatingRemainder\n")
print("| x | y | `remainder` → | flags | `truncatingRemainder` → | flags |")
print("|---|---|---|---|---|---|")
rows_bits = []
for xs, ys, note in REM:
    xt, yt = parse(xs), parse(ys)
    rn, fn = ieee_rem(xt, yt, True)
    rtr, ftr = ieee_rem(xt, yt, False)
    print(f"| `{xs}` | `{ys}` | `{human(rn)}` | {','.join(sorted(fn)) or '—'} "
          f"| `{human(rtr)}` | {','.join(sorted(ftr)) or '—'} |")
    rows_bits.append((xs, ys, enc(xt), enc(yt), rn, rtr, note))

print("\nBit-pattern form (`x`, `y`, `remainder`, `truncatingRemainder`):\n")
print("```")
for xs, ys, xb, yb, rn, rtr, note in rows_bits:
    print(f"// {xs} rem {ys}  ({note})")
    print(f"({hx(xb)}, {hx(yb)},\n {hx(rn)}, {hx(rtr)}),")
print("```")

print("\n#### quantized(by:rounding:)\n")
print("| x | y | rule | result | flags |")
print("|---|---|---|---|---|")
qrows = []
for xs, ys, rule, note in QNT:
    xt, yt = parse(xs), parse(ys)
    rb, fl = ieee_quantize(xt, yt, rule)
    print(f"| `{xs}` | `{ys}` | `.{rule}` | `{human(rb)}` | "
          f"{','.join(sorted(fl)) or '—'} |")
    qrows.append((xs, ys, rule, enc(xt), enc(yt), rb, fl, note))

print("\nBit-pattern form (`x`, `y`, rule, result, inexact, invalid):\n")
print("```")
for xs, ys, rule, xb, yb, rb, fl, note in qrows:
    print(f"// {xs} quantized by {ys} .{rule}  ({note})")
    print(f"({hx(xb)}, {hx(yb)}, .{rule},\n {hx(rb)}, "
          f"{str('inexact' in fl).lower()}, {str('invalid' in fl).lower()}),")
print("```")
```

### 6.1 Generated vectors

Assertions for the Swift test suite must compare **`bitPattern`**, not `==`
(cohort members like `1E+2` and `100E+0` compare equal but have different
quanta), and should assert the flag columns once `_signal` grows a test hook.

#### remainder / truncatingRemainder

| x | y | `remainder` → | flags | `truncatingRemainder` → | flags |
|---|---|---|---|---|---|
| `7` | `2` | `-1E+0` | — | `1E+0` | — |
| `-7` | `2` | `1E+0` | — | `-1E+0` | — |
| `150` | `4` | `-2E+0` | — | `2E+0` | — |
| `15E1` | `4` | `-2E+0` | — | `2E+0` | — |
| `5` | `10` | `5E+0` | — | `5E+0` | — |
| `15` | `10` | `-5E+0` | — | `5E+0` | — |
| `25` | `10` | `5E+0` | — | `5E+0` | — |
| `6` | `1E1` | `-4E+0` | — | `6E+0` | — |
| `1E100` | `7` | `-3E+0` | — | `4E+0` | — |
| `1E-6000` | `3` | `1E-6000` | — | `1E-6000` | — |
| `9999999999999999999999999999999999E6111` | `7E-6176` | `1E-6176` | — | `1E-6176` | — |
| `9999999999999999999999999999999999E6111` | `1E-6176` | `0E-6176` | — | `0E-6176` | — |
| `9999999999999999999999999999999999E-6000` | `3000000000000000000000000000000001E67` | `9999999999999999999999999999999999E-6000` | — | `9999999999999999999999999999999999E-6000` | — |
| `3` | `3` | `0E+0` | — | `0E+0` | — |
| `-3` | `3` | `-0E+0` | — | `-0E+0` | — |
| `-3E5` | `3E1` | `-0E+1` | — | `-0E+1` | — |
| `3E-6176` | `2E-6176` | `-1E-6176` | — | `1E-6176` | — |
| `0E5` | `1E2` | `0E+2` | — | `0E+2` | — |
| `-0E-5` | `1E2` | `-0E-5` | — | `-0E-5` | — |
| `100E-2` | `Inf` | `100E-2` | — | `100E-2` | — |
| `0E5` | `-Inf` | `0E+5` | — | `0E+5` | — |
| `1` | `0E0` | `NaN` | invalid | `NaN` | invalid |
| `Inf` | `2` | `NaN` | invalid | `NaN` | invalid |
| `1E6111` | `9999999999999999999999999999999999E-6176` | `10000000000000E-6176` | — | `10000000000000E-6176` | — |

Bit-pattern form (`x`, `y`, `remainder`, `truncatingRemainder`):

```
// 7 rem 2  (tie: 3.5 -> n=4 even; nearest flips)
(0x30400000000000000000000000000007, 0x30400000000000000000000000000002,
 0xB0400000000000000000000000000001, 0x30400000000000000000000000000001),
// -7 rem 2  (sign of x drives result sign)
(0xB0400000000000000000000000000007, 0x30400000000000000000000000000002,
 0x30400000000000000000000000000001, 0xB0400000000000000000000000000001),
// 150 rem 4  (tie 37.5 -> n=38; nearest flips)
(0x30400000000000000000000000000096, 0x30400000000000000000000000000004,
 0xB0400000000000000000000000000002, 0x30400000000000000000000000000002),
// 15E1 rem 4  (same value via coarser quantum of x)
(0x3042000000000000000000000000000F, 0x30400000000000000000000000000004,
 0xB0400000000000000000000000000002, 0x30400000000000000000000000000002),
// 5 rem 10  (tie 0.5 -> n=0 even; keep)
(0x30400000000000000000000000000005, 0x3040000000000000000000000000000A,
 0x30400000000000000000000000000005, 0x30400000000000000000000000000005),
// 15 rem 10  (1.5 -> n=2; nearest flips)
(0x3040000000000000000000000000000F, 0x3040000000000000000000000000000A,
 0xB0400000000000000000000000000005, 0x30400000000000000000000000000005),
// 25 rem 10  (2.5 -> n=2 even; keep)
(0x30400000000000000000000000000019, 0x3040000000000000000000000000000A,
 0x30400000000000000000000000000005, 0x30400000000000000000000000000005),
// 6 rem 1E1  (k=1 flip: 0.6 -> n=1)
(0x30400000000000000000000000000006, 0x30420000000000000000000000000001,
 0xB0400000000000000000000000000004, 0x30400000000000000000000000000006),
// 1E100 rem 7  (chunked reduction; GDA says invalid, IEEE says -3)
(0x31080000000000000000000000000001, 0x30400000000000000000000000000007,
 0xB0400000000000000000000000000003, 0x30400000000000000000000000000004),
// 1E-6000 rem 3  (tiny x: r = x)
(0x01600000000000000000000000000001, 0x30400000000000000000000000000003,
 0x01600000000000000000000000000001, 0x01600000000000000000000000000001),
// 9999999999999999999999999999999999E6111 rem 7E-6176  (maximal gap, ~12287 fold digits)
(0x5FFFED09BEAD87C0378D8E63FFFFFFFF, 0x00000000000000000000000000000007,
 0x00000000000000000000000000000001, 0x00000000000000000000000000000001),
// 9999999999999999999999999999999999E6111 rem 1E-6176  (divisor one ulp-min: r = 0 at Q=-6176)
(0x5FFFED09BEAD87C0378D8E63FFFFFFFF, 0x00000000000000000000000000000001,
 0x00000000000000000000000000000000, 0x00000000000000000000000000000000),
// 9999999999999999999999999999999999E-6000 rem 3000000000000000000000000000000001E67  (tiny vs huge: r = x)
(0x0161ED09BEAD87C0378D8E63FFFFFFFF, 0x30C693E952CDA8B9AA44111E00000001,
 0x0161ED09BEAD87C0378D8E63FFFFFFFF, 0x0161ED09BEAD87C0378D8E63FFFFFFFF),
// 3 rem 3  (exact zero, sign +)
(0x30400000000000000000000000000003, 0x30400000000000000000000000000003,
 0x30400000000000000000000000000000, 0x30400000000000000000000000000000),
// -3 rem 3  (exact zero keeps sign of x)
(0xB0400000000000000000000000000003, 0x30400000000000000000000000000003,
 0xB0400000000000000000000000000000, 0xB0400000000000000000000000000000),
// -3E5 rem 3E1  (zero at min exponent)
(0xB04A0000000000000000000000000003, 0x30420000000000000000000000000003,
 0xB0420000000000000000000000000000, 0xB0420000000000000000000000000000),
// 3E-6176 rem 2E-6176  (subnormal ops: 1.5 -> n=2; exact, no underflow)
(0x00000000000000000000000000000003, 0x00000000000000000000000000000002,
 0x80000000000000000000000000000001, 0x00000000000000000000000000000001),
// 0E5 rem 1E2  (zero dividend: exponent min(5,2))
(0x304A0000000000000000000000000000, 0x30440000000000000000000000000001,
 0x30440000000000000000000000000000, 0x30440000000000000000000000000000),
// -0E-5 rem 1E2  (zero dividend keeps sign, exponent min(-5,2))
(0xB0360000000000000000000000000000, 0x30440000000000000000000000000001,
 0xB0360000000000000000000000000000, 0xB0360000000000000000000000000000),
// 100E-2 rem Inf  (y infinite: x unchanged (quantum kept))
(0x303C0000000000000000000000000064, 0x78000000000000000000000000000000,
 0x303C0000000000000000000000000064, 0x303C0000000000000000000000000064),
// 0E5 rem -Inf  (zero dividend, y infinite)
(0x304A0000000000000000000000000000, 0xF8000000000000000000000000000000,
 0x304A0000000000000000000000000000, 0x304A0000000000000000000000000000),
// 1 rem 0E0  (division by zero: invalid NaN)
(0x30400000000000000000000000000001, 0x30400000000000000000000000000000,
 0x7C000000000000000000000000000000, 0x7C000000000000000000000000000000),
// Inf rem 2  (infinite dividend: invalid NaN)
(0x78000000000000000000000000000000, 0x30400000000000000000000000000002,
 0x7C000000000000000000000000000000, 0x7C000000000000000000000000000000),
// 1E6111 rem 9999999999999999999999999999999999E-6176  (huge gap, 34-digit divisor)
(0x5FFE0000000000000000000000000001, 0x0001ED09BEAD87C0378D8E63FFFFFFFF,
 0x0000000000000000000009184E72A000, 0x0000000000000000000009184E72A000),
```

#### quantized(by:rounding:)

| x | y | rule | result | flags |
|---|---|---|---|---|
| `25E-1` | `1E0` | `.toNearestOrEven` | `2E+0` | inexact |
| `25E-1` | `1E0` | `.toNearestOrAwayFromZero` | `3E+0` | inexact |
| `35E-1` | `1E0` | `.toNearestOrEven` | `4E+0` | inexact |
| `-25E-1` | `1E0` | `.down` | `-3E+0` | inexact |
| `-25E-1` | `1E0` | `.towardZero` | `-2E+0` | inexact |
| `217E0` | `1E1` | `.toNearestOrEven` | `22E+1` | inexact |
| `100E-2` | `1E0` | `.toNearestOrEven` | `1E+0` | — |
| `123E0` | `1E0` | `.toNearestOrEven` | `123E+0` | — |
| `1E2` | `1E0` | `.toNearestOrEven` | `100E+0` | — |
| `1E0` | `1E-33` | `.toNearestOrEven` | `1000000000000000000000000000000000E-33` | — |
| `1E0` | `1E-34` | `.toNearestOrEven` | `NaN` | invalid |
| `9999999999999999999999999999999999E0` | `1E-1` | `.toNearestOrEven` | `NaN` | invalid |
| `9999999999999999999999999999999999E0` | `1E1` | `.toNearestOrEven` | `1000000000000000000000000000000000E+1` | inexact |
| `5E33` | `1E34` | `.toNearestOrEven` | `0E+34` | inexact |
| `5E33` | `1E34` | `.toNearestOrAwayFromZero` | `1E+34` | inexact |
| `1E0` | `1E100` | `.toNearestOrEven` | `0E+100` | inexact |
| `1E0` | `1E100` | `.up` | `1E+100` | inexact |
| `-1E0` | `1E100` | `.down` | `-1E+100` | inexact |
| `-1E0` | `1E100` | `.up` | `-0E+100` | inexact |
| `1E-10` | `1E0` | `.towardZero` | `0E+0` | inexact |
| `-5E-1` | `1E0` | `.toNearestOrEven` | `-0E+0` | inexact |
| `0E5` | `1E-3` | `.toNearestOrEven` | `0E-3` | — |
| `123E0` | `0E2` | `.toNearestOrEven` | `1E+2` | inexact |
| `Inf` | `Inf` | `.toNearestOrEven` | `+Inf` | — |
| `-Inf` | `Inf` | `.toNearestOrEven` | `-Inf` | — |
| `Inf` | `1E0` | `.toNearestOrEven` | `NaN` | invalid |
| `1E0` | `Inf` | `.toNearestOrEven` | `NaN` | invalid |

Bit-pattern form (`x`, `y`, rule, result, inexact, invalid):

```
// 25E-1 quantized by 1E0 .toNearestOrEven  (2.5 -> 2)
(0x303E0000000000000000000000000019, 0x30400000000000000000000000000001, .toNearestOrEven,
 0x30400000000000000000000000000002, true, false),
// 25E-1 quantized by 1E0 .toNearestOrAwayFromZero  (2.5 -> 3)
(0x303E0000000000000000000000000019, 0x30400000000000000000000000000001, .toNearestOrAwayFromZero,
 0x30400000000000000000000000000003, true, false),
// 35E-1 quantized by 1E0 .toNearestOrEven  (3.5 -> 4)
(0x303E0000000000000000000000000023, 0x30400000000000000000000000000001, .toNearestOrEven,
 0x30400000000000000000000000000004, true, false),
// -25E-1 quantized by 1E0 .down  (-2.5 -> -3 (floor))
(0xB03E0000000000000000000000000019, 0x30400000000000000000000000000001, .down,
 0xB0400000000000000000000000000003, true, false),
// -25E-1 quantized by 1E0 .towardZero  (-2.5 -> -2)
(0xB03E0000000000000000000000000019, 0x30400000000000000000000000000001, .towardZero,
 0xB0400000000000000000000000000002, true, false),
// 217E0 quantized by 1E1 .toNearestOrEven  (21.7 -> 22, inexact)
(0x304000000000000000000000000000D9, 0x30420000000000000000000000000001, .toNearestOrEven,
 0x30420000000000000000000000000016, true, false),
// 100E-2 quantized by 1E0 .toNearestOrEven  (exact rescale 1.00 -> 1)
(0x303C0000000000000000000000000064, 0x30400000000000000000000000000001, .toNearestOrEven,
 0x30400000000000000000000000000001, false, false),
// 123E0 quantized by 1E0 .toNearestOrEven  (same quantum: identity)
(0x3040000000000000000000000000007B, 0x30400000000000000000000000000001, .toNearestOrEven,
 0x3040000000000000000000000000007B, false, false),
// 1E2 quantized by 1E0 .toNearestOrEven  (exact widen 1E2 -> 100)
(0x30440000000000000000000000000001, 0x30400000000000000000000000000001, .toNearestOrEven,
 0x30400000000000000000000000000064, false, false),
// 1E0 quantized by 1E-33 .toNearestOrEven  (widen to 34 digits: exact)
(0x30400000000000000000000000000001, 0x2FFE0000000000000000000000000001, .toNearestOrEven,
 0x2FFE314DC6448D9338C15B0A00000000, false, false),
// 1E0 quantized by 1E-34 .toNearestOrEven  (widen to 35 digits: invalid)
(0x30400000000000000000000000000001, 0x2FFC0000000000000000000000000001, .toNearestOrEven,
 0x7C000000000000000000000000000000, false, true),
// 9999999999999999999999999999999999E0 quantized by 1E-1 .toNearestOrEven  (widen max significand: invalid)
(0x3041ED09BEAD87C0378D8E63FFFFFFFF, 0x303E0000000000000000000000000001, .toNearestOrEven,
 0x7C000000000000000000000000000000, false, true),
// 9999999999999999999999999999999999E0 quantized by 1E1 .toNearestOrEven  (round up at cap: quo 10^33-1 -> 10^33, fits)
(0x3041ED09BEAD87C0378D8E63FFFFFFFF, 0x30420000000000000000000000000001, .toNearestOrEven,
 0x3042314DC6448D9338C15B0A00000000, true, false),
// 5E33 quantized by 1E34 .toNearestOrEven  (tie, quo 0 even: -> 0, inexact)
(0x30820000000000000000000000000005, 0x30840000000000000000000000000001, .toNearestOrEven,
 0x30840000000000000000000000000000, true, false),
// 5E33 quantized by 1E34 .toNearestOrAwayFromZero  (tie -> 1E34)
(0x30820000000000000000000000000005, 0x30840000000000000000000000000001, .toNearestOrAwayFromZero,
 0x30840000000000000000000000000001, true, false),
// 1E0 quantized by 1E100 .toNearestOrEven  (discard all, below half -> 0)
(0x30400000000000000000000000000001, 0x31080000000000000000000000000001, .toNearestOrEven,
 0x31080000000000000000000000000000, true, false),
// 1E0 quantized by 1E100 .up  (discard all, ceiling -> 1E100)
(0x30400000000000000000000000000001, 0x31080000000000000000000000000001, .up,
 0x31080000000000000000000000000001, true, false),
// -1E0 quantized by 1E100 .down  (discard all, floor -> -1E100)
(0xB0400000000000000000000000000001, 0x31080000000000000000000000000001, .down,
 0xB1080000000000000000000000000001, true, false),
// -1E0 quantized by 1E100 .up  (ceiling toward zero -> -0E100)
(0xB0400000000000000000000000000001, 0x31080000000000000000000000000001, .up,
 0xB1080000000000000000000000000000, true, false),
// 1E-10 quantized by 1E0 .towardZero  (nonzero -> zero significand, inexact)
(0x302C0000000000000000000000000001, 0x30400000000000000000000000000001, .towardZero,
 0x30400000000000000000000000000000, true, false),
// -5E-1 quantized by 1E0 .toNearestOrEven  (-0.5 -> -0, sign kept)
(0xB03E0000000000000000000000000005, 0x30400000000000000000000000000001, .toNearestOrEven,
 0xB0400000000000000000000000000000, true, false),
// 0E5 quantized by 1E-3 .toNearestOrEven  (zero x: zero at y quantum)
(0x304A0000000000000000000000000000, 0x303A0000000000000000000000000001, .toNearestOrEven,
 0x303A0000000000000000000000000000, false, false),
// 123E0 quantized by 0E2 .toNearestOrEven  (y zero: only its exponent matters)
(0x3040000000000000000000000000007B, 0x30440000000000000000000000000000, .toNearestOrEven,
 0x30440000000000000000000000000001, true, false),
// Inf quantized by Inf .toNearestOrEven  (both infinite: x)
(0x78000000000000000000000000000000, 0x78000000000000000000000000000000, .toNearestOrEven,
 0x78000000000000000000000000000000, false, false),
// -Inf quantized by Inf .toNearestOrEven  (sign preserved)
(0xF8000000000000000000000000000000, 0x78000000000000000000000000000000, .toNearestOrEven,
 0xF8000000000000000000000000000000, false, false),
// Inf quantized by 1E0 .toNearestOrEven  (one infinite: invalid)
(0x78000000000000000000000000000000, 0x30400000000000000000000000000001, .toNearestOrEven,
 0x7C000000000000000000000000000000, false, true),
// 1E0 quantized by Inf .toNearestOrEven  (one infinite: invalid)
(0x30400000000000000000000000000001, 0x78000000000000000000000000000000, .toNearestOrEven,
 0x7C000000000000000000000000000000, false, true),
```

### 6.2 Suggested additional property tests (Swift-side)

- `x.remainder(dividingBy: y).bitPattern == (-x).remainder(dividingBy: y).bitPattern ^ (1 << 127)` (sign antisymmetry) and invariance under `y.negate()`.
- For finite nonzero `x, y`: reconstruct `x == y * n + r` in exact integer
  arithmetic (test-side bignums), with `n` re-derived from `(x - r) / y`;
  check `2|r| <= |y|` (nearest, with equality only when `n` even) and
  `|r| < |y|`, `sign(r) == sign(x)` (truncating).
- `x.quantized(by: y).hasSameQuantum(as: y)` for every finite non-NaN result.
- `x.quantized(by: x).bitPattern == x.bitPattern` for finite canonical `x`.
- Idempotence: `x.quantized(by: y).quantized(by: y)` is exact the second time
  (no inexact signal).

---

## 7. Open questions / risks

1. **⚠️ `_signal` is currently a no-op.** The flag expectations in §6 (invalid
   / inexact columns) are designed in but not observable until the exception
   scaffold records flags. The listings route every path through the correct
   `_signal` call so no revisit is needed later.

2. **⚠️ NaN payload propagation in vectors.** The generated NaN vectors use the
   canonical quiet NaN (`0x7C << 110-shifted`); the implementation propagates
   the *operand's* canonicalized payload (`lhs._quiet._canonical`). Tests
   exercising payloads should build expectations from the operand, as the
   existing `adding` tests presumably do — the vector table's plain-NaN rows
   only assert NaN-ness plus flags.

3. **⚠️ GDA-vs-IEEE remainder divergence** (§1.1). Anyone cross-testing against
   decNumber, Python `decimal`, or the `dectest` suites (`remainder.decTest`,
   `remainderNear.decTest`) must skip/expect-invalid the cases where the
   quotient exceeds 34 digits — those suites encode GDA behavior, not IEEE.
   Conversely Intel's `bid128_rem` tests match this design. If the project
   later wants a GDA-compatible mode, it would be a separate API, not a change
   here.

4. **Performance.** Worst-case `Δ = 12287` runs 324 iterations of one
   128×128→256 multiply plus one 256÷128 divide — microseconds, and only for
   pathological exponent gaps; typical financial data hits the `Δ = 0` or
   small-`Δ` fast paths. If profiling ever shows the loop hot, chunk quotients
   `q_i` need not be materialized except in the last iteration (`s < 38 ⇒`
   last), enabling a cheaper Barrett/G-M reciprocal-of-`c2` reuse across
   iterations — out of scope now.

5. **`divided(by:rounding:)` interplay.** None. The remainders deliberately do
   not share code with the planned division (sticky-bit `_round` extension is
   irrelevant here because remainders are exact and quantize rounds at a fixed
   exponent with a full remainder in hand). `quantized` can adopt
   `UInt128._quotientAndRemainder(dividingBy1e:)` as a drop-in when it lands
   (§4.3 note).

6. **`fatalError` reachability in the existing stub.** §4.3 removes the inner
   `fatalError("Not implemented")` by making the zero-`x` return unconditional;
   the reasoning (NaN/∞ exhausted ⟹ `isZero`, including noncanonical
   encodings) should be double-checked against `isZero`'s definition (it
   returns `true` for `g >= 0x18000 && g < 0x1e000`, i.e. noncanonical finite
   — confirmed by reading lines 355–361).

7. **Unverified corner: `exponentBitPattern` of noncanonical `other` in
   `quantized`.** The design reads `other.exponentBitPattern` even when
   `other` is a noncanonical finite value (treated as zero but still carrying
   an exponent field). The property reads the correct field for both encoding
   forms, so the result quantum follows the encoded exponent — matching the
   IEEE view that quantize keys on `other`'s *exponent*, not its value. A test
   with a noncanonical `other` (e.g. combination `11…` form) is recommended.

