#!/usr/bin/env python3
"""Machine verification for the Decimal128 plan documents.

Transcribes, as faithfully as possible, the algorithms specified in:
  - Plans/01 (sticky-aware `_round` + regrow fix, with the generalized
    tininess ladder for 256-bit intermediates -- see NOTE-TININESS below),
  - Plans/02 (division),
  - Plans/08 (fused multiply-add),
  - Plans/07 (remainder / truncatingRemainder / quantize listings),
and checks them against IEEE decimal128 oracles: CPython `decimal`
(libmpdec, prec=34, Emin=-6143, Emax=6144, clamp=1) for rounded operations,
and exact integer arithmetic for the always-exact remainders (GDA -- hence
libmpdec -- diverges from IEEE 754 when the integer quotient needs > 34
digits; demonstrated in part 5).

NOTE-TININESS: the Swift `_round` as of Decimal128.swift:751 classifies
tininess with shortcuts (`e < -34` => tiny; `e < -68` => below half of
leastNonzeroMagnitude) that are valid only for intermediates < 10^68 (true
for adding/multiplied). Division and FMA intermediates reach ~1.16e77
(2^256), where those shortcuts misclassify. This harness implements the
exact criterion (I < 10^(33-e)); Plans/01 records the generalized constants.

Run: python3 verify_plans.py   (exit 0 iff all checks pass)
"""
import random
import sys
from decimal import (Decimal, Context, Inexact, Overflow, Underflow,
                     InvalidOperation, ROUND_HALF_EVEN, ROUND_HALF_UP,
                     ROUND_DOWN, ROUND_UP, ROUND_FLOOR, ROUND_CEILING)

random.seed(0xDEC1)

PREC, EMIN, EMAX = 34, -6143, 6144
CMAX = 10**34 - 1
BIAS = 6176
EBMAX = 12287              # max biased exponent
RULES = {
    'toNearestOrEven': ROUND_HALF_EVEN,
    'toNearestOrAwayFromZero': ROUND_HALF_UP,
    'towardZero': ROUND_DOWN,
    'awayFromZero': ROUND_UP,
    'down': ROUND_FLOOR,
    'up': ROUND_CEILING,
}
FAILURES = []
CHECKS = [0]

def ctx(rule):
    c = Context(prec=PREC, Emin=EMIN, Emax=EMAX, clamp=1,
                rounding=RULES[rule])
    for t in list(c.traps):
        c.traps[t] = False
    return c

def dec(sign, c, eb):
    """Decimal from (sign, significand, biased exponent)."""
    return Decimal((sign, tuple(int(d) for d in str(c)), eb - BIAS))

def triple(d):
    """(sign, significand, biased exponent) of a finite Decimal, or 'inf'."""
    if d.is_infinite():
        return ('inf', 1 if d < 0 else 0)
    t = d.as_tuple()
    return (t.sign, int(''.join(map(str, t.digits))), t.exponent + BIAS)

def check(cond, label, detail):
    CHECKS[0] += 1
    if not cond:
        FAILURES.append((label, detail))
        if len(FAILURES) <= 25:
            print(f"FAIL [{label}]: {detail}")

# ----------------------------------------------------------------------
# Part 1: transcription of sticky-aware _round (Plans/01).
# Value = I * 10^(e - 6176), plus a fraction in (0, 1) unit iff sticky.
# Returns ((sign, c, eb) | ('inf', sign), flags-set, )
# ----------------------------------------------------------------------

def _away(rule, neg, quo, rem, pow_, rem2, sticky):
    gt_half = rem > pow_ // 2 or (rem == pow_ // 2 and (rem2 > 0 or sticky))
    eq_half = rem == pow_ // 2 and rem2 == 0 and not sticky
    if rule == 'awayFromZero':
        return True
    if rule == 'down':
        return neg
    if rule == 'up':
        return not neg
    if rule == 'towardZero':
        return False
    if rule == 'toNearestOrAwayFromZero':
        return gt_half or eq_half
    if rule == 'toNearestOrEven':
        return gt_half or (eq_half and (quo & 1) == 1)
    raise AssertionError(rule)

def round_sink(neg, e, I, sticky, rule):
    assert I > 0 and I < 1 << 256
    # Nearest-mode sticky is only decidable when digits are stripped below
    # the rounding position; all callers guarantee it (doc 01 precondition).
    flags = set()
    tiny = (33 - e) > 0 and I < 10**(33 - e)     # exact, sticky-safe (strict)
    if tiny:
        if e < 0:
            pow_ = 10**(-e)
            quo, rem = divmod(I, pow_)
            e = 0
        else:
            quo, rem, pow_ = I, 0, 1
        if rem == 0 and not sticky:
            return (neg, quo, e), flags          # exact: no underflow signal
        assert not (pow_ == 1 and rule.startswith('toNearest'))
        if _away(rule, neg, quo, rem, pow_, 0, sticky):
            quo += 1                              # 10^33 = least normal: fine
        return (neg, quo, e), {'inexact', 'underflow'}
    n = max(0, len(str(I)) - 34)
    pow_ = 10**n
    quo, rem = divmod(I, pow_)
    e += n
    inexact = rem > 0 or sticky
    if inexact:
        assert not (pow_ == 1 and rule.startswith('toNearest'))
        if _away(rule, neg, quo, rem, pow_, 0, sticky):
            quo += 1
            if quo == 10**34:
                quo, e = 10**33, e + 1
    if e > EBMAX:                                 # regrow (doc 01 fix), then overflow
        k = e - EBMAX
        if k <= 33 and quo <= CMAX // 10**k:
            quo, e = quo * 10**k, EBMAX
        else:
            big = {'awayFromZero': True, 'toNearestOrEven': True,
                   'toNearestOrAwayFromZero': True, 'towardZero': False,
                   'down': neg, 'up': not neg}[rule]
            if big:
                return ('inf', neg), {'overflow', 'inexact'}
            return (neg, CMAX, EBMAX), {'overflow', 'inexact'}
    return (neg, quo, e), ({'inexact'} if inexact else set())

# ----------------------------------------------------------------------
# Part 2: division (Plans/02) -- finite nonzero operands only.
# ----------------------------------------------------------------------

def plan_divide(s1, c1, e1, s2, c2, e2, rule):
    neg = s1 != s2
    pref = e1 - e2 + BIAS
    if c2 == 1:
        res, flags = round_sink(neg, pref, c1, False, rule)
    else:
        lzc = 128 - (c1 | 1).bit_length()
        shift = (lzc * 1233) >> 12
        scaled = c1 * 10**shift
        if scaled <= ((1 << 128) - 1) // 10:
            shift += 1
            scaled *= 10
        Q, r2 = divmod(scaled * 10**38, c2)
        assert Q < 1 << 256
        res, flags = round_sink(neg, pref - shift - 38, Q, r2 != 0, rule)
    if res[0] != 'inf' and 'inexact' not in flags:
        sg, c, e = res
        # Strip toward the preferred exponent, but never beyond the largest
        # encodable exponent: IEEE selects the cohort member whose exponent
        # is closest to preferred AMONG THOSE THAT EXIST (caught by this
        # harness: an unbounded strip walks past 12287, undoing the regrow).
        while e < min(pref, EBMAX) and c % 10 == 0 and c > 0:
            c //= 10
            e += 1
        res = (sg, c, e)
    return res, flags

def oracle_bin(op, s1, c1, e1, s2, c2, e2, rule):
    c = ctx(rule)
    r = getattr(c, op)(dec(s1, c1, e1), dec(s2, c2, e2))
    fl = set()
    if c.flags[Inexact]: fl.add('inexact')
    if c.flags[Overflow]: fl.add('overflow')
    if c.flags[Underflow]: fl.add('underflow')
    return triple(r), fl

def rand_operand():
    c = random.choice([
        1, 2, 5, 9, 10**random.randint(0, 33),
        10**random.randint(1, 34) - 1, CMAX,
        random.randint(1, CMAX)])
    e = random.choice([
        0, 1, 5, BIAS, BIAS + 1, EBMAX, EBMAX - 40,
        random.randint(0, EBMAX)])
    return random.randint(0, 1), min(c, CMAX), e

def test_division(n_per_rule=1500):
    for rule in RULES:
        for _ in range(n_per_rule):
            a, b = rand_operand(), rand_operand()
            got, gf = plan_divide(*a, *b, rule)
            want, wf = oracle_bin('divide', *a, *b, rule)
            check(got == want and gf == wf, 'divide',
                  f"{a}/{b} {rule}: got {got}{gf} want {want}{wf}")
    # Cohort pins from Plans/02 (10/2 preferred-exponent worked example).
    got, _ = plan_divide(0, 1, BIAS + 1, 0, 2, BIAS, 'toNearestOrEven')
    check(got == (0, 5, BIAS), 'divide-pref', f"10/2 -> {got}")
    # Fast path cohort: x / 10^k.
    got, _ = plan_divide(0, 123, BIAS, 0, 1, BIAS + 40, 'toNearestOrEven')
    want, _ = oracle_bin('divide', 0, 123, BIAS, 0, 1, BIAS + 40,
                         'toNearestOrEven')
    check(got == want, 'divide-pow10', f"got {got} want {want}")

# ----------------------------------------------------------------------
# Part 3: the regrow bug (Plans/01 sec 1.2) demonstrated via multiply.
# ----------------------------------------------------------------------

def test_regrow():
    # 1e6111 (c=1, eb=12287) x 10 (c=1, eb=6177): representable product.
    got, gf = round_sink(False, 12287 + 6177 - BIAS, 1, False,
                         'toNearestOrEven')
    want, wf = oracle_bin('multiply', 0, 1, 12287, 0, 1, 6177,
                          'toNearestOrEven')
    check(got == (False, 10, EBMAX) and triple_eq(got, want) and gf == wf,
          'regrow', f"got {got}{gf} want {want}{wf}")
    # Genuine overflow must still overflow.
    got, gf = round_sink(False, 12287 + 12287 - BIAS, CMAX * CMAX, False,
                         'toNearestOrEven')
    check(got == ('inf', False) and 'overflow' in gf, 'regrow-ovf',
          f"got {got}{gf}")
    # Random sweep of multiply through the sink (also exercises strip/tie).
    for rule in RULES:
        for _ in range(1200):
            a, b = rand_operand(), rand_operand()
            (s1, c1, e1), (s2, c2, e2) = a, b
            got, gf = round_sink(s1 != s2, e1 + e2 - BIAS, c1 * c2, False,
                                 rule)
            want, wf = oracle_bin('multiply', *a, *b, rule)
            check(triple_eq(got, want) and gf == wf, 'multiply',
                  f"{a}*{b} {rule}: got {got}{gf} want {want}{wf}")

def triple_eq(got, want):
    if got[0] == 'inf':
        return want[0] == 'inf' and got[1] == want[1]
    return (int(got[0]), got[1], got[2]) == want

# ----------------------------------------------------------------------
# Part 4: fused multiply-add (Plans/08) -- finite operands, product and
# addend nonzero (specials and zero cases delegate per the doc).
# ----------------------------------------------------------------------

def plan_fma(s1, c1, e1, s2, c2, e2, s3, c3, e3, rule):
    sp = s1 != s2
    P = c1 * c2
    ep = e1 + e2 - BIAS
    pref = min(ep, e3)
    if c3 == 0:
        res, flags = round_sink(sp, ep, P, False, rule)
        return _pad_exact(res, flags, pref), flags
    delta = e3 - ep
    Dp = len(str(P))
    stickyP = stickyS = 0
    if delta >= 0:
        if delta <= 43:                       # regime A
            eC, Pv, S = ep, P, c3 * 10**delta
        else:                                 # regime B
            eC = e3 - 43
            S = c3 * 10**43
            Pv, stickyP = divmod(P, 10**(eC - ep))
    else:
        k = min(-delta, 77 - Dp)
        if -delta <= 77 - Dp:                 # regime C
            eC, Pv, S = e3, P * 10**(-delta), c3
        else:                                 # regime D
            eC = ep - k
            Pv = P * 10**k
            S, stickyS = divmod(c3, 10**(eC - e3))
    assert Pv < 1 << 256 and S < 1 << 256
    if sp == s3:
        I, sticky, sign = Pv + S, stickyP > 0 or stickyS > 0, sp
        assert I < 1 << 256
    else:
        if Pv > S:
            I, sign = Pv - S, sp
            if stickyS:                       # subtrahend truncated: borrow
                I -= 1
            sticky = stickyP > 0 or stickyS > 0
        elif S > Pv:
            I, sign = S - Pv, s3
            if stickyP:
                I -= 1
            sticky = stickyP > 0 or stickyS > 0
        else:
            assert stickyP == 0 and stickyS == 0, "lemma: no trunc+cancel"
            e0 = min(max(pref, 0), EBMAX)
            return (rule == 'down', 0, e0), set()
    res, flags = round_sink(sign, eC, I, sticky, rule)
    return _pad_exact(res, flags, pref), flags

def _pad_exact(res, flags, pref):
    if res[0] != 'inf' and 'inexact' not in flags:
        sg, c, e = res
        while e > max(pref, 0) and c <= 10**33 - 1 and c > 0:
            c *= 10
            e -= 1
        res = (sg, c, e)
    return res

def oracle_fma(a, b, z, rule):
    c = ctx(rule)
    r = c.fma(dec(*a), dec(*b), dec(*z))
    fl = set()
    if c.flags[Inexact]: fl.add('inexact')
    if c.flags[Overflow]: fl.add('overflow')
    if c.flags[Underflow]: fl.add('underflow')
    return triple(r), fl

def test_fma(n_per_rule=1200):
    def one(a, b, z, rule):
        got, gf = plan_fma(*a, *b, *z, rule)
        want, wf = oracle_fma(a, b, z, rule)
        ok = (triple_eq(got, want) if got[2:] != () or True else False) \
            and gf == wf
        check(triple_eq(got, want) and gf == wf, 'fma',
              f"{a},{b},{z} {rule}: got {got}{gf} want {want}{wf}")
    for rule in RULES:
        for _ in range(n_per_rule):
            a, b = rand_operand(), rand_operand()
            # Half the time, target a regime boundary for the addend.
            if random.random() < 0.5:
                ep = a[2] + b[2] - BIAS
                Dp = len(str(a[1] * b[1]))
                dl = random.choice([0, 1, 42, 43, 44, 60, 5000,
                                    -1, -(77 - Dp) + 1, -(77 - Dp),
                                    -(77 - Dp) - 1, -40, -5000])
                e3 = ep + dl
                if not (0 <= e3 <= EBMAX):
                    e3 = random.randint(0, EBMAX)
                z = (random.randint(0, 1), rand_operand()[1], e3)
            else:
                z = rand_operand()
            one(a, b, z, rule)
        # Exact cancellation sign: fma(x, y, -(x*y)) == +0 (-0 under .down).
        for _ in range(50):
            a, b = rand_operand(), rand_operand()
            if a[1] * b[1] > CMAX:
                continue
            ep = a[2] + b[2] - BIAS
            if not (0 <= ep <= EBMAX):
                continue
            z = (1 - (a[0] ^ b[0]), a[1] * b[1], ep)
            one(a, b, z, rule)

# ----------------------------------------------------------------------
# Part 5: remainder / truncatingRemainder (Plans/07 listing) against an
# exact-integer IEEE oracle; GDA-divergence demonstration.
# ----------------------------------------------------------------------

def plan_remainder(s1, c1, e1, s2, c2, e2, nearest):
    # Transcription of _remainder(dividingBy:nearest:) main path.
    if e1 == e2:
        q, rt = divmod(c1, c2)
        odd = q & 1 == 1
        bH, bL = 0, c2
    elif e1 > e2:
        delta = e1 - e2
        q, acc = 0, c1 % c2
        while delta > 0:
            s = min(delta, 38)
            prod = acc * 10**s
            assert prod // (1 << 128) < c2      # dividingFullWidth precond.
            q, acc = divmod(prod, c2)
            assert q < 1 << 128
            delta -= s
        rt, odd = acc, q & 1 == 1
        bH, bL = 0, c2
    else:
        k = e2 - e1
        if k > 34:
            return (s1, c1, e1)                 # early return: x unchanged
        b = c2 * 10**k
        bH, bL = b >> 128, b & ((1 << 128) - 1)
        if bH != 0 or c1 < bL:
            rt, odd = c1, False
        else:
            q, rt = divmod(c1, bL)
            odd = q & 1 == 1
    e = min(e1, e2)
    if nearest:
        twice = rt << 1
        if bH == 0 and (twice > bL or (twice == bL and odd)):
            return (1 - s1, bL - rt, e)
    return (s1, rt, e)

def ieee_rem(s1, c1, e1, s2, c2, e2, nearest):
    qm = min(e1, e2)
    A, B = c1 * 10**(e1 - qm), c2 * 10**(e2 - qm)
    nt, rt = divmod(A, B)
    if nearest and (2 * rt > B or (2 * rt == B and nt & 1)):
        m, sg = B - rt, 1 - s1
    else:
        m, sg = rt, s1
    if m == 0:
        sg = s1
    assert m <= CMAX, "representability lemma violated?!"
    return (sg, m, qm)

def test_remainder(n=6000):
    for _ in range(n):
        a, b = rand_operand(), rand_operand()
        if b[1] == 0:
            continue
        for nearest in (True, False):
            got = plan_remainder(*a, *b, nearest)
            want = ieee_rem(*a, *b, nearest)
            check(got == want, 'remainder',
                  f"{a} rem {b} nearest={nearest}: got {got} want {want}")
    # Engineered ties where quotient parity decides (2*rt == b).
    for _ in range(400):
        c2 = random.randrange(2, CMAX, 2)       # even divisor
        half = c2 // 2
        nt = random.randint(1, 10**30)
        e2 = random.randint(0, 200) + BIAS
        # dividend = nt * c2 + half at same exponent, if it fits
        c1 = nt * c2 + half
        if c1 > CMAX:
            continue
        a, b = (0, c1, e2), (0, c2, e2)
        got = plan_remainder(*a, *b, True)
        want = ieee_rem(*a, *b, True)
        check(got == want, 'remainder-tie',
              f"{a} rem {b}: got {got} want {want} (nt odd={nt & 1})")
    # GDA divergence demo (documented in Plans/07 sec 1.1): mpdecimal
    # signals invalid when the integer quotient needs > 34 digits; IEEE
    # defines the result and our plan computes it.
    c = ctx('toNearestOrEven')
    r = c.remainder_near(Decimal('1E+100'), Decimal(7))
    check(r.is_nan() and c.flags[InvalidOperation], 'gda-divergence',
          f"mpdecimal remainder_near(1E100, 7) = {r} (expected NaN+invalid)")
    got = plan_remainder(0, 1, 100 + BIAS, 0, 7, BIAS, True)
    want = ieee_rem(0, 1, 100 + BIAS, 0, 7, BIAS, True)
    check(got == want, 'gda-divergence-ieee',
          f"plan {got} vs exact {want}")

# ----------------------------------------------------------------------
# Part 6: quantize (Plans/07 sec 4.3 listing) against mpdecimal.
# ----------------------------------------------------------------------

def plan_quantize(s1, c1, e1, s2, c2, e2, rule):
    if e1 >= e2:
        n = e1 - e2
        if len(str(c1)) + n > 34:
            return None, {'invalid'}            # NaN
        return (s1, c1 * 10**n, e2), set()
    n = e2 - e1
    if n > 34:
        away = {'awayFromZero': True, 'down': s1 == 1, 'up': s1 == 0,
                'toNearestOrAwayFromZero': False, 'toNearestOrEven': False,
                'towardZero': False}[rule]
        return (s1, 1 if away else 0, e2), {'inexact'}
    pow_ = 10**n
    quo, rem = divmod(c1, pow_)
    if rem == 0:
        return (s1, quo, e2), set()
    away = _away(rule, s1 == 1, quo, rem, pow_, 0, False)
    return (s1, quo + (1 if away else 0), e2), {'inexact'}

def test_quantize(n=5000):
    for rule in RULES:
        for _ in range(n // 6):
            a, b = rand_operand(), rand_operand()
            got, gf = plan_quantize(*a, *b, rule)
            c = ctx(rule)
            r = c.quantize(dec(*a), dec(*b))
            if r.is_nan():
                check(got is None and 'invalid' in gf, 'quantize',
                      f"{a} q {b} {rule}: got {got}{gf} want NaN")
            else:
                wf = {'inexact'} if c.flags[Inexact] else set()
                want = triple(r)
                check(got is not None and
                      (int(got[0]), got[1], got[2]) == want and gf == wf,
                      'quantize',
                      f"{a} q {b} {rule}: got {got}{gf} want {want}{wf}")

# ----------------------------------------------------------------------

if __name__ == '__main__':
    test_regrow()
    test_division()
    test_fma()
    test_remainder()
    test_quantize()
    print(f"\n{CHECKS[0]} checks, {len(FAILURES)} failures")
    sys.exit(1 if FAILURES else 0)
