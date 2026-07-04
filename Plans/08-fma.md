# 08 — Fused multiply-add: `addingProduct(_:_:rounding:)`

Implements `self + lhs·rhs` with a **single** rounding (IEEE 754-2019
fusedMultiplyAdd, §5.4.1). No Foundation counterpart exists; this design is
from first principles on top of the repo's 256-bit primitives, structurally
informed by `adding(_:rounding:)` (whose far-apart perturbation trick it
generalizes) and by the public structure of Intel `bid128_fma` (384-bit
intermediates, regime split) and decNumber `decNumberFMA` (exact product,
exact add, one round). Requires doc 01 (sticky-aware `_round`).

Notation: product operands `x = lhs = (s₁, c₁, E₁)`, `y = rhs = (s₂, c₂, E₂)`
(biased exponents); addend `z = self = (s₃, c₃, E₃)`. Product significand
`P = c₁·c₂ ∈ [1, 10⁶⁸)` — exact in 226 bits via `multipliedFullWidth`;
product sign `sₚ = s₁ ⊕ s₂`; product biased exponent `eₚ = E₁ + E₂ − 6176`
(`Int`; range [−6176, 18398] — intermediate only). `δ = E₃ − eₚ`.

## 8.1 Special cases

Ladder order (receiver first, then products; each returns immediately):

1. `self` sNaN → invalid, `self._quiet._canonical`; then `lhs` sNaN, `rhs`
   sNaN likewise.
2. **0×∞**: `(lhs.isZero && rhs.isInfinite) || (lhs.isInfinite && rhs.isZero)`
   → if `self` is (q)NaN, return `self._canonical` **without** signaling
   invalid — IEEE §7.2 makes this case implementation-defined; we choose the
   quiet behavior for consistency with "NaN operands propagate silently"
   (document at the call site; Intel signals invalid here — an acceptable
   divergence, but pick one and test it). Otherwise → invalid, NaN.
3. `self` qNaN → `self._canonical`; then `lhs` qNaN, `rhs` qNaN.
4. Product infinite (`lhs` or `rhs` infinite; neither is zero/NaN now):
   if `self` is infinite with sign ≠ `sₚ` → invalid, NaN; else `±∞` (sign
   `sₚ`) — note this also covers finite `self`.
5. `self` infinite (finite product) → `self` (i.e. `±∞`).
6. Product zero (`lhs.isZero || rhs.isZero`): degenerate to **addition**:
   `return self.adding(pz, rounding: rule)` where
   `pz = (sₚ, 0, clamp(eₚ, 0…12287))` — `adding` already implements IEEE §6.3
   zero-sign rules and min-quantum selection for `x + 0`.
7. `self` zero, product nonzero: fall through to the main path with `c₃ = 0`
   treated via the same alignment machinery (the listing folds it in; the
   preferred exponent min(Qₚ, Q₃) is achieved by the same alignment-at-min
   argument as §8.4).

Every path must preserve the invalid/quiet conventions of `adding` verbatim.

## 8.2 Main path: alignment regimes

Goal: an intermediate `(high, low)` at a common biased exponent `e_C`, plus a
`sticky` bit obeying doc 01's invariant, such that exactly **one** rounding
(inside `_round`) produces the result. 2²⁵⁶ ≈ 1.158·10⁷⁷, so 77 decimal
digits is the working capacity; `P < 10⁶⁸` and `c₃ < 10³⁴`.

**Regime table** (`Dₚ = P`'s digit count via `_UInt256._commonLogarithm + 1`):

| Regime | Condition | `e_C` | Scaled/truncated |
| --- | --- | --- | --- |
| A: full, addend above | `0 ≤ δ ≤ 43` | `eₚ` | addend ×10^δ (≤ 77 digits), product exact |
| B: product-sticky | `δ > 43` | `E₃ − 43` | addend ×10⁴³ (77 digits), product ÷10^(δ−43) → sticky |
| C: full, addend below | `δ < 0`, `|δ| ≤ 77 − Dₚ` | `E₃` | product ×10^{|δ|} (≤ 77 digits), addend exact |
| D: addend-sticky | `δ < 0`, `|δ| > 77 − Dₚ` | `eₚ − (77 − Dₚ)` | product ×10^(77−Dₚ) (77 digits), addend ÷10^(e_C − E₃) → sticky |

Capacity proofs:

- A: `c₃·10^δ < 10^{34+43} = 10^{77}` ✓; sum `< 10^{77} + 10^{68} < 2^{256}` ✓
  (`2^{256} − 10^{77} ≈ 1.6·10^{76} > 10^{68}`).
- B: product reduced, so both parts `< 10^{77}`, sum `< 10^{77} + 10^{68}` ✓.
- C: `P·10^{|δ|} < 10^{Dₚ + (77−Dₚ)} = 10^{77}` ✓; `+ c₃ < 10^{34}` ✓.
- D: product scaled to exactly ≤ 77 digits; addend quotient `< 10^{34}` ✓.

Scaling `c₃` by `10^k` for `k > 38`: `10^k` exceeds `UInt128`, so compute
`c₃.multipliedFullWidth(by: _exp10(38))` into `_UInt256`, then `&* _exp10(k−38)`
(both k-parts ≤ 38). Product scaling likewise via `_UInt256 &* UInt128`.
Truncations use the doc 01 256-bit ÷10^m helper, capturing `(quo, rem)`.

**No catastrophic cancellation can coincide with truncation** (the design's
load-bearing lemma):

- Regime B (`δ > 43`): scaled addend `S = c₃·10^{43} ≥ 10^{33}·10^{43} =
  10^{76}`; truncated product `< 10^{68 − (δ−43)} ≤ 10^{67}`. Opposite-sign
  difference `≥ 10^{76} − 10^{67}` — the leading digit budges by at most one
  position; the rounding window never descends into the truncated tail. ✓
- Regime D: scaled product `≥ 10^{76}` (it has exactly 77 or 76+1 digits by
  construction: `Dₚ + (77 − Dₚ) = 77`); addend quotient `< 10^{34}`.
  Same argument. ✓
- Deep cancellation (operands within one digit position of each other) can
  therefore only happen in regimes A and C, where **both** operands are held
  exactly, and the difference — however deeply it cancels — is *exact*, so
  correctness is unconditional (`_round` of an exact small intermediate).
  This is why regime C's boundary is `77 − Dₚ` rather than a constant: a
  constant cutoff (say 9) admits small products (`Dₚ` small) whose scaled
  value collides with a *truncated* addend around the same magnitude — the
  truncated digits would then decide the result's leading digits. With the
  `Dₚ`-dependent cutoff, truncation implies a ≥ 42-digit magnitude gap.
  Include this paragraph's reasoning as a code comment; it is not obvious.

## 8.3 Combining, and sticky across subtraction

Same sign (`sₚ == s₃`): 256-bit add (cannot overflow, §8.2 bounds); result
sign `sₚ`; `sticky` = truncation remainder ≠ 0.

Opposite signs: exactly one side may carry a truncation (B: product;
D: addend; A/C: neither). Let the *kept* integer of the truncated side be
`t = quo`, true value `t + φ` with `φ = rem/10^m ∈ [0, 1)`:

| Case | True difference | Intermediate to `_round` | sticky |
| --- | --- | --- | --- |
| no truncation | exact | exact difference | false |
| truncated side is **minuend**, rem ≠ 0 | `(t + φ) − other` | `t − other` | true |
| truncated side is **subtrahend**, rem ≠ 0 | `other − (t + φ)` | `other − t − 1` | true |

The third row is the *borrow trick*: rounding the subtrahend **up** by one
unit turns the deficit into a positive sub-unit excess,
`other − t − 1 + (1 − φ)` with `(1 − φ) ∈ (0, 1)` — exactly doc 01's sticky
invariant. (`rem == 0` rows degrade to exact.) Magnitude comparison to decide
minuend/subtrahend uses the *adjusted* integers (after the borrow), and the
result sign is the sign of the operand supplying the minuend. Exact-zero
difference (equal integers, no sticky): sign per IEEE §6.3 — `+0`, except
`.down` → `−0` (mirror `adding`, Decimal128.swift:1112-1117).

Then a single call:

```swift
return ._round(resultSign, eC, (hi, lo), sticky: sticky, rule)
```

Tininess-before-rounding, subnormals, overflow: all inside `_round` (doc 01
audits the sticky interaction with the tiny path's two-level remainder).

## 8.4 Preferred exponent

IEEE preferred exponent for exact results: `min(Q(x)+Q(y), Q(z))`, i.e.
biased `min(eₚ, E₃)`.

- Regimes A and C align at exactly `min(eₚ, E₃)` — an exact result leaves
  `_round` at the preferred exponent *automatically* (same mechanism that
  makes `adding` IEEE-conformant without post-processing).
- Regimes B and D align higher than the preferred exponent. Results there are
  *usually* inexact (sticky), where preferred exponents don't apply — but a
  truncation with `rem == 0` can produce an **exact** result at a
  non-preferred exponent. Post-process this corner: if no inexactness
  occurred anywhere (no sticky, `_round` stripped nothing — expose via an
  internal `(result, inexact)` return like doc 02's `_divideCore`), pad the
  result toward the preferred exponent: while `e > preferred && c ≤ 10³³−1`:
  `c &*= 10; e &-= 1` (≤ 33 iterations; note this *pads* — the mirror image
  of division's trailing-zero *stripping*, because here the achieved exponent
  is above preferred rather than below).
- [ ] Cohort tests (bitPattern) for: exact B-regime case, e.g.
      `c₃ = 10³³, E₃ = eₚ + 60`, product `3·10^{17}` exactly divisible by the
      truncation modulus… construct concrete vectors with the doc 10
      generator (`mpdecimal`'s `fma` is correctly rounded and
      cohort-faithful).

## 8.5 Special-case and edge tests

- Full 5×5-ish matrix of `{±0, ±finite, ±∞, qNaN, sNaN}` for each of the
  three operands where distinct (the §8.1 ladder linearizes it; enumerate in
  the fixture generator rather than by hand).
- `0×∞ + qNaN` (both operand orders) — pins the implementation-defined
  choice.
- Exact cancellation `fma(x, y, −x·y)` for random x, y with exactly
  representable products → `+0` (`−0` under `.down`).
- Catastrophic cancellation with exact operands:
  `fma(c·10^k, c'·10^j, z)` where `c·c'·10^{k+j}` and `−z` agree in their
  top 60 digits (regime A/C exactness — compare against oracle digit by
  digit).
- Regime boundaries: `δ ∈ {42, 43, 44}`, `|δ| ∈ {77−Dₚ−1, 77−Dₚ, 77−Dₚ+1}`
  with `Dₚ ∈ {1, 34, 68}` — nine families.
- Ties: results landing exactly on a half-ulp with and without sticky
  (sticky must break them), all five rules.
- Subnormal/underflow: product and sum landing in `[10⁻⁶¹⁷⁶, 10⁻⁶¹⁴³)` with
  sticky set — tininess-before-rounding vectors (compare flags columns once
  flags land; values meanwhile).
- Double-rounding trap regression: `fma(a, b, c) != (a*b) + c` witness
  vectors (any case where the product rounds before adding in the naïve
  formulation — the oracle generator finds them by comparing
  `ctx.fma(a,b,c)` against `ctx.add(ctx.multiply(a,b), c)` and keeping
  mismatches; these are the vectors that prove the implementation is
  actually fused).

## 8.6 API surface

The stubs at Decimal128.swift:1429-1457 already define
`addingProduct(_:_:rounding:)` (this design), the mutating `addProduct`
forms, and the rule-defaulted overloads — only the first needs a body.

## 8.7 Open questions / risks

1. The `0×∞ + qNaN` invalid-signaling choice (§8.1.2) — revisit when flags
   become observable; the test pins whichever choice ships.
2. The exact-after-truncation pad (§8.4) depends on `_round` exposing
   exactness; if `_divideCore`-style `(result, inexact)` returns are not
   adopted repo-wide, an equivalent local detection is
   `sticky == false && rem-of-all-truncations == 0 && _round stripped
   nothing` — the last conjunct is the awkward one; prefer the tuple return.
3. Regime B's constant 43 and D's `77 − Dₚ` were chosen for the 2²⁵⁶
   capacity bound with the no-cancellation lemma; if `_UInt256` gains a
   cheap 320-bit sibling the split simplifies. Not worth it now.
4. Performance: two full-width multiplies + up to one 256-bit divide per
   call. Fine for a first implementation; Intel's 384-bit specialization is
   the known optimization if FMA ever becomes hot.
