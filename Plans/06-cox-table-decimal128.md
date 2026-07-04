# 06 — Extending the Cox power-of-ten table to `Decimal128` ↔ `Double`

Analysis of what the Foundation rewrite's conversion machinery
(`Decimal+FloatingPointConversion.swift`: the 696-entry `_table`,
`_cox_uscale`, `_cox_parse`, `_parseWide`, `_Wide`) requires before it can
serve `Decimal128`. Doc 05 deliberately ships without this — its exact
multiword path (`Double → Decimal128`) and truncate/bracket path
(`Decimal128 → Double`) are provable today. This document is the design
record for the table-driven endgame, on the working assumption (to be proven
separately) that **entries are widened to 192 or 256 bits**.

## 6.1 Why Foundation never faced these problems (range analysis)

Exact bounds (computed, not estimated):

| Type | Max magnitude | Min positive |
| --- | --- | --- |
| `Foundation.Decimal` | (2¹²⁸−1)·10¹²⁷ ≈ 10¹⁶⁵·⁵ | 10⁻¹²⁸ |
| `Double` normal | ≈ 1.798·10³⁰⁸ | ≈ 2.225·10⁻³⁰⁸ |
| `Double` incl. subnormal | — | ≈ 4.941·10⁻³²⁴ |
| `Decimal128` | (10³⁴−1)·10⁶¹¹¹ ≈ 10⁶¹⁴⁵ | 10⁻⁶¹⁷⁶ |

`Foundation.Decimal`'s entire range sits strictly inside `Double`'s *normal*
range (10⁻¹²⁸ ≫ 10⁻³⁰⁷·⁷). Hence `__doubleValue` never needs overflow
saturation, never underflows, and never rounds into `Double`'s subnormal
region — three code paths that simply don't exist there and are all mandatory
for `Decimal128`. Its table spans 10⁻³⁴⁸…10³⁴⁷ with margin because the
19-digit truncated significand `d·10^p` keeps `p` within ±(128+39)-ish.

`Decimal128` exceeds `Double`'s range by ~5,800 orders of magnitude on both
ends, so the conversion is dominated by the *out-of-range* cases, and the
table only ever sees the narrow window that survives saturation.

## 6.2 Index range required (after saturation)

For round-to-nearest, nonzero finite `Double` results only arise for
`2⁻¹⁰⁷⁵ < |x| < 2¹⁰²⁴ − 2⁹⁷⁰`, i.e. `10⁻³²³·⁶¹ … 10³⁰⁸·²⁵`.

- **`Decimal128` → `Double`, full-width indexing** (the point of wider
  entries: no 19-digit truncation): input `c·10^q`, `c ∈ [1, 10³⁴)`. The
  in-window `q` range is `q ∈ [−357, 309]` (`q = −357` still reaches
  ≈ 2.47·10⁻³²⁴ with 34-digit `c`). The existing table's lower bound (−348)
  **falls 9 entries short**; upper bound is fine.
- **`Double` → `Decimal128`**: input `m·2^e` scaled by `10^−k` to land the
  34-digit window; `k ∈ [−357, 275]`, i.e. entries `10^p`, `p ∈ [−275, 357]` —
  the existing table's *upper* bound (+347) falls 10 entries short.
- **Unified table**: `p ∈ [−358, 358]` (one guard entry each side) =
  **717 entries**. Storage: 192-bit ⇒ ~17 KB; 256-bit ⇒ ~23 KB (vs. ~11 KB
  today). Note the pleasing symmetry: both directions need almost exactly
  the mirror-image range, so one table serves both.

(If instead the 19-digit truncation is retained for `Decimal128 → Double`,
its `p = q + (digits−19)` stays within `[−342, 309]` and the *existing* range
suffices — that is what doc 05 relies on.)

## 6.3 Saturation constants (exact, precomputed)

All four round-to-nearest decision boundaries are *not representable in 34
digits* (verified: 2¹⁰²⁴−2⁹⁷⁰ is a 309-digit integer with no trailing zeros;
2⁻¹⁰⁷⁵ has a 752-digit significand), so saturation is a **strict comparison
against the 34-digit floor** of each boundary — exact because the largest
representable value ≤ B and the smallest representable value > B differ by
one ulp₃₄ that brackets B:

| Purpose | Boundary B | floor₃₄(B) — becomes a `Decimal128` constant |
| --- | --- | --- |
| RN → ±∞ iff \|x\| > | 2¹⁰²⁴ − 2⁹⁷⁰ | `1.797693134862315807937289714053034e+308` |
| directed-mode gfm test | 2¹⁰²⁴ − 2⁹⁷¹ (= gfm) | `1.797693134862315708145274237317043e+308` |
| RN → ±0 iff \|x\| ≤ | 2⁻¹⁰⁷⁵ | `2.470328229206232720882843964341106e-324` |
| result = ±lnz region | 2⁻¹⁰⁷⁴ (= leastNonzero) | `4.940656458412465441765687928682213e-324` |

(Bit patterns: e.g. row 1 is `c = 1797693134862315807937289714053034`,
biased `E = 275 + 6176 = 6451`. Regenerate all four with the doc 10 fixture
script rather than hand-transcribing.)

Directed rounding needs the second row: e.g. `.towardZero` maps everything
above gfm to gfm, `.up` maps anything above gfm to +∞ but anything below
−gfm to −gfm, etc. The `Double(x)` API in doc 05 is RN-only; a future
`init(_:rounding:)` consumes the full table.

## 6.4 Entry width: the error budget

Uniform framework. A table entry for 10^p is a `w`-bit truncation `pm`
(`10^p·2^σ = pm + δ`, `0 ≤ δ < 1`, `pm ∈ [2^{w−1}, 2^w)`). Scaling an
`n`-bit input `u` computes the exact product `P = u·pm` (`n+w` bits); the
true scaled value is `P + u·δ` with `0 ≤ u·δ < 2^n`. If rounding consumes the
top `T` bits of `P` (output precision + guard/round), the uncertainty
measured in units of the kept lsb is:

```
U = 2^n / 2^(n + w − T) = 2^(T − w)
```

| Direction | n (input) | T (output+2) | U, w=128 | U, w=192 | U, w=256 |
| --- | --- | --- | --- | --- | --- |
| `Decimal128`→`Double` (full-width) | 113 | 56 | 2⁻⁷² | 2⁻¹³⁶ | 2⁻²⁰⁰ |
| `Double`→`Decimal128` (34-digit out) | 53 | 115 | **2⁻¹³** | 2⁻⁷⁷ | 2⁻¹⁴¹ |
| (Foundation's proven case, for scale) | 64 | ~66 | 2⁻⁶² | — | — |

Two conclusions:

1. **The binding constraint is `Double` → `Decimal128`** (34-digit output):
   128-bit entries leave a 2⁻¹³ uncertainty window — three orders of
   magnitude *worse* than the case Cox's proof covers, and far too wide to
   argue no rounding boundary lands inside it. 192-bit entries restore a
   2⁻⁷⁷ margin (better than Foundation's proven 2⁻⁶²); 256-bit gives 2⁻¹⁴¹.
   This is the quantitative justification for the planned widening.
2. `Decimal128` → `Double` full-width is *margin*-comfortable even at
   w = 128 (2⁻⁷²) — its problems are the index range (§6.2) and boundary
   cases (§6.5), not the width. Widening still helps by unifying the proof
   and eliminating the truncate/bracket/exact-fallback structure.

## 6.5 Boundary (exact and tie) cases are confined to a small window

The uncertainty argument can only ever show "the computed guard/sticky bits
are right unless the true value is within U of a rounding boundary". Values
*exactly on* a boundary defeat any finite w; they must be handled
structurally. The saving fact — 2-adic/5-adic valuation confines them:

- `c·10^q = m·2^t` (a `Decimal128` value exactly equal to a `Double`)
  requires odd(c)·5^q < 2⁵³ when `q ≥ 0` ⇒ `q ≤ 22`; and `5^{|q|} | c` when
  `q < 0` ⇒ `|q| ≤ 48` (5⁴⁹ > 10³⁴). Midpoints (`(2m+1)·2^{t−1}`) likewise:
  `q ∈ [−48, 23]`.
- `m·2^e` exactly representable in 34 decimal digits requires
  `e ∈ [−48, ~73]` by the mirrored argument (5^{|e|}·m ≤ 10³⁴−1 for `e < 0`;
  trailing-zero absorption bounded by the 5-valuation of m for `e > 0`).

Inside these windows every candidate value fits exact verification in
`_UInt256` (`c·5⁴⁸ < 2²²⁵`), so the design is: **exact-window fast path in
integer arithmetic; table path everywhere else, where the conversion is
provably inexact** (sticky is definitionally 1, and only the
*near*-boundary worst case bound below is needed).

## 6.6 What remains to prove (the separately-planned work)

1. **Worst-case closeness bound**: for inputs *outside* the exact windows,
   a lower bound on the distance from `c·10^q` (resp. `m·2^e·10^{−k}`) to the
   nearest rounding boundary, to compare against U. This is the
   decimal128 analogue of Cox's lemma (research.swtch.com/fp) and of the
   Lefèvre–Muller worst-case searches; expect either a continued-fraction
   bound per exponent or an exhaustive search over the ~717 exponents ×
   boundary structure. Acceptance criterion: bound > U at the chosen w with
   headroom.
2. **Entry encoding**: Foundation stores `(high, low)` meaning
   `high·2⁶⁴ − low` (high rounded *up*, low negated) so that a two-limb
   refinement is one subtraction. Choose the 3/4-limb generalization (e.g.
   plain truncation, δ ∈ [0,1), refined limb-by-limb) and re-derive
   `_cox_uscale`'s clean-low-bits refinement chain for it: with limbs
   `pm = pm₀·2^{128} + pm₁` (192-bit: 64+128 split is natural for
   `multipliedFullWidth` shapes), compute `u·pm₀`, refine with `u·pm₁` only
   when the guard window is dirty — same structure, one more rung.
3. **Table generation**: extend the doc 10 fixture generator to emit the
   717×(192|256)-bit table from exact big-integer 10^p (Python `int` math),
   with a checksum test that recomputes ~20 random entries at runtime against
   `_UInt256._exp10`-derived values (catches transcription damage).
4. **Subnormal-`Double` rounding positions** interact with U: rounding at
   bit positions coarser than 54 only *shrinks* T, hence shrinks U — no new
   obligation, but record it in the proof.

## 6.7 Bottom line

- Doc 05's exact/bracketing design is correct with today's proven machinery
  and should land first; nothing in this document blocks it.
- The table extension is: **717 entries** spanning `10^±358`, **192-bit
  entries minimum** (2⁻⁷⁷ margin; 256-bit if the worst-case search wants
  headroom), **four saturation constants** (§6.3, exact), an
  **exact-window fast path** for `q ∈ [−48, 23]` / `e ∈ [−48, 73]`, and one
  outstanding **worst-case-closeness proof** before the fast path can replace
  the bracketing path.
