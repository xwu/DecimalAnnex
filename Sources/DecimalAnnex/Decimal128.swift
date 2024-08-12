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

    assert(estimate < 39)
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

#if false
    // Yao's method.
    var y = 1 as Self
    y &*= 1 &+ 9 &* Self(truncatingIfNeeded: n & 1)
    y &*= 1 &+ 99 &* Self(truncatingIfNeeded: (n &>> 1) & 1)
    y &*= 1 &+ 9999 &* Self(truncatingIfNeeded: (n &>> 2) & 1)
    y &*= 1 &+ 9999_9999 &* Self(truncatingIfNeeded: (n &>> 3) & 1)
    y &*= 1 &+ 9999_9999_9999_9999 &* Self(truncatingIfNeeded: (n &>> 4) & 1)
    y &*=
      1 &+ 9999_9999_9999_9999_9999_9999_9999_9999 &*
        Self(truncatingIfNeeded: (n &>> 5) & 1)
    return y
#endif
  }
}

@available(macOS 15.0, *)
@frozen
public struct Decimal128: Sendable {
  @usableFromInline @inline(__always)
  internal var _encoding: UInt128

  @_transparent
  public var bitPattern: UInt128 { _encoding }

  @_transparent
  public init() {
    _encoding = 0
  }

  @_transparent
  public init(bitPattern: UInt128) {
    _encoding = bitPattern
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
    _encoding ^= ~(~0 &>> 1)
  }

  @inlinable
  public init(signOf sign: Self, magnitudeOf magnitude: Self) {
    _encoding =
      (sign.bitPattern & (1 &<< 127)) |
        (magnitude.bitPattern & (~0 &>> 1))
  }
}


@available(macOS 15.0, *)
extension Decimal128 {
  public typealias RawSignificand = UInt128

  @inlinable
  internal static var _exponentBias: UInt {
    @inline(__always) get { 6176 }
  }

  @inlinable
  internal var _combinationBitPattern: UInt {
    @inline(__always) get {
      UInt(truncatingIfNeeded: bitPattern &>> 110) & 0x1ffff
    }
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

  @inlinable
  internal var _trailingSignificandBitPattern: UInt128 {
    @inline(__always) get {
      bitPattern & (1 &<< 110 &- 1)
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
  internal init(
    _sign: FloatingPointSign,
    combinationBitPattern g: UInt,
    trailingSignificandBitPattern t: UInt128
  ) {
    _encoding =
      (UInt128(truncatingIfNeeded: _sign.rawValue) &<< 127) |
        (UInt128(truncatingIfNeeded: g & 0x1ffff) &<< 110) |
          (t & (1 &<< 110 &- 1))
  }

  @inlinable
  public init(
    sign: FloatingPointSign,
    exponentBitPattern e: UInt,
    significandBitPattern c: UInt128
  ) {
    if (c &>> 113) & 1 == 0 {
      _encoding =
        (UInt128(truncatingIfNeeded: sign.rawValue) &<< 127) |
          (UInt128(truncatingIfNeeded: e & 0x3fff) &<< 113) |
            (c & (1 &<< 113 &- 1))
    } else {
      _encoding =
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
    Self(bitPattern: (0x17ff8 &<< 110) | 9_999_999_999_999_999_999_999_999_999_999_999)
  }

  @inlinable
  public static var leastNonzeroMagnitude: Self {
    Self(bitPattern: 1)
  }

  @inlinable
  public init(nan payload: UInt128, signaling: Bool) {
    _encoding =
      ((signaling ? 0x1f800 : 0x1f000) &<< 110) |
        (payload & (1 &<< 110 &- 1))
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
    // When the combination field begins `11...`,
    // all significands are noncanonical.
    guard g < 0x18000 else { return false }
    // Having excluded all values where the combination field begins `11...`,
    // we know the represented significand is in the lower 113 bits.
    return bitPattern & (1 &<< 113 &- 1) <= 9_999_999_999_999_999_999_999_999_999_999_999 as UInt128
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
  public var isSubnormal: Bool {
    @inline(__always) get { false }
  }

  @inlinable
  public var isNormal: Bool {
    @inline(__always) get { isFinite }
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

  @inlinable
  internal var _isFiniteNonzero: Bool {
    guard _combinationBitPattern < 0x18000 else { return false }
    // Having excluded all values where the combination field begins `11...`,
    // we know the represented significand is in the lower 113 bits.
    let c = bitPattern & (1 &<< 113 &- 1)
    return c > 0 as UInt128 && c < 10_000_000_000_000_000_000_000_000_000_000_000
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
    guard isFinite else { return .max }
    guard !isZero else { return .min }
    return Int(exponentBitPattern) - Int(Self._exponentBias) +
      significandBitPattern._log10
  }
}

@available(macOS 15.0, *)
extension Decimal128: Equatable {
  @inlinable
  public static func == (lhs: Self, rhs: Self) -> Bool {
    if lhs.bitPattern == rhs.bitPattern { return !lhs.isNaN }

    guard lhs._isFiniteNonzero && rhs._isFiniteNonzero else {
      if lhs.isNaN || rhs.isNaN { return false }

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
      n = -n
    }

    // Equivalent values cannot differ in exponent bit pattern by more than 33.
    if n > 33 { return false }
    let (lc, rc) = (lhs.significandBitPattern, rhs.significandBitPattern)
    guard lc < rc else { return false }
    return lc.multipliedFullWidth(by: UInt128._exp10(n)) == (high: 0, low: rc)
  }
}

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
      var string = String(_encoding & (1 &<< 113 &- 1))
      let count = string.utf8.count

      // We compute the exponent right away to determine if we need special
      // handling for the significand.
      let exponent =
        Int(_combinationBitPattern &>> 3) - Int(Self._exponentBias) + count - 1

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
