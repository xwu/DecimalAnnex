import Numerics

extension UInt32 {
  @inlinable
  internal var _log10: Int {
    // See discussion at:
    // https://lemire.me/blog/2021/05/28/computing-the-number-of-digits-of-an-integer-quickly/
    let table: [Self] =
      [9, 99, 999, 9_999, 99_999, 999_999, 9_999_999, 99_999_999, 999_999_999]
    let estimate = (9 &* (31 &- (self|1).leadingZeroBitCount)) &>> 5
    return self > table[estimate] ? estimate &+ 1 : estimate
  }
}

@available(macOS 15.0, *)
extension UInt128 {
  @inlinable
  internal var _log10: Int {
    // Use a lookup table for smaller values.
    if self <= UInt32.max { return UInt32(self)._log10 }

    // See discussion at:
    // https://lemire.me/blog/2021/05/28/computing-the-number-of-digits-of-an-integer-quickly/
    //
    // To approximate `1 / log2(10)`, we must use 19/64 (expressed here as
    // `(19 &* ...) &>> 6`) instead of 9/32. This is so that the estimate is at
    // most one less than the true floor log10.
    //
    // Meanwhile, we avoid using an even more precise approximation such as
    // 39/128, because if we estimate `(UInt128.max)._log10` bang on then we'll
    // end up trying to compute `10 ** 39` while checking if our estimate is
    // off by one, which results in overflow.
    let estimate = (19 &* (127 &- (self|1).leadingZeroBitCount)) &>> 6
    // Now, use Yao's method to compute `10 ** (estimate + 1)`.
    let n = estimate &+ 1
    var y = 1 as Self
    y &*= 1 &+ 9 &* Self(truncatingIfNeeded: n & 1)
    y &*= 1 &+ 99 &* Self(truncatingIfNeeded: (n &>> 1) & 1)
    y &*= 1 &+ 9999 &* Self(truncatingIfNeeded: (n &>> 2) & 1)
    y &*= 1 &+ 9999_9999 &* Self(truncatingIfNeeded: (n &>> 3) & 1)
    y &*= 1 &+ 9999_9999_9999_9999 &* Self(truncatingIfNeeded: (n &>> 4) & 1)
    y &*=
      1 &+ 9999_9999_9999_9999_9999_9999_9999_9999 &*
        Self(truncatingIfNeeded: (n &>> 5) & 1)
    return self > y &- 1 ? estimate &+ 1 : estimate
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
    let rawValue = Int(truncatingIfNeeded: _encoding &>> 127)
    return FloatingPointSign(rawValue: rawValue).unsafelyUnwrapped
  }

  @inlinable
  internal var _isSignMinus: Bool {
    @inline(__always) get { _encoding &>> 127 == 1 }
  }

  @inlinable
  public var magnitude: Self {
    @inline(__always) get { Self(bitPattern: _encoding & (~0 &>> 1)) }
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
      UInt(truncatingIfNeeded: _encoding &>> 110) & (1 &<< 17 &- 1)
    }
  }

  /// The 14-bit encoding of the value's exponent field.
  ///
  /// This property is unadjusted by the exponent bias. In the case of
  /// non-finite values, it excludes two leading bits of the combination field
  /// and includes extra trailing bits.
  @inlinable
  public var exponentBitPattern: UInt {
    let g = _combinationBitPattern
    return if g < 0x18000 { g &>> 3 & 0x3fff } else { g &>> 1 & 0x3fff }
  }

  @inlinable
  internal var _trailingSignificandBitPattern: UInt128 {
    @inline(__always) get { _encoding & (1 &<< 110 &- 1) }
  }

  /// The 114-bit encoding of the value's concatenated significand field,
  /// including any implicit leading bit.
  ///
  /// In the case of non-finite values, the implicit leading bit is always set:
  /// for NaN values, this property includes the payload with extra leading
  /// bits; for infinite values, it includes ignored bits.
  @inlinable
  public var significandBitPattern: UInt128 {
    if _combinationBitPattern < 0x18000 {
      _encoding & (1 &<< 113 &- 1)
    } else {
      _encoding & (1 &<< 111 &- 1) | (1 &<< 113)
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
      (UInt128(truncatingIfNeeded: g & (1 &<< 17 &- 1)) &<< 110) |
      (t & (1 &<< 110 &- 1))
  }

  @inlinable
  public init(
    _sign: FloatingPointSign,
    exponentBitPattern e: UInt,
    significandBitPattern c: UInt128
  ) {
    if (c &>> 113) & 1 == 0 {
      _encoding =
        (UInt128(truncatingIfNeeded: _sign.rawValue) &<< 127) |
        (UInt128(truncatingIfNeeded: e & 0x3fff) &<< 113) |
        (c & (1 &<< 113 &- 1))
    } else {
      _encoding =
        (UInt128(truncatingIfNeeded: _sign.rawValue) &<< 127) |
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
      return magnitude._encoding == Self.infinity._encoding
    }
    // When the combination field begins `11...`,
    // all significands are noncanonical.
    guard g < 0x18000 else { return false }
    // Having excluded all values where the combination field begins `11...`,
    // we know the represented significand is in the lower 113 bits.
    return _encoding & (1 &<< 113 &- 1) <= 9_999_999_999_999_999_999_999_999_999_999_999 as UInt128
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
    let significand = _encoding & (1 &<< 113 &- 1)
    return significand == 0 ||
      significand > 9_999_999_999_999_999_999_999_999_999_999_999 as UInt128
  }
}

// MARK: - Quantum and exponent (5.3.2)
@available(macOS 15.0, *)
extension Decimal128 {
  @inlinable
  public var quantum: Self {
    if isFinite {
      Self(
        _sign: sign,
        exponentBitPattern: exponentBitPattern,
        significandBitPattern: 1)
    } else {
      Self(bitPattern: _encoding & Self.nan._encoding)
    }
  }

  @inlinable
  public func hasSameQuantum(as other: Self) -> Bool {
    guard isFinite && other.isFinite else {
      return _encoding & Self.nan._encoding ==
        other._encoding & Self.nan._encoding
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
