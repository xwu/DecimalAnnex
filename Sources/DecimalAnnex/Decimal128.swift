/// A 128-bit decimal floating-point value.
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
@frozen
public struct Decimal128: BitwiseCopyable, Sendable {
  /// The bit pattern of the value’s binary encoding.
  public var bitPattern: UInt128

  /// Creates a new value with the given binary-encoded bit pattern.
  ///
  /// - Parameters:
  ///   - bitPattern: The binary encoding of a `Decimal128` instance.
  @inline(always)
  public init(bitPattern: UInt128) {
    self.bitPattern = bitPattern
  }

  /// Creates a new value equal to zero.
  @inline(always)
  public init() {
    bitPattern = 6176 &<< 113
  }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension Decimal128 {
  @inlinable
  public var sign: FloatingPointSign {
    let rawValue = Int(truncatingIfNeeded: bitPattern &>> 127)
    return unsafe FloatingPointSign(rawValue: rawValue).unsafelyUnwrapped
  }

  @inlinable
  internal var _isSignMinus: Bool {
    @inline(always) get { bitPattern &>> 127 == 1 }
  }

  @inlinable
  public var magnitude: Decimal128 {
    @inline(always) get { Self(bitPattern: bitPattern & (~0 &>> 1)) }
  }

  @inlinable
  public static prefix func - (operand: Decimal128) -> Decimal128 {
    var result = operand
    result.negate()
    return result
  }

  @inlinable
  public mutating func negate() {
    bitPattern ^= 1 &<< 127
  }

  @inlinable
  public init(signOf sign: Decimal128, magnitudeOf magnitude: Decimal128) {
    bitPattern =
      (sign.bitPattern & (1 &<< 127)) | (magnitude.bitPattern & (~0 &>> 1))
  }
}


@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension Decimal128 {
#if false
  /// A type that represents the encoded exponent of a value.
  public typealias RawExponent = UInt

  /// A type that represents the encoded significand of a value.
  public typealias RawSignificand = UInt128
#endif

  /// The raw encoding of the value's combination field.
  @inlinable
  internal var _combinationBitPattern: UInt {
    @inline(always) get {
      UInt(truncatingIfNeeded: bitPattern &>> 110) & 0x1ffff
    }
  }

  /// The raw encoding of the value's trailing significand field.
  @inlinable
  internal var _trailingSignificandBitPattern: UInt128 {
    @inline(always) get {
      bitPattern & (1 &<< 110 &- 1)
    }
  }

  /// Creates a new instance from the specified sign and bit patterns.
  ///
  /// - Parameters:
  ///   - sign: The sign of the new value.
  ///   - combinationBitPattern: The bit pattern to use for the combination
  ///     field of the new value.
  ///   - trailingSignificandBitPattern: The bit pattern to use for the trailing
  ///     significand field of the new value.
  @inlinable
  internal init(
    _sign: FloatingPointSign,
    combinationBitPattern: UInt,
    trailingSignificandBitPattern: UInt128
  ) {
    bitPattern =
      (UInt128(truncatingIfNeeded: _sign.rawValue) &<< 127)
      | (UInt128(truncatingIfNeeded: combinationBitPattern & 0x1ffff) &<< 110)
      | (trailingSignificandBitPattern & (1 &<< 110 &- 1))
  }

  /// The 14-bit encoding of the value's exponent field.
  ///
  /// This property is unadjusted by the exponent bias. In the case of
  /// non-finite values, it excludes two leading bits of the combination field
  /// and includes extra trailing bits.
  @inlinable
  public var exponentBitPattern: UInt {
    if magnitude.bitPattern < (0x3 &<< 125) {
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
    if magnitude.bitPattern < (0x3 &<< 125) {
      bitPattern & (1 &<< 113 &- 1)
    } else {
      bitPattern & (1 &<< 111 &- 1) | (1 &<< 113)
    }
  }

  /// Creates a new instance from the specified sign and bit patterns.
  ///
  /// To create a non-finite value:
  /// - set the implicit leading bit of the 114-bit pattern passed as
  ///   `significandBitPattern`; and
  /// - exclude two leading bits of the combination field and include extra
  ///   trailing bits to pad the 14-bit pattern passed as `exponentBitPattern`.
  ///
  /// - Parameters:
  ///   - sign: The sign of the new value.
  ///   - exponentBitPattern: The bit pattern to use for the exponent field of
  ///     the new value.
  ///   - significandBitPattern: The bit pattern to use for the concatenated
  ///     significand field of the new value, including any implicit leading
  ///     bit.
  @inlinable
  public init(
    sign: FloatingPointSign,
    exponentBitPattern: UInt,
    significandBitPattern: UInt128
  ) {
    if (significandBitPattern &>> 113) & 1 == 0 {
      bitPattern =
        (UInt128(truncatingIfNeeded: sign.rawValue) &<< 127)
        | (UInt128(truncatingIfNeeded: exponentBitPattern & 0x3fff) &<< 113)
        | (significandBitPattern & (1 &<< 113 &- 1))
    } else {
      bitPattern =
        (UInt128(truncatingIfNeeded: sign.rawValue) &<< 127)
        | (UInt128(
            truncatingIfNeeded: (exponentBitPattern & 0x3fff) | 0xc000) &<< 111)
        | (significandBitPattern & (1 &<< 111 &- 1))
    }
  }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension Decimal128 {
  @inlinable
  public static var nan: Decimal128 {
    Self(bitPattern: 0x1f000 &<< 110)
  }

  @inlinable
  public static var signalingNaN: Decimal128 {
    Self(bitPattern: 0x1f800 &<< 110)
  }

  /// Creates a NaN ("not a number") value with the specified payload.
  ///
  /// - Parameters:
  ///   - payload: The payload to use for the new NaN value.
  ///   - signaling: Pass `true` to create a signaling NaN or `false` to create
  ///     a quiet NaN.
  @inlinable
  public init(nan payload: UInt128, signaling: Bool) {
    precondition(payload < (1 &<< 110), "NaN payload is not encodable.")
    bitPattern = ((signaling ? 0x1f800 : 0x1f000) &<< 110) | payload
  }

  @inlinable
  public static var infinity: Decimal128 {
    Self(bitPattern: 0x1e000 &<< 110)
  }

  @inlinable
  public static var greatestFiniteMagnitude: Decimal128 {
    Self(bitPattern: (12287 &<< 113) | 9_999_999_999_999_999_999_999_999_999_999_999)
  }

  @inlinable
  public static var leastNormalMagnitude: Decimal128 {
    Self(bitPattern: (33 &<< 113) | 1)
  }

  @inlinable
  public static var leastNonzeroMagnitude: Decimal128 {
    Self(bitPattern: 1)
  }

  @inlinable
  public static var pi: Decimal128 {
    Self(bitPattern: (6143 &<< 113) | 3_141_592_653_589_793_238_462_643_383_279_503)
  }

  @inlinable
  public var isCanonical: Bool {
    let g = _combinationBitPattern
    guard g < 0x1f000 else {
      // NaN is canonical if:
      // - all but the most significant six bits of the combination field are
      //   zero; and
      // - the payload, which is the trailing significand field, is not more
      //   than 10 ** 33 - 1 (note the exponent).
      return g & 0x7ff == 0 &&
        _trailingSignificandBitPattern <=
          999_999_999_999_999_999_999_999_999_999_999
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
      9_999_999_999_999_999_999_999_999_999_999_999
  }

  /// The value represented in its canonical form.
  ///
  /// Decimal floating-point types admit a large number of non-canonical
  /// encodings. Finite non-canonical values are canonicalized as zeros.
  /// Consult the IEEE 754 standard for additional details.
  @inlinable
  internal var _canonical: Decimal128 {
    let g = _combinationBitPattern
    guard g < 0x1f000 else {
      var mask: UInt128 = 0x3f800 &<< 110
      if _trailingSignificandBitPattern <=
          999_999_999_999_999_999_999_999_999_999_999 {
        mask |= 1 &<< 110 &- 1
      }
      return Self(bitPattern: bitPattern & mask)
    }
    guard g < 0x1e000 else {
      return Self(bitPattern: bitPattern & (0x3e000 &<< 110))
    }
    guard g < 0x18000 &&
      (bitPattern & (1 &<< 113 &- 1) <=
        9_999_999_999_999_999_999_999_999_999_999_999) else {
      return Self(
        sign: sign,
        exponentBitPattern: exponentBitPattern,
        significandBitPattern: 0)
    }
    return self
  }

  @inlinable
  public var isNaN: Bool {
    @inline(always) get { _combinationBitPattern >= 0x1f000 }
  }

  @inlinable
  public var isSignalingNaN: Bool {
    @inline(always) get { _combinationBitPattern >= 0x1f800 }
  }

  // The value with its representation unchanged except to clear the signaling
  // bit if the value is NaN ("not a number").
  @inlinable
  internal var _quiet: Decimal128 {
    @inline(always) get {
      _combinationBitPattern < 0x1f800
        ? self
        : Self(bitPattern: bitPattern ^ (1 &<< 121))
    }
  }

  @inlinable
  public var isInfinite: Bool {
    @inline(always) get {
      let g = _combinationBitPattern
      return g >= 0x1e000 && g < 0x1f000
    }
  }

  @inlinable
  public var isFinite: Bool {
    @inline(always) get { _combinationBitPattern < 0x1e000 }
  }

  /// A Boolean value indicating whether this instance is both finite and not
  /// equal to zero.
  @inlinable
  internal var _isFiniteNonzero: Bool {
    @inline(always) get {
      guard _combinationBitPattern < 0x18000 else { return false }
      // Having excluded all values where the combination field begins `11...`,
      // we know the represented significand is in the lower 113 bits.
      let c = bitPattern & (1 &<< 113 &- 1)
      return c > 0 && c < 10_000_000_000_000_000_000_000_000_000_000_000
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
    return c > 0 && c < UInt128._exp10(33 - Int(e))
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
      return c > 0 && c < 10_000_000_000_000_000_000_000_000_000_000_000
    }
    return c >= UInt128._exp10(33 - Int(e)) &&
      c < 10_000_000_000_000_000_000_000_000_000_000_000
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
    return c == 0 || c > 9_999_999_999_999_999_999_999_999_999_999_999
  }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension Decimal128 {
  public var nextUp: Decimal128 {
    guard _isFiniteNonzero else {
      if isSignalingNaN {
        return _signal(.invalid, default: _quiet._canonical)
      }
      if isNaN {
        return _canonical
      }
      if isInfinite {
        return _isSignMinus ? -.greatestFiniteMagnitude : .infinity
      }
      return .leastNonzeroMagnitude
    }

    var e = exponentBitPattern
    var c = significandBitPattern
    if e != 0 {
      // Estimate log10(c). See `UInt128._log10` for a detailed explanation.
      // It is important that this estimate be at least the true floor log10 and
      // at most one greater.
      let estimate = ((19 &* (127 &- (c|1).leadingZeroBitCount)) &>> 6) &+ 1
      let n = min(e, UInt(max(0, 33 &- estimate)))
      if n != 0 {
        c &*= UInt128._exp10(Int(n))
        e &-= n
      }
      if e != 0 && c <= 999_999_999_999_999_999_999_999_999_999_999 {
        c &*= 10
        e &-= 1
      }
    }
    if _isSignMinus {
      if e != 0 && c == 1_000_000_000_000_000_000_000_000_000_000_000 {
        c = 9_999_999_999_999_999_999_999_999_999_999_999
        e &-= 1
      } else {
        c &-= 1
      }
    } else {
      if c == 9_999_999_999_999_999_999_999_999_999_999_999 {
        if e == 12287 { return .infinity }
        c = 1_000_000_000_000_000_000_000_000_000_000_000
        e &+= 1
      } else {
        c &+= 1
      }
    }
    return Self(sign: sign, exponentBitPattern: e, significandBitPattern: c)
  }

  @inlinable
  public var nextDown: Decimal128 {
    @inline(always) get { -(-self).nextUp }
  }

  @inlinable
  public var ulp: Decimal128 {
    guard _isFiniteNonzero else {
      if isNaN {
        return .nan
      }
      return .leastNonzeroMagnitude
    }
    let e = exponentBitPattern
    let c = significandBitPattern
    return Self(
      sign: .plus,
      exponentBitPattern: UInt(
        truncatingIfNeeded: max(0, Int(e) &+ c._commonLogarithm &- 33)),
      significandBitPattern: 1)
  }
  // TODO: File bug to clarify documentation for `FloatingPoint.ulp`.

  /// The quantum, or decade, of this value.
  ///
  /// If `x` is finite, then `x.quantum` is equivalent to `x.ulp`. However,
  /// if `x` is infinite, then `x.quantum` is `infinity` even as `x.ulp` is NaN.
  ///
  /// This property implements the `quantum` operation defined by the IEEE 754
  /// specification.
  @inlinable
  public var quantum: Decimal128 {
    guard isFinite else {
      let result = Self(bitPattern: bitPattern & Self.nan.bitPattern)
      return isSignalingNaN ? _signal(.invalid, default: result) : result
    }
    // Exact result.
    // Under default exception handling, no underflow is signaled.
    return Self(
      sign: sign,
      exponentBitPattern: exponentBitPattern,
      significandBitPattern: 1)
  }

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

  /// Returns a Boolean value indicating whether this value has the same quantum
  /// as another.
  ///
  /// Two finite values have the same quantum if they have the same exponent
  /// bit pattern. Any two infinite values have the same quantum, as do any two
  /// NaN ("not a number") values. If exactly one of two values is infinite or
  /// exactly one of two values is NaN, then those two values do not have the
  /// same quantum.
  ///
  /// This method implements the `sameQuantum` operation defined by the IEEE 754
  /// specification.
  ///
  /// - Parameters:
  ///   - other: The value to use for comparing quantums with this value.
  @inlinable
  public func hasSameQuantum(as other: Decimal128) -> Bool {
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
  public var significand: Decimal128 {
    guard isFinite else { return magnitude._canonical }
    guard !isZero else { return Self() }
    let c = significandBitPattern
    let e = 6176 &- c._commonLogarithm
    return Self(bitPattern: UInt128(truncatingIfNeeded: e) &<< 113 | c)
  }

  public init(sign: FloatingPointSign, exponent: Int, significand: Decimal128) {
    // scaleB
    fatalError("Not implemented")
  }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension Decimal128: Equatable {
  @inlinable
  public static func == (lhs: Decimal128, rhs: Decimal128) -> Bool {
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

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension Decimal128: Hashable {
  /// Returns the result of adding +0 to the value using the default rounding
  /// mode and without signaling any floating-point exceptions.
  ///
  /// The +0 operand is represented with the least possible exponent such that
  /// the result is represented with the least possible exponent.
  @inlinable
  internal func _addingZeroWithLeastQuantum() -> Decimal128 {
    guard _isFiniteNonzero else {
      if isNaN {
        // Note that `mask` will clear the signaling bit, silencing sNaN.
        var mask: UInt128 = 0x3f000 &<< 110
        // Preserve the payload (i.e., trailing significand bit pattern) only if
        // it is canonical.
        if _trailingSignificandBitPattern <=
            999_999_999_999_999_999_999_999_999_999_999 {
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
    guard e != 0 else { return self }
    var c = significandBitPattern
    // Estimate log10(c). See `UInt128._log10` for a detailed explanation.
    // It is important that this estimate be at least the true floor log10 and
    // at most one greater.
    let estimate = ((19 &* (127 &- (c|1).leadingZeroBitCount)) &>> 6) &+ 1
    let n = min(e, UInt(max(0, 33 &- estimate)))
    if n != 0 {
      c &*= UInt128._exp10(Int(n))
      e &-= n
    }
    if e != 0 && c <= 999_999_999_999_999_999_999_999_999_999_999 {
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

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension Decimal128: Comparable {
  @inlinable
  public static func < (lhs: Decimal128, rhs: Decimal128) -> Bool {
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
    let scaled = lc.multipliedFullWidth(by: UInt128._exp10(n))
    return isSwapped ? scaled > (0, rc) : scaled < (0, rc)
  }

  @inlinable
  public static func > (lhs: Decimal128, rhs: Decimal128) -> Bool {
    return rhs < lhs
  }

  @inlinable
  public static func <= (lhs: Decimal128, rhs: Decimal128) -> Bool {
    if lhs.isNaN || rhs.isNaN {
      return _signal(.invalid, default: false)
    }
    return !(rhs < lhs)
  }

  @inlinable
  public static func >= (lhs: Decimal128, rhs: Decimal128) -> Bool {
    if lhs.isNaN || rhs.isNaN {
      return _signal(.invalid, default: false)
    }
    return !(lhs < rhs)
  }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension Decimal128: ExpressibleByIntegerLiteral {
  @inlinable
  public init(integerLiteral value: Int128) {
    bitPattern = value.magnitude
    guard bitPattern <= 9_999_999_999_999_999_999_999_999_999_999_999 else {
      fatalError("Potentially inexact integer conversion not implemented")
    }
    bitPattern |= Self().bitPattern
    if value < 0 { self.negate() }
  }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension Decimal128: AdditiveArithmetic {
  @inlinable
  @inline(__always)
  internal static func _round(
    _ isSignMinus: Bool,
    _ biasedExponent: Int,
    _ significand: (high: UInt128, low: UInt128),
    _ rule: FloatingPointRoundingRule
  ) -> Decimal128 {
    var e = biasedExponent
    let (hi, lo) = significand

    // Per IEEE 754, detect tininess (i.e., underflow) before rounding.
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
          fatalError("Unknown rounding rule.")
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
        ? (rem, rem_) > (pow &>> 1, 0)
        : rem >= (pow &>> 1)
      case .towardZero:
        false
      case .up:
        !isSignMinus
      @unknown default:
        fatalError("Unknown rounding rule.")
      }
      assert(e == 0)
      let abs = Self(bitPattern: nextAway ? quo &+ 1 : quo)
      return _signal(.underflowInexact, default: isSignMinus ? -abs : abs)
    }

    // Remove decimal digits from intermediate result, if necessary.
    var pow, quo, rem: UInt128
    if hi != 0 {
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
    } else if lo > 9_999_999_999_999_999_999_999_999_999_999_999 {
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
        fatalError("Unknown rounding rule.")
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
      fatalError("Unknown rounding rule.")
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

  /// Returns the result of adding the given value to this value,
  /// rounding to a representable value if needed with the given rounding rule.
  ///
  /// This method implements the `addition` operation defined by the
  /// IEEE 754 specification.
  ///
  /// - Parameters:
  ///   - rhs: The value to add to this value.
  ///   - rule: The rounding rule for computing an inexact result.
  @inlinable
  public func adding(
    _ rhs: Decimal128,
    rounding rule: FloatingPointRoundingRule = .toNearestOrEven
  ) -> Decimal128 {
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
          // Adding ±0 and ±0. See IEEE 754 §6.3.
          let isSignMinus = rule == .down
            ? lhs._isSignMinus || rhs._isSignMinus
            : lhs._isSignMinus && rhs._isSignMinus
          let e = min(lhs.exponentBitPattern, rhs.exponentBitPattern)
          let abs = Self(bitPattern: UInt128(truncatingIfNeeded: e) &<< 113)
          return isSignMinus ? -abs : abs
        }
        // Swap operands so that `lhs` is nonzero and `rhs` is zero.
        swap(&lhs, &rhs)
        // Fall through.
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
      if e1 > e2 && c1 <= 999_999_999_999_999_999_999_999_999_999_999 {
        c1 &*= 10
        e1 &-= 1
      }
      return Self(
        sign: lhs.sign, exponentBitPattern: e1, significandBitPattern: c1)
    }

    var (e1, e2) = (lhs.exponentBitPattern, rhs.exponentBitPattern)
    if e1 < e2 {
      swap(&e1, &e2)
      swap(&lhs, &rhs)
    }
    let n = Int(e1 &- e2)

    var isSignMinus = lhs._isSignMinus

    var c1 = lhs.significandBitPattern
    let logc1 = c1._commonLogarithm
    let c2 = rhs.significandBitPattern
    if n &+ (logc1 &- c2._commonLogarithm) > 34 {
      // Inexact.
      var isTiny = false
      if logc1 < 33 {
        let n_ = UInt(33 &- logc1)
        if e1 < n_ {
          // Note that the result isn't tiny if `e1 == n_`.
          isTiny = true
          c1 &*= UInt128._exp10(Int(e1))
          e1 = 0
        } else {
          c1 &*= UInt128._exp10(Int(n_))
          e1 &-= n_
        }
      }
      if isSignMinus == rhs._isSignMinus {
        let nextAway: Bool = switch rule {
        case .awayFromZero:            true
        case .down:                    isSignMinus
        case .toNearestOrAwayFromZero: false
        case .toNearestOrEven:         false
        case .towardZero:              false
        case .up:                      !isSignMinus
        @unknown default:              fatalError("Unknown rounding rule.")
        }
        if nextAway {
          if c1 == 9_999_999_999_999_999_999_999_999_999_999_999 {
            if e1 == 12287 {
              return _signal(
                .overflowInexact, default: isSignMinus ? -.infinity : .infinity)
            }
            c1 = 1_000_000_000_000_000_000_000_000_000_000_000
            e1 &+= 1
          } else {
            c1 &+= 1
          }
        }
      } else {
        let nextToward: Bool = switch rule {
        case .awayFromZero:            false
        case .down:                    !isSignMinus
        case .toNearestOrAwayFromZero: false
        case .toNearestOrEven:         false
        case .towardZero:              true
        case .up:                      isSignMinus
        @unknown default:              fatalError("Unknown rounding rule.")
        }
        if nextToward {
          if c1 == 1_000_000_000_000_000_000_000_000_000_000_000 {
            if e1 == 0 {
              isTiny = true
              c1 &-= 1
            } else {
              c1 = 9_999_999_999_999_999_999_999_999_999_999_999
              e1 &-= 1
            }
          } else {
            c1 &-= 1
          }
        }
      }
      let abs = Self(bitPattern: UInt128(truncatingIfNeeded: e1) &<< 113 | c1)
      return _signal(
        isTiny ? .underflowInexact : .inexact,
        default: isSignMinus ? -abs : abs)
    }

    // Compute the intermediate result.
    var (hi, lo) = n == 0
      ? (0, c1)
      : c1.multipliedFullWidth(by: UInt128._exp10(n))
    if isSignMinus == rhs._isSignMinus {
      let carry: Bool
      (lo, carry) = lo.addingReportingOverflow(c2)
      if carry { hi &+= 1 }
    } else {
      let borrow: Bool
      (lo, borrow) = lo.subtractingReportingOverflow(c2)
      if borrow {
        if hi == 0 {
          lo = ~lo &+ 1
          isSignMinus.toggle()
        } else {
          hi &-= 1
        }
      } else if (hi, lo) == (0, 0) {
        // Exact zero. See IEEE 754 §6.3.
        isSignMinus = rule == .down
        let abs = Self(bitPattern: UInt128(truncatingIfNeeded: e2) &<< 113)
        return isSignMinus ? -abs : abs
      }
    }

    return ._round(isSignMinus, Int(e2), (hi, lo), rule)
  }

  /// Adds the given value to this value in place,
  /// rounding to a representable value if needed with the given rounding rule.
  ///
  /// - Parameters:
  ///   - rhs: The value to add to this value.
  ///   - rule: The rounding rule for computing an inexact result.
  @inlinable
  @inline(__always)
  public mutating func add(
    _ rhs: Decimal128,
    rounding rule: FloatingPointRoundingRule = .toNearestOrEven
  ) {
    self = adding(rhs, rounding: rule)
  }

  /// Adds two values and produces their sum,
  /// rounding to a representable value if needed.
  ///
  /// This method implements the `addition` operation defined by the
  /// IEEE 754 specification.
  ///
  /// - Parameters:
  ///   - lhs: The first value to add.
  ///   - rhs: The second value to add.
  @inlinable
  @inline(__always)
  public static func + (lhs: Decimal128, rhs: Decimal128) -> Decimal128 {
    lhs.adding(rhs)
  }

  /// Adds two values and stores the result in the left-hand-side variable,
  /// rounding to a representable value if needed.
  ///
  /// - Parameters:
  ///   - lhs: The first value to add.
  ///   - rhs: The second value to add.
  @inlinable
  @inline(__always)
  public static func += (lhs: inout Decimal128, rhs: Decimal128) {
    lhs = lhs + rhs
  }

  /// Returns the result of subtracting the given value from this value,
  /// rounding to a representable value if needed with the given rounding rule.
  ///
  /// This method implements the `subtraction` operation defined by the
  /// IEEE 754 specification.
  ///
  /// - Parameters:
  ///   - rhs: The value to subtract from this value.
  ///   - rule: The rounding rule to use for computing an inexact result.
  @inlinable
  @inline(__always)
  public func subtracting(
    _ rhs: Decimal128,
    rounding rule: FloatingPointRoundingRule = .toNearestOrEven
  ) -> Decimal128 {
    adding(-rhs, rounding: rule)
  }

  /// Subtracts the given value from this value in place,
  /// rounding to a representable value if needed with the given rounding rule.
  ///
  /// - Parameters:
  ///   - rhs: The value to subtract from this value.
  ///   - rule: The rounding rule to use for computing an inexact result.
  @inlinable
  @inline(__always)
  public mutating func subtract(
    _ rhs: Decimal128,
    rounding rule: FloatingPointRoundingRule = .toNearestOrEven
  ) {
    self = subtracting(rhs, rounding: rule)
  }

  /// Subtracts one value from another and produces their difference,
  /// rounding to a representable value if needed.
  ///
  /// This method implements the `subtraction` operation defined by the
  /// IEEE 754 specification.
  ///
  /// - Parameters:
  ///   - lhs: A numeric value.
  ///   - rhs: The value to subtract from `lhs`.
  @inlinable
  @inline(__always)
  public static func - (lhs: Decimal128, rhs: Decimal128) -> Decimal128 {
    lhs.subtracting(rhs)
  }

  /// Subtracts the second value from the first and stores the difference in the
  /// left-hand-side variable, rounding to a representable value if needed.
  ///
  /// - Parameters:
  ///   - lhs: A numeric value.
  ///   - rhs: The value to subtract from `lhs`.
  @inlinable
  @inline(__always)
  public static func -= (lhs: inout Decimal128, rhs: Decimal128) {
    lhs = lhs - rhs
  }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension Decimal128: Numeric {
  /// Returns the result of multiplying this value by the given value,
  /// rounding to a representable value if needed with the given rounding rule.
  ///
  /// This method implements the `multiplication` operation defined by the
  /// IEEE 754 specification.
  ///
  /// - Parameters:
  ///   - rhs: The value by which to multiply this value.
  ///   - rule: The rounding rule to use for computing an inexact result.
  @inlinable
  public func multiplied(
    by rhs: Decimal128,
    rounding rule: FloatingPointRoundingRule = .toNearestOrEven
  ) -> Decimal128 {
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
    let e = Int(lhs.exponentBitPattern) &- 6176 &+ Int(rhs.exponentBitPattern)
    let (hi, lo) =
      lhs.significandBitPattern.multipliedFullWidth(
        by: rhs.significandBitPattern)

    return ._round(isSignMinus, e, (hi, lo), rule)
  }

  /// Multiplies this value by the given value in place, rounding to a
  /// representable value if needed with the given rounding rule.
  ///
  /// - Parameters:
  ///   - rhs: The value by which to multiply this value.
  ///   - rule: The rounding rule to use for computing an inexact result.
  @inlinable
  @inline(__always)
  public mutating func multiply(
    by rhs: Decimal128,
    rounding rule: FloatingPointRoundingRule = .toNearestOrEven
  ) {
    self = multiplied(by: rhs, rounding: rule)
  }

  /// Multiplies two values and produces their product,
  /// rounding to a representable value if needed.
  ///
  /// This method implements the `multiplication` operation defined by the
  /// IEEE 754 specification.
  ///
  /// - Parameters:
  ///   - lhs: The first value to multiply.
  ///   - rhs: The second value to multiply.
  @inlinable
  @inline(__always)
  public static func * (lhs: Decimal128, rhs: Decimal128) -> Decimal128 {
    lhs.multiplied(by: rhs)
  }

  /// Multiplies two values and stores the result in the left-hand-side
  /// variable, rounding to a representable value if needed.
  ///
  /// - Parameters:
  ///   - lhs: The first value to multiply.
  ///   - rhs: The second value to multiply.
  @inlinable
  @inline(__always)
  public static func *= (lhs: inout Decimal128, rhs: Decimal128) {
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

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension Decimal128: SignedNumeric { }

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension Decimal128: Strideable {
  @inlinable
  public func distance(to other: Decimal128) -> Decimal128 { other - self }

  @inlinable
  public func advanced(by n: Decimal128) -> Decimal128 { self + n }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension Decimal128 {
  public init<T: BinaryInteger>(_ source: T) {
    fatalError("Not implemented")
  }

#if false
  public init?(exactly source: Float16) {
    if source.isNaN {
      if source.isSignalingNaN { _signal(.invalid) }
      return nil
    }
    if source.isInfinite {
      self = source < 0 ? -.infinity : .infinity
      return
    }
    if source.isZero {
      self = source.sign == .minus ? -Self() : Self()
      return
    }

    if source.isSubnormal {
      // ...
    }
    fatalError("Not implemented")
  }

  public init?(exactly source: Float) {
    fatalError("Not implemented")
  }

  public init?(exactly source: Double) {
    fatalError("Not implemented")
  }
#endif

  public init?<T: BinaryFloatingPoint>(exactly source: T) {
    fatalError("Not implemented")
  }

#if false
  public init(_ source: Float16) {
    fatalError("Not implemented")
  }

  public init(_ source: Float) {
    fatalError("Not implemented")
  }

  public init(_ source: Double) {
    fatalError("Not implemented")
  }
#endif

  public init<T: BinaryFloatingPoint>(_ source: T) {
    fatalError("Not implemented")
  }

  // TODO: Conversion from `Decimal128` to binary integer or floating point.
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension Decimal128: FloatingPoint {
  @inlinable
  public static var radix: Int { 10 }

  @_transparent
  public func isEqual(to other: Decimal128) -> Bool { self == other }

  @_transparent
  public func isLess(than other: Decimal128) -> Bool { self < other }

  @_transparent
  public func isLessThanOrEqualTo(_ other: Decimal128) -> Bool { self <= other }

  public func isTotallyOrdered(belowOrEqualTo other: Decimal128) -> Bool {
    fatalError("Not implemented")
  }

  public func addingProduct(
    _ lhs: Decimal128, _ rhs: Decimal128,
    rounding rule: FloatingPointRoundingRule
  ) -> Decimal128 {
    fatalError("Not implemented")
  }

  @inlinable
  @inline(__always)
  public mutating func addProduct(
    _ lhs: Decimal128, _ rhs: Decimal128,
    rounding rule: FloatingPointRoundingRule
  ) {
    self = addingProduct(lhs, rhs, rounding: rule)
  }

  @inlinable
  @inline(__always)
  public func addingProduct(
    _ lhs: Decimal128, _ rhs: Decimal128
  ) -> Decimal128 {
    addingProduct(lhs, rhs, rounding: .toNearestOrEven)
  }

  @inlinable
  @inline(__always)
  public mutating func addProduct(_ lhs: Decimal128, _ rhs: Decimal128) {
    self = addingProduct(lhs, rhs)
  }

  public func divided(
    by rhs: Decimal128,
    rounding rule: FloatingPointRoundingRule = .toNearestOrEven
  ) -> Decimal128 {
    fatalError("Not implemented")
  }

  @inlinable
  @inline(__always)
  public static func / (lhs: Decimal128, rhs: Decimal128) -> Decimal128 {
    lhs.divided(by: rhs)
  }

  @inlinable
  @inline(__always)
  public static func /= (lhs: inout Decimal128, rhs: Decimal128) {
    lhs = lhs / rhs
  }

  public func remainder(dividingBy other: Decimal128) -> Decimal128 {
    fatalError("Not implemented")
  }

  @inlinable
  @inline(__always)
  public mutating func formRemainder(dividingBy other: Decimal128) {
    self = remainder(dividingBy: other)
  }

  public func truncatingRemainder(dividingBy other: Decimal128) -> Decimal128 {
    fatalError("Not implemented")
  }

  @inlinable
  @inline(__always)
  public mutating func formTruncatingRemainder(dividingBy other: Decimal128) {
    self = truncatingRemainder(dividingBy: other)
  }

  public func squareRoot(
    rounding rule: FloatingPointRoundingRule
  ) -> Decimal128 {
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
  public func squareRoot() -> Decimal128 {
    squareRoot(rounding: .toNearestOrEven)
  }

  @inlinable
  @inline(__always)
  public mutating func formSquareRoot() {
    self = squareRoot()
  }

  public func rounded(_ rule: FloatingPointRoundingRule) -> Decimal128 {
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

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension Decimal128 {
  /// The bit pattern of the value’s binary encoding.
  ///
  /// This property is equivalent to `bitPattern` and implements the
  /// `encodeBinary` operation defined by the IEEE 754 specification.
  @_transparent
  public var binaryEncoding: UInt128 { bitPattern }

  /// Creates a new value with the given binary-encoded bit pattern.
  ///
  /// This initializer is equivalent to `init(bitPattern:)` and implements the
  /// `decodeBinary` operation defined by the IEEE 754 specification.
  ///
  /// - Parameters:
  ///   - binaryEncoding: The binary encoding of a `Decimal128` instance.
  @_transparent
  public init(binaryEncoding: UInt128) {
    bitPattern = binaryEncoding
  }

  /// The bit pattern of the value's decimal encoding.
  ///
  /// The computed decimal encoding is canonical even if the value itself is not
  /// canonically encoded.
  ///
  /// This property implements the `encodeDecimal` operation defined by the
  /// IEEE 754 specification.
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
      var result = canonicalBitPattern & (0x3f800 &<< 110)
      // Encode any NaN payload.
      if c != 0 { result |= _DPD.encode(c) }
      // An early exit here avoids having to consider non-finite
      // combination field bit patterns later.
      return result
    }
    let c10 = (c != 0) ? _DPD.encode(c) : 0

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

  /// Creates a new value with the given decimal-encoded bit pattern.
  ///
  /// The result is canonically encoded even if the given decimal encoding is
  /// not canonical.
  ///
  /// This initializer implements the `decodeDecimal` operation defined by the
  /// IEEE 754 specification.
  ///
  /// - Parameters:
  ///   - decimalEncoding: The decimal encoding of a `Decimal128` instance.
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
        bitPattern = decimalEncoding & (0x3f800 &<< 110)
        // Decode any NaN payload.
        let payload10 = decimalEncoding & (1 &<< 110 &- 1)
        if payload10 != 0 {
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
    bitPattern |= (c10 != 0) ? _DPD.decode(c10) : 0
  }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension Decimal128: Codable {
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(binaryEncoding)
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    self = try Self(binaryEncoding: container.decode(UInt128.self))
  }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
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
      return _isSignMinus ? "-0." : "0."
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

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension Decimal128: LosslessStringConvertible {
  public init?<T: StringProtocol>(_ description: T) {
    fatalError("Not implemented")
  }
}
