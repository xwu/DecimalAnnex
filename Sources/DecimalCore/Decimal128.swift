/// A 128-bit decimal floating-point value type.
@available(anyAppleOS 26.0, *)
@frozen
public struct Decimal128: BitwiseCopyable, Sendable {
  /// The bit pattern of the value's binary encoding.
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
  /// - Precondition: `payload` is less than `1e33`.
  @inlinable
  public init(nan payload: UInt128, signaling: Bool) {
    precondition(payload < ._1e33, "NaN payload is not canonically encodable.")
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

  /// The mathematical constant pi (π), approximately equal to 3.14159.
  ///
  /// When measuring an angle in radians, π is equivalent to a half-turn.
  ///
  /// This value is rounded to the nearest representable value (ties to even).
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
  @inline(always)
  public init(integerLiteral value: Int128) {
    self.init(value)
  }
}

@available(anyAppleOS 26.0, *)
extension Decimal128 {
  /// The bit pattern of the value's binary encoding.
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
