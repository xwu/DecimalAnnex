/// A 128-bit decimal floating-point value type.
@available(anyAppleOS 26.0, *)
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

@available(anyAppleOS 26.0, *)
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

  @inline(always)
  public static prefix func - (operand: Decimal128) -> Decimal128 {
    var result = operand
    result.negate()
    return result
  }

  @inline(always)
  public mutating func negate() {
    bitPattern ^= 1 &<< 127
  }

  @inlinable
  public init(signOf sign: Decimal128, magnitudeOf magnitude: Decimal128) {
    bitPattern =
      (sign.bitPattern & (1 &<< 127)) | (magnitude.bitPattern & (~0 &>> 1))
  }
}


@available(anyAppleOS 26.0, *)
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

@available(anyAppleOS 26.0, *)
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
      return g & 0x7ff == 0 && _trailingSignificandBitPattern < ._1e33
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
    return bitPattern & (1 &<< 113 &- 1) < ._1e34
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
      if _trailingSignificandBitPattern < ._1e33 {
        mask |= 1 &<< 110 &- 1
      }
      return Self(bitPattern: bitPattern & mask)
    }
    guard g < 0x1e000 else {
      return Self(bitPattern: bitPattern & (0x3e000 &<< 110))
    }
    guard g < 0x18000 && (bitPattern & (1 &<< 113 &- 1) < ._1e34) else {
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
      return c > 0 && c < ._1e34
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
    return unsafe c > 0 && c < UInt128._exp10[unchecked: 33 - Int(e)]
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
      return c > 0 && c < ._1e34
    }
    return unsafe c >= UInt128._exp10[unchecked: 33 - Int(e)] && c < ._1e34
  }

  @inlinable
  public var isZero: Bool {
    @inline(always) get {
      let g = _combinationBitPattern
      // When the combination field begins `11...`, either:
      // - the value is infinity or NaN; or
      // - the significand is noncanonical and treated as zero.
      guard g < 0x18000 else { return g < 0x1e000 }
      // Having excluded all values where the combination field begins `11...`,
      // we know the represented significand is in the lower 113 bits.
      let c = bitPattern & (1 &<< 113 &- 1)
      return c == 0 || c >= ._1e34
    }
  }
}

@available(anyAppleOS 26.0, *)
extension Decimal128 {
  @inlinable
  public var nextUp: Decimal128 {
    guard _isFiniteNonzero else {
      if isSignalingNaN {
        _signal(.invalid)
        return _quiet._canonical
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
      // Estimate log10(c). See `UInt128._commonLogarithm` for more explanation.
      // It is important that this estimate be at least the true floor log10 and
      // at most one greater.
      let estimate = ((19 &* (127 &- (c|1).leadingZeroBitCount)) &>> 6) &+ 1
      let n = min(e, UInt(max(0, 33 &- estimate)))
      if n != 0 {
        c &*= unsafe ._exp10[unchecked: Int(n)]
        e &-= n
      }
      if e != 0 && c < ._1e33 {
        c &*= 10
        e &-= 1
      }
    }
    if _isSignMinus {
      if e != 0 && c == ._1e33 {
        c = ._1e34 &- 1
        e &-= 1
      } else {
        c &-= 1
      }
    } else {
      if c == ._1e34 &- 1 {
        if e == 12287 { return .infinity }
        c = ._1e33
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

  // TODO: Clarify documentation for `FloatingPoint.ulp`.
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

  /// The quantum of this value.
  ///
  /// If `x` is finite, then `x.quantum` is the floating-point value with
  /// positive sign and the same represented exponent as this value, but with a
  /// significand of 1.0.
  /// If `x` is infinite, then `x.quantum` is positive `infinity`.
  ///
  /// This property implements the `quantum` operation defined by the IEEE 754
  /// specification. Unlike `BinaryFloatingPoint.binade`, the result of this
  /// operation is always positive.
  @inline(always)
  public var quantum: Decimal128 {
    var flags: DecimalFloatingPointStatusFlags = []
    return quantum(&flags)
  }

  /// Returns the quantum of this value, accumulating status flags.
  ///
  /// If `x` is finite, then the result is the floating-point value with
  /// positive sign and the same represented exponent as this value, but with a
  /// significand of 1.0.
  /// If `x` is infinite, then the result is positive `infinity`.
  ///
  /// This method implements the `quantum` operation defined by the IEEE 754
  /// specification. Unlike `BinaryFloatingPoint.binade`, the result of this
  /// operation is always positive.
  @inlinable
  public func quantum(
    _ flags: inout DecimalFloatingPointStatusFlags
  ) -> Decimal128 {
    guard isFinite else {
      if isSignalingNaN {
        flags.insert(.invalid)
        return _quiet._canonical
      }
      if isNaN {
        return _canonical
      }
      return .infinity
    }
    // Exact result.
    // Under default exception handling, no underflow is signaled.
    return Self(
      sign: .plus,
      exponentBitPattern: exponentBitPattern,
      significandBitPattern: 1)
  }

  @inline(always)
  public mutating func quantize(
    by other: Decimal128,
    rounding rule: FloatingPointRoundingRule
  ) {
    var flags: DecimalFloatingPointStatusFlags = []
    quantize(by: other, rounding: rule, &flags)
  }

  @inline(always)
  public mutating func quantize(
    by other: Decimal128,
    rounding rule: FloatingPointRoundingRule,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) {
    self = quantized(by: other, rounding: rule, &flags)
  }

  @inline(always)
  public func quantized(
    by other: Decimal128,
    rounding rule: FloatingPointRoundingRule = .toNearestOrEven
  ) -> Decimal128 {
    var flags: DecimalFloatingPointStatusFlags = []
    return quantized(by: other, rounding: rule, &flags)
  }

  @inlinable
  public func quantized(
    by other: Decimal128,
    rounding rule: FloatingPointRoundingRule = .toNearestOrEven,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) -> Decimal128 {
    guard isFinite && other.isFinite else {
      if isSignalingNaN {
        flags.insert(.invalid)
        return _quiet._canonical
      }
      if other.isSignalingNaN {
        flags.insert(.invalid)
        return other._quiet._canonical
      }

      if isNaN {
        return _canonical
      }
      if other.isNaN {
        return other._canonical
      }

      if isInfinite && other.isFinite {
        return _isSignMinus ? -.infinity : .infinity
      }
      flags.insert(.invalid)
      return .nan
    }
    let oe = other.exponentBitPattern
    if isZero {
      return Self(sign: sign, exponentBitPattern: oe, significandBitPattern: 0)
    }
    let n = Int(exponentBitPattern) - Int(oe)
    var c = significandBitPattern
    if n >= 0 {
      guard n <= 33 - c._commonLogarithm else {
        flags.insert(.invalid)
        return .nan
      }
      c &*= unsafe ._exp10[unchecked: n]
    } else {
      let digit: UInt128
      let sticky: Bool
      if n < -34 {
        (c, digit) = (0, 0)
        sticky = true
      } else {
        let (q, r) = c._quotientAndRemainder(dividingBy1e: -n &- 1)
        (c, digit) = q.quotientAndRemainder(dividingBy: 10)
        sticky = r != 0
      }
      let digit_ = UInt8(digit)
      if Self._roundsAway(
        isSignMinus: _isSignMinus,
        significand: c,
        digit: digit_,
        sticky: sticky,
        rule
      ) {
        c &+= 1
      }
      if c >= ._1e34 {
        flags.insert(.invalid)
        return .nan
      }
      if digit_ != 0 || sticky { flags.insert(.inexact) }
    }
    return Self(sign: sign, exponentBitPattern: oe, significandBitPattern: c)
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
      _signal(.invalid)
      return .max
    }
    guard !isZero else {
      _signal(.invalid)
      return .min
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

@available(anyAppleOS 26.0, *)
extension Decimal128: Equatable {
  @inlinable
  public static func == (lhs: Decimal128, rhs: Decimal128) -> Bool {
    if lhs.bitPattern == rhs.bitPattern {
      if lhs.isNaN {
        // `==` is a 'quiet predicate' per IEEE 754 §5.11.
        if lhs.isSignalingNaN { _signal(.invalid) }
        return false
      }
      return true
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
    return unsafe lc.multipliedFullWidth(by: ._exp10[unchecked: n]) == (0, rc)
  }
}

@available(anyAppleOS 26.0, *)
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
        if _trailingSignificandBitPattern < ._1e33 {
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
    // Estimate log10(c). See `UInt128._commonLogarithm` for more explanation.
    // It is important that this estimate be at least the true floor log10 and
    // at most one greater.
    let estimate = ((19 &* (127 &- (c|1).leadingZeroBitCount)) &>> 6) &+ 1
    let n = min(e, UInt(max(0, 33 &- estimate)))
    if n != 0 {
      c &*= unsafe ._exp10[unchecked: Int(n)]
      e &-= n
    }
    if e != 0 && c < ._1e33 {
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

@usableFromInline
@frozen
@c
internal enum _WeakOrdering: Int8 {
  case less = -1
  case equivalent = 0
  case greater = 1
}

@available(anyAppleOS 26.0, *)
extension Decimal128: Comparable {
  @inlinable
  internal func _compared(to other: Decimal128) -> _WeakOrdering? {
    var lhs = self, rhs = other
    if lhs.bitPattern == rhs.bitPattern {
      if lhs.isNaN { return nil }
      return .equivalent
    }

    guard lhs._isFiniteNonzero && rhs._isFiniteNonzero else {
      if lhs.isNaN || rhs.isNaN { return nil }
      if lhs.isInfinite {
        return lhs._isSignMinus
          ? rhs.isInfinite && rhs._isSignMinus ? .equivalent : .less
          : rhs.isInfinite && !rhs._isSignMinus ? .equivalent : .greater
      }
      if rhs.isInfinite {
        return rhs._isSignMinus ? .greater : .less
      }
      if lhs.isZero {
        if rhs.isZero { return .equivalent }
        return rhs._isSignMinus ? .greater : .less
      }
      return lhs._isSignMinus ? .less : .greater
    }

    if lhs._isSignMinus {
      if !rhs._isSignMinus { return .less }
      // For explanation, see `<`.
      swap(&lhs, &rhs)
    } else if rhs._isSignMinus {
      return .greater
    }

    var n = Int(lhs.exponentBitPattern) - Int(rhs.exponentBitPattern)
    if n == 0 {
      // Equivalent finite nonzero values with the same exponent bit pattern
      // must have the same overall bit pattern, in which case we've already
      // taken the early exit above.
      return lhs.significandBitPattern < rhs.significandBitPattern
        ? .less
        : .greater
    }
    var isSwapped = false
    if n < 0 {
      // For explanation, see `<`.
      swap(&lhs, &rhs)
      isSwapped = true
      n.negate()
    }

    if n > 33 { return isSwapped ? .less : .greater }
    let (lc, rc) = (lhs.significandBitPattern, rhs.significandBitPattern)
    guard lc < rc else { return isSwapped ? .less : .greater }
    let scaled = unsafe lc.multipliedFullWidth(by: ._exp10[unchecked: n])
    if scaled == (0, rc) { return .equivalent }
    return isSwapped
      ? scaled > (0, rc) ? .less : .greater
      : scaled < (0, rc) ? .less : .greater
  }

  @inlinable
  public static func < (lhs: Decimal128, rhs: Decimal128) -> Bool {
    if lhs.bitPattern == rhs.bitPattern {
      if lhs.isNaN {
        // `<` is a 'signaling predicate' per IEEE 754 §5.11.
        _signal(.invalid)
        return false
      }
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
    let scaled = unsafe lc.multipliedFullWidth(by: ._exp10[unchecked: n])
    return isSwapped ? scaled > (0, rc) : scaled < (0, rc)
  }

  @inline(always)
  public static func > (lhs: Decimal128, rhs: Decimal128) -> Bool {
    return rhs < lhs
  }

  @inlinable
  public static func <= (lhs: Decimal128, rhs: Decimal128) -> Bool {
    if lhs.isNaN || rhs.isNaN {
      _signal(.invalid)
      return false
    }
    return !(rhs < lhs)
  }

  @inlinable
  public static func >= (lhs: Decimal128, rhs: Decimal128) -> Bool {
    if lhs.isNaN || rhs.isNaN {
      _signal(.invalid)
      return false
    }
    return !(lhs < rhs)
  }
}

@available(anyAppleOS 26.0, *)
extension Decimal128: ExpressibleByIntegerLiteral {
  @inlinable
  public init(integerLiteral value: Int128) {
    bitPattern = value.magnitude
    guard bitPattern < ._1e34 else {
      fatalError("Potentially inexact integer conversion not implemented")
    }
    bitPattern |= Self().bitPattern
    if value < 0 { self.negate() }
  }
}

@available(anyAppleOS 26.0, *)
extension Decimal128: AdditiveArithmetic {
  @inlinable
  @inline(always)
  internal static func _roundsAway(
    isSignMinus: Bool,
    significand: UInt128,
    digit: UInt8,
    sticky: Bool,
    _ rule: FloatingPointRoundingRule
  ) -> Bool {
    assert(digit < 10)
    guard digit != 0 || sticky else { return false }
    switch rule {
    case .toNearestOrEven:
      return digit > 5 || (digit == 5 && (sticky || (significand & 1) != 0))
    case .toNearestOrAwayFromZero:
      return digit >= 5
    case .up: return !isSignMinus
    case .down: return isSignMinus
    case .awayFromZero: return true
    case .towardZero: return false
    @unknown default: fatalError("Unknown rounding rule.")
    }
  }

  @inlinable
  @inline(always)
  internal static func _overflow(
    isSignMinus: Bool,
    _ rule: FloatingPointRoundingRule,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) -> Decimal128 {
    let infinite: Bool =
      switch rule {
      case .toNearestOrEven: true
      case .toNearestOrAwayFromZero: true
      case .up: !isSignMinus
      case .down: isSignMinus
      case .awayFromZero: true
      case .towardZero: false
      @unknown default: fatalError("Unknown rounding rule.")
      }
    let magnitude: Self = infinite ? .infinity : .greatestFiniteMagnitude
    flags.formUnion(.overflowInexact)
    return isSignMinus ? -magnitude : magnitude
  }

  @inlinable
  internal static func _round(
      isSignMinus: Bool,
      biasedExponent: Int,
      significand: (high: UInt128, low: UInt128),
      sticky: Bool = false,
      preferredBiasedExponent: Int? = nil,
      _ rule: FloatingPointRoundingRule,
      _ flags: inout DecimalFloatingPointStatusFlags
  ) -> Decimal128 {
    var e = biasedExponent
    let pe = min(12287, max(0, preferredBiasedExponent ?? e))
    let (hi, lo) = significand
    assert(!sticky || (hi, lo) >= (0, ._1e34))
    assert((hi, lo) < UInt128._1e34.multipliedFullWidth(by: ._1e34))
    if (hi, lo) == (0, 0) {
      let abs = Self(bitPattern: UInt128(truncatingIfNeeded: pe) &<< 113)
      return isSignMinus ? -abs : abs
    }
    if e > 12320 {
      return _overflow(isSignMinus: isSignMinus, rule, &flags)
    }
    if e < -68 {
      let nextAway = _roundsAway(
        isSignMinus: isSignMinus,
        significand: 0,
        digit: 0,
        sticky: true,
        rule)
      let abs = Self(bitPattern: nextAway ? 1 : 0)
      flags.formUnion(.underflowInexact)
      return isSignMinus ? -abs : abs
    }

    // Per IEEE 754, detect tininess (i.e., underflow) before rounding.
    let isTiny: Bool = if e < -34 {
      true
    } else if e < -5 {
      unsafe hi == 0 || (hi, lo) <
        UInt128._exp10[unchecked: -e].multipliedFullWidth(by: ._1e33)
    } else if e < 33 {
      unsafe hi == 0 && lo < ._exp10[unchecked: 33 &- e]
    } else {
      false
    }

    // Remove decimal digits from intermediate result, if necessary.
    var divisor, quo, rem: UInt128
    var sticky = sticky
    if isTiny {
      if e < -38 {
        let (q, r) = _UInt256(hi, lo)._quotientAndRemainderDividingBy1e38()
        if r.low != 0 { sticky = true }
        let n = -e &- 38
        divisor = ._exp10[n]
        (quo, rem) = q.low._quotientAndRemainder(dividingBy1e: n)
        e = 0
      } else if e < 0 {
        let n = -e
        divisor = unsafe ._exp10[unchecked: n]
        (quo, rem) =
          UInt128._quotientAndRemainder(fullWidth: (hi, lo), dividingBy1e: n)
        e = 0
      } else {
        divisor = 1
        (quo, rem) = (lo, 0)
      }
    } else if hi != 0 {
      // See explanatory comment in `UInt128._commonLogarithm`.
      // Note that here we underestimate.
      var n = ((77 &* (255 &- hi.leadingZeroBitCount)) &>> 8) &- 33
      divisor = unsafe ._exp10[unchecked: n]
      if (hi, lo) >= divisor.multipliedFullWidth(by: ._1e34) {
        n &+= 1
        divisor &*= 10
      }
      (quo, rem) =
        UInt128._quotientAndRemainder(fullWidth: (hi, lo), dividingBy1e: n)
      e &+= n
    } else if lo >= ._1e34 {
      var n = ((77 &* (127 &- (lo|1).leadingZeroBitCount)) &>> 8) &- 33
      divisor = unsafe ._exp10[unchecked: n]
      let (x, overflow) = divisor.multipliedReportingOverflow(by: ._1e34)
      if !overflow && lo >= x {
        n &+= 1
        divisor &*= 10
      }
      (quo, rem) = lo._quotientAndRemainder(dividingBy1e: n)
      e &+= n
    } else {
      divisor = 1
      (quo, rem) = (lo, 0)
    }

    let inexact = rem != 0 || sticky
    if !inexact {
      // Select exact cohort before checking for overflow.
      if e < pe {
        if (quo & 1) == 0, let quo_ = quo._quotientIfExactDividingBy10() {
          var delta = pe &- (e &+ 1)
          quo = quo_
          if delta >= 32 && (quo & 0xFFFFFFFF) == 0,
              let quo_ = quo._quotientIfExactDividingBy1e32() {
            delta &-= 32
            quo = quo_
          }
          if delta >= 16 && (quo & 0xFFFF) == 0,
              let quo_ = quo._quotientIfExactDividingBy1e16() {
            delta &-= 16
            quo = quo_
          }
          if delta >= 8 && (quo & 0xFF) == 0,
              let quo_ = quo._quotientIfExactDividingBy1e8() {
            delta &-= 8
            quo = quo_
          }
          if delta >= 4 && (quo & 0xF) == 0,
              let quo_ = quo._quotientIfExactDividingBy10000() {
            delta &-= 4
            quo = quo_
          }
          if delta >= 2 && (quo & 0x3) == 0,
              let quo_ = quo._quotientIfExactDividingBy100() {
            delta &-= 2
            quo = quo_
          }
          if delta >= 1 && (quo & 1) == 0,
              let quo_ = quo._quotientIfExactDividingBy10() {
            delta &-= 1
            quo = quo_
          }
          e = pe &- delta
        }
      } else if e > pe {
        let estimate = ((19 &* (127 &- quo.leadingZeroBitCount)) &>> 6) &+ 1
        let n = min(e &- pe, max(0, 33 &- estimate))
        if n > 0 {
          quo &*= unsafe ._exp10[unchecked: n]
          e &-= n
        }
        if e > pe && quo < ._1e33 {
          quo &*= 10
          e &-= 1
        }
      }
    }

    guard e <= 12287 else {
      return _overflow(isSignMinus: isSignMinus, rule, &flags)
    }
    if !inexact {
      // Exact result.
      let abs = Self(bitPattern: UInt128(truncatingIfNeeded: e) &<< 113 | quo)
      return isSignMinus ? -abs : abs
    }

    // Inexact.
    let nextAway: Bool =
      switch rule {
      case .awayFromZero:
        true
      case .down:
        isSignMinus
      case .toNearestOrAwayFromZero:
        rem >= (divisor &>> 1)
      case .toNearestOrEven:
        rem > (divisor &>> 1) ||
          (rem == (divisor &>> 1) && (sticky || (quo & 1) != 0))
      case .towardZero:
        false
      case .up:
        !isSignMinus
      @unknown default:
        fatalError("Unknown rounding rule.")
      }
    if nextAway {
      if quo == ._1e34 &- 1 {
        if e == 12287 {
          flags.formUnion(.overflowInexact)
          return isSignMinus ? -.infinity : .infinity
        }
        quo = ._1e33
        e &+= 1
      } else {
        quo &+= 1
      }
    }
    let abs = Self(bitPattern: UInt128(truncatingIfNeeded: e) &<< 113 | quo)
    if isTiny {
      flags.formUnion(.underflowInexact)
    } else {
      flags.insert(.inexact)
    }
    return isSignMinus ? -abs : abs
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
  @inline(always)
  public func adding(
    _ rhs: Decimal128,
    rounding rule: FloatingPointRoundingRule = .toNearestOrEven
  ) -> Decimal128 {
    var flags: DecimalFloatingPointStatusFlags = []
    return adding(rhs, rounding: rule, &flags)
  }

  @inlinable
  public func adding(
    _ rhs: Decimal128,
    rounding rule: FloatingPointRoundingRule = .toNearestOrEven,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) -> Decimal128 {
    var lhs = self, rhs = rhs

    guard lhs._isFiniteNonzero && rhs._isFiniteNonzero else {
      if lhs.isSignalingNaN {
        flags.insert(.invalid)
        lhs = lhs._quiet
      }
      if rhs.isSignalingNaN {
        flags.insert(.invalid)
        rhs = rhs._quiet
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
          flags.insert(.invalid)
          return .nan
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
      // Estimate log10(c). See `UInt128._commonLogarithm` for more explanation.
      // It is important that this estimate be at least the true floor log10 and
      // at most one greater.
      let estimate = ((19 &* (127 &- (c1|1).leadingZeroBitCount)) &>> 6) &+ 1
      let n = min(e1 &- e2, UInt(max(0, 33 &- estimate)))
      if n > 0 {
        c1 &*= unsafe ._exp10[unchecked: Int(n)]
        e1 &-= n
      }
      if e1 > e2 && c1 < ._1e33 {
        c1 &*= 10
        e1 &-= 1
      }
      return Self(
        sign: lhs.sign, exponentBitPattern: e1, significandBitPattern: c1)
    }

    var (e1, e2) = (lhs.exponentBitPattern, rhs.exponentBitPattern)

    if e1 == e2 {
      var isSignMinus = lhs._isSignMinus
      var c1 = lhs.significandBitPattern
      let c2 = rhs.significandBitPattern
      if isSignMinus == rhs._isSignMinus {
        c1 &+= c2
        if c1 >= ._1e34 {
          return ._round(
            isSignMinus: isSignMinus,
            biasedExponent: Int(e1),
            significand: (0, c1), // TODO: Consider not using the general rounder.
            rule,
            &flags)
        }
      } else {
        let borrow: Bool
        (c1, borrow) = c1.subtractingReportingOverflow(c2)
        if borrow {
          c1 = ~c1 &+ 1
          isSignMinus.toggle()
        } else if c1 == 0 {
          // Exact zero. See IEEE 754 §6.3.
          isSignMinus = rule == .down
        }
      }
      // Exact result.
      let abs = Self(bitPattern: UInt128(truncatingIfNeeded: e1) &<< 113 | c1)
      return isSignMinus ? -abs : abs
    }

    if e1 < e2 {
      swap(&e1, &e2)
      swap(&lhs, &rhs)
    }
    let n = Int(e1 &- e2)

    var isSignMinus = lhs._isSignMinus

    var c1 = lhs.significandBitPattern
    let logc1 = c1._commonLogarithm
    let c2 = rhs.significandBitPattern
    let logc2 = c2._commonLogarithm
    let delta = n &+ (logc1 &- logc2)
    if delta > 34 {
      // Inexact.
      var isTiny = false
      if logc1 < 33 {
        let n_ = UInt(33 &- logc1)
        if e1 < n_ {
          // Note that the result isn't tiny if `e1 == n_`.
          isTiny = true
          c1 &*= unsafe ._exp10[unchecked: Int(e1)]
          e1 = 0
        } else {
          c1 &*= unsafe ._exp10[unchecked: Int(n_)]
          e1 &-= n_
        }
      }
      if isSignMinus == rhs._isSignMinus {
        let nextAway: Bool =
          switch rule {
          case .awayFromZero:
            true
          case .down:
            isSignMinus
          case .toNearestOrAwayFromZero, .toNearestOrEven:
            false
          case .towardZero:
            false
          case .up:
            !isSignMinus
          @unknown default:
            fatalError("Unknown rounding rule.")
          }
        if nextAway {
          if c1 == ._1e34 &- 1 {
            if e1 == 12287 {
              flags.formUnion(.overflowInexact)
              return isSignMinus ? -.infinity : .infinity
            }
            c1 = ._1e33
            e1 &+= 1
          } else {
            c1 &+= 1
          }
        }
      } else {
        let nextToward: Bool =
          switch rule {
          case .awayFromZero:
            false
          case .down:
            !isSignMinus
          case .toNearestOrAwayFromZero, .toNearestOrEven:
            unsafe delta == 35 &&
              c1 == ._1e33 && c2 > 5 &* ._exp10[unchecked: logc2]
          case .towardZero:
            true
          case .up:
            isSignMinus
          @unknown default:
            fatalError("Unknown rounding rule.")
          }
        if nextToward {
          if c1 == ._1e33 {
            if e1 == 0 {
              isTiny = true
              c1 &-= 1
            } else {
              c1 = ._1e34 &- 1
              e1 &-= 1
            }
          } else {
            c1 &-= 1
          }
        }
      }
      let abs = Self(bitPattern: UInt128(truncatingIfNeeded: e1) &<< 113 | c1)
      if isTiny {
        flags.formUnion(.underflowInexact)
      } else {
        flags.insert(.inexact)
      }
      return isSignMinus ? -abs : abs
    }

    // Compute the intermediate result.
    assert(n != 0)
    var (hi, lo) = n <= 38
      ? c1._multipliedFullWidth(by1e: n)
      : (c1 * ._exp10[n &- 34]).multipliedFullWidth(by: ._1e34)
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

    return Self._round(
      isSignMinus: isSignMinus,
      biasedExponent: Int(e2),
      significand: (hi, lo),
      rule,
      &flags)
  }

  /// Adds the given value to this value in place,
  /// rounding to a representable value if needed with the given rounding rule.
  ///
  /// - Parameters:
  ///   - rhs: The value to add to this value.
  ///   - rule: The rounding rule for computing an inexact result.
  @inline(always)
  public mutating func add(
    _ rhs: Decimal128,
    rounding rule: FloatingPointRoundingRule = .toNearestOrEven
  ) {
    self = adding(rhs, rounding: rule)
  }

  @inline(always)
  public mutating func add(
    _ rhs: Decimal128,
    rounding rule: FloatingPointRoundingRule = .toNearestOrEven,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) {
    self = adding(rhs, rounding: rule, &flags)
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
  @inline(always)
  public static func + (lhs: Decimal128, rhs: Decimal128) -> Decimal128 {
    lhs.adding(rhs)
  }

  /// Adds two values and stores the result in the left-hand-side variable,
  /// rounding to a representable value if needed.
  ///
  /// - Parameters:
  ///   - lhs: The first value to add.
  ///   - rhs: The second value to add.
  @inline(always)
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
  @inline(always)
  public func subtracting(
    _ rhs: Decimal128,
    rounding rule: FloatingPointRoundingRule = .toNearestOrEven
  ) -> Decimal128 {
    var flags: DecimalFloatingPointStatusFlags = []
    return adding(-rhs, rounding: rule, &flags)
  }

  @inline(always)
  public func subtracting(
    _ rhs: Decimal128,
    rounding rule: FloatingPointRoundingRule = .toNearestOrEven,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) -> Decimal128 {
    return adding(-rhs, rounding: rule, &flags)
  }

  /// Subtracts the given value from this value in place,
  /// rounding to a representable value if needed with the given rounding rule.
  ///
  /// - Parameters:
  ///   - rhs: The value to subtract from this value.
  ///   - rule: The rounding rule to use for computing an inexact result.
  @inline(always)
  public mutating func subtract(
    _ rhs: Decimal128,
    rounding rule: FloatingPointRoundingRule = .toNearestOrEven
  ) {
    self = subtracting(rhs, rounding: rule)
  }

  @inline(always)
  public mutating func subtract(
    _ rhs: Decimal128,
    rounding rule: FloatingPointRoundingRule = .toNearestOrEven,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) {
    self = subtracting(rhs, rounding: rule, &flags)
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
  @inline(always)
  public static func - (lhs: Decimal128, rhs: Decimal128) -> Decimal128 {
    lhs.subtracting(rhs)
  }

  /// Subtracts the second value from the first and stores the difference in the
  /// left-hand-side variable, rounding to a representable value if needed.
  ///
  /// - Parameters:
  ///   - lhs: A numeric value.
  ///   - rhs: The value to subtract from `lhs`.
  @inline(always)
  public static func -= (lhs: inout Decimal128, rhs: Decimal128) {
    lhs = lhs - rhs
  }
}

@available(anyAppleOS 26.0, *)
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
  @inline(always)
  public func multiplied(
    by rhs: Decimal128,
    rounding rule: FloatingPointRoundingRule = .toNearestOrEven
  ) -> Decimal128 {
    var flags: DecimalFloatingPointStatusFlags = []
    return multiplied(by: rhs, rounding: rule, &flags)
  }

  @inlinable
  public func multiplied(
    by rhs: Decimal128,
    rounding rule: FloatingPointRoundingRule = .toNearestOrEven,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) -> Decimal128 {
    var lhs = self, rhs = rhs
    let isSignMinus = lhs._isSignMinus != rhs._isSignMinus

    guard lhs._isFiniteNonzero && rhs._isFiniteNonzero else {
      if lhs.isSignalingNaN {
        flags.insert(.invalid)
        lhs = lhs._quiet
      }
      if rhs.isSignalingNaN {
        flags.insert(.invalid)
        rhs = rhs._quiet
      }
      if lhs.isNaN {
        return lhs._canonical
      }
      if rhs.isNaN {
        return rhs._canonical
      }

      if lhs.isInfinite {
        if rhs.isZero {
          flags.insert(.invalid)
          return .nan
        }
        return isSignMinus ? -.infinity : .infinity
      }
      if rhs.isInfinite {
        if lhs.isZero {
          flags.insert(.invalid)
          return .nan
        }
        return isSignMinus ? -.infinity : .infinity
      }

      let e = Int(lhs.exponentBitPattern) &- 6176 &+ Int(rhs.exponentBitPattern)
      let abs = Self(
        bitPattern: UInt128(truncatingIfNeeded: min(12287, max(e, 0))) &<< 113)
      return isSignMinus ? -abs : abs
    }

    // Compute the intermediate result.
    let e = Int(lhs.exponentBitPattern) &- 6176 &+ Int(rhs.exponentBitPattern)
    let lc = lhs.significandBitPattern
    let rc = rhs.significandBitPattern
    let product: (high: UInt128, low: UInt128)
    if lc <= 0xFFFF_FFFF_FFFF_FFFF && rc <= 0xFFFF_FFFF_FFFF_FFFF {
      let (hi, lo) =
        UInt64(truncatingIfNeeded: lc).multipliedFullWidth(
          by: UInt64(truncatingIfNeeded: rc))
      let c = UInt128(hi) &<< 64 | UInt128(lo)
      if c < ._1e34 && e >= 0 && e <= 12287 {
        let abs = Self(bitPattern: UInt128(truncatingIfNeeded: e) &<< 113 | c)
        return isSignMinus ? -abs : abs
      }
      product = (0, c)
    } else {
      product = lc.multipliedFullWidth(by: rc)
    }

    return ._round(
      isSignMinus: isSignMinus,
      biasedExponent: e,
      significand: product,
      rule,
      &flags)
  }

  /// Multiplies this value by the given value in place, rounding to a
  /// representable value if needed with the given rounding rule.
  ///
  /// - Parameters:
  ///   - rhs: The value by which to multiply this value.
  ///   - rule: The rounding rule to use for computing an inexact result.
  @inline(always)
  public mutating func multiply(
    by rhs: Decimal128,
    rounding rule: FloatingPointRoundingRule = .toNearestOrEven
  ) {
    self = multiplied(by: rhs, rounding: rule)
  }

  @inline(always)
  public mutating func multiply(
    by rhs: Decimal128,
    rounding rule: FloatingPointRoundingRule = .toNearestOrEven,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) {
    self = multiplied(by: rhs, rounding: rule, &flags)
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
  @inline(always)
  public static func * (lhs: Decimal128, rhs: Decimal128) -> Decimal128 {
    lhs.multiplied(by: rhs)
  }

  /// Multiplies two values and stores the result in the left-hand-side
  /// variable, rounding to a representable value if needed.
  ///
  /// - Parameters:
  ///   - lhs: The first value to multiply.
  ///   - rhs: The second value to multiply.
  @inline(always)
  public static func *= (lhs: inout Decimal128, rhs: Decimal128) {
    lhs = lhs * rhs
  }

  @inlinable
  public init?<T: BinaryInteger>(exactly source: T) {
    let magnitude = source.magnitude
    guard magnitude.bitWidth < 113 || magnitude < UInt128._1e34 else {
      fatalError("Potentially inexact integer conversion not implemented")
    }
    bitPattern = UInt128(truncatingIfNeeded: magnitude)
    bitPattern |= Self().bitPattern
    if source < (0 as T) { self.negate() }
  }
}

@available(anyAppleOS 26.0, *)
extension Decimal128: SignedNumeric { }

@available(anyAppleOS 26.0, *)
extension Decimal128: Strideable {
  @inlinable
  public func distance(to other: Decimal128) -> Decimal128 { other - self }

  @inlinable
  public func advanced(by n: Decimal128) -> Decimal128 { self + n }
}

@available(anyAppleOS 26.0, *)
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

@available(anyAppleOS 26.0, *)
extension Decimal128: FloatingPoint {
  @inline(always)
  public static var radix: Int { 10 }

  @inline(always)
  public func isEqual(to other: Decimal128) -> Bool { self == other }

  @inline(always)
  public func isLess(than other: Decimal128) -> Bool { self < other }

  @inline(always)
  public func isLessThanOrEqualTo(_ other: Decimal128) -> Bool { self <= other }

  @inlinable
  public func isTotallyOrdered(belowOrEqualTo other: Decimal128) -> Bool {
    let cmp = _compared(to: other)
    switch cmp {
    case .less: return true
    case .greater: return false
    default: break
    }
    // `self` and `other` are equal or unordered.
    let lhs: Self, rhs: Self
    if _isSignMinus {
      if !other._isSignMinus { return true }
      (lhs, rhs) = (other._canonical, _canonical) // Swap to compare magnitudes.
    } else if other._isSignMinus {
      return false
    } else {
      (lhs, rhs) = (_canonical, other._canonical)
    }
    // `self` and `other` have matching sign bits.
    let (le, re) = (lhs.exponentBitPattern, rhs.exponentBitPattern)
    guard cmp == nil else { return le <= re }
    // Look at exponents, but order +sNaN before +qNaN (and -qNaN before -sNaN).
    if le > re { return le == 0x3c00 && re == 0x3800 }
    if le < re { return le != 0x3800 || re != 0x3c00 }
    return lhs.significandBitPattern <= rhs.significandBitPattern
  }

  public func addingProduct(
    _ lhs: Decimal128, _ rhs: Decimal128,
    rounding rule: FloatingPointRoundingRule
  ) -> Decimal128 {
    fatalError("Not implemented")
  }

  @inline(always)
  public mutating func addProduct(
    _ lhs: Decimal128, _ rhs: Decimal128,
    rounding rule: FloatingPointRoundingRule
  ) {
    self = addingProduct(lhs, rhs, rounding: rule)
  }

  @inline(always)
  public func addingProduct(
    _ lhs: Decimal128, _ rhs: Decimal128
  ) -> Decimal128 {
    addingProduct(lhs, rhs, rounding: .toNearestOrEven)
  }

  @inline(always)
  public mutating func addProduct(_ lhs: Decimal128, _ rhs: Decimal128) {
    self = addingProduct(lhs, rhs)
  }

  @inline(always)
  public func divided(
    by rhs: Decimal128,
    rounding rule: FloatingPointRoundingRule = .toNearestOrEven
  ) -> Decimal128 {
    var flags: DecimalFloatingPointStatusFlags = []
    return divided(by: rhs, rounding: rule, &flags)
  }

  @inlinable
  public func divided(
    by rhs: Decimal128,
    rounding rule: FloatingPointRoundingRule = .toNearestOrEven,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) -> Decimal128 {
    var lhs = self, rhs = rhs
    let isSignMinus = lhs._isSignMinus != rhs._isSignMinus

    guard lhs._isFiniteNonzero && rhs._isFiniteNonzero else {
      if lhs.isSignalingNaN {
        flags.insert(.invalid)
        lhs = lhs._quiet
      }
      if rhs.isSignalingNaN {
        flags.insert(.invalid)
        rhs = rhs._quiet
      }
      if lhs.isNaN {
        return lhs._canonical
      }
      if rhs.isNaN {
        return rhs._canonical
      }

      if lhs.isInfinite {
        if rhs.isInfinite {
          flags.insert(.invalid)
          return .nan
        }
        return isSignMinus ? -.infinity : .infinity
      }
      if rhs.isInfinite {
        let abs = Self(bitPattern: 0)
        return isSignMinus ? -abs : abs
      }

      if rhs.isZero {
        if lhs.isZero {
          flags.insert(.invalid)
          return .nan
        }
        flags.insert(.divisionByZero)
        return isSignMinus ? -.infinity : .infinity
      }
      let e = Int(lhs.exponentBitPattern) &- Int(rhs.exponentBitPattern) &+ 6176
      let abs = Self(
        bitPattern: UInt128(truncatingIfNeeded: min(12287, max(e, 0))) &<< 113)
      return isSignMinus ? -abs : abs
    }

    var e = Int(lhs.exponentBitPattern) &- Int(rhs.exponentBitPattern) &+ 6176
    let lc = lhs.significandBitPattern
    let rc = rhs.significandBitPattern

    if rc == 1 {
      if e >= 0 && e <= 12287 {
        let abs = Self(bitPattern: UInt128(truncatingIfNeeded: e) &<< 113 | lc)
        return isSignMinus ? -abs : abs
      }
      return ._round(
        isSignMinus: isSignMinus,
        biasedExponent: e,
        significand: (0, lc), // TODO: Does this really require the general rounder?
        rule,
        &flags)
    }

    let n: Int
    var quo: UInt128
    let rem: UInt128
    if lc >= rc {
      let (q, r) = lc.quotientAndRemainder(dividingBy: rc)
      if r == 0 {
        if e >= 0 && e <= 12287 {
          let abs = Self(bitPattern: UInt128(truncatingIfNeeded: e) &<< 113 | q)
          return isSignMinus ? -abs : abs
        }
        return ._round(
          isSignMinus: isSignMinus,
          biasedExponent: e,
          significand: (0, q), // TODO: Does this really require the general rounder?
          rule,
          &flags)
      }
      n = 33 &- q._commonLogarithm
      (quo, rem) = rc.dividingFullWidth(r._multipliedFullWidth(by1e: n))
      quo &+= unsafe q &* ._exp10[unchecked: n]
    } else {
      let delta = rc._commonLogarithm &- lc._commonLogarithm
      n = unsafe 33 &+ delta &+ (lc &* ._exp10[unchecked: delta] < rc ? 1 : 0)
      let dividend = n <= 38
        ? lc._multipliedFullWidth(by1e: n)
        : (lc * ._exp10[n &- 34]).multipliedFullWidth(by: ._1e34)
      (quo, rem) = rc.dividingFullWidth(dividend)
    }
    let pe = e // Hang on to the preferred exponent for later.
    e &-= n

    let rr = rem &<< 1 // `rem * 2`.
    if rem != 0 && e >= 0 && e <= 12287 {
      if Self._roundsAway(
        isSignMinus: isSignMinus,
        significand: quo,
        digit: rr >= rc ? 5 : 0,
        // A proxy guard digit (5 if midpoint or above; otherwise 0).
        sticky: rr != rc,
        rule
      ) {
        if quo == ._1e34 &- 1 {
          if e == 12287 {
            flags.formUnion(.overflowInexact)
            return isSignMinus ? -.infinity : .infinity
          }
          quo = ._1e33
          e &+= 1
        } else {
          quo &+= 1
        }
      }
      flags.insert(.inexact)
      let abs = Self(bitPattern: UInt128(truncatingIfNeeded: e) &<< 113 | quo)
      return isSignMinus ? -abs : abs
    }
    if rem == 0 {
      return ._round(
        isSignMinus: isSignMinus,
        biasedExponent: e,
        significand: (0, quo), // TODO: Does this really require the general rounder?
        preferredBiasedExponent: pe,
        rule,
        &flags)
    }
    return ._round(
      isSignMinus: isSignMinus,
      biasedExponent: e &- 1,
      significand: (0, quo &* 10 &+ (rr >= rc ? 5 : 0)),
      // Tack on a proxy guard digit (5 if midpoint or above; otherwise 0).
      // TODO: Using integer multiplication to pass in a guard digit is inelegant.
      // ...Perhaps restore passing a tail or round bit?
      sticky: /* rem != 0 && */ rr != rc,
      preferredBiasedExponent: pe,
      rule,
      &flags)
  }

  @inline(always)
  public mutating func divide(
    by rhs: Decimal128,
    rounding rule: FloatingPointRoundingRule = .toNearestOrEven
  ) {
    self = divided(by: rhs, rounding: rule)
  }

  @inline(always)
  public mutating func divide(
    by rhs: Decimal128,
    rounding rule: FloatingPointRoundingRule = .toNearestOrEven,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) {
    self = divided(by: rhs, rounding: rule, &flags)
  }

  @inline(always)
  public static func / (lhs: Decimal128, rhs: Decimal128) -> Decimal128 {
    lhs.divided(by: rhs)
  }

  @inline(always)
  public static func /= (lhs: inout Decimal128, rhs: Decimal128) {
    lhs = lhs / rhs
  }

  public func remainder(dividingBy other: Decimal128) -> Decimal128 {
    fatalError("Not implemented")
  }

  @inline(always)
  public mutating func formRemainder(dividingBy other: Decimal128) {
    self = remainder(dividingBy: other)
  }

  public func truncatingRemainder(dividingBy other: Decimal128) -> Decimal128 {
    fatalError("Not implemented")
  }

  @inline(always)
  public mutating func formTruncatingRemainder(dividingBy other: Decimal128) {
    self = truncatingRemainder(dividingBy: other)
  }

  public func squareRoot(
    rounding rule: FloatingPointRoundingRule
  ) -> Decimal128 {
    fatalError("Not implemented")
  }

  @inline(always)
  public mutating func formSquareRoot(
    rounding rule: FloatingPointRoundingRule
  ) {
    self = squareRoot(rounding: rule)
  }

  @inline(always)
  public func squareRoot() -> Decimal128 {
    squareRoot(rounding: .toNearestOrEven)
  }

  @inline(always)
  public mutating func formSquareRoot() {
    self = squareRoot()
  }

  public func rounded(_ rule: FloatingPointRoundingRule) -> Decimal128 {
    if isSignalingNaN {
      _signal(.invalid)
      return _quiet._canonical
    }
    fatalError("Not implemented")
  }

  @inline(always)
  public mutating func round(_ rule: FloatingPointRoundingRule) {
    self = rounded(rule)
  }
}

@available(anyAppleOS 26.0, *)
extension Decimal128 {
  /// The bit pattern of the value’s binary encoding.
  ///
  /// This property is equivalent to `bitPattern` and implements the
  /// `encodeBinary` operation defined by the IEEE 754 specification.
  @inline(always)
  public var binaryEncoding: UInt128 { bitPattern }

  /// Creates a new value with the given binary-encoded bit pattern.
  ///
  /// This initializer is equivalent to `init(bitPattern:)` and implements the
  /// `decodeBinary` operation defined by the IEEE 754 specification.
  ///
  /// - Parameters:
  ///   - binaryEncoding: The binary encoding of a `Decimal128` instance.
  @inline(always)
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

@available(anyAppleOS 26.0, *)
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

@available(anyAppleOS 26.0, *)
extension Decimal128: CustomStringConvertible {
  public var description: String {
    guard _isFiniteNonzero else {
      if isSignalingNaN {
        _signal(.invalid)
        return _isSignMinus ? "-nan" : "nan"
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
        unsafe buffer.initializeElement(at: 0, to: 45 /* '-' */)
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
          index = unsafe buffer[index...].initialize(fromContentsOf: $0[..<x])
          unsafe buffer.initializeElement(at: index, to: 46 /* '.' */)
          if x == count {
            index += 1
          } else {
            index =
              unsafe buffer[(index + 1)...].initialize(fromContentsOf: $0[x...])
          }
        }
        return index
      }

      if exponent < 0 && exponent >= -4 {
        unsafe buffer.initializeElement(at: index, to: 48 /* '0' */)
        unsafe buffer.initializeElement(at: index + 1, to: 46 /* '.' */)
        index =
          unsafe buffer[(index + 2)...].initialize(
            fromContentsOf: repeatElement(48 /* '0' */, count: -(exponent + 1)))
        string.withUTF8 {
          index = unsafe buffer[index...].initialize(fromContentsOf: $0)
        }
        return index
      }

      string.withUTF8 {
        unsafe buffer.initializeElement(at: index, to: $0[0])
        if count == 1 {
          index += 1
        } else {
          unsafe buffer.initializeElement(at: index + 1, to: 46 /* '.' */)
          index =
            unsafe buffer[(index + 2)...].initialize(fromContentsOf: $0[1...])
        }
      }
      unsafe buffer.initializeElement(at: index, to: 101 /* 'e' */)
      unsafe buffer.initializeElement(
        at: index + 1,
        to: exponent < 0 ? 45 /* '-' */ : 43 /* '+' */)
      string = String(abs(exponent))
      string.withUTF8 {
        index = unsafe buffer[(index + 2)...].initialize(fromContentsOf: $0)
      }
      return index
    }
  }
}

@available(anyAppleOS 26.0, *)
extension Decimal128: LosslessStringConvertible {
  public init?<T: StringProtocol>(_ description: T) {
    fatalError("Not implemented")
  }
}
