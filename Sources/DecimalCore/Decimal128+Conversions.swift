@available(anyAppleOS 26.0, *)
extension Decimal128 {
  @inlinable
  internal init<T: BinaryInteger>(
    _ source: T,
    _rounding rule: _DecimalFloatingPointRoundingRule,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) {
    let magnitude = source.magnitude
    let isSignMinus = source < (0 as T)

    if magnitude.bitWidth < 113 || magnitude < T.Magnitude(UInt128._1e34) {
      bitPattern = UInt128(truncatingIfNeeded: magnitude)
      bitPattern |= Self().bitPattern
      if isSignMinus { negate() }
      return
    }
    if let c = UInt128(exactly: magnitude) {
      let n = c._commonLogarithm &- 33
      var e = 6176 &+ n
      var (q, r) = c._quotientAndRemainder(dividingBy1e: n)
      if r != 0 {
        let half: UInt128 = unsafe ._exp10[unchecked: n] &>> 1
        if Self._roundsAway(
          isSignMinus: isSignMinus,
          significand: q,
          digit: r >= half ? 5 : 0,
          sticky: r != half,
          rule
        ) {
          if q == ._1e34 &- 1 {
            q = ._1e33
            e &+= 1
          } else {
            q &+= 1
          }
        }
        _signal(.inexact, into: &flags)
      }
      let abs = Self(bitPattern: UInt128(truncatingIfNeeded: e) &<< 113 | q)
      self = isSignMinus ? -abs : abs
      return
    }

    // Determine bit width, excluding leading zero bits, using public APIs.
    var bits = ((magnitude.bitWidth &- 1) / UInt.bitWidth) * UInt.bitWidth
    var highWord = UInt(truncatingIfNeeded: magnitude >> bits)
    while highWord == 0 {
      bits &-= UInt.bitWidth
      highWord = UInt(truncatingIfNeeded: magnitude >> bits)
    }
    bits += (UInt.bitWidth &- highWord.leadingZeroBitCount)

    guard bits <= 20414 else {
      self = ._overflow(isSignMinus: isSignMinus, rule, &flags)
      return
    }
    // Underestimate floor(log10), off by at most one, then choose `k`, a
    // multiple of 32 such that `magnitude / 10**k` retains 35 to 67 digits.
    let underestimate = (1233 &* (bits &- 1)) &>> 12
    let k = (underestimate &- 34) & ~31
    // Build `5**k` from `5**32` using exponentiation by squaring.
    var n = k &>> 5 // `k / 32`.
    var divisor: T.Magnitude = 1
    var power = T.Magnitude(UInt128._exp10[32] &>> 32) // `5**32`.
    while n != 0 {
      if n & 1 != 0 { divisor *= power }
      n &>>= 1
      if n != 0 { power *= power }
    }
    // Compute `magnitude / 10**k = (magnitude >> k) / 5**k`.
    let (q, r) = (magnitude >> k).quotientAndRemainder(dividingBy: divisor)
    let sticky = r != 0 || magnitude.trailingZeroBitCount < k
    self = ._pack(
      isSignMinus: isSignMinus,
      biasedExponent: 6176 &+ k,
      significand:
        (UInt128(truncatingIfNeeded: q >> 128), UInt128(truncatingIfNeeded: q)),
      sticky: sticky,
      preferredBiasedExponent: 6176,
      rule,
      &flags)
  }

  @inline(always)
  public init<T: BinaryInteger>(_ source: T) {
    var flags: DecimalFloatingPointStatusFlags = []
    self.init(source, _rounding: .toNearestOrEven, &flags)
  }

  @inline(always)
  public init<T: BinaryInteger>(
    _ source: T,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) {
    self.init(source, _rounding: .toNearestOrEven, &flags)
  }

  @inline(always)
  public init<T: BinaryInteger>(
    _ source: T,
    rounding rule: FloatingPointRoundingRule
  ) {
    var flags: DecimalFloatingPointStatusFlags = []
    self.init(source, _rounding: .init(rule), &flags)
  }

  @inline(always)
  public init<T: BinaryInteger>(
    _ source: T,
    rounding rule: FloatingPointRoundingRule,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) {
    self.init(source, _rounding: .init(rule), &flags)
  }
}

@available(anyAppleOS 26.0, *)
extension BinaryFloatingPoint {
  @inlinable
  @inline(always)
  internal static var _format: (precision: Int, emin: Int, emax: Int) {
    let precision = Self.significandBitCount &+ 1
    guard
      precision > 1 && precision <= 113,
      let tiny = Int(exactly: Self.leastNonzeroMagnitude.exponent),
      let emin = Int(exactly: Self.leastNormalMagnitude.exponent),
      let emax = Int(exactly: Self.greatestFiniteMagnitude.exponent),
      tiny == emin &- (precision &- 1) && emin >= -16382 && emax <= 16383
    else {
      preconditionFailure("Unsupported binary floating-point format.")
    }
    return (precision, emin, emax)
  }

  @inlinable
  internal func _unpack(precision: Int) -> (m: UInt128, e: Int) {
    assert(isFinite && !isZero)
    assert(precision == Self.significandBitCount &+ 1)
    let shift = 128 &- precision
    let m = 1 &<< 127 | (UInt128(significand.significandBitPattern) &<< shift)
    return (m, Int(exponent) &- 127)
  }
}

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

  @inlinable
  @inline(always)
  internal static func log2pow10(_ x: Int) -> Int {
    assert((-6176...6111).contains(x))
    return Int((Int64(x) &* 55732705) &>> 24)
  }

  @inlinable
  @inline(always)
  internal static func log10pow2(_ x: Int) -> Int {
    assert((-16495...16384).contains(x))
    return Int((Int64(x) &* 20201781) &>> 26)
  }

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
    _ m: UInt128,
    _ e: Int,
  ) -> (d: UInt128, p: Int, inexact: Bool) {
    assert(m & (1 &<< 127) != 0 && (1...34).contains(width))
    var p = width &- 1 &- log10pow2(e &+ 127)
    var u = uscale(m, prescale(e, p))
    if unsafe round(u) >= ._exp10[unchecked: width] {
      let (q, r) = u.quotientAndRemainder(dividingBy: 10)
      u = q | (r != 0 ? 1 : 0) | (u & 1)
      p &-= 1
    }
    return (round(u), -p, u & 3 != 0)
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
    assert(T._format == (precision, emin, emax))
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

@available(anyAppleOS 26.0, *)
extension Decimal128 {
  @inlinable
  public init<T: BinaryFloatingPoint>(
    nearest source: T,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) {
    let format = T._format
    if source.isNaN {
      if source.isSignalingNaN { _signal(.invalid, into: &flags) }
      self = source.sign == .minus ? -.nan : .nan
      return
    }
    if source.isInfinite {
      self = source.sign == .minus ? -.infinity : .infinity
      return
    }
    if source.isZero {
      self = source.sign == .minus ? -Self() : Self()
      return
    }
    let (m, e) = source._unpack(precision: format.precision)
    var d: UInt128
    let p: Int
    let inexact: Bool
    (d, p, inexact) = _Cox.fixed(width: 34, m, e)
    var biasedExponent = p &+ 6176
    if inexact {
      _signal(.inexact, into: &flags)
    } else {
      Self._select(
        biasedExponent: &biasedExponent,
        nonzeroSignificand: &d,
        boundedPreferredBiasedExponent: 6176)
    }
    self.init(
      sign: source.sign,
      exponentBitPattern: UInt(biasedExponent),
      significandBitPattern: d)
  }

  @inline(always)
  public init<T: BinaryFloatingPoint>(nearest source: T) {
    var flags: DecimalFloatingPointStatusFlags = []
    self.init(nearest: source, &flags)
  }

  @inline(always)
  public init?<T: BinaryFloatingPoint>(exactly source: T) {
    if source.isNaN { return nil } 
    var flags: DecimalFloatingPointStatusFlags = []
    self.init(nearest: source, &flags)
    if flags.contains(.inexact) { return nil }
  }

  @inlinable
  internal init?<T: BinaryFloatingPoint>(
    _shortest source: T,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) {
    let format = T._format
    guard source.isFinite && !source.isZero else {
      self.init(nearest: source, &flags)
      return
    }
    let (m, e) = source._unpack(precision: format.precision)
    let (d, p, inexact) =
      _Cox.short(m, e, precision: format.precision, emin: format.emin)
    guard d < ._1e34 && p >= -6176 && p <= 6111 else { return nil }
    if let inexact {
      if inexact { _signal(.inexact, into: &flags) }
    } else {
      // This is a somewhat costly check.
      let u = _Cox.uscale(m, _Cox.prescale(e, -p))
      if u != d &<< 2 { _signal(.inexact, into: &flags) }
    }
    self.init(
      sign: source.sign,
      exponentBitPattern: UInt(p &+ 6176),
      significandBitPattern: d)
  }

  @inline(always)
  public init(shortest source: Float16) {
    var flags: DecimalFloatingPointStatusFlags = []
    self.init(_shortest: source, &flags)!
  }

  @inline(always)
  public init(
    shortest source: Float16,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) {
    self.init(_shortest: source, &flags)!
  }

  @inline(always)
  public init(shortest source: Float) {
    var flags: DecimalFloatingPointStatusFlags = []
    self.init(_shortest: source, &flags)!
  }

  @inline(always)
  public init(
    shortest source: Float,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) {
    self.init(_shortest: source, &flags)!
  }

  @inline(always)
  public init(shortest source: Double) {
    var flags: DecimalFloatingPointStatusFlags = []
    self.init(_shortest: source, &flags)!
  }

  @inline(always)
  public init(
    shortest source: Double,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) {
    self.init(_shortest: source, &flags)!
  }
}

@available(anyAppleOS 26.0, *)
extension BinaryFloatingPoint {
  @inlinable
  public init(nearest source: Decimal128) {
    let format = Self._format
    guard source._isFiniteNonzero else {
      if source.isNaN {
        self = source._isSignMinus ? -.nan : .nan
        return
      }
      if source.isInfinite {
        self = source._isSignMinus ? -.infinity : .infinity
        return
      }
      self = source._isSignMinus ? -.zero : .zero
      return
    }
    let abs: Self
    (abs, _) = _Cox.parse(
      source.significandBitPattern,
      Int(source.exponentBitPattern) &- 6176,
      precision: format.precision,
      emin: format.emin,
      emax: format.emax)
    self = source._isSignMinus ? -abs : abs
  }
}

@available(anyAppleOS 26.0, *)
extension UInt64 {
  @usableFromInline
  internal static let _asciiDigits: [100 of (UInt8, UInt8)] = [
    (0x30, 0x30), (0x30, 0x31), (0x30, 0x32), (0x30, 0x33), (0x30, 0x34),
    (0x30, 0x35), (0x30, 0x36), (0x30, 0x37), (0x30, 0x38), (0x30, 0x39),
    (0x31, 0x30), (0x31, 0x31), (0x31, 0x32), (0x31, 0x33), (0x31, 0x34),
    (0x31, 0x35), (0x31, 0x36), (0x31, 0x37), (0x31, 0x38), (0x31, 0x39),
    (0x32, 0x30), (0x32, 0x31), (0x32, 0x32), (0x32, 0x33), (0x32, 0x34),
    (0x32, 0x35), (0x32, 0x36), (0x32, 0x37), (0x32, 0x38), (0x32, 0x39),
    (0x33, 0x30), (0x33, 0x31), (0x33, 0x32), (0x33, 0x33), (0x33, 0x34),
    (0x33, 0x35), (0x33, 0x36), (0x33, 0x37), (0x33, 0x38), (0x33, 0x39),
    (0x34, 0x30), (0x34, 0x31), (0x34, 0x32), (0x34, 0x33), (0x34, 0x34),
    (0x34, 0x35), (0x34, 0x36), (0x34, 0x37), (0x34, 0x38), (0x34, 0x39),
    (0x35, 0x30), (0x35, 0x31), (0x35, 0x32), (0x35, 0x33), (0x35, 0x34),
    (0x35, 0x35), (0x35, 0x36), (0x35, 0x37), (0x35, 0x38), (0x35, 0x39),
    (0x36, 0x30), (0x36, 0x31), (0x36, 0x32), (0x36, 0x33), (0x36, 0x34),
    (0x36, 0x35), (0x36, 0x36), (0x36, 0x37), (0x36, 0x38), (0x36, 0x39),
    (0x37, 0x30), (0x37, 0x31), (0x37, 0x32), (0x37, 0x33), (0x37, 0x34),
    (0x37, 0x35), (0x37, 0x36), (0x37, 0x37), (0x37, 0x38), (0x37, 0x39),
    (0x38, 0x30), (0x38, 0x31), (0x38, 0x32), (0x38, 0x33), (0x38, 0x34),
    (0x38, 0x35), (0x38, 0x36), (0x38, 0x37), (0x38, 0x38), (0x38, 0x39),
    (0x39, 0x30), (0x39, 0x31), (0x39, 0x32), (0x39, 0x33), (0x39, 0x34),
    (0x39, 0x35), (0x39, 0x36), (0x39, 0x37), (0x39, 0x38), (0x39, 0x39),
  ]

  @unsafe
  @inlinable
  @inline(always)
  @discardableResult
  internal func _ascii(
    _ span: inout MutableRawSpan,
    uncheckedEndOffset: Int? = nil
  ) -> Int {
    var value = self
    var offset = uncheckedEndOffset ?? span.byteCount
    if value == 0 {
      offset &-= 1
      unsafe span.storeBytes(
        of: 0x30 /* '0' */,
        toUncheckedByteOffset: offset,
        as: UInt8.self)
    } else {
      while value >= 10 {
        offset &-= 2
        let r: Self
        (value, r) = value.quotientAndRemainder(dividingBy: 100)
        unsafe span.storeBytes(
          of: Self._asciiDigits[unchecked: Int(truncatingIfNeeded: r)],
          toUncheckedByteOffset: offset,
          as: (UInt8, UInt8).self)
      }
      if value != 0 {
        offset &-= 1
        unsafe span.storeBytes(
          of: UInt8(truncatingIfNeeded: value) | 0x30,
          toUncheckedByteOffset: offset,
          as: UInt8.self)
      }
    }
    return offset
  }
}

@available(anyAppleOS 26.0, *)
extension Decimal128: CustomStringConvertible {
  @inlinable
  internal func _description(_ output: inout OutputSpan<UInt8>) {
    precondition(isFinite && output.freeCapacity >= 42)

    if _isSignMinus {
      output.append(45 /* '-' */)
    }
    let g = _combinationBitPattern
    var c = bitPattern & (1 &<< 113 &- 1)
    // Noncanonical zero (cf. `_canonical`).
    if g >= 0x18000 || c >= ._1e34 { c = 0 }

    var scratch = [34 of UInt8](repeating: 48 /* '0' */)
    var span_ = scratch.mutableSpan
    var span = span_.mutableBytes
    var startOffset: Int
    if c <= 0xFFFF_FFFF_FFFF_FFFF /* UInt64.max */ {
      startOffset = unsafe UInt64(truncatingIfNeeded: c)._ascii(&span)
    } else {
      let (q, r) = c._quotientAndRemainder(dividingBy1e: 19)
      unsafe UInt64(truncatingIfNeeded: r)._ascii(&span)
      startOffset =
        unsafe UInt64(truncatingIfNeeded: q)
          ._ascii(&span, uncheckedEndOffset: 15)
    }
    let count = 34 &- startOffset
    let quantumExponent = Int(exponentBitPattern) &- 6176
    let exponent = quantumExponent &+ count &- 1
    if quantumExponent <= 0 && exponent >= 0 && exponent < 16 {
      let unitOffset = quantumExponent &+ 33
      for i in startOffset...unitOffset {
        unsafe output.append(span[unchecked: i])
      }
      if unitOffset != 33 {
        output.append(46 /* '.' */)
        for i in (unitOffset &+ 1)..<34 {
          unsafe output.append(span[unchecked: i])
        }
      }
      return
    }
    if exponent >= -4 && exponent < 0 {
      output.append(48 /* '0' */)
      output.append(46 /* '.' */)
      output.append(repeating: 48, count: -exponent &- 1)
      for i in startOffset..<34 {
        unsafe output.append(span[unchecked: i])
      }
      return
    }
    // Scientific notation.
    unsafe output.append(span[unchecked: startOffset])
    if count != 1 {
      output.append(46 /* '.' */)
      for i in (startOffset &+ 1)..<34 {
        unsafe output.append(span[unchecked: i])
      }
    }
    output.append(101 /* 'e' */)
    output.append(exponent < 0 ? 45 /* '-' */ : 43 /* '+' */)
    // Reuse the same scratch.
    startOffset =
      unsafe UInt64(exponent.magnitude)._ascii(&span, uncheckedEndOffset: 34)
    for i in startOffset..<34 {
      unsafe output.append(span[unchecked: i])
    }
  }

  @inlinable
  public var description: String {
    if isNaN {
      if isSignalingNaN { _signal(.invalid) }
      return "nan"
    }
    if isInfinite {
      return _isSignMinus ? "-inf" : "inf"
    }
    if magnitude.bitPattern == Self().bitPattern {
      return _isSignMinus ? "-0" : "0"
    }
    return withTemporaryAllocation(of: UInt8.self, capacity: 42) { output in
      _description(&output)
      let utf8 = unsafe UTF8Span(unchecked: output.span, isKnownASCII: true)
      return String(copying: utf8)
    }
  }
}

@available(anyAppleOS 26.0, *)
extension Decimal128: CustomDebugStringConvertible {
  @inlinable
  public var debugDescription: String {
    if isNaN {
      let t = _trailingSignificandBitPattern
      if t == 0 || t >= ._1e33 {
        if isSignalingNaN {
          return _isSignMinus ? "-snan" : "snan"
        }
        return _isSignMinus ? "-nan" : "nan"
      }
      return withTemporaryAllocation(of: UInt8.self, capacity: 37) { output in
        if _isSignMinus {
          output.append( 45 /* '-' */)
        }
        if isSignalingNaN {
          output.append(115 /* 's' */)
        }
        output.append(  110 /* 'n' */)
        output.append(   97 /* 'a' */)
        output.append(  110 /* 'n' */)
        output.append(   40 /* '(' */)
        output.append(   48 /* '0' */)
        output.append(  120 /* 'x' */)
        var i = (127 &- t.leadingZeroBitCount) & ~3
        repeat {
          let x = UInt8(truncatingIfNeeded: t &>> i) & 15
          output.append(x &+ (x < 10 ? 48 : 87))
          i &-= 4
        } while i >= 0
        output.append(   41 /* ')' */)
        let utf8 = unsafe UTF8Span(unchecked: output.span, isKnownASCII: true)
        return String(copying: utf8)
      }
    }
    return description
  }
}

@available(anyAppleOS 26.0, *)
extension Decimal128: LosslessStringConvertible {
  @inlinable
  internal static func _parse(
    utf8: Span<UInt8>,
    rounding rule: _DecimalFloatingPointRoundingRule,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) -> Decimal128? {
    let count = utf8.count
    guard count != 0 else { return nil }
    guard count <= (Int.max / 10) &- 6256 else { return nil }
    // See `limit` below for derivation of this upper bound.
    // TODO: Consider if we want to support ludicrously large strings.
    var index = 0

    // Get the sign.
    var isSignMinus = false
    var codeUnit = unsafe utf8[unchecked: index]
    if codeUnit == 43 /* '+' */ || codeUnit == 45 /* '-' */ {
      isSignMinus = codeUnit == 45
      index &+= 1
      guard index != count else { return nil }
      codeUnit = unsafe utf8[unchecked: index]
    }

    // Handle infinity and NaN.
    codeUnit |= 0x20
    if codeUnit == 105 || codeUnit == 110 || codeUnit == 115 /* 'i' 'n' 's' */ {
      @inline(always)
      func starts(with prefix: StaticString) -> Bool {
        prefix.withUTF8Buffer {
          guard count &- index >= $0.count else { return false }
          for i in 0..<$0.count {
            if unsafe (utf8[unchecked: index &+ i] | 0x20) != $0[i] {
              return false
            }
          }
          return true
        }
      }
      let abs: Self
      if codeUnit == 105 {
        guard
          (count &- index == 3 && starts(with: "inf")) ||
          (count &- index == 8 && starts(with: "infinity"))
        else {
          return nil
        }
        abs = .infinity
      } else {
        let signaling: Bool
        if starts(with: "nan") {
          signaling = false
          index &+= 3
        } else if starts(with: "snan") {
          signaling = true
          index &+= 4
        } else {
          return nil
        }
        var payload: UInt128 = 0
        if index != count {
          guard
            count &- index >= 2,
            unsafe utf8[unchecked: index] == 40 /* '(' */,
            unsafe utf8[unchecked: count &- 1] == 41 /* ')' */
          else {
            return nil
          }
          index &+= 1
          let end = count &- 1
          var radix: UInt8 = 10
          if end &- index >= 2, unsafe utf8[unchecked: index] == 48 /* '0' */ {
            if unsafe (utf8[unchecked: index &+ 1] | 0x20) == 120 /* 'x' */ {
              radix = 16
              index &+= 2
            } else {
              radix = 8
              index &+= 1
            }
          }
          let (a, b) = radix > 10 ? (9, radix &- 11) : (radix &- 1, 0)
          while index != end {
            codeUnit = unsafe utf8[unchecked: index]
            var digit = codeUnit &- 48 /* '0' */
            if digit > a {
              if radix > 10 {
                digit = (codeUnit | 0x20) &- 97 /* 'a' */
                if digit > b {
                  return nil
                }
                digit &+= 10
              } else {
                return nil
              }
            }
            payload = min(._1e33, payload &* UInt128(radix) &+ UInt128(digit))
            index &+= 1
          }
        }
        abs = Self(nan: payload == ._1e33 ? 0 : payload, signaling: signaling)
      }
      return isSignMinus ? -abs : abs
    }

    // Build the significand and exponent.
    var digitCount = 0
    var significand: UInt128
    var guardDigit: UInt8
    var sticky = false
    var biasedExponent = 6176

    @inline(always)
    func digit(_ codeUnit: UInt8) -> UInt8? {
      let digit = codeUnit &- 48 /* '0' */
      return digit < 10 ? digit : nil
    }

    if count &- index <= 19 {
      var significand_: UInt64 = 0

      let anchor = index
      while index != count, let d = digit(unsafe utf8[unchecked: index]) {
        index &+= 1
        if digitCount == 0 && d == 0 { continue }
        significand_ = significand_ &* 10 &+ UInt64(d)
        digitCount &+= 1
      }
      let hasIntegerPart = index != anchor
      if index != count, unsafe utf8[unchecked: index] == 46 /* '.' */ {
        index &+= 1
        let anchor = index
        while index != count, let d = digit(unsafe utf8[unchecked: index]) {
          index &+= 1
          // Decrement exponent if a fractional digit.
          biasedExponent &-= 1
          if digitCount == 0 && d == 0 { continue }
          significand_ = significand_ &* 10 &+ UInt64(d)
          digitCount &+= 1
        }
        let hasFractionalPart = index != anchor
        guard hasIntegerPart || hasFractionalPart else { return nil }
      } else {
        guard hasIntegerPart else { return nil }
      }
      significand = UInt128(significand_)
      guardDigit = 0
    } else {
      var leading: UInt64 = 0
      var trailing: UInt64 = 0
      var next: UInt8? = nil

      @inline(always)
      func consume(_ digit: UInt8, into chunk: inout UInt64, fraction: Bool) {
        // Decrement exponent if a fractional digit.
        if fraction { biasedExponent &-= 1 }
        if digitCount == 0 && digit == 0 { return }
        chunk = chunk &* 10 &+ UInt64(digit)
        digitCount &+= 1
      }

      let anchor = index
      integer: do {
        while digitCount < 19 {
          guard index != count, let d = digit(unsafe utf8[unchecked: index])
          else { break integer }
          consume(d, into: &leading, fraction: false)
          index &+= 1
        }
        while digitCount < 34 {
          guard index != count, let d = digit(unsafe utf8[unchecked: index])
          else { break integer }
          consume(d, into: &trailing, fraction: false)
          index &+= 1
        }
        if next == nil {
          guard index != count, let d = digit(unsafe utf8[unchecked: index])
          else { break integer }
          next = d
          biasedExponent &+= 1
          index &+= 1
        }
        let anchor = index
        while index != count, let d = digit(unsafe utf8[unchecked: index]) {
          if d != 0 { sticky = true }
          index &+= 1
        }
        biasedExponent &+= index &- anchor
      }
      let hasIntegerPart = index != anchor
      if index != count, unsafe utf8[unchecked: index] == 46 /* '.' */ {
        index &+= 1
        let anchor = index
        fractional: do {
          while digitCount < 19 {
            guard index != count, let d = digit(unsafe utf8[unchecked: index])
            else { break fractional }
            consume(d, into: &leading, fraction: true)
            index &+= 1
          }
          while digitCount < 34 {
            guard index != count, let d = digit(unsafe utf8[unchecked: index])
            else { break fractional }
            consume(d, into: &trailing, fraction: true)
            index &+= 1
          }
          if next == nil {
            guard index != count, let d = digit(unsafe utf8[unchecked: index])
            else { break fractional }
            next = d
            index &+= 1
          }
          while index != count, let d = digit(unsafe utf8[unchecked: index]) {
            if d != 0 { sticky = true }
            index &+= 1
          }
        }
        let hasFractionalPart = index != anchor
        guard hasIntegerPart || hasFractionalPart else { return nil }
      } else {
        guard hasIntegerPart else { return nil }
      }
      if digitCount <= 19 {
        significand = UInt128(leading)
      } else {
        significand =
          unsafe UInt128(leading) &* ._exp10[unchecked: digitCount &- 19]
            &+ UInt128(trailing)
      }
      guardDigit = next ?? 0
    }

    if index != count, unsafe (utf8[unchecked: index] | 0x20) == 101 /* 'e' */ {
      index &+= 1
      var isExponentSignMinus = false
      if index != count {
        codeUnit = unsafe utf8[unchecked: index]
        if codeUnit == 43 /* '+' */ || codeUnit == 45 /* '-' */ {
          isExponentSignMinus = codeUnit == 45
          index &+= 1
        }
      }
      // A limit sufficient for saturation to guarantee overflow or underflow.
      let limit = count &+ 6255
      let anchor = index
      var x = 0
      while index != count, let d = digit(unsafe utf8[unchecked: index]) {
        x = min(limit, x &* 10 &+ Int(d))
        index &+= 1
      }
      guard index != anchor else { return nil }
      if isExponentSignMinus {
        biasedExponent &-= x
      } else {
        biasedExponent &+= x
      }
    }
    guard index == count else { return nil }

    if digitCount == 0 {
      biasedExponent = min(12287, max(biasedExponent, 0))
      let abs =
        Self(bitPattern: UInt128(truncatingIfNeeded: biasedExponent) &<< 113)
      return isSignMinus ? -abs : abs
    }

    var isKnownTiny = false
    if biasedExponent < -34 {
      isKnownTiny = true
      significand = 0
      guardDigit = 0
      sticky = true
      biasedExponent = 0
    } else if biasedExponent < 0 {
      isKnownTiny = true
      let n = -biasedExponent
      let r: UInt128
      (significand, r) = significand._quotientAndRemainder(dividingBy1e: n)
      let half: UInt128 = unsafe ._exp10[unchecked: n] &>> 1
      if guardDigit != 0 || (r != 0 && r != half) {
        sticky = true
      }
      guardDigit = r >= half ? 5 : 0
      biasedExponent = 0
    } else if biasedExponent > 12287 {
      let n = biasedExponent &- 12287
      guard n <= 34 &- digitCount else {
        return ._overflow(isSignMinus: isSignMinus, rule, &flags)
      }
      significand &*= unsafe ._exp10[unchecked: n]
      assert(guardDigit == 0 && !sticky)
      biasedExponent = 12287
    }

    if guardDigit != 0 || sticky {
      // Inexact.
      if Self._roundsAway(
        isSignMinus: isSignMinus,
        significand: significand,
        digit: guardDigit,
        sticky: sticky,
        rule
      ) {
        if significand == ._1e34 &- 1 {
          if biasedExponent == 12287 {
            _signal(.overflowInexact, into: &flags)
            return isSignMinus ? -.infinity : .infinity
          }
          significand = ._1e33
          biasedExponent &+= 1
        } else {
          significand &+= 1
        }
      }
      // `isKnownTiny == true` for all *inexact* tiny values.
      if isKnownTiny {
        _signal(.underflowInexact, into: &flags)
      } else {
        _signal(.inexact, into: &flags)
      }
    }
    let abs = Self(
      bitPattern: UInt128(truncatingIfNeeded: biasedExponent) &<< 113
        | significand)
    return isSignMinus ? -abs : abs
  }

  @inlinable
  internal init?<T: StringProtocol>(
    _ description: T,
    _rounding rule: _DecimalFloatingPointRoundingRule,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) {
    let x: Self?? = description.utf8.withContiguousStorageIfAvailable {
      unsafe ._parse(utf8: $0.span, rounding: rule, &flags)
    }
    let y: Self?
    if let x {
      y = x
    } else {
      var string = String(description)
      y = string.withUTF8 {
        unsafe ._parse(utf8: $0.span, rounding: rule, &flags)
      }
    }
    if let y {
      self = y
      return
    }
    return nil
  }

  @inline(always)
  public init?<T: StringProtocol>(_ description: T) {
    var flags: DecimalFloatingPointStatusFlags = []
    self.init(description, _rounding: .toNearestOrEven, &flags)
  }

  @inline(always)
  public init?<T: StringProtocol>(
    _ description: T,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) {
    self.init(description, _rounding: .toNearestOrEven, &flags)
  }

  @inline(always)
  public init?<T: StringProtocol>(
    _ description: T,
    rounding rule: FloatingPointRoundingRule
  ) {
    var flags: DecimalFloatingPointStatusFlags = []
    self.init(description, _rounding: .init(rule), &flags)
  }

  @inline(always)
  public init?<T: StringProtocol>(
    _ description: T,
    rounding rule: FloatingPointRoundingRule,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) {
    self.init(description, _rounding: .init(rule), &flags)
  }
}
