// Conversion between binary and decimal formats using Cox's unrounded scaling:
// https://research.swtch.com/fp
//
// For an "unrounded" value `u`, `u >> 2` is the integer part, bit 1 is the half
// bit, and bit 0 is the sticky bit--i.e., the OR of all lower bits.
//
// See the original reference (and accompanying proof) for details.
@frozen
public enum _Cox { }

@available(anyAppleOS 26.0, *)
extension _Cox {
  @inlinable
  internal static func _reconstruct_pow10(
    _ x: Int
  ) -> (high: UInt128, low: UInt128) {
    precondition(x >= -4999 && x <= 4999, "Unsupported power of ten.")
    // The 'coarse' table includes a block of entries for exponents below -357
    // followed by a block of entries for exponents above 357.
    let i = x < -357 ? x &+ 5005 : x &- 358 &+ 4648
    let (q, r) = i.quotientAndRemainder(dividingBy: 56)
    var (hi, mid, lo) = unsafe _cox_coarse_pow10[unchecked: q]
    let fine = unsafe _cox_direct_pow10[unchecked: r &+ 357].0

    // Multiply.
    let a = lo.multipliedFullWidth(by: fine)
    let b = mid.multipliedFullWidth(by: fine)
    let c = hi.multipliedFullWidth(by: fine)
    // Form the positive correction product `((mid << 128) + lo) * fine`.
    let carry: Bool
    (lo, carry) = b.low.addingReportingOverflow(a.high)
    mid = b.high &+ (carry ? 1 : 0)
    // Subtract the correction product from `(hi * fine) << 256`.
    let borrow1 = a.low != 0
    let borrow2 = lo != 0 || borrow1
    lo = (0 &- lo) &- (borrow1 ? 1 : 0)
    let borrow3: Bool
    (mid, borrow3) = c.low.subtractingReportingOverflow(mid)
    let borrow4: Bool
    (mid, borrow4) = mid.subtractingReportingOverflow(borrow2 ? 1 : 0)
    hi = c.high &- (borrow3 || borrow4 ? 1 : 0)

    // The 511- or 512-bit product is `(hi, mid, lo, 0 &- a.low)`.
    // Extract its leading 256 bits.
    let upper: UInt128
    let lower: UInt128
    let sticky: Bool
    if hi & (1 &<< 127) != 0 {
      upper = hi
      lower = mid
      sticky = lo != 0 || a.low != 0
    } else {
      upper = hi &<< 1 | mid &>> 127
      lower = mid &<< 1 | lo &>> 127
      sticky = lo & ((1 &<< 127) &- 1) != 0 || a.low != 0
    }
    return (
      upper &+ ((lower != 0 || sticky) ? 1 : 0),
      (0 &- lower) &- (sticky ? 1 : 0))
  }

  @inlinable
  @inline(always)
  internal static func pow10(_ x: Int) -> (high: UInt128, low: UInt128) {
    if x >= -357 && x <= 357 {
      return unsafe _cox_direct_pow10[unchecked: x &+ 357]
    }
    return _reconstruct_pow10(x)
  }

  // Computes `floor(log2(10**x))` throughout the asserted range.
  @inlinable
  @inline(always)
  internal static func log2pow10(_ x: Int) -> Int {
    assert((-6176...6111).contains(x))
    return Int((Int64(x) &* 55732705) &>> 24)
  }

  // Computes `floor(log10(2**x))` throughout the asserted range.
  @inlinable
  @inline(always)
  internal static func log10pow2(_ x: Int) -> Int {
    assert((-16495...16384).contains(x))
    return Int((Int64(x) &* 20201781) &>> 26)
  }

  // Computes `floor(log10(3/4 * 2**x))` throughout the asserted range.
  @inlinable
  @inline(always)
  internal static func skewed(_ x: Int) -> Int {
    assert((-16495...16384).contains(x)) // (These are overly generous bounds.)
    return Int((Int64(x) &* 20201781 &- 8384497) &>> 26)
  }

  @inlinable
  @inline(always)
  internal static func round(_ u: UInt128) -> UInt128 {
    (u &+ 1 &+ ((u &>> 2) & 1)) &>> 2
  }

  @inlinable
  @inline(always)
  internal static func round(
    isSignMinus: Bool,
    _ u: UInt128,
    _ rule: _DecimalFloatingPointRoundingRule
  ) -> UInt128 {
    let q = u &>> 2
    return q &+
      (Decimal128._roundsAway(
        isSignMinus: isSignMinus,
        significand: q,
        digit: u & 2 != 0 ? 5 : 0,
        sticky: u & 1 != 0,
        rule
      ) ? 1 : 0)
  }

  @inlinable
  internal static func trimZeros(_ x: UInt128, _ p: Int) -> (UInt128, Int) {
    // See also `Decimal128._select`.
    assert(x != 0)
    guard var x = x._quotientIfExactDividingBy10() else {
      return (x, p)
    }
    var p = p &+ 1
    if let q = x._quotientIfExactDividingBy1e32() {
      x = q
      p &+= 32
    }
    if let q = x._quotientIfExactDividingBy1e16() {
      x = q
      p &+= 16
    }
    if let q = x._quotientIfExactDividingBy1e8() {
      x = q
      p &+= 8
    }
    if let q = x._quotientIfExactDividingBy10000() {
      x = q
      p &+= 4
    }
    if let q = x._quotientIfExactDividingBy100() {
      x = q
      p &+= 2
    }
    if let q = x._quotientIfExactDividingBy10() {
      x = q
      p &+= 1
    }
    return (x, p)
  }

  @inlinable
  @inline(always)
  internal static func prescale(
    _ e: Int,
    _ p: Int
  ) -> (pm: (high: UInt128, low: UInt128), s: Int) {
    return (pow10(p), -(e &+ log2pow10(p) &+ 3))
  }

  @inlinable
  internal static func uscale(
    _ x: UInt128,
    _ scaler: (pm: (high: UInt128, low: UInt128), s: Int)
  ) -> UInt128 {
    if scaler.s >= 128 { return 1 }
    var hi: UInt128
    let mid: UInt128
    (hi, mid) = x.multipliedFullWidth(by: scaler.pm.high)
    var sticky = true
    if hi & ((1 &<< scaler.s) &- 1) == 0 {
      // See Cox's discussion for justification of this approach.
      let (correction, _) = x.multipliedFullWidth(by: scaler.pm.low)
      sticky = mid &- correction > 1
      if mid < correction { hi &-= 1}
    }
    return (hi &>> scaler.s) | (sticky ? 1 : 0)
  }

  @inlinable
  internal static func fixed(
    width: Int,
    isSignMinus: Bool,
    _ m: UInt128,
    _ e: Int,
    _ rule: _DecimalFloatingPointRoundingRule
  ) -> (d: UInt128, p: Int, inexact: Bool) {
    assert(m & (1 &<< 127) != 0 && (1...34).contains(width))
    var p = width &- 1 &- log10pow2(e &+ 127)
    var u = uscale(m, prescale(e, p))
    if unsafe round(
      isSignMinus: isSignMinus, u, rule
    ) >= ._exp10[unchecked: width] {
      let (q, r) = u.quotientAndRemainder(dividingBy: 10)
      u = q | (r != 0 ? 1 : 0) | (u & 1)
      p &-= 1
    }
    return (round(isSignMinus: isSignMinus, u, rule), -p, u & 3 != 0)
  }

  @inlinable
  internal static func short(
    _ m: UInt128,
    _ e: Int,
    precision: Int,
    emin: Int
  ) -> (d: UInt128, p: Int, inexact: Bool?) {
    assert(m & (1 &<< 127) != 0 && (2...113).contains(precision))
    let tiny = emin &- (precision &- 1)
    let z = max(128 &- precision, tiny &- e)
    assert((15...127).contains(z))
    let p: Int
    let lo: UInt128
    let half: UInt128 = 1 &<< (z &- 1)
    if m == 1 &<< 127 && e &+ 127 > emin {
      p = -skewed(e &+ z)
      lo = m &- (half &>> 1)
    } else {
      p = -log10pow2(e &+ z)
      lo = m &- half
    }
    let hi = m &+ half
    let odd = (m &>> z) & 1
    let (pm, s) = prescale(e, p)
    let ulo = lo & (1 &<< 127) != 0
      ? uscale(lo, (pm, s))
      : uscale(lo &<< 1, (pm, s &+ 1))
    let dlo = (ulo &+ odd &+ 3) &>> 2
    let dhi = (uscale(hi, (pm, s)) &- odd) &>> 2

    var d = dhi / 10
    if d &* 10 >= dlo {
      let (c, e) = trimZeros(d, -(p &- 1))
      return (c, e, nil)
    }
    d = dlo
    if dlo < dhi {
      let u = uscale(m, (pm, s))
      d = round(u)
      return (d, -p, u & 3 != 0)
    }
    return (d, -p, nil)
  }

  @inlinable
  internal static func parse<T: BinaryFloatingPoint>(
    _ d: UInt128,
    _ p: Int,
    precision: Int,
    emin: Int,
    emax: Int
  ) -> (magnitude: T, flags: DecimalFloatingPointStatusFlags) {
    assert(d > 0 && d < ._1e34)
    assert((2...113).contains(precision))
    let tiny = emin &- (precision &- 1)
    if p < log10pow2(tiny &- 1) &- 33 {
      return (0, .underflowInexact)
    }
    if p > log10pow2(emax &+ 1) {
      return (.infinity, .overflowInexact)
    }
    let clz = d.leadingZeroBitCount
    let lp = log2pow10(p)
    var e = min(-tiny, precision &- 128 &+ clz &- lp)
    var u = uscale(d &<< clz, prescale(e &- clz, p))
    let isTiny = e == -tiny && u < ((1 as UInt128) &<< (precision &+ 1))
    if u >= ((1 as UInt128) &<< (precision &+ 2)) &- 2 {
      u = (u &>> 1) | (u & 1)
      e &-= 1
    }
    let m = round(u)
    let clz_ = m.leadingZeroBitCount
    let exponent = 127 &- clz_ &- e
    if m != 0 && exponent > emax {
      return (.infinity, .overflowInexact)
    }
    let fraction =
      exponent < emin ? m : (m &<< (clz_ &+ 1)) &>> (129 &- precision)
    let magnitude = T(
      sign: .plus,
      exponentBitPattern: .init(max(exponent &+ emax, 0)),
      significandBitPattern: .init(fraction))
    let flags: DecimalFloatingPointStatusFlags =
      u & 3 == 0 ? [] : (isTiny ? .underflowInexact : .inexact)
    return (magnitude, flags)
  }
}
