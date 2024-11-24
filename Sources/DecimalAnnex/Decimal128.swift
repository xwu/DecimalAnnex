import Numerics

@available(macOS 15.0, *)
extension UInt128 {
  @inlinable
  internal var _commonLogarithm: Int {
    // See discussion at:
    // https://lemire.me/blog/2021/05/28/computing-the-number-of-digits-of-an-integer-quickly/
    //
    // To approximate `1 / log2(10)`, we must use 19/64 (expressed here as
    // `(19 &* ...) &>> 6`) instead of 9/32. This is so that the estimate (after
    // adding one) is at least the true floor log10.
    //
    // Meanwhile, we avoid using an even more precise approximation such as
    // 77/256, because if we overestimate `(UInt128.max)._commonLogarithm` then
    // we'll end up trying to compute `10 ** 39` while checking if our estimate
    // is off by one, which results in overflow.
    let estimate = ((19 &* (127 &- (self|1).leadingZeroBitCount)) &>> 6) &+ 1
    return self >= UInt128._exp10(estimate) ? estimate : estimate &- 1
  }

  @inlinable
  internal static func _exp10(_ n: Int) -> Self {
    let table: [UInt64] = [
                               1,
                              10,
                             100,
                           1_000,
                          10_000,
                         100_000,
                       1_000_000,
                      10_000_000,
                     100_000_000,
                   1_000_000_000,
                  10_000_000_000,
                 100_000_000_000,
               1_000_000_000_000,
              10_000_000_000_000,
             100_000_000_000_000,
           1_000_000_000_000_000,
          10_000_000_000_000_000,
         100_000_000_000_000_000,
       1_000_000_000_000_000_000,
      10_000_000_000_000_000_000
    ]
    if n <= 19 { return n < 0 ? 0 : UInt128(table[n]) }
    return 10_000_000_000_000_000_000 &* UInt128(table[n &- 19])
  }
}

@inlinable
internal func _signal(_: _DecimalException, `default`: Bool) -> Bool {
  // No-op (for now).
  return `default`
}

@inlinable
internal func _signal(_: _DecimalException, `default`: String) -> String {
  // No-op (for now).
  return `default`
}

@inlinable
internal func _signal<T: Numeric>(_: _DecimalException, `default`: T) -> T {
  // No-op (for now).
  return `default`
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

  public static let overflowInexact: _DecimalException  = [.overflow, .inexact]
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
  public var decade: Self {
    guard isFinite else { return .nan }

    fatalError("Not implemented")
  }

  public var nextUp: Self {
    fatalError("Not implemented")
  }

  @inlinable
  public var nextDown: Self {
    @inline(__always) get { -(-self).nextUp }
  }

  @inlinable
  public var ulp: Self {
    guard isFinite else { return .nan }
    return Self(
      sign: sign,
      exponentBitPattern: exponentBitPattern,
      significandBitPattern: 1)
  }

  @inlinable
  public var quantum: Self {
    guard isFinite else {
      // TODO: Does this operation signal invalid if the operand is sNaN?
      return Self(bitPattern: bitPattern & Self.nan.bitPattern)
    }
    // TODO: Does this operation signal underflow if the result is subnormal?
    return Self(
      sign: sign,
      exponentBitPattern: exponentBitPattern,
      significandBitPattern: 1)
  }

  public func quantized(
    by other: Self, rounding rule: FloatingPointRoundingRule = .toNearestOrEven
  ) -> Self {
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

      if isZero {
        return Self(
          sign: sign,
          exponentBitPattern: other.exponentBitPattern,
          significandBitPattern: 0)
      }
      fatalError("Not implemented")
    }
    fatalError("Not implemented")
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
      return _signal(.invalid, default: .max)
    }
    guard !isZero else {
      return _signal(.invalid, default: .min)
    }
    return Int(exponentBitPattern) &- 6176 &+
      significandBitPattern._commonLogarithm
  }

  @inlinable
  public var significand: Self {
    guard isFinite else { return _canonical }
    guard !isZero else { return Self() }
    let c = significandBitPattern
    let e = 6176 &- c._commonLogarithm
    return Self(bitPattern: UInt128(truncatingIfNeeded: e) &<< 113 | c)
  }

  public init(sign: FloatingPointSign, exponent: Int, significand: Self) {
    // scaleB
    fatalError("Not implemented")
  }
}

@available(macOS 15.0, *)
extension Decimal128: Equatable {
  @inlinable
  public static func == (lhs: Self, rhs: Self) -> Bool {
    if lhs.bitPattern == rhs.bitPattern {
      if lhs.isNaN {
        if lhs.isSignalingNaN {
          return _signal(.invalid, default: false)
        }
        return false
      }
      return true
    }

    guard lhs._isFiniteNonzero && rhs._isFiniteNonzero else {
      if lhs.isNaN || rhs.isNaN {
        if lhs.isSignalingNaN || rhs.isSignalingNaN {
          return _signal(.invalid, default: false)
        }
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
  /// floating-point exceptions and using the default rounding mode.
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
      // The result of adding +0 to ±0 is +0 (using the default rounding mode).
      return Self(bitPattern: 0)
    }

    var e = exponentBitPattern
    guard e > 0 else { return self }
    var c = significandBitPattern
    // Estimate log10(c). See `UInt128._log10` for a detailed explanation.
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
      if lhs.isNaN {
        return _signal(.invalid, default: false)
      }
      return false
    }

    guard lhs._isFiniteNonzero && rhs._isFiniteNonzero else {
      if lhs.isNaN || rhs.isNaN {
        return _signal(.invalid, default: false)
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
      return _signal(.invalid, default: false)
    }
    return !(rhs < lhs)
  }

  @inlinable
  public static func >= (lhs: Self, rhs: Self) -> Bool {
    if lhs.isNaN || rhs.isNaN {
      return _signal(.invalid, default: false)
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
  public func adding(
    _ rhs: Self, rounding rule: FloatingPointRoundingRule = .toNearestOrEven
  ) -> Self {
    var lhs = self, rhs = rhs

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
        let isSignMinus = lhs._isSignMinus
        if rhs.isInfinite && isSignMinus != rhs._isSignMinus {
          return _signal(.invalid, default: .nan)
        }
        return isSignMinus ? -.infinity : .infinity
      }
      if rhs.isInfinite {
        return rhs._isSignMinus ? -.infinity : .infinity
      }

      if lhs.isZero {
        if rhs.isZero {
          // Adding ±0 and ±0. See IEEE-754 §6.3.
          let isSignMinus = rule == .down
            ? lhs._isSignMinus || rhs._isSignMinus
            : lhs._isSignMinus && rhs._isSignMinus
          let e = min(lhs.exponentBitPattern, rhs.exponentBitPattern)
          let abs = Self(bitPattern: UInt128(truncatingIfNeeded: e) &<< 113)
          return isSignMinus ? -abs : abs
        }
        // Swap operands so that `lhs` is nonzero and `rhs` is zero.
        swap(&lhs, &rhs)
      }
      var e1 = lhs.exponentBitPattern
      let e2 = rhs.exponentBitPattern
      guard e1 > e2 else { return lhs }
      var c1 = lhs.significandBitPattern
      // Estimate log10(c). See `UInt128._log10` for a detailed explanation.
      // It is important that this estimate be at least the true floor log10 and
      // at most one greater.
      let estimate = ((19 &* (127 &- (c1|1).leadingZeroBitCount)) &>> 6) &+ 1
      let n = min(e1 &- e2, UInt(max(0, 33 &- estimate)))
      if n > 0 {
        c1 &*= UInt128._exp10(Int(n))
        e1 &-= n
      }
      if e1 > e2 && c1 <= 999_999_999_999_999_999_999_999_999_999_999 as UInt128 {
        c1 &*= 10
        e1 &-= 1
      }
      return Self(
        sign: lhs.sign, exponentBitPattern: e1, significandBitPattern: c1)
    }

    let isAway = lhs._isSignMinus == rhs._isSignMinus

    var e1 = lhs.exponentBitPattern
    var e2 = rhs.exponentBitPattern
    if e1 < e2 {
      swap(&lhs, &rhs)
      swap(&e1, &e2)
    }

    let c1 = lhs.significandBitPattern
    let c2 = rhs.significandBitPattern
    let logc1 = c1._commonLogarithm
    let logc2 = c2._commonLogarithm
    if Int(e1 &- e2) &+ (logc1 &- logc2) > 33 {
      // ...
      if isAway { /* ... */ }
    }
    // ...
    fatalError("Not implemented")
  }

  @inlinable
  @inline(__always)
  public func subtracting(
    _ rhs: Self, rounding rule: FloatingPointRoundingRule = .toNearestOrEven
  ) -> Self {
    adding(-rhs, rounding: rule)
  }

  @inlinable
  @inline(__always)
  public static func + (lhs: Self, rhs: Self) -> Self {
    lhs.adding(rhs)
  }

  @inlinable
  @inline(__always)
  public static func += (lhs: inout Self, rhs: Self) {
    lhs = lhs + rhs
  }

  @inlinable
  @inline(__always)
  public static func - (lhs: Self, rhs: Self) -> Self {
    lhs.subtracting(rhs)
  }

  @inlinable
  @inline(__always)
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
        if rhs.isZero { return _signal(.invalid, default: .nan) }
        return isSignMinus ? -.infinity : .infinity
      }
      if rhs.isInfinite {
        if lhs.isZero { return _signal(.invalid, default: .nan) }
        return isSignMinus ? -.infinity : .infinity
      }

      let e = Int(lhs.exponentBitPattern) &- 6176 &+ Int(rhs.exponentBitPattern)
      let abs = Self(bitPattern: UInt128(truncatingIfNeeded: max(e, 0)) &<< 113)
      return isSignMinus ? -abs : abs
    }

    // Compute the intermediate result.
    var e = Int(lhs.exponentBitPattern) &- 6176 &+ Int(rhs.exponentBitPattern)
    let (hi, lo) =
      lhs.significandBitPattern.multipliedFullWidth(
        by: rhs.significandBitPattern)

    // Per IEEE-754, detect tininess (i.e., underflow) before rounding.
    let isTiny: Bool = if e < -34 {
      true
    } else if e < -5 {
      hi == 0 || (hi, lo) <
        UInt128._exp10(-e).multipliedFullWidth(
          by: 1_000_000_000_000_000_000_000_000_000_000_000)
    } else if e < 33 {
      hi == 0 && lo < UInt128._exp10(33 &- e)
    } else {
      false
    }

    guard !isTiny else {
      if e < -68 {
        // The magnitude of the result is less than
        // 1/2 * .leastNonzeroMagnitude.
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
          fatalError("Not implemented")
        }
        let abs = Self(bitPattern: nextAway ? 1 : 0)
        return _signal(.underflowInexact, default: isSignMinus ? -abs : abs)
      }

      // Remove decimal digits from intermediate result, if necessary.
      let pow, quo, rem, rem_: UInt128
      if e < -38 {
        let _x = _UInt256(hi, lo)._quotientAndRemainderDividingBy1e38()
        let quo_ = _x.quotient.low
        rem_ = _x.remainder.low
        pow = UInt128._exp10(-e &- 38)
        (quo, rem) = quo_.quotientAndRemainder(dividingBy: pow)
        e = 0
      } else if e < 0 {
        rem_ = 0
        pow = UInt128._exp10(-e)
        (quo, rem) = pow.dividingFullWidth((hi, lo))
        e = 0
      } else {
        rem_ = 0
        pow = 1
        (quo, rem) = (lo, 0)
      }

      if (rem, rem_) == (0, 0) {
        // Exact result.
        // Under default exception handling, no underflow is signaled.
        let abs = Self(bitPattern: UInt128(truncatingIfNeeded: e) &<< 113 | quo)
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
        ? (rem, rem_) > (pow &>> 1, 0 as UInt128)
        : rem >= (pow &>> 1)
      case .towardZero:
        false
      case .up:
        !isSignMinus
      @unknown default:
        fatalError("Not implemented")
      }
      assert(e == 0)
      let abs = Self(bitPattern: nextAway ? quo &+ 1 : quo)
      return _signal(.underflowInexact, default: isSignMinus ? -abs : abs)
    }

    // Remove decimal digits from intermediate result, if necessary.
    var pow, quo, rem: UInt128
    if hi != 0 as UInt128 {
      // See explanatory comment in `UInt128._commonLogarithm`.
      // Note that here we underestimate.
      var n = ((77 &* (255 &- hi.leadingZeroBitCount)) &>> 8) &- 33
      pow = UInt128._exp10(n)
      if (hi, lo) >=
          pow.multipliedFullWidth(by: 10_000_000_000_000_000_000_000_000_000_000_000) {
        n &+= 1
        pow &*= 10
      }
      (quo, rem) = pow.dividingFullWidth((hi, lo))
      e &+= n
    } else if lo > 9_999_999_999_999_999_999_999_999_999_999_999 as UInt128 {
      var n = ((77 &* (127 &- (lo|1).leadingZeroBitCount)) &>> 8) &- 33
      pow = UInt128._exp10(n)
      if lo >= pow &* 10_000_000_000_000_000_000_000_000_000_000_000 {
        n &+= 1
        pow &*= 10
      }
      (quo, rem) = lo.quotientAndRemainder(dividingBy: pow)
      e &+= n
    } else {
      pow = 1
      (quo, rem) = (lo, 0)
    }

    guard e <= 12287 else {
      // Overflow.
      let x: Self = switch rule {
      case .awayFromZero:
        isSignMinus ? -.infinity : .infinity
      case .down:
        isSignMinus ? -.infinity : .greatestFiniteMagnitude
      case .toNearestOrAwayFromZero:
        isSignMinus ? -.infinity : .infinity
      case .toNearestOrEven:
        isSignMinus ? -.infinity : .infinity
      case .towardZero:
        isSignMinus ? -.greatestFiniteMagnitude : .greatestFiniteMagnitude
      case .up:
        isSignMinus ? -.greatestFiniteMagnitude : .infinity
      @unknown default:
        fatalError("Not implemented")
      }
      return _signal(.overflow, default: x)
    }

    if rem == 0 {
      // Exact result.
      let abs = Self(bitPattern: UInt128(truncatingIfNeeded: e) &<< 113 | quo)
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
      fatalError("Not implemented")
    }
    if nextAway {
      if quo == 9_999_999_999_999_999_999_999_999_999_999_999 {
        if e == 12287 {
          return _signal(
            .overflowInexact, default: isSignMinus ? -.infinity : .infinity)
        }
        quo = 1_000_000_000_000_000_000_000_000_000_000_000
        e &+= 1
      } else {
        quo &+= 1
      }
    }
    let abs = Self(bitPattern: UInt128(truncatingIfNeeded: e) &<< 113 | quo)
    return _signal(.inexact, default: isSignMinus ? -abs : abs)
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
extension Decimal128: Strideable {
  @inlinable
  public func distance(to other: Self) -> Self { other - self }

  @inlinable
  public func advanced(by n: Self) -> Self { self + n }
}

@available(macOS 15.0, *)
extension Decimal128 {
  public init<T: BinaryInteger>(_ source: T) {
    fatalError("Not implemented")
  }

  public init?(exactly source: Float16) {
    fatalError("Not implemented")
  }

  public init?(exactly source: Float) {
    fatalError("Not implemented")
  }

  public init?(exactly source: Double) {
    fatalError("Not implemented")
  }

  public init?<T: BinaryFloatingPoint>(exactly source: T) {
    fatalError("Not implemented")
  }

  public init(_ source: Float16) {
    fatalError("Not implemented")
  }

  public init(_ source: Float) {
    fatalError("Not implemented")
  }

  public init(_ source: Double) {
    fatalError("Not implemented")
  }

  public init<T: BinaryFloatingPoint>(_ source: T) {
    fatalError("Not implemented")
  }

  // TODO: Conversion from `Decimal128` to binary integer or floating point.
}

@available(macOS 15.0, *)
extension Decimal128: FloatingPoint {
  @_transparent
  public func isEqual(to other: Self) -> Bool { self == other }

  @_transparent
  public func isLess(than other: Self) -> Bool { self < other }

  @_transparent
  public func isLessThanOrEqualTo(_ other: Self) -> Bool { self <= other }

  public func isTotallyOrdered(belowOrEqualTo other: Self) -> Bool {
    fatalError("Not implemented")
  }

  public func addingProduct(
    _ lhs: Self, _ rhs: Self, rounding rule: FloatingPointRoundingRule
  ) -> Self {
    fatalError("Not implemented")
  }

  @inlinable
  @inline(__always)
  public mutating func addProduct(
    _ lhs: Self, _ rhs: Self, rounding rule: FloatingPointRoundingRule
  ) {
    self = addingProduct(lhs, rhs, rounding: rule)
  }

  @inlinable
  @inline(__always)
  public func addingProduct(_ lhs: Self, _ rhs: Self) -> Self {
    addingProduct(lhs, rhs, rounding: .toNearestOrEven)
  }

  @inlinable
  @inline(__always)
  public mutating func addProduct(_ lhs: Self, _ rhs: Self) {
    self = addingProduct(lhs, rhs)
  }

  public func divided(
    by rhs: Self, rounding rule: FloatingPointRoundingRule = .toNearestOrEven
  ) -> Self {
    fatalError("Not implemented")
  }

  @inlinable
  @inline(__always)
  public static func / (lhs: Self, rhs: Self) -> Self {
    lhs.divided(by: rhs)
  }

  @inlinable
  @inline(__always)
  public static func /= (lhs: inout Self, rhs: Self) {
    lhs = lhs / rhs
  }

  public func remainder(dividingBy other: Self) -> Self {
    fatalError("Not implemented")
  }

  @inlinable
  @inline(__always)
  public mutating func formRemainder(dividingBy other: Self) {
    self = remainder(dividingBy: other)
  }

  public func truncatingRemainder(dividingBy other: Self) -> Self {
    fatalError("Not implemented")
  }

  @inlinable
  @inline(__always)
  public mutating func formTruncatingRemainder(dividingBy other: Self) {
    self = truncatingRemainder(dividingBy: other)
  }

  public func squareRoot(rounding rule: FloatingPointRoundingRule) -> Self {
    fatalError("Not implemented")
  }

  @inlinable
  @inline(__always)
  public mutating func formSquareRoot(
    rounding rule: FloatingPointRoundingRule
  ) {
    self = squareRoot(rounding: rule)
  }

  @inlinable
  @inline(__always)
  public func squareRoot() -> Self {
    squareRoot(rounding: .toNearestOrEven)
  }

  @inlinable
  @inline(__always)
  public mutating func formSquareRoot() {
    self = squareRoot()
  }

  public func rounded(_ rule: FloatingPointRoundingRule) -> Self {
    if isSignalingNaN {
      return _signal(.invalid, default: _quiet._canonical)
    }
    fatalError("Not implemented")
  }

  @inlinable
  @inline(__always)
  public mutating func round(_ rule: FloatingPointRoundingRule) {
    self = rounded(rule)
  }
}

@available(macOS 15.0, *)
extension Decimal128 {
  @_transparent
  public var binaryEncoding: UInt128 { bitPattern }

  @_transparent
  public init(binaryEncoding: UInt128) {
    bitPattern = binaryEncoding
  }

  @inlinable
  public var decimalEncoding: UInt128 {
    let canonicalBitPattern = _canonical.bitPattern

    // With a canonical bit pattern, if the significand is non-zero,
    // then we have either a finite non-zero value or a NaN payload,
    // and we can unconditionally retrieve the lower 113 bits to
    // obtain it.
    //
    // For non-finite values, note that this does *not* include an
    // always-set leading bit, unlike `significandBitPattern`. This
    // means that we cannot recover the `Decimal128` value using
    // `init(sign:exponentBitPattern:significandBitPattern:)` without
    // special handling of the exponent bit pattern, but we have no
    // intention of doing so anyway because we'll need to encode the
    // exponent differently.
    //
    // Meanwhile, `_DPD.encode(_:)` will *reject* any extraneous
    // always-set leading bit in the significand as non-canonical,
    // so manually retrieving the lower 113 bits is exactly what we
    // want here.
    let c = canonicalBitPattern & (1 &<< 113 &- 1)

    guard isFinite else {
      // TODO: Does this operation signal any exceptions?
      var result = canonicalBitPattern & (0x3f800 &<< 110)
      // Encode any NaN payload.
      if c != (0 as UInt128) {
        result |= _DPD.encode(c)
      }
      // An early exit here avoids having to consider non-finite
      // combination field bit patterns later.
      return result
    }
    let c10 = c != (0 as UInt128) ? _DPD.encode(c) : 0

    // Though the biased exponent of a canonical finite value is always
    // encoded in the same bits in the *binary* encoding of `Decimal128`,
    // the *decimal* encoding requires right-shifting some of these bits.
    //
    // Which bits and how much to shift depends on the leading digit of
    // the DPD-encoded significand:
    //
    //      ┌─ Combination ─┐  ┌──── Trailing significand ───── (...)
    //
    //   Binary encoding:
    //   s  eeeeeeeeeeeeeeccc  cccccccccc cccccccccc cccccccccc
    //      ══════════════
    //
    //   Decimal encoding *if leading digit is less than 8*:
    //   s  eeccceeeeeeeeeeee  cccccccccc cccccccccc cccccccccc
    //      ══   ════════════
    //
    //   Decimal encoding *if leading digit is 8 or 9*:
    //   (Of course, top 3 bits of leading digit are not explicitly encoded)
    //   s  11eeceeeeeeeeeeee  cccccccccc cccccccccc cccccccccc
    //        ══ ════════════
    //
    //   (Legend--s: sign; e: exponent; c: concatenated significand)
    var result: UInt128
    if (c10 &>> 110) < 8 {
      // Copy sign bit and top 2 bits of exponent en bloc.
      result = canonicalBitPattern & (0x38000 &<< 110)
      // Shift in the leading digit of the significand,
      // setting at most 3 bits since it's less than 8.
      result |= (c10 & (7 &<< 110)) &<< 12
    } else {
      // Copy sign bit.
      result = canonicalBitPattern & (1 &<< 127)
      // Set 2 bits that trail the sign bit.
      result |= 3 &<< 125
      // Shift the top 2 bits of the exponent right by 2.
      result |= (canonicalBitPattern & (0x18000 &<< 110)) &>> 2
      // Shift in the leading digit of the significand,
      // but only its bottom bit since the rest aren't explicitly encoded.
      result |= (c10 & (1 &<< 110)) &<< 12
    }
    // Shift the remaining 12 bits of the exponent right by 3.
    result |= (canonicalBitPattern & (0x7ff8 &<< 110)) &>> 3
    // Copy the remaining 110 bits of `c10`--i.e., the trailing significand.
    result |= c10 & (1 &<< 110 &- 1)
    return result
  }

  @inlinable
  public init(decimalEncoding: UInt128) {
    // Extract the combination field.
    let g10 = UInt(truncatingIfNeeded: decimalEncoding &>> 110) & 0x1ffff

    guard g10 < 0x1e000 else {
      // If we're here, then the value being decoded isn't finite.
      if g10 < 0x1f000 {
        // Infinity.
        //
        // We consider this case separately because we need to clear any
        // extraneous bits for a canonical encoding.
        bitPattern = decimalEncoding & (0x3e000 &<< 110)
      } else {
        // NaN.
        // TODO: Does this operation signal any exceptions?
        bitPattern = decimalEncoding & (0x3f800 &<< 110)
        // Decode any NaN payload.
        let payload10 = decimalEncoding & (1 &<< 110 &- 1)
        if payload10 != (0 as UInt128) {
          bitPattern |= _DPD.decode(payload10)
        }
      }
      // An early exit here avoids having to consider non-finite
      // combination field bit patterns later.
      return
    }

    // (Refer to the diagram in the implementation of `decimalEncoding`.)
    //
    // How to concatenate the leading digit to the trailing significand
    // depends on the value of the 2 bits immediately trailing the sign bit.
    var c10 = decimalEncoding & (1 &<< 110 &- 1)
    if g10 < 0x18000 {
      // If we're here, then the leading digit is less than 8.
      c10 |= (decimalEncoding & (7 &<< 122)) &>> 12
      // Again, we'll copy the sign bit and top 2 bits of the exponent en bloc.
      bitPattern = decimalEncoding & (0x38000 &<< 110)
    } else {
      // Otherwise, the leading digit is 8 or 9,
      // and only its bottom bit is explicitly encoded.
      c10 |= (decimalEncoding & (1 &<< 122)) &>> 12
      c10 |= 1 &<< 113
      // Copy sign bit.
      bitPattern = decimalEncoding & (1 &<< 127)
      // Shift the top 2 bits of the exponent left by 2.
      bitPattern |= (decimalEncoding & (3 &<< 123)) &<< 2
    }
    // Shift the remaining 12 bits of the exponent left by 3.
    bitPattern |= (decimalEncoding & (0xfff &<< 110)) &<< 3
    // Copy the decoding of the concatenated significand,
    // which we know cannot exceed 113 bits.
    bitPattern |= c10 != (0 as UInt128) ? _DPD.decode(c10) : 0
  }
}

@available(macOS 15.0, *)
extension Decimal128: CustomStringConvertible {
  public var description: String {
    guard _isFiniteNonzero else {
      if isSignalingNaN {
        return _signal(.invalid, default: _isSignMinus ? "-nan" : "nan")
      }

      if isNaN {
        return _isSignMinus ? "-nan" : "nan"
      }

      if isInfinite {
        return _isSignMinus ? "-inf" : "inf"
      }

      // TODO: Decide if we want to preserve quantum.
      return _isSignMinus ? "-0.0" : "0.0"
    }

    // TODO: Re-implement.
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
            index += 1
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

@available(macOS 15.0, *)
extension Decimal128: LosslessStringConvertible {
  public init?<T: StringProtocol>(_ description: T) {
    fatalError("Not implemented")
  }
}
