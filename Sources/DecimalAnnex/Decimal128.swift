import Numerics

extension UInt32 {
  @inlinable
  internal var _log10: Int {
    // See discussion at:
    // https://lemire.me/blog/2021/05/28/computing-the-number-of-digits-of-an-integer-quickly/
    let estimate = ((9 &* (31 &- (self|1).leadingZeroBitCount)) &>> 5) &+ 1
    return self >= Self._exp10(estimate) ? estimate : estimate &- 1
  }

  @inlinable
  internal static func _exp10(_ n: Int) -> Self {
    let table: [Self] = [
                  1,
                 10,
                100,
              1_000,
             10_000,
            100_000,
          1_000_000,
         10_000_000,
        100_000_000,
      1_000_000_000
    ]
    return n < 0 ? 0 : table[n]
  }
}

@available(macOS 15.0, *)
extension UInt128 {
  @inlinable
  internal var _log10: Int {
    if self <= UInt32.max { return UInt32(self)._log10 }

    // See discussion at:
    // https://lemire.me/blog/2021/05/28/computing-the-number-of-digits-of-an-integer-quickly/
    //
    // To approximate `1 / log2(10)`, we must use 19/64 (expressed here as
    // `(19 &* ...) &>> 6`) instead of 9/32. This is so that the estimate (after
    // adding one) is at least the true floor log10.
    //
    // Meanwhile, we avoid using an even more precise approximation such as
    // 39/128, because if we overestimate `(UInt128.max)._log10` then we'll end
    // up trying to compute `10 ** 39` while checking if our estimate is off by
    // one, which results in overflow.
    let estimate = ((19 &* (127 &- (self|1).leadingZeroBitCount)) &>> 6) &+ 1
    let table: [Self] = [
                                      100_000_000,
                           10_000_000_000_000_000,
                1_000_000_000_000_000_000_000_000,
      100_000_000_000_000_000_000_000_000_000_000
    ]
    return self >=
        table[(estimate &>> 3) &- 1] &* Self(UInt32._exp10(estimate & 7))
      ? estimate
      : estimate &- 1
  }

  @inlinable
  internal static func _exp10(_ n: Int) -> Self {
    if n <= 9 { return Self(UInt32._exp10(n)) }

    precondition(n < 39, "Arithmetic overflow")
    let table: [Self] = [
                                      100_000_000,
                           10_000_000_000_000_000,
                1_000_000_000_000_000_000_000_000,
      100_000_000_000_000_000_000_000_000_000_000
    ]
    return table[(n &>> 3) &- 1] &* Self(UInt32._exp10(n & 7))
  }
}

@inlinable
internal func _signal(_: _DecimalException) {
  // No-op (for now).
}

@frozen
public struct _DecimalException: OptionSet {
  public let rawValue: UInt8

  public init(rawValue: UInt8) {
    self.rawValue = rawValue
  }

  public static let invalid: _DecimalException          = Self(rawValue:  1)
  public static let divisionByZero: _DecimalException   = Self(rawValue:  2)
  public static let overflow: _DecimalException         = Self(rawValue:  4)
  public static let underflow: _DecimalException        = Self(rawValue:  8)
  public static let inexact: _DecimalException          = Self(rawValue: 16)

  public static let underflowInexact: _DecimalException = [.underflow, .inexact]
}

@available(macOS 15.0, *)
@frozen
public struct Decimal128: Sendable {
  public var bitPattern: UInt128

  @_transparent
  public init() {
    bitPattern = 6176 &<< 113
  }

  @_transparent
  public init(bitPattern: UInt128) {
    self.bitPattern = bitPattern
  }
}

@available(macOS 15.0, *)
extension Decimal128 {
  @inlinable
  public var sign: FloatingPointSign {
    let rawValue = Int(truncatingIfNeeded: bitPattern &>> 127)
    return FloatingPointSign(rawValue: rawValue).unsafelyUnwrapped
  }

  @inlinable
  internal var _isSignMinus: Bool {
    @inline(__always) get { bitPattern &>> 127 == 1 }
  }

  @inlinable
  public var magnitude: Self {
    @inline(__always) get { Self(bitPattern: bitPattern & (~0 &>> 1)) }
  }

  @inlinable
  public static prefix func - (operand: Self) -> Self {
    var result = operand
    result.negate()
    return result
  }

  @inlinable
  public mutating func negate() {
    bitPattern ^= 1 &<< 127
  }

  @inlinable
  public init(signOf sign: Self, magnitudeOf magnitude: Self) {
    bitPattern =
      (sign.bitPattern & (1 &<< 127)) | (magnitude.bitPattern & (~0 &>> 1))
  }
}


@available(macOS 15.0, *)
extension Decimal128 {
  public typealias RawSignificand = UInt128

  @inlinable
  public static var radix: Int { 10 }

  @inlinable
  internal var _combinationBitPattern: UInt {
    @inline(__always) get {
      UInt(truncatingIfNeeded: bitPattern &>> 110) & 0x1ffff
    }
  }

  @inlinable
  internal var _trailingSignificandBitPattern: UInt128 {
    @inline(__always) get {
      bitPattern & (1 &<< 110 &- 1)
    }
  }

  @inlinable
  internal init(
    _sign: FloatingPointSign,
    combinationBitPattern g: UInt,
    trailingSignificandBitPattern t: UInt128
  ) {
    bitPattern =
      (UInt128(truncatingIfNeeded: _sign.rawValue) &<< 127) |
        (UInt128(truncatingIfNeeded: g & 0x1ffff) &<< 110) |
          (t & (1 &<< 110 &- 1))
  }

  /// The 14-bit encoding of the value's exponent field.
  ///
  /// This property is unadjusted by the exponent bias. In the case of
  /// non-finite values, it excludes two leading bits of the combination field
  /// and includes extra trailing bits.
  @inlinable
  public var exponentBitPattern: UInt {
    if magnitude.bitPattern < ((0x3 as UInt128) &<< 125) {
      UInt(truncatingIfNeeded: bitPattern &>> 113) & 0x3fff
    } else {
      UInt(truncatingIfNeeded: bitPattern &>> 111) & 0x3fff
    }
  }

  /// The 114-bit encoding of the value's concatenated significand field,
  /// including any implicit leading bit.
  ///
  /// In the case of non-finite values, the implicit leading bit is always set:
  /// for NaN values, this property includes the payload with extra leading
  /// bits; for infinite values, it includes ignored bits.
  @inlinable
  public var significandBitPattern: UInt128 {
    if magnitude.bitPattern < ((0x3 as UInt128) &<< 125) {
      bitPattern & (1 &<< 113 &- 1)
    } else {
      bitPattern & (1 &<< 111 &- 1) | (1 &<< 113)
    }
  }

  @inlinable
  public init(
    sign: FloatingPointSign,
    exponentBitPattern e: UInt,
    significandBitPattern c: UInt128
  ) {
    if (c &>> 113) & 1 == 0 {
      bitPattern =
        (UInt128(truncatingIfNeeded: sign.rawValue) &<< 127) |
          (UInt128(truncatingIfNeeded: e & 0x3fff) &<< 113) |
            (c & (1 &<< 113 &- 1))
    } else {
      bitPattern =
        (UInt128(truncatingIfNeeded: sign.rawValue) &<< 127) |
          (UInt128(truncatingIfNeeded: (e & 0x3fff) | 0xc000) &<< 111) |
            (c & (1 &<< 111 &- 1))
    }
  }
}

@available(macOS 15.0, *)
extension Decimal128 {
  @inlinable
  public static var infinity: Self {
    Self(bitPattern: 0x1e000 &<< 110)
  }

  @inlinable
  public static var nan: Self {
    Self(bitPattern: 0x1f000 &<< 110)
  }

  @inlinable
  public static var signalingNaN: Self {
    Self(bitPattern: 0x1f800 &<< 110)
  }

  @inlinable
  public static var greatestFiniteMagnitude: Self {
    Self(bitPattern: (12287 &<< 113) | 9_999_999_999_999_999_999_999_999_999_999_999)
  }

  @inlinable
  public static var leastNormalMagnitude: Self {
    Self(bitPattern: (33 &<< 113) | 1)
  }

  @inlinable
  public static var leastNonzeroMagnitude: Self {
    Self(bitPattern: 1)
  }

  @inlinable
  public static var pi: Self {
    Self(bitPattern: (6143 &<< 113) | 3_141_592_653_589_793_238_462_643_383_279_502)
  }

  @inlinable
  public init(nan payload: UInt128, signaling: Bool) {
    bitPattern =
      ((signaling ? 0x1f800 : 0x1f000) &<< 110) | (payload & (1 &<< 110 &- 1))
  }

  @inlinable
  public var isCanonical: Bool {
    let g = _combinationBitPattern
    guard g < 0x1f000 else {
      // NaN is canonical if:
      // - all but the highest 6 bits of the combination field are zero; and
      // - the payload, which is the trailing significand, is not more than
      //   10 ** 33 - 1 (note the exponent).
      return g & 0x7ff == 0 &&
        _trailingSignificandBitPattern <=
          999_999_999_999_999_999_999_999_999_999_999 as UInt128
    }
    guard g < 0x1e000 else {
      // Infinity.
      return magnitude.bitPattern == Self.infinity.bitPattern
    }
    // When the combination field begins `11...`, all significands are
    // noncanonical.
    guard g < 0x18000 else { return false }
    // Having excluded all values where the combination field begins `11...`,
    // we know the represented significand is in the lower 113 bits.
    return bitPattern & (1 &<< 113 &- 1) <=
      9_999_999_999_999_999_999_999_999_999_999_999 as UInt128
  }

  @inlinable
  internal var _canonical: Self {
    let g = _combinationBitPattern
    guard g < 0x1f000 else {
      var mask: UInt128 = 0x3f800 &<< 110
      if _trailingSignificandBitPattern <=
          999_999_999_999_999_999_999_999_999_999_999 as UInt128 {
        mask |= 1 &<< 110 &- 1
      }
      return Self(bitPattern: bitPattern & mask)
    }
    guard g < 0x1e000 else {
      return Self(bitPattern: bitPattern & (0x3e000 &<< 110))
    }
    guard g < 0x18000 &&
      (bitPattern & (1 &<< 113 &- 1) <=
        9_999_999_999_999_999_999_999_999_999_999_999 as UInt128) else {
      return Self(
        sign: sign,
        exponentBitPattern: exponentBitPattern,
        significandBitPattern: 0)
    }
    return self
  }

  @inlinable
  public var isNaN: Bool {
    @inline(__always) get { _combinationBitPattern >= 0x1f000 }
  }

  @inlinable
  public var isSignalingNaN: Bool {
    @inline(__always) get { _combinationBitPattern >= 0x1f800 }
  }

  @inlinable
  internal var _quiet: Self {
    @inline(__always) get {
      _combinationBitPattern < 0x1f800
        ? self
        : Self(bitPattern: bitPattern ^ (1 &<< 121))
    }
  }

  @inlinable
  public var isInfinite: Bool {
    @inline(__always) get {
      let g = _combinationBitPattern
      return g >= 0x1e000 && g < 0x1f000
    }
  }

  @inlinable
  public var isFinite: Bool {
    @inline(__always) get { _combinationBitPattern < 0x1e000 }
  }

  @inlinable
  internal var _isFiniteNonzero: Bool {
    @inline(__always) get {
      guard _combinationBitPattern < 0x18000 else { return false }
      // Having excluded all values where the combination field begins `11...`,
      // we know the represented significand is in the lower 113 bits.
      let c = bitPattern & (1 &<< 113 &- 1)
      return c > 0 as UInt128 && c < 10_000_000_000_000_000_000_000_000_000_000_000
    }
  }

  @inlinable
  public var isSubnormal: Bool {
    // We don't need to consider separately values where the combination field
    // begins `11...`, because all such values are either treated as zero or
    // aren't finite, and therefore all aren't subnormal.
    let e = _combinationBitPattern &>> 3
    guard e < 33 else { return false }
    // By now, we know the represented significand is in the lower 113 bits.
    let c = bitPattern & (1 &<< 113 &- 1)
    // We don't need to consider noncanonical representations of zero separately
    // because their significand bit pattern would be necessary greater than the
    // upper limit we're testing for.
    return c > 0 as UInt128 && c < UInt128._exp10(33 - Int(e))
  }

  @inlinable
  public var isNormal: Bool {
    let g = _combinationBitPattern
    guard g < 0x18000 else { return false }

    let e = g &>> 3
    // By now, we know the represented significand is in the lower 113 bits.
    let c = bitPattern & (1 &<< 113 &- 1)
    guard e < 33 else {
      // If the exponent isn't small, the value is normal if it's nonzero.
      return c > 0 as UInt128 && c < 10_000_000_000_000_000_000_000_000_000_000_000
    }
    return c >= UInt128._exp10(33 - Int(e))
  }

  @inlinable
  public var isZero: Bool {
    let g = _combinationBitPattern
    // When the combination field begins `11...`, either:
    // - the value is infinity or NaN; or
    // - the significand is noncanonical and treated as zero.
    guard g < 0x18000 else { return g < 0x1e000 }
    // Having excluded all values where the combination field begins `11...`,
    // we know the represented significand is in the lower 113 bits.
    let c = bitPattern & (1 &<< 113 &- 1)
    return c == 0 || c > 9_999_999_999_999_999_999_999_999_999_999_999 as UInt128
  }
}

@available(macOS 15.0, *)
extension Decimal128 {
  @inlinable
  public var quantum: Self {
    if isFinite {
      Self(
        sign: sign,
        exponentBitPattern: exponentBitPattern,
        significandBitPattern: 1)
      // TODO: Does this operation signal underflow if the result is subnormal?
    } else {
      Self(bitPattern: bitPattern & Self.nan.bitPattern)
    }
  }

  @inlinable
  public func hasSameQuantum(as other: Self) -> Bool {
    guard isFinite && other.isFinite else {
      return bitPattern & Self.nan.bitPattern ==
        other.bitPattern & Self.nan.bitPattern
    }
    return exponentBitPattern == other.exponentBitPattern
  }

  @inlinable
  public var exponent: Int {
    guard isFinite else {
      _signal(.invalid)
      return .max
    }
    guard !isZero else {
      _signal(.invalid)
      return .min
    }
    return Int(exponentBitPattern) - 6176 + significandBitPattern._log10
  }
}

@available(macOS 15.0, *)
extension Decimal128: Equatable {
  @inlinable
  public static func == (lhs: Self, rhs: Self) -> Bool {
    if lhs.bitPattern == rhs.bitPattern {
      if lhs.isSignalingNaN { _signal(.invalid) }
      return !lhs.isNaN
    }

    guard lhs._isFiniteNonzero && rhs._isFiniteNonzero else {
      if lhs.isNaN || rhs.isNaN {
        if lhs.isSignalingNaN || rhs.isSignalingNaN { _signal(.invalid) }
        return false
      }

      if lhs.isInfinite {
        return rhs.isInfinite && (lhs._isSignMinus == rhs._isSignMinus)
      }
      if rhs.isInfinite { return false }

      return lhs.isZero && rhs.isZero
    }

    if lhs._isSignMinus != rhs._isSignMinus { return false }

    var lhs = lhs, rhs = rhs
    var n = Int(lhs.exponentBitPattern) - Int(rhs.exponentBitPattern)
    // Equivalent finite nonzero values with the same exponent bit pattern must
    // have the same overall bit pattern, in which case we've already taken the
    // early exit above.
    if n == 0 { return false }
    // If necessary, swap operands to simplify the logic that follows.
    if n < 0 {
      swap(&lhs, &rhs)
      n.negate()
    }

    // Equivalent values cannot differ in exponent bit pattern by more than 33.
    if n > 33 { return false }
    let (lc, rc) = (lhs.significandBitPattern, rhs.significandBitPattern)
    guard lc < rc else { return false }
    return lc.multipliedFullWidth(by: UInt128._exp10(n)) == (high: 0, low: rc)
  }
}

@available(macOS 15.0, *)
extension Decimal128: Hashable {
  /// Returns the result of adding +0 to the value without signaling any
  /// floating-point exceptions.
  ///
  /// The +0 operand is represented with the least possible exponent, so the
  /// result is represented with the least possible exponent.
  @inlinable
  internal func _addingZeroWithLeastQuantum() -> Self {
    guard _isFiniteNonzero else {
      if isNaN {
        // Note that `mask` will clear the signaling bit, silencing sNaN.
        var mask: UInt128 = 0x3f000 &<< 110
        // Preserve the payload (i.e., trailing significand bit pattern) only if
        // it is canonical.
        if _trailingSignificandBitPattern <=
            999_999_999_999_999_999_999_999_999_999_999 as UInt128 {
          mask |= 1 &<< 110 &- 1
        }
        return Self(bitPattern: bitPattern & mask)
      }
      if isInfinite {
        return Self(bitPattern: bitPattern & (0x3e000 &<< 110))
      }
      // The result of adding +0 to ±0 is +0.
      return Self(bitPattern: 0)
    }

    var e = exponentBitPattern
    guard e > 0 else { return self }
    var c = significandBitPattern
    // Estimate log10(c). See `UInt128._log10` for a more detailed explanation.
    // It is important that this estimate be at least the true floor log10 and
    // at most one greater.
    let estimate = ((19 &* (127 &- (c|1).leadingZeroBitCount)) &>> 6) &+ 1
    let n = min(e, UInt(max(0, 33 &- estimate)))
    if n > 0 {
      c &*= UInt128._exp10(Int(n))
      e &-= n
    }
    if e > 0 && c <= 999_999_999_999_999_999_999_999_999_999_999 as UInt128 {
      c &*= 10
      e &-= 1
    }
    return Self(sign: sign, exponentBitPattern: e, significandBitPattern: c)
  }

  @inlinable
  public func hash(into hasher: inout Hasher) {
    // By adding zero, we hash every representation of zero the same way, and
    // we also obtain a consistent canonical representation for every number,
    // whether finite or infinite. (Signaling NaNs are also quieted.)
    hasher.combine(_addingZeroWithLeastQuantum().bitPattern)
  }
}

@available(macOS 15.0, *)
extension Decimal128: Comparable {
  @inlinable
  public static func < (lhs: Self, rhs: Self) -> Bool {
    if lhs.bitPattern == rhs.bitPattern {
      if lhs.isNaN { _signal(.invalid) }
      return false
    }

    guard lhs._isFiniteNonzero && rhs._isFiniteNonzero else {
      if lhs.isNaN || rhs.isNaN {
        _signal(.invalid)
        return false
      }

      if lhs.isInfinite {
        return lhs._isSignMinus && !(rhs._isSignMinus && rhs.isInfinite)
      }
      if rhs.isInfinite { return !rhs._isSignMinus }

      if lhs.isZero {
        return !rhs._isSignMinus && !rhs.isZero
      }
      return lhs._isSignMinus
    }

    var lhs = lhs, rhs = rhs
    if lhs._isSignMinus {
      if !rhs._isSignMinus { return true }
      // If operands are both negative, then swap and compare magnitudes (i.e.,
      // if lhs < 0, rhs < 0, and lhs < rhs, then |rhs| < |lhs|).
      // Since we won't be checking the sign again, it suffices just to swap
      // the values themselves rather than actually computing their magnitudes.
      swap(&lhs, &rhs)
    } else if rhs._isSignMinus {
      return false
    }

    var n = Int(lhs.exponentBitPattern) - Int(rhs.exponentBitPattern)
    if n == 0 { return lhs.significandBitPattern < rhs.significandBitPattern }
    // If necessary, swap operands to simplify the logic that follows, but we
    // will need to remember that we did that.
    var isSwapped = false
    if n < 0 {
      swap(&lhs, &rhs)
      isSwapped = true
      n.negate()
    }

    // If lhs < rhs, then the exponent bit pattern of `lhs` cannot be more than
    // 33 _greater_ than that of `rhs`.
    if n > 33 { return isSwapped }
    let (lc, rc) = (lhs.significandBitPattern, rhs.significandBitPattern)
    guard lc < rc else { return isSwapped }
    return isSwapped !=
      (lc.multipliedFullWidth(by: UInt128._exp10(n)) < (high: 0, low: rc))
  }

  @inlinable
  public static func > (lhs: Self, rhs: Self) -> Bool {
    return rhs < lhs
  }

  @inlinable
  public static func <= (lhs: Self, rhs: Self) -> Bool {
    if lhs.isNaN || rhs.isNaN {
      _signal(.invalid)
      return false
    }
    return !(rhs < lhs)
  }

  @inlinable
  public static func >= (lhs: Self, rhs: Self) -> Bool {
    if lhs.isNaN || rhs.isNaN {
      _signal(.invalid)
      return false
    }
    return !(lhs < rhs)
  }
}

@available(macOS 15.0, *)
extension Decimal128: ExpressibleByIntegerLiteral {
  @inlinable
  public init(integerLiteral value: Int128) {
    bitPattern = value.magnitude
    guard bitPattern <= 9_999_999_999_999_999_999_999_999_999_999_999 as UInt128 else {
      fatalError("Potentially inexact integer conversion not implemented")
    }
    bitPattern |= Self().bitPattern
    if value < 0 { self.negate() }
  }
}

@available(macOS 15.0, *)
extension Decimal128: AdditiveArithmetic {
  @inlinable
  public static func + (lhs: Self, rhs: Self) -> Self {
    fatalError("Not implemented")
  }

  @inlinable
  public static func += (lhs: inout Self, rhs: Self) {
    lhs = lhs + rhs
  }

  @inlinable
  public static func - (lhs: Self, rhs: Self) -> Self {
    fatalError("Not implemented")
  }

  @inlinable
  public static func -= (lhs: inout Self, rhs: Self) {
    lhs = lhs - rhs
  }
}

@available(macOS 15.0, *)
extension Decimal128: Numeric {
  @inlinable
  public func multiplied(
    by rhs: Self, rounding rule: FloatingPointRoundingRule = .toNearestOrEven
  ) -> Self {
    let lhs = self
    let isSignMinus = lhs._isSignMinus != rhs._isSignMinus

    guard lhs._isFiniteNonzero && rhs._isFiniteNonzero else {
      if lhs.isNaN {
        if lhs.isSignalingNaN { _signal(.invalid) }
        return lhs._quiet._canonical
      }
      if rhs.isNaN {
        if rhs.isSignalingNaN { _signal(.invalid) }
        return rhs._quiet._canonical
      }

      if lhs.isInfinite {
        if rhs.isZero {
          _signal(.invalid)
          return .nan
        }
        return isSignMinus ? -.infinity : .infinity
      }
      if rhs.isInfinite {
        if lhs.isZero {
          _signal(.invalid)
          return .nan
        }
        return isSignMinus ? -.infinity : .infinity
      }

      let e = Int(lhs.exponentBitPattern) + Int(rhs.exponentBitPattern) - 6176
      let z = Self(bitPattern: UInt128(truncatingIfNeeded: max(0, e)) &<< 113)
      return isSignMinus ? -z : z
    }

    let e = Int(lhs.exponentBitPattern) + Int(rhs.exponentBitPattern) - 6176
    let (hi, lo) =
      lhs.significandBitPattern.multipliedFullWidth(
        by: rhs.significandBitPattern)
    if e >= 0 && e <= 12287
        && hi == 0 && lo <= 9_999_999_999_999_999_999_999_999_999_999_999 as UInt128 {
      let abs = Self(bitPattern: UInt128(truncatingIfNeeded: e) &<< 113 | lo)
      return isSignMinus ? -abs : abs
    }
    fatalError("Not implemented")
  }

  @inlinable
  @inline(__always)
  public static func * (lhs: Self, rhs: Self) -> Self {
    lhs.multiplied(by: rhs)
  }

  @inlinable
  @inline(__always)
  public static func *= (lhs: inout Self, rhs: Self) {
    lhs = lhs * rhs
  }

  @inlinable
  public init?<T: BinaryInteger>(exactly source: T) {
    let magnitude = source.magnitude
    let max = 9_999_999_999_999_999_999_999_999_999_999_999 as UInt128
    guard magnitude.bitWidth < 113 || magnitude <= max else {
      fatalError("Potentially inexact integer conversion not implemented")
    }
    bitPattern = UInt128(truncatingIfNeeded: magnitude)
    bitPattern |= Self().bitPattern
    if source < (0 as T) { self.negate() }
  }
}

@available(macOS 15.0, *)
extension Decimal128: SignedNumeric { }

@available(macOS 15.0, *)
extension Decimal128: CustomStringConvertible {
  public var description: String {
    if isNaN {
      return _isSignMinus ? "-nan" : "nan"
    }

    if isInfinite {
      return _isSignMinus ? "-inf" : "inf"
    }

    if isZero {
      return _isSignMinus ? "-0.0" : "0.0"
    }

    return String(unsafeUninitializedCapacity: 42) { buffer in
      // We'll keep track of the index of the first uninitialized element, which
      // we'll need to eventually return as the intiailized count.
      var index: Int

      if _isSignMinus {
        buffer.initializeElement(at: 0, to: 45 /* '-' */)
        index = 1
      } else {
        index = 0
      }

      // Since noncanonical significands are treated as zero, and values where
      // the combination field begins `11...` have noncanonical significands,
      // by this point we know that the represented significand is in the lower
      // 113 bits.
      var string = String(bitPattern & (1 &<< 113 &- 1))
      let count = string.utf8.count

      // We compute the exponent right away to determine if we need special
      // handling for the significand.
      let exponent = Int(_combinationBitPattern &>> 3) - 6176 + count - 1

      if exponent >= 0 && exponent < min(count, 16) {
        let x = exponent + 1
        string.withUTF8 {
          index = buffer[index...].initialize(fromContentsOf: $0[..<x])
          buffer.initializeElement(at: index, to: 46 /* '.' */)
          if x == count {
            buffer.initializeElement(at: index + 1, to: 48 /* '0' */)
            index += 2
          } else {
            index = buffer[(index + 1)...].initialize(fromContentsOf: $0[x...])
          }
        }
        return index
      }

      if exponent < 0 && exponent >= -4 {
        buffer.initializeElement(at: index, to: 48 /* '0' */)
        buffer.initializeElement(at: index + 1, to: 46 /* '.' */)
        index =
          buffer[(index + 2)...].initialize(
            fromContentsOf: repeatElement(48 /* '0' */, count: -(exponent + 1)))
        string.withUTF8 {
          index = buffer[index...].initialize(fromContentsOf: $0)
        }
        return index
      }

      string.withUTF8 {
        buffer.initializeElement(at: index, to: $0[0])
        if count == 1 {
          index += 1
        } else {
          buffer.initializeElement(at: index + 1, to: 46 /* '.' */)
          index = buffer[(index + 2)...].initialize(fromContentsOf: $0[1...])
        }
      }
      buffer.initializeElement(at: index, to: 101 /* 'e' */)
      buffer.initializeElement(
        at: index + 1,
        to: exponent < 0 ? 45 /* '-' */ : 43 /* '+' */)
      string = String(abs(exponent))
      string.withUTF8 {
        index = buffer[(index + 2)...].initialize(fromContentsOf: $0)
      }
      return index
    }
  }
}
