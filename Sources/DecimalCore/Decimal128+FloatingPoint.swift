@available(anyAppleOS 26.0, *)
extension Decimal128: Strideable {
  @inlinable
  public func distance(to other: Decimal128) -> Decimal128 { other - self }

  @inlinable
  public func advanced(by n: Decimal128) -> Decimal128 { self + n }
}

@available(anyAppleOS 26.0, *)
extension Decimal128: FloatingPoint {
  /// The radix, or base of exponentiation, for this floating-point type (10).
  ///
  /// The magnitude of a floating-point value `x` of type `F` can be calculated
  /// by using the following formula, where `**` is exponentiation:
  ///
  ///     x.significand * (F.radix ** x.exponent)
  @inline(always)
  public static var radix: Int { 10 }

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
    if e != 0 && c < ._1e33 {
      let n = min(e, UInt(truncatingIfNeeded: 33 &- c._commonLogarithm))
      c &*= unsafe ._exp10[unchecked: Int(n)]
      e &-= n
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
  /// The unit in the last place of this value.
  ///
  /// For most finite values `x`, this is the difference between `x.magnitude`
  /// and the next greater representable value. If `x` is not a finite number,
  /// its `ulp` is NaN. The value of `greatestFiniteMagnitude.ulp` is finite,
  /// even though the next greater representable value is `infinity`.
  ///
  /// Equal finite values have the same `ulp` even when they have different
  /// quantums.
  ///
  /// See also the `ulpOfOne` static property.
  @inlinable
  public var ulp: Decimal128 {
    guard _isFiniteNonzero else {
      if !isFinite { return .nan }
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

  // A failable, always-inlined fast path for canonical, finite values where
  // the scaled exponent fits in the exponent field. Purely an optimization.
  @inlinable
  @inline(always)
  internal init?(_sign: FloatingPointSign, exponent: Int, significand: Self) {
    guard significand.significandBitPattern < ._1e34 else { return nil }
    let e = significand.exponentBitPattern &+ UInt(bitPattern: exponent)
    guard e <= 12287 else { return nil }
    let x = UInt128(truncatingIfNeeded: exponent) &<< 113
    let scaled = Self(bitPattern: significand.bitPattern &+ x)
    self = _sign == .minus ? -scaled : scaled
  }

  @usableFromInline
  internal init(
    _sign: FloatingPointSign,
    exponent: Int,
    significand: Decimal128,
    rounding rule: _DecimalFloatingPointRoundingRule,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) {
    let isSignMinus = (_sign == .minus) != significand._isSignMinus
    guard significand._isFiniteNonzero else {
      if significand.isSignalingNaN {
        _raise(.invalid, in: &flags)
        self = significand._quiet._canonical
        return
      }
      if significand.isNaN {
        self = significand._canonical
        return
      }
      if significand.isInfinite {
        self = isSignMinus ? -.infinity : .infinity
        return
      }
      var e: Int
      let overflow: Bool
      (e, overflow) =
        Int(significand.exponentBitPattern).addingReportingOverflow(exponent)
      if overflow {
        e = 12287
      } else {
        e = min(12287, max(e, 0))
      }
      let abs = Self(bitPattern: UInt128(truncatingIfNeeded: e) &<< 113)
      self = isSignMinus ? -abs : abs
      return
    }

    var e: Int
    let overflow: Bool
    (e, overflow) =
      Int(significand.exponentBitPattern).addingReportingOverflow(exponent)
    if overflow { e = .max }
    var c = significand.significandBitPattern

    if e < 0 {
      let r: UInt128
      let half: UInt128
      if e < -34 {
        r = c
        half = ._1e34
        c = 0
      } else {
        (c, r) = c._quotientAndRemainder(dividingBy1e: -e)
        half = unsafe ._exp10[unchecked: -e] &>> 1
      }
      if r != 0 {
        let nextAway: Bool =
          switch rule {
          case .toNearestOrEven:
            r &+ (c & 1) > half
          case .toNearestOrAwayFromZero:
            r >= half
          case .towardZero:
            false
          case .awayFromZero:
            true
          case .down:
            isSignMinus
          case .up:
            !isSignMinus
          @unknown default:
            fatalError("Unknown rounding rule.")
          }
        c &+= nextAway ? 1 : 0
        // Every such inexact result is tiny before rounding.
        _raise(.underflowInexact, in: &flags)
      }
      e = 0
    } else if e > 12287 {
      if c >= ._1e33 {
        self = ._overflow(isSignMinus: isSignMinus, rule, &flags)
        return
      }
      Self._select(
        biasedExponent: &e,
        nonzeroSignificand: &c,
        boundedPreferredBiasedExponent: 12287)
      if e > 12287 {
        self = ._overflow(isSignMinus: isSignMinus, rule, &flags)
        return
      }
    }

    let abs = Self(bitPattern: UInt128(truncatingIfNeeded: e) &<< 113 | c)
    self = isSignMinus ? -abs : abs
  }

  /// Creates a new value from the given sign, exponent, and significand.
  ///
  /// The result is rounded if needed to the nearest representable value
  /// (ties to even).
  ///
  /// This initializer is equivalent to the following calculation, where `**`
  /// is exponentiation, computed as if by a single, correctly rounded,
  /// floating-point operation:
  ///
  ///     (sign == .minus ? -1 : 1) * significand * 10 ** exponent
  ///
  /// As with any basic operation, if this value is outside the representable
  /// range of the type, overflow or underflow occurs, and zero, a subnormal
  /// value, or infinity may result. In addition, there are two other edge
  /// cases:
  ///
  /// - If the value you pass to `significand` is zero or infinite, the result
  ///   is zero or infinite, regardless of the value of `exponent`.
  /// - If the value you pass to `significand` is NaN, the result is NaN.
  ///
  /// This initializer implements the `scaleB` operation defined by the
  /// IEEE 754 specification.
  ///
  /// - Parameters:
  ///   - sign: The sign to apply to `significand`.
  ///   - exponent: The power of ten by which to scale `significand`.
  ///   - significand: The significand to scale.
  @inline(always)
  public init(sign: FloatingPointSign, exponent: Int, significand: Decimal128) {
    if let x = Self(_sign: sign, exponent: exponent, significand: significand) {
      self = x
      return
    }
    var flags: DecimalFloatingPointStatusFlags = []
    defer { _signal(flags) }
    self.init(
      _sign: sign,
      exponent: exponent,
      significand: significand,
      rounding: .toNearestOrEven,
      &flags)
  }

  /// Creates a new value from the given sign, exponent, and significand,
  /// accumulating status flags.
  ///
  /// The result is rounded if needed to the nearest representable value
  /// (ties to even).
  ///
  /// This initializer is equivalent to the following calculation, where `**`
  /// is exponentiation, computed as if by a single, correctly rounded,
  /// floating-point operation:
  ///
  ///     (sign == .minus ? -1 : 1) * significand * 10 ** exponent
  ///
  /// As with any basic operation, if this value is outside the representable
  /// range of the type, overflow or underflow occurs, and zero, a subnormal
  /// value, or infinity may result. In addition, there are two other edge
  /// cases:
  ///
  /// - If the value you pass to `significand` is zero or infinite, the result
  ///   is zero or infinite, regardless of the value of `exponent`.
  /// - If the value you pass to `significand` is NaN, the result is NaN.
  ///
  /// This initializer implements the `scaleB` operation defined by the
  /// IEEE 754 specification.
  ///
  /// - Parameters:
  ///   - sign: The sign to apply to `significand`.
  ///   - exponent: The power of ten by which to scale `significand`.
  ///   - significand: The significand to scale.
  ///   - flags: A value that accumulates decimal floating-point arithmetic
  ///     status flags.
  @inline(always)
  public init(
    sign: FloatingPointSign,
    exponent: Int,
    significand: Decimal128,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) {
    if let x = Self(_sign: sign, exponent: exponent, significand: significand) {
      self = x
      return
    }
    self.init(
      _sign: sign,
      exponent: exponent,
      significand: significand,
      rounding: .toNearestOrEven,
      &flags)
  }

  /// Creates a new value from the given sign, exponent, and significand.
  ///
  /// The result is rounded if needed using the given rounding rule.
  ///
  /// This initializer is equivalent to the following calculation, where `**`
  /// is exponentiation, computed as if by a single, correctly rounded,
  /// floating-point operation:
  ///
  ///     (sign == .minus ? -1 : 1) * significand * 10 ** exponent
  ///
  /// As with any basic operation, if this value is outside the representable
  /// range of the type, overflow or underflow occurs, and zero, a subnormal
  /// value, or infinity may result. In addition, there are two other edge
  /// cases:
  ///
  /// - If the value you pass to `significand` is zero or infinite, the result
  ///   is zero or infinite, regardless of the value of `exponent`.
  /// - If the value you pass to `significand` is NaN, the result is NaN.
  ///
  /// This initializer implements the `scaleB` operation defined by the
  /// IEEE 754 specification.
  ///
  /// - Parameters:
  ///   - sign: The sign to apply to `significand`.
  ///   - exponent: The power of ten by which to scale `significand`.
  ///   - significand: The significand to scale.
  ///   - rule: The rounding rule to use for an inexact result.
  @inline(always)
  public init(
    sign: FloatingPointSign,
    exponent: Int,
    significand: Decimal128,
    rounding rule: FloatingPointRoundingRule
  ) {
    if let x = Self(_sign: sign, exponent: exponent, significand: significand) {
      self = x
      return
    }
    var flags: DecimalFloatingPointStatusFlags = []
    defer { _signal(flags) }
    self.init(
      _sign: sign,
      exponent: exponent,
      significand: significand,
      rounding: .init(rule),
      &flags)
  }

  /// Creates a new value from the given sign, exponent, and significand,
  /// accumulating status flags.
  ///
  /// The result is rounded if needed using the given rounding rule.
  ///
  /// This initializer is equivalent to the following calculation, where `**`
  /// is exponentiation, computed as if by a single, correctly rounded,
  /// floating-point operation:
  ///
  ///     (sign == .minus ? -1 : 1) * significand * 10 ** exponent
  ///
  /// As with any basic operation, if this value is outside the representable
  /// range of the type, overflow or underflow occurs, and zero, a subnormal
  /// value, or infinity may result. In addition, there are two other edge
  /// cases:
  ///
  /// - If the value you pass to `significand` is zero or infinite, the result
  ///   is zero or infinite, regardless of the value of `exponent`.
  /// - If the value you pass to `significand` is NaN, the result is NaN.
  ///
  /// This initializer implements the `scaleB` operation defined by the
  /// IEEE 754 specification.
  ///
  /// - Parameters:
  ///   - sign: The sign to apply to `significand`.
  ///   - exponent: The power of ten by which to scale `significand`.
  ///   - significand: The significand to scale.
  ///   - rule: The rounding rule to use for an inexact result.
  ///   - flags: A value that accumulates decimal floating-point arithmetic
  ///     status flags.
  @inline(always)
  public init(
    sign: FloatingPointSign,
    exponent: Int,
    significand: Decimal128,
    rounding rule: FloatingPointRoundingRule,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) {
    if let x = Self(_sign: sign, exponent: exponent, significand: significand) {
      self = x
      return
    }
    self.init(
      _sign: sign,
      exponent: exponent,
      significand: significand,
      rounding: .init(rule),
      &flags)
  }

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

  @usableFromInline
  internal func _addingProduct(
    _ lhs: Decimal128, _ rhs: Decimal128,
    rounding rule: _DecimalFloatingPointRoundingRule,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) -> Decimal128 {
    var z = self, x = lhs, y = rhs

    // See `significandBitPattern`:
    let cx = x.bitPattern & (1 &<< 113 &- 1)
    let cy = y.bitPattern & (1 &<< 113 &- 1)
    // See `exponentBitPattern`:
    let ex = Int(truncatingIfNeeded: x.bitPattern &>> 113) & 0x3fff
    let ey = Int(truncatingIfNeeded: y.bitPattern &>> 113) & 0x3fff
    let exy = ex &+ ey &- 6176
    let sxy = x._isSignMinus != y._isSignMinus

    // A fast path for certain 'everyday' values. Purely an optimization.
    do {
      let cz = z.bitPattern & (1 &<< 113 &- 1)
      let ez = Int(truncatingIfNeeded: z.bitPattern &>> 113) & 0x3fff
      let delta = exy &- ez

      if (cz | cx | cy) <= 0x7fff_ffff_ffff_ffff /* Int64.max */
        && max(ez, max(ex, ey)) <= 0x2fff // No combination field starts `0b11...`.
        && exy >= 0 && delta.magnitude <= 18
      {
        var cz64 = Int64(truncatingIfNeeded: cz)
        let cx64 = Int64(truncatingIfNeeded: cx)
        let cy64 = Int64(truncatingIfNeeded: cy)
        var product1: Int64
        let overflow1: Bool
        (product1, overflow1) = cx64.multipliedReportingOverflow(by: cy64)
        if sxy { product1 = 0 &- product1 }
        if z._isSignMinus { cz64 = 0 &- cz64 }
        let (hi, lo) = delta < 0 ? (cz64, product1) : (product1, cz64)
        let scale = unsafe Int64(
          truncatingIfNeeded: UInt128._exp10[unchecked: abs(delta)])
        let (product2, overflow2) = hi.multipliedReportingOverflow(by: scale)
        let (sum, overflow3) = product2.addingReportingOverflow(lo)
        if !overflow1 && !overflow2 && !overflow3 {
          if sum != 0 {
            return Self(
              sign: sum < 0 ? .minus : .plus,
              exponentBitPattern: UInt(min(exy, ez)),
              significandBitPattern: UInt128(sum.magnitude))
          }
          let isSignMinus = sxy == z._isSignMinus
            ? sxy
            : rule == .down
          let abs = Self(bitPattern: UInt128(min(exy, ez)) &<< 113)
          return isSignMinus ? -abs : abs
        }
      }
    }

    let lte = (cx | cy) <= 0xffff_ffff_ffff_ffff /* UInt64.max */
    guard z.isFinite /* && x._isFiniteNonzero && y._isFiniteNonzero */
      && max(ex, ey) <= 0x2fff
      && cx != 0 && cy != 0
      && (lte || (cx < ._1e34 && cy < ._1e34))
    else {
      if z.isSignalingNaN {
        _raise(.invalid, in: &flags)
        z = z._quiet
      }
      if x.isSignalingNaN {
        _raise(.invalid, in: &flags)
        x = x._quiet
      }
      if y.isSignalingNaN {
        _raise(.invalid, in: &flags)
        y = y._quiet
      }
      let invalid = (x.isZero && y.isInfinite) || (y.isZero && x.isInfinite)
      if invalid {
        _raise(.invalid, in: &flags)
      }
      if z.isNaN { return z._canonical }
      if x.isNaN { return x._canonical }
      if y.isNaN { return y._canonical }
      if invalid { return .nan }

      if x.isInfinite || y.isInfinite {
        let isSignMinus = x._isSignMinus != y._isSignMinus
        if z.isInfinite && z._isSignMinus != isSignMinus {
          _raise(.invalid, in: &flags)
          return .nan
        }
        return isSignMinus ? -.infinity : .infinity
      }
      if z.isInfinite {
        return z._canonical
      }

      // `x.isZero || y.isZero`.
      var ez = Int(z.exponentBitPattern)
      let e_ =
        min(ez, Int(x.exponentBitPattern) &- 6176 &+ Int(y.exponentBitPattern))
      if z.isZero {
        let isSignMinus = rule == .down
          ? z._isSignMinus || (x._isSignMinus != y._isSignMinus)
          : z._isSignMinus && (x._isSignMinus != y._isSignMinus)
        let abs = Self(
          bitPattern: UInt128(truncatingIfNeeded: max(0, e_)) &<< 113)
        return isSignMinus ? -abs : abs
      }
      var cz = z.significandBitPattern
      Self._select(
        biasedExponent: &ez,
        nonzeroSignificand: &cz,
        boundedPreferredBiasedExponent: max(e_, 0))
      let abs = Self(bitPattern: UInt128(truncatingIfNeeded: ez) &<< 113 | cz)
      return z._isSignMinus ? -abs : abs
    }

    let ez = Int(z.exponentBitPattern)
    var cz = z.significandBitPattern
    if cz >= ._1e34 { cz = 0 }
    let cxy: (high: UInt128, low: UInt128)
    let sameSign = sxy == z._isSignMinus
    if cz != 0 {
      let n = ez &- exy
      if n >= 69 {
        let logcz = cz._commonLogarithm
        // Without computing the product `cxy`, we know it has at most 68
        // digits, and hence `log10(cxy)` is at most 67.
        let minDelta = n &+ logcz &- 67
        if minDelta >= 35 {
          // Inexact.
          var e = max(0, ez &+ logcz &- 33)
          var c = unsafe cz &* ._exp10[unchecked: ez &- e]
          let isTiny = e == 0 && (sameSign ? c < ._1e33 : c <= ._1e33)
          if sameSign {
            let nextAway: Bool =
              switch rule {
              case .toNearestOrEven, .toNearestOrAwayFromZero:
                false
              case .towardZero:
                false
              case .awayFromZero:
                true
              case .down:
                sxy
              case .up:
                !sxy
              @unknown default:
                fatalError("Unknown rounding rule.")
              }
            if nextAway {
              if c == ._1e34 &- 1 {
                if e == 12287 {
                  _raise(.overflowInexact, in: &flags)
                  return sxy ? -.infinity : .infinity
                }
                c = ._1e33
                e &+= 1
              } else {
                c &+= 1
              }
            }
          } else {
            let nextToward: Bool
            switch rule {
            case .toNearestOrEven, .toNearestOrAwayFromZero:
              if minDelta == 35 && c == ._1e33 && e != 0 {
                let _5e33: UInt128 = ._1e34 &>> 1
                nextToward = cx > _5e33 && cy > _5e33 &&
                  cx._multipliedFullWidth(by: cy) >
                    _5e33._multipliedFullWidth(by: ._1e34)
              } else {
                nextToward = false
              }
            case .towardZero:
              nextToward = true
            case .awayFromZero:
              nextToward = false
            case .down:
              nextToward = sxy
            case .up:
              nextToward = !sxy
            @unknown default:
              fatalError("Unknown rounding rule.")
            }
            if nextToward {
              if c == ._1e33 && e != 0 {
                c = ._1e34 &- 1
                e &-= 1
              } else {
                c &-= 1
              }
            }
          }
          let abs = Self(bitPattern: UInt128(truncatingIfNeeded: e) &<< 113 | c)
          if isTiny {
            _raise(.underflowInexact, in: &flags)
          } else {
            _raise(.inexact, in: &flags)
          }
          return z._isSignMinus ? -abs : abs
        }
      }
    }

    if lte {
      let (hi, lo) =
        UInt64(truncatingIfNeeded: cx).multipliedFullWidth(
          by: UInt64(truncatingIfNeeded: cy))
      cxy = (0, UInt128(hi) &<< 64 | UInt128(lo))
    } else {
      cxy = cx._multipliedFullWidth(by: cy)
    }
    if cxy.high == 0 && cxy.low < ._1e34 && exy >= 0 && exy <= 12287 {
      let isSignMinus = x._isSignMinus != y._isSignMinus
      let abs = Self(
        bitPattern: UInt128(truncatingIfNeeded: exy) &<< 113 | cxy.low)
      return z._adding(isSignMinus ? -abs : abs, rounding: rule, &flags)
    }

    let pe = min(exy, ez)
    if cz == 0 {
      return ._pack(
        isSignMinus: x._isSignMinus != y._isSignMinus,
        biasedExponent: exy,
        significand: cxy,
        preferredBiasedExponent: pe,
        rule,
        &flags)
    }

    var isSignMinus: Bool
    var e: Int
    var c: (high: UInt128, low: UInt128)
    var sticky = false
    let n_ = ez &- exy
    if n_ >= 0 && n_ <= 34 {
      let cz_ = n_ == 0
        ? (high: 0, low: cz)
        : unsafe cz._multipliedFullWidth(by: ._exp10[unchecked: n_])
      // Compute `cxy + cz_` if same sign,
      // or `abs(cxy - cz_) = abs(~(~cxy + cz_))` if not.
      let mask: UInt128 = sameSign ? 0 : .max
      let carry: Bool
      (c.low, carry) = (cxy.low ^ mask).addingReportingOverflow(cz_.low)
      c.low ^= mask
      c.high = ((cxy.high ^ mask) &+ cz_.high &+ (carry ? 1 : 0)) ^ mask
      let complement = Int128(bitPattern: c.high) < 0
      if complement {
        c.high = ~c.high &+ (c.low == 0 ? 1 : 0)
        c.low = 0 &- c.low
      }
      isSignMinus = c == (0, 0) ? rule == .down : sxy != complement
      return ._pack(
        isSignMinus: isSignMinus,
        biasedExponent: exy,
        significand: c,
        rule,
        &flags)
    }

    let logcz = cz._commonLogarithm
    if ez &+ logcz < exy && (cxy.high != 0 || cxy.low >= ._1e34) {
      // Normalize the product while obtaining its remainder.
      var n: Int
      var divisor: UInt128
      var quo: UInt128
      var rem: UInt128
      if cxy.high == 0 {
        n = cxy.low._commonLogarithm &- 33
        divisor = unsafe ._exp10[unchecked: n]
        (quo, rem) = cxy.low._quotientAndRemainder(dividingBy1e: n)
      } else {
        // See explanatory comment in `UInt128._commonLogarithm`.
        // Note that here we underestimate using a closer approximation.
        n = ((1233 &* (255 &- cxy.high.leadingZeroBitCount)) &>> 12) &- 33
        divisor = unsafe ._exp10[unchecked: n]
        (quo, rem) =
          UInt128._quotientAndRemainder(fullWidth: cxy, dividingBy1e: n)
        if quo >= ._1e34 {
          let digit: UInt128
          (quo, digit) = quo.quotientAndRemainder(dividingBy: 10)
          rem &+= digit &* divisor
          divisor &*= 10
          n &+= 1
        }
      }
      e = exy &+ n
      if rem != 0 || sameSign {
        switch rule {
        case .toNearestOrEven, .toNearestOrAwayFromZero:
          quo &+= rem &+ (sameSign ? 1 : 0) > (divisor &>> 1) ? 1 : 0
        case .towardZero:
          break
        case .awayFromZero:
          quo &+= 1
        case .down:
          quo &+= sxy ? 1 : 0
        case .up:
          quo &+= sxy ? 0 : 1
        @unknown default:
          fatalError("Unknown rounding rule.")
        }
        if quo == ._1e34 {
          quo = ._1e33
          e &+= 1
        }
      } else {
        let nextToward: Bool =
          switch rule {
          case .toNearestOrEven, .toNearestOrAwayFromZero:
            if quo == ._1e33 && n == 1 && ez &+ logcz == exy &- 1 {
              unsafe cz > ._exp10[unchecked: logcz &+ 1] &>> 1
            } else {
              false
            }
          case .towardZero:
            true
          case .awayFromZero:
            false
          case .down:
            !sxy
          case .up:
            sxy
          @unknown default:
            fatalError("Unknown rounding rule.")
          }
        if nextToward {
          if quo == ._1e33 {
            quo = ._1e34 &- 1
            e &-= 1
          } else {
            quo &-= 1
          }
        }
      }
      guard e <= 12287 else {
        return ._overflow(isSignMinus: sxy, rule, &flags)
      }
      let abs = Self(bitPattern: UInt128(truncatingIfNeeded: e) &<< 113 | quo)
      _raise(.inexact, in: &flags)
      return sxy ? -abs : abs
    }

    var n: Int
    var divisor: UInt128 = 0
    if cxy.high == 0 {
      n = cxy.low._commonLogarithm &- 33
    } else {
      // See explanatory comment in `UInt128._commonLogarithm`.
      // Note that here we underestimate.
      n = ((77 &* (255 &- cxy.high.leadingZeroBitCount)) &>> 8) &- 33
      divisor = unsafe UInt128._exp10[unchecked: n]
      if cxy >= divisor._multipliedFullWidth(by: ._1e34) {
        n &+= 1
      }
    }
    let delta = ez &+ logcz &- (exy &+ n &+ 33)
    if (sameSign ? delta >= 0 : delta >= 2) && ez &+ logcz >= 34 {
      let n_ = n &+ delta
      if n_ >= 1 && n_ <= 38 {
        // Shrink.
        let cz_ = unsafe cz &* ._exp10[unchecked: 33 &- logcz]
        divisor = unsafe ._exp10[unchecked: n_]
        var (q, r) =
          if cxy.high == 0 {
            cxy.low < divisor
              ? (0, cxy.low)
              : cxy.low._quotientAndRemainder(dividingBy1e: n_)
          } else {
            UInt128._quotientAndRemainder(
              fullWidth: (cxy.high, cxy.low), dividingBy1e: n_)
          }
        if sameSign {
          q &+= cz_
        } else {
          assert(cz_ > q)
          q = cz_ &- q
          if r != 0 {
            q &-= 1
            r = divisor &- r
          }
        }

        isSignMinus = z._isSignMinus
        e = ez &+ logcz &- 33
        if q >= ._1e34 {
          sticky = r != 0
          (q, r) = q.quotientAndRemainder(dividingBy: 10)
          divisor = 10
          e &+= 1
        } else {
          sticky = false
          // Recover one digit, if necessary.
          if q < ._1e33 {
            let digit: UInt128
            (digit, r) = r._quotientAndRemainder(dividingBy1e: n_ &- 1)
            q = q &* 10 &+ digit
            divisor = unsafe ._exp10[unchecked: n_ &- 1]
            e &-= 1
          }
        }
        assert(q >= ._1e33 && q < ._1e34)
        guard e <= 12287 else {
          return ._overflow(isSignMinus: isSignMinus, rule, &flags)
        }
        if r != 0 || sticky {
          let half = divisor &>> 1
          switch rule {
          case .toNearestOrEven:
            q &+= r &+ (sticky || (q & 1) != 0 ? 1 : 0) > half ? 1 : 0
          case .toNearestOrAwayFromZero:
            q &+= r >= half ? 1 : 0
          case .towardZero:
            break
          case .awayFromZero:
            q &+= 1
          case .down:
            q &+= isSignMinus ? 1 : 0
          case .up:
            q &+= isSignMinus ? 0 : 1
          @unknown default:
            fatalError("Unknown rounding rule.")
          }
          if q == ._1e34 {
            if e == 12287 {
              _raise(.overflowInexact, in: &flags)
              return isSignMinus ? -.infinity : .infinity
            }
            q = ._1e33
            e &+= 1
          }
          _raise(.inexact, in: &flags)
        }
        let abs = Self(bitPattern: UInt128(truncatingIfNeeded: e) &<< 113 | q)
        return isSignMinus ? -abs : abs
      }
    }

    if !sameSign && delta >= -1 && delta <= 1 {
      // Deep cancellation.
      e = pe
      let cz_: (high: UInt128, low: UInt128)
      let cxy_: (high: UInt128, low: UInt128)
      let n_ = ez &- exy
      if n_ > 0 {
        cxy_ = cxy
        if n_ <= 38 {
          cz_ = cz._multipliedFullWidth(by1e: n_)
        } else {
          let p = unsafe cz &* ._exp10[unchecked: n_ &- 34]
          cz_ = p._multipliedFullWidth(by: ._1e34)
        }
      } else {
        cz_ = (0, cz)
        assert(cxy.high == 0)
        cxy_ = cxy.low._multipliedFullWidth(by1e: -n_)
      }
      if cxy_ >= cz_ {
        let borrow: Bool
        (c.low, borrow) = cxy_.low.subtractingReportingOverflow(cz_.low)
        c.high = cxy_.high &- (cz_.high &+ (borrow ? 1 : 0))
        isSignMinus = c == (0, 0)
          ? rule == .down // Exact zero. See IEEE 754 §6.3.
          : sxy
      } else {
        let borrow: Bool
        (c.low, borrow) = cz_.low.subtractingReportingOverflow(cxy_.low)
        c.high = cz_.high &- (cxy_.high &+ (borrow ? 1 : 0))
        isSignMinus = z._isSignMinus
      }
    } else if delta >= 0 {
      // Addend `z` is dominant.
      isSignMinus = z._isSignMinus
      // Keep 36 digits.
      e = ez &+ logcz &- 35
      let cz_ = unsafe cz &* ._exp10[unchecked: 35 &- logcz]
      let cxy_: UInt128
      let n_ = e &- exy
      if n_ <= 0 {
        assert(cxy.high == 0)
        cxy_ = unsafe cxy.low &* ._exp10[unchecked: -n_]
      } else if n_ > n &+ 33 {
        cxy_ = 0
        sticky = true
      } else if n_ <= 38 {
        let r: UInt128
        (cxy_, r) = cxy.high == 0
          ? cxy.low._quotientAndRemainder(dividingBy1e: n_)
          : UInt128._quotientAndRemainder(fullWidth: cxy, dividingBy1e: n_)
        sticky = r != 0
      } else {
        let (q1, r1) =
          UInt128._quotientAndRemainder(fullWidth: cxy, dividingBy1e: 38)
        let r2: UInt128
        (cxy_, r2) = q1._quotientAndRemainder(dividingBy1e: n_ &- 38)
        sticky = r1 != 0 || r2 != 0
      }
      if sameSign {
        c = (0, cz_ &+ cxy_)
      } else {
        c = (0, cz_ &- cxy_)
        if sticky {
          c.low &-= 1
        }
      }
    } else {
      // Product is dominant.
      isSignMinus = sxy
      // Again, keep 36 digits.
      e = exy
      if n >= 2 {
        c = cxy
      } else {
        e &-= 2 &- n
        c = (0, unsafe cxy.low &* ._exp10[unchecked: 2 &- n])
      }
      let cz_: (high: UInt128, low: UInt128)
      let n_ = ez &- e
      if n_ >= 0 {
        if n_ <= 38 {
          cz_ = cz._multipliedFullWidth(by1e: n_)
        } else {
          let p = unsafe cz &* ._exp10[unchecked: n_ &- 34]
          cz_ = p._multipliedFullWidth(by: ._1e34)
        }
      } else if -n_ > logcz {
        cz_ = (0, 0)
        sticky = true
      } else {
        let (q, r) = cz._quotientAndRemainder(dividingBy1e: -n_)
        cz_ = (0, q)
        sticky = r != 0
      }
      if sameSign {
        let carry: Bool
        (c.low, carry) = c.low.addingReportingOverflow(cz_.low)
        c.high &+= cz_.high &+ (carry ? 1 : 0)
      } else {
        let borrow1: Bool
        (c.low, borrow1) = c.low.subtractingReportingOverflow(cz_.low)
        c.high &-= cz_.high &+ (borrow1 ? 1 : 0)
        if sticky {
          let borrow2: Bool
          (c.low, borrow2) = c.low.subtractingReportingOverflow(1)
          if borrow2 { c.high &-= 1 }
        }
      }
    }
    return ._pack(
      isSignMinus: isSignMinus,
      biasedExponent: e,
      significand: c,
      sticky: sticky,
      preferredBiasedExponent: pe,
      rule,
      &flags)
  }

  /// Returns the result of adding the product of the two given values
  /// to this value, computed without intermediate rounding.
  ///
  /// The final result is rounded if needed to the nearest representable value
  /// (ties to even).
  ///
  /// This method implements the `fusedMultiplyAdd` operation defined by the
  /// IEEE 754 specification.
  ///
  /// - Parameters:
  ///   - lhs: One of the values to multiply before adding to this value.
  ///   - rhs: The other value to multiply.
  /// - Returns: The product of `lhs` and `rhs`, added to this value.
  @inline(always)
  public func addingProduct(
    _ lhs: Decimal128, _ rhs: Decimal128
  ) -> Decimal128 {
    var flags: DecimalFloatingPointStatusFlags = []
    defer { _signal(flags) }
    return _addingProduct(lhs, rhs, rounding: .toNearestOrEven, &flags)
  }

  /// Returns the result of adding the product of the two given values
  /// to this value, computed without intermediate rounding,
  /// accumulating status flags.
  ///
  /// The final result is rounded if needed to the nearest representable value
  /// (ties to even).
  ///
  /// This method implements the `fusedMultiplyAdd` operation defined by the
  /// IEEE 754 specification.
  ///
  /// - Parameters:
  ///   - lhs: One of the values to multiply before adding to this value.
  ///   - rhs: The other value to multiply.
  ///   - flags: A value that accumulates decimal floating-point arithmetic
  ///     status flags.
  /// - Returns: The product of `lhs` and `rhs`, added to this value.
  @inline(always)
  public func addingProduct(
    _ lhs: Decimal128, _ rhs: Decimal128,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) -> Decimal128 {
    _addingProduct(lhs, rhs, rounding: .toNearestOrEven, &flags)
  }

  /// Returns the result of adding the product of the two given values
  /// to this value, computed without intermediate rounding.
  ///
  /// The final result is rounded if needed using the given rounding rule.
  ///
  /// This method implements the `fusedMultiplyAdd` operation defined by the
  /// IEEE 754 specification.
  ///
  /// - Parameters:
  ///   - lhs: One of the values to multiply before adding to this value.
  ///   - rhs: The other value to multiply.
  ///   - rule: The rounding rule to use for an inexact result.
  /// - Returns: The product of `lhs` and `rhs`, added to this value.
  @inline(always)
  public func addingProduct(
    _ lhs: Decimal128, _ rhs: Decimal128,
    rounding rule: FloatingPointRoundingRule
  ) -> Decimal128 {
    var flags: DecimalFloatingPointStatusFlags = []
    defer { _signal(flags) }
    return _addingProduct(lhs, rhs, rounding: .init(rule), &flags)
  }

  /// Returns the result of adding the product of the two given values
  /// to this value, computed without intermediate rounding,
  /// accumulating status flags.
  ///
  /// The final result is rounded if needed using the given rounding rule.
  ///
  /// This method implements the `fusedMultiplyAdd` operation defined by the
  /// IEEE 754 specification.
  ///
  /// - Parameters:
  ///   - lhs: One of the values to multiply before adding to this value.
  ///   - rhs: The other value to multiply.
  ///   - rule: The rounding rule to use for an inexact result.
  ///   - flags: A value that accumulates decimal floating-point arithmetic
  ///     status flags.
  /// - Returns: The product of `lhs` and `rhs`, added to this value.
  @inline(always)
  public func addingProduct(
    _ lhs: Decimal128, _ rhs: Decimal128,
    rounding rule: FloatingPointRoundingRule,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) -> Decimal128 {
    _addingProduct(lhs, rhs, rounding: .init(rule), &flags)
  }

  /// Adds the product of the two given values to this value in place,
  /// computed without intermediate rounding.
  ///
  /// The final result is rounded if needed to the nearest representable value
  /// (ties to even).
  ///
  /// - Parameters:
  ///   - lhs: One of the values to multiply before adding to this value.
  ///   - rhs: The other value to multiply.
  @inline(always)
  public mutating func addProduct(_ lhs: Decimal128, _ rhs: Decimal128) {
    self = addingProduct(lhs, rhs)
  }

  /// Adds the product of the two given values to this value in place,
  /// computed without intermediate rounding, accumulating status flags.
  ///
  /// The final result is rounded if needed to the nearest representable value
  /// (ties to even).
  ///
  /// - Parameters:
  ///   - lhs: One of the values to multiply before adding to this value.
  ///   - rhs: The other value to multiply.
  ///   - flags: A value that accumulates decimal floating-point arithmetic
  ///     status flags.
  @inline(always)
  public mutating func addProduct(
    _ lhs: Decimal128, _ rhs: Decimal128,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) {
    self = addingProduct(lhs, rhs, &flags)
  }

  /// Adds the product of the two given values to this value in place,
  /// computed without intermediate rounding.
  ///
  /// The final result is rounded if needed using the given rounding rule.
  ///
  /// - Parameters:
  ///   - lhs: One of the values to multiply before adding to this value.
  ///   - rhs: The other value to multiply.
  ///   - rule: The rounding rule to use for an inexact result.
  @inline(always)
  public mutating func addProduct(
    _ lhs: Decimal128, _ rhs: Decimal128,
    rounding rule: FloatingPointRoundingRule
  ) {
    self = addingProduct(lhs, rhs, rounding: rule)
  }

  /// Adds the product of the two given values to this value in place,
  /// computed without intermediate rounding, accumulating status flags.
  ///
  /// The final result is rounded if needed using the given rounding rule.
  ///
  /// - Parameters:
  ///   - lhs: One of the values to multiply before adding to this value.
  ///   - rhs: The other value to multiply.
  ///   - rule: The rounding rule to use for an inexact result.
  ///   - flags: A value that accumulates decimal floating-point arithmetic
  ///     status flags.
  @inline(always)
  public mutating func addProduct(
    _ lhs: Decimal128, _ rhs: Decimal128,
    rounding rule: FloatingPointRoundingRule,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) {
    self = addingProduct(lhs, rhs, rounding: rule, &flags)
  }

  @usableFromInline
  internal func _divided(
    by rhs: Decimal128,
    rounding rule: _DecimalFloatingPointRoundingRule,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) -> Decimal128 {
    var lhs = self, rhs = rhs
    let isSignMinus = lhs._isSignMinus != rhs._isSignMinus

    guard lhs._isFiniteNonzero && rhs._isFiniteNonzero else {
      if lhs.isSignalingNaN {
        _raise(.invalid, in: &flags)
        lhs = lhs._quiet
      }
      if rhs.isSignalingNaN {
        _raise(.invalid, in: &flags)
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
          _raise(.invalid, in: &flags)
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
          _raise(.invalid, in: &flags)
          return .nan
        }
        _raise(.divisionByZero, in: &flags)
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
      return ._pack(
        isSignMinus: isSignMinus,
        biasedExponent: e,
        significand: (0, lc),
        rule,
        &flags)
    }

    // Fast path for integer significands that fit in 64 bits.
    if (lc | rc) <= 0xffff_ffff_ffff_ffff /* UInt64.max */ {
      let x = UInt64(truncatingIfNeeded: lc)
      let y = UInt64(truncatingIfNeeded: rc)
      let q = x / y
      if x &- q &* y == 0 && UInt(bitPattern: e) <= 12287 {
        let abs = Self(bitPattern: UInt128(e) &<< 113 | UInt128(q))
        return isSignMinus ? -abs : abs
      }
      let ctz1 = y.trailingZeroBitCount
      var y_ = y &>> ctz1
      var fives1 = 0
      while y_ % 5 == 0 {
        y_ /= 5
        fives1 &+= 1
      }
      // Now, `y = (2 ** ctz1) * (5 ** fives1) * y_`,
      // where `y_` and 10 are co-prime.
      //
      // The decimal expansion of `x / y` terminates exactly
      // when `y_` divides `x`.
      if x % y_ == 0 {
        let ctz2 = x.trailingZeroBitCount
        var x_ = x
        var fives2 = 0
        while x_ % 5 == 0 {
          x_ /= 5
          fives2 &+= 1
        }
        let digitCount = max(ctz1 &- ctz2, fives1 &- fives2)
        if digitCount <= 19 {
          let digitCount_ = max(0, digitCount)
          let scale = unsafe UInt64(
            truncatingIfNeeded: UInt128._exp10[unchecked: digitCount_])
          let overflow: Bool
          (x_, overflow) = x.multipliedReportingOverflow(by: scale)
          // Since we may fall through, we won't mutate `e` itself.
          let e_ = e &- digitCount_
          if !overflow && UInt(bitPattern: e_) <= 12287 {
            let q = x_ / y
            let abs = Self(bitPattern: UInt128(e_) &<< 113 | UInt128(q))
            return isSignMinus ? -abs : abs
          }
        }
      }
    }

    let n: Int
    var quo: UInt128
    let rem: UInt128
    // Fast path for division by powers of ten.
    let ctz = UInt64(truncatingIfNeeded: rc).trailingZeroBitCount
    if unsafe ctz <= 33 && rc == ._exp10[unchecked: ctz] {
      n = ctz
      (quo, rem) = (lc, 0)
    } else if rc <= 18446744 /* UInt64.max / 1_000_000_000_000 */
      && lc < UInt128(UInt64(truncatingIfNeeded: rc) &* 1_000_000_000_000)
    {
      // For a sufficiently small `rc`, compute the 34-digit quotient using
      // three 64-bit divisions.
      var x = UInt64(truncatingIfNeeded: lc)
      let y = UInt64(truncatingIfNeeded: rc)
      // See explanatory comment in `UInt128._commonLogarithm`.
      // Note that here we use a closer approximation.
      let estimate =
        (1233 &* (x.leadingZeroBitCount &- y.leadingZeroBitCount &+ 1)) &>> 12

      // First, scale the numerator just enough for 12 quotient digits.
      var n_ = max(0, 11 &+ estimate)
      x &*= unsafe UInt64(truncatingIfNeeded: UInt128._exp10[unchecked: n_])
      let _1e11: UInt64 = 100_000_000_000
      if x < y &* _1e11 {
        n_ &+= 1
        x &*= 10
      }
      let q1: UInt64
      (q1, x) = x.quotientAndRemainder(dividingBy: y)
      // Multiply the remainder by `10**11` and divide for 11 quotient digits.
      let q2: UInt64
      (q2, x) = (x &* _1e11).quotientAndRemainder(dividingBy: y)
      // Again.
      let q3: UInt64
      (q3, x) = (x &* _1e11).quotientAndRemainder(dividingBy: y)

      n = n_ &+ 22
      quo =
        UInt128(q1) &* 10_000_000_000_000_000_000_000 &+
        UInt128(q2) &* 100_000_000_000 &+
        UInt128(q3)
      rem = UInt128(x)
    } else {
      // Check the integer estimate before scaling.
      if (lc | rc) > UInt64.max && lc >= rc {
        let shift = max(0, 64 &- lc.leadingZeroBitCount)
        let x = UInt64(truncatingIfNeeded: lc &>> shift)
        let y = UInt64(truncatingIfNeeded: rc &>> shift)
        if y != 0 {
          let q = UInt128(x / y)
          if q &* rc == lc {
            if e >= 0 && e <= 12287 {
              let abs =
                Self(bitPattern: UInt128(truncatingIfNeeded: e) &<< 113 | q)
              return isSignMinus ? -abs : abs
            }
            return ._pack(
              isSignMinus: isSignMinus,
              biasedExponent: e,
              significand: (0, q),
              rule,
              &flags)
          }
        }
      }
      // Choose `n` such that `10**33 <= (lc * 10**n / rc) < 10**34`.
      //
      // See explanatory comment in `UInt128._commonLogarithm`.
      // Note that here we use a closer approximation.
      let estimate =
        (1233 &* (lc.leadingZeroBitCount &- rc.leadingZeroBitCount &+ 1)) &>> 12
      let dividend: (high: UInt128, low: UInt128)
      if estimate < 0 {
        n = unsafe lc < rc &* ._exp10[unchecked: -estimate]
          ? 34 &+ estimate
          : 33 &+ estimate
        dividend = lc._multipliedFullWidth(by1e: n)
      } else {
        let x = unsafe lc &* ._exp10[unchecked: estimate]
        let lt = x < rc
        n = estimate &+ (lt ? 34 : 33)
        dividend = x._multipliedFullWidth(by: lt ? ._1e34 : ._1e33)
      }
      (quo, rem) = UInt128.__quotientAndRemainder(
        fullWidth: dividend, dividingBy: rc)
    }
    let pe = e // Hang on to the preferred exponent for later.
    e &-= n

    if rem == 0 {
      if e >= 0 && e <= 12287 {
        let pe = min(12287, pe)
        if e < pe {
          Self._select(
            biasedExponent: &e,
            nonzeroSignificand: &quo,
            boundedPreferredBiasedExponent: pe)
        }
        let abs = Self(bitPattern: UInt128(truncatingIfNeeded: e) &<< 113 | quo)
        return isSignMinus ? -abs : abs
      }
      return ._pack(
        isSignMinus: isSignMinus,
        biasedExponent: e,
        significand: (0, quo),
        preferredBiasedExponent: pe,
        rule,
        &flags)
    }
    if e > 12287 {
      return ._overflow(isSignMinus: isSignMinus, rule, &flags)
    }
    if e >= 0 {
      let rr = rem &<< 1 // `rem * 2`.
      let nextAway: Bool =
        switch rule {
        case .toNearestOrEven:
          rr &+ (quo & 1) > rc
        case .toNearestOrAwayFromZero:
          rr >= rc
        case .towardZero:
          false
        case .awayFromZero:
          true
        case .down:
          isSignMinus
        case .up:
          !isSignMinus
        @unknown default:
          fatalError("Unknown rounding rule.")
        }
      quo &+= nextAway ? 1 : 0
      _raise(.inexact, in: &flags)
      let abs = Self(bitPattern: UInt128(truncatingIfNeeded: e) &<< 113 | quo)
      return isSignMinus ? -abs : abs
    }
    // Inexact underflow.
    let nearestAway: Bool
    if e < -34 {
      quo = 0
      nearestAway = false
    } else {
      let r: UInt128
      (quo, r) = quo._quotientAndRemainder(dividingBy1e: -e)
      // The sticky bit is always set, so there are no ties.
      nearestAway = unsafe r >= (._exp10[unchecked: -e] &>> 1)
    }
    switch rule {
    case .toNearestOrEven, .toNearestOrAwayFromZero:
      quo &+= nearestAway ? 1 : 0
    case .towardZero:
      break
    case .awayFromZero:
      quo &+= 1
    case .down:
      quo &+= isSignMinus ? 1 : 0
    case .up:
      quo &+= isSignMinus ? 0 : 1
    @unknown default:
      fatalError("Unknown rounding rule.")
    }
    _raise(.underflowInexact, in: &flags)
    let abs = Self(bitPattern: quo)
    return isSignMinus ? -abs : abs
  }

  /// Returns the quotient of dividing the first value by the second.
  ///
  /// The result is rounded if needed to the nearest representable value
  /// (ties to even).
  ///
  /// This method implements the `division` operation defined by the
  /// IEEE 754 specification.
  ///
  /// - Parameters:
  ///   - lhs: The value to divide.
  ///   - rhs: The value by which to divide `lhs`.
  /// - Returns: The quotient of `lhs` and `rhs`, rounded if needed.
  @inline(always)
  public static func / (lhs: Decimal128, rhs: Decimal128) -> Decimal128 {
    var flags: DecimalFloatingPointStatusFlags = []
    defer { _signal(flags) }
    return lhs._divided(by: rhs, rounding: .toNearestOrEven, &flags)
  }

  /// Returns the result of dividing this value by the given value,
  /// accumulating status flags.
  ///
  /// The result is rounded if needed to the nearest representable value
  /// (ties to even).
  ///
  /// This method implements the `division` operation defined by the
  /// IEEE 754 specification.
  ///
  /// - Parameters:
  ///   - rhs: The value by which to divide this value.
  ///   - flags: A value that accumulates decimal floating-point arithmetic
  ///     status flags.
  /// - Returns: The quotient of this value and `rhs`, rounded if needed.
  @inline(always)
  public func divided(
    by rhs: Decimal128,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) -> Decimal128 {
    _divided(by: rhs, rounding: .toNearestOrEven, &flags)
  }

  /// Returns the result of dividing this value by the given value.
  ///
  /// The result is rounded if needed using the given rounding rule.
  ///
  /// This method implements the `division` operation defined by the
  /// IEEE 754 specification.
  ///
  /// - Parameters:
  ///   - rhs: The value by which to divide this value.
  ///   - rule: The rounding rule to use for an inexact result.
  /// - Returns: The quotient of this value and `rhs`, rounded if needed.
  @inline(always)
  public func divided(
    by rhs: Decimal128,
    rounding rule: FloatingPointRoundingRule
  ) -> Decimal128 {
    var flags: DecimalFloatingPointStatusFlags = []
    defer { _signal(flags) }
    return _divided(by: rhs, rounding: .init(rule), &flags)
  }

  /// Returns the result of dividing this value by the given value,
  /// accumulating status flags.
  ///
  /// The result is rounded if needed using the given rounding rule.
  ///
  /// This method implements the `division` operation defined by the
  /// IEEE 754 specification.
  ///
  /// - Parameters:
  ///   - rhs: The value by which to divide this value.
  ///   - rule: The rounding rule to use for an inexact result.
  ///   - flags: A value that accumulates decimal floating-point arithmetic
  ///     status flags.
  /// - Returns: The quotient of this value and `rhs`, rounded if needed.
  @inline(always)
  public func divided(
    by rhs: Decimal128,
    rounding rule: FloatingPointRoundingRule,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) -> Decimal128 {
    _divided(by: rhs, rounding: .init(rule), &flags)
  }

  /// Divides the first value by the second
  /// and stores the quotient in the left-hand-side variable.
  ///
  /// The result is rounded if needed to the nearest representable value
  /// (ties to even).
  ///
  /// - Parameters:
  ///   - lhs: The value to divide.
  ///   - rhs: The value by which to divide `lhs`.
  @inline(always)
  public static func /= (lhs: inout Decimal128, rhs: Decimal128) {
    lhs = lhs / rhs
  }

  /// Divides this value by the given value in place, accumulating status flags.
  ///
  /// The result is rounded if needed to the nearest representable value
  /// (ties to even).
  ///
  /// - Parameters:
  ///   - rhs: The value by which to divide this value.
  ///   - flags: A value that accumulates decimal floating-point arithmetic
  ///     status flags.
  @inline(always)
  public mutating func divide(
    by rhs: Decimal128,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) {
    self = divided(by: rhs, &flags)
  }

  /// Divides this value by the given value in place.
  ///
  /// The result is rounded if needed using the given rounding rule.
  ///
  /// - Parameters:
  ///   - rhs: The value by which to divide this value.
  ///   - rule: The rounding rule to use for an inexact result.
  @inline(always)
  public mutating func divide(
    by rhs: Decimal128,
    rounding rule: FloatingPointRoundingRule
  ) {
    self = divided(by: rhs, rounding: rule)
  }

  /// Divides this value by the given value in place, accumulating status flags.
  ///
  /// The result is rounded if needed using the given rounding rule.
  ///
  /// - Parameters:
  ///   - rhs: The value by which to divide this value.
  ///   - rule: The rounding rule to use for an inexact result.
  ///   - flags: A value that accumulates decimal floating-point arithmetic
  ///     status flags.
  @inline(always)
  public mutating func divide(
    by rhs: Decimal128,
    rounding rule: FloatingPointRoundingRule,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) {
    self = divided(by: rhs, rounding: rule, &flags)
  }

  @usableFromInline
  internal func _remainder(
    truncating: Bool,
    dividingBy divisor: Decimal128,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) -> Decimal128 {
    var x = self, y = divisor

    // A fast path for certain 'everyday' values. Purely an optimization.
    do {
      // See `significandBitPattern`:
      let cx = x.bitPattern & ((1 &<< 113) &- 1)
      let cy = y.bitPattern & ((1 &<< 113) &- 1)
      // See `exponentBitPattern`:
      let ex = Int(truncatingIfNeeded: x.bitPattern &>> 113) & 0x3fff
      let ey = Int(truncatingIfNeeded: y.bitPattern &>> 113) & 0x3fff
      let delta = ex &- ey
      if (cx | cy) <= 0xffff_ffff_ffff_ffff /* UInt64.max */
        && max(ex, ey) <= 0x2fff // Neither combination field starts `0b11...`.
        && delta.magnitude <= 19 && cy != 0
      {
        let cx64 = UInt64(truncatingIfNeeded: cx)
        let cy64 = UInt64(truncatingIfNeeded: cy)
        let scale = unsafe UInt64(
          truncatingIfNeeded: UInt128._exp10[unchecked: abs(delta)])
        let (scaled, overflow) = (delta < 0 ? cy64 : cx64)
          .multipliedReportingOverflow(by: scale)
        if !overflow {
          let a = delta < 0 ? cx64 : scaled
          let b = delta < 0 ? scaled : cy64
          let (q, r) = a.quotientAndRemainder(dividingBy: b)
          let complement = b &- r
          // At the midpoint, take the complement only for an odd quotient.
          let adjust = !truncating && r &+ (q & 1) > complement
          return Self(
            sign: x._isSignMinus != adjust ? .minus : .plus,
            exponentBitPattern: UInt(min(ex, ey)),
            significandBitPattern: UInt128(adjust ? complement : r))
        }
      }
    }

    guard x._isFiniteNonzero && y._isFiniteNonzero else {
      if x.isSignalingNaN {
        _raise(.invalid, in: &flags)
        x = x._quiet
      }
      if y.isSignalingNaN {
        _raise(.invalid, in: &flags)
        y = y._quiet
      }
      if x.isNaN {
        return x._canonical
      }
      if y.isNaN {
        return y._canonical
      }

      if x.isInfinite || y.isZero {
        _raise(.invalid, in: &flags)
        return .nan
      }
      if y.isInfinite {
        return x._canonical
      }

      let e = min(x.exponentBitPattern, y.exponentBitPattern)
      let abs = Self(bitPattern: UInt128(truncatingIfNeeded: e) &<< 113)
      return x._isSignMinus ? -abs : abs
    }

    let cy = y.significandBitPattern
    let cx = x.significandBitPattern
    var isSignMinus = x._isSignMinus
    let e: UInt
    var shift = Int(x.exponentBitPattern) &- Int(y.exponentBitPattern)
    var residue: UInt128

    // Fast path for remainder dividing by powers of ten.
    let ctz = UInt64(truncatingIfNeeded: cy).trailingZeroBitCount
    if unsafe ctz <= 33 && cy == ._exp10[unchecked: ctz] {
      let e = min(x.exponentBitPattern, y.exponentBitPattern)
      let n = ctz &- shift
      if n <= 0 {
        let abs = Self(bitPattern: UInt128(truncatingIfNeeded: e) &<< 113)
        return isSignMinus ? -abs : abs
      }
      if n > 34 { return x }
      let quo: UInt128
      (quo, residue) = cx._quotientAndRemainder(dividingBy1e: n)
      if !truncating {
        let complement = unsafe ._exp10[unchecked: n] &- residue
        let adjust = residue &+ (quo & 1) > complement
        residue = adjust ? complement : residue
        isSignMinus = isSignMinus != adjust
      }
      if shift > 0 {
        // Adjust significand for the preferred exponent.
        residue &*= unsafe ._exp10[unchecked: shift]
      }
      let abs =
        Self(bitPattern: UInt128(truncatingIfNeeded: e) &<< 113 | residue)
      return isSignMinus ? -abs : abs
    }

    if shift < 0 {
      e = x.exponentBitPattern
      if -shift > 34 {
        // Both truncated and nearest quotient are zero.
        residue = cx
      } else {
        let (hi, lo) = cy._multipliedFullWidth(by1e: -shift)
        if hi != 0 {
          residue = cx
        } else if truncating {
          residue = cx % lo
        } else {
          let quo: UInt128
          if cx < lo {
            (quo, residue) = (0, cx)
          } else {
            (quo, residue) =
              UInt128._quotientAndRemainder(fullWidth: (0, cx), dividingBy: lo)
          }
          // `(quo, residue) = cx.quotientAndRemainder(dividingBy: lo)`
          let complement = lo &- residue
          let adjust = residue &+ (quo & 1) > complement
          residue = adjust ? complement : residue
          isSignMinus = isSignMinus != adjust
        }
      }
    } else {
      e = y.exponentBitPattern
      var cx_ = cx
      if shift > 0 {
        if shift >= 152 && cx_ >= cy {
          // Discover exact multiples up front to avoid setting up for modular
          // exponentiation if we don't have to.
          cx_ = ._quotientAndRemainder(
            fullWidth: (0, cx_),
            dividingBy: cy).remainder
          if cx_ == 0 {
            let abs = Self(bitPattern: UInt128(truncatingIfNeeded: e) &<< 113)
            return isSignMinus ? -abs : abs
          }
        }

        let last = (shift &- 1) % 38 &+ 1
        // See if we can decrease the total number of 38-digit chunks by one,
        // which depends on whether `cx_ * (10 ** last)` would fit in `UInt128`.
        //
        // See explanatory comment in `UInt128._commonLogarithm`.
        // Note that here we underestimate using a closer approximation.
        let estimate = (1233 &* cx_.leadingZeroBitCount) &>> 12
        if last <= estimate {
          cx_ = unsafe cx_ &* ._exp10[unchecked: last]
          shift &-= last
        }
      }
      // Crossover to modular exponentiation starting at four complete chunks of
      // 38 digits, as determined by the number of remainder operations.
      if shift < 152 {
        var quo: UInt128
        (quo, residue) =
          UInt128._quotientAndRemainder(fullWidth: (0, cx_), dividingBy: cy)
          // `cx_.quotientAndRemainder(dividingBy: cy)`
        while shift > 0 && residue != 0 {
          let chunk = min(shift, 38)
          (quo, residue) = UInt128._quotientAndRemainder(
            fullWidth: residue._multipliedFullWidth(by1e: chunk),
            dividingBy: cy)
          shift &-= chunk
        }
        if !truncating {
          let complement = cy &- residue
          // A stale quotient is harmless when `residue == 0`.
          let adjust = residue &+ (quo & 1) > complement
          residue = adjust ? complement : residue
          isSignMinus = isSignMinus != adjust
        }
      } else {
        // Use modular exponentiation for a large exponent gap.
        var n = shift / 38
        shift %= 38
        residue = cx_
        var power: UInt128 =
          ._quotientAndRemainder(
            fullWidth: unsafe (0, ._exp10[unchecked: 38]),
            dividingBy: cy).remainder
          // `._exp10[38] % cy`
        while n != 0 && residue != 0 {
          if (n & 1) != 0 {
            residue = ._quotientAndRemainder(
              fullWidth: residue._multipliedFullWidth(by: power),
              dividingBy: cy).remainder
          }
          n &>>= 1
          if n != 0 && residue != 0 {
            power = ._quotientAndRemainder(
              fullWidth: power._multipliedFullWidth(by: power),
              dividingBy: cy).remainder
          }
        }
        if shift != 0 && residue != 0 {
          residue = ._quotientAndRemainder(
            fullWidth: residue._multipliedFullWidth(by1e: shift),
            dividingBy: cy).remainder
        }
        if !truncating {
          let complement = cy &- residue
          // For exponent gaps at least 112, we can never have a tie that
          // requires consulting quotient parity.
          assert(residue != complement)
          if residue > complement {
            residue = complement
            isSignMinus.toggle()
          }
        }
      }
    }

    assert(residue < ._1e34)
    let abs =
      Self(bitPattern: UInt128(truncatingIfNeeded: e) &<< 113 | residue)
    return isSignMinus ? -abs : abs
  }

  /// Returns the remainder of this value divided by the given value.
  ///
  /// For two finite values `x` and `y`, where `y` is nonzero, the remainder `r`
  /// of dividing `x` by `y` satisfies `x == y * q + r`, where `q` is the
  /// integer nearest to `x / y`. If `x / y` is exactly halfway between two
  /// integers, `q` is chosen to be even. Note that `q` is *not* `x / y`
  /// computed in floating-point arithmetic, and that `q` may not be
  /// representable in any available integer type.
  ///
  /// If this value and `other` are both finite numbers and `other` is nonzero,
  /// the remainder has magnitude at most half of `other.magnitude`. The result
  /// is always exact.
  ///
  /// This method implements the `remainder` operation defined by the
  /// IEEE 754 specification.
  ///
  /// - Parameters:
  ///   - other: The value to use when dividing this value.
  /// - Returns: The remainder of this value divided by `other`.
  @inline(always)
  public func remainder(dividingBy other: Decimal128) -> Decimal128 {
    var flags: DecimalFloatingPointStatusFlags = []
    defer { _signal(flags) }
    return _remainder(truncating: false, dividingBy: other, &flags)
  }

  /// Returns the remainder of this value divided by the given value,
  /// accumulating status flags.
  ///
  /// For two finite values `x` and `y`, where `y` is nonzero, the remainder `r`
  /// of dividing `x` by `y` satisfies `x == y * q + r`, where `q` is the
  /// integer nearest to `x / y`. If `x / y` is exactly halfway between two
  /// integers, `q` is chosen to be even. Note that `q` is *not* `x / y`
  /// computed in floating-point arithmetic, and that `q` may not be
  /// representable in any available integer type.
  ///
  /// If this value and `other` are both finite numbers and `other` is nonzero,
  /// the remainder has magnitude at most half of `other.magnitude`. The result
  /// is always exact.
  ///
  /// This method implements the `remainder` operation defined by the
  /// IEEE 754 specification.
  ///
  /// - Parameters:
  ///   - other: The value to use when dividing this value.
  ///   - flags: A value that accumulates decimal floating-point arithmetic
  ///     status flags.
  /// - Returns: The remainder of this value divided by `other`.
  @inline(always)
  public func remainder(
    dividingBy other: Decimal128,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) -> Decimal128 {
    _remainder(truncating: false, dividingBy: other, &flags)
  }

  /// Replaces this value with the remainder of itself divided by the given
  /// value.
  ///
  /// For two finite values `x` and `y`, where `y` is nonzero, the remainder `r`
  /// of dividing `x` by `y` satisfies `x == y * q + r`, where `q` is the
  /// integer nearest to `x / y`. If `x / y` is exactly halfway between two
  /// integers, `q` is chosen to be even. Note that `q` is *not* `x / y`
  /// computed in floating-point arithmetic, and that `q` may not be
  /// representable in any available integer type.
  ///
  /// If this value and `other` are both finite numbers and `other` is nonzero,
  /// the remainder has magnitude at most half of `other.magnitude`. The result
  /// is always exact.
  ///
  /// - Parameters:
  ///   - other: The value to use when dividing this value.
  @inline(always)
  public mutating func formRemainder(dividingBy other: Decimal128) {
    self = remainder(dividingBy: other)
  }

  /// Replaces this value with the remainder of itself divided by the given
  /// value, accumulating status flags.
  ///
  /// For two finite values `x` and `y`, where `y` is nonzero, the remainder `r`
  /// of dividing `x` by `y` satisfies `x == y * q + r`, where `q` is the
  /// integer nearest to `x / y`. If `x / y` is exactly halfway between two
  /// integers, `q` is chosen to be even. Note that `q` is *not* `x / y`
  /// computed in floating-point arithmetic, and that `q` may not be
  /// representable in any available integer type.
  ///
  /// If this value and `other` are both finite numbers and `other` is nonzero,
  /// the remainder has magnitude at most half of `other.magnitude`. The result
  /// is always exact.
  ///
  /// - Parameters:
  ///   - other: The value to use when dividing this value.
  ///   - flags: A value that accumulates decimal floating-point arithmetic
  ///     status flags.
  @inline(always)
  public mutating func formRemainder(
    dividingBy other: Decimal128,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) {
    self = remainder(dividingBy: other, &flags)
  }

  /// Returns the remainder of this value divided by the given value using
  /// truncating division.
  ///
  /// Performing truncating division with floating-point values results in a
  /// truncated integer quotient and a remainder. For values `x` and `y` and
  /// their truncated integer quotient `q`, the remainder `r` satisfies
  /// `x == y * q + r`.
  ///
  /// If this value and `other` are both finite numbers and `other` is nonzero,
  /// the truncating remainder has the same sign as this value and is strictly
  /// smaller in magnitude than `other`. The result is always exact.
  ///
  /// - Parameters:
  ///   - other: The value to use when dividing this value.
  /// - Returns: The remainder of this value divided by `other` using
  ///   truncating division.
  @inline(always)
  public func truncatingRemainder(dividingBy other: Decimal128) -> Decimal128 {
    var flags: DecimalFloatingPointStatusFlags = []
    defer { _signal(flags) }
    return _remainder(truncating: true, dividingBy: other, &flags)
  }

  /// Returns the remainder of this value divided by the given value using
  /// truncating division, accumulating status flags.
  ///
  /// Performing truncating division with floating-point values results in a
  /// truncated integer quotient and a remainder. For values `x` and `y` and
  /// their truncated integer quotient `q`, the remainder `r` satisfies
  /// `x == y * q + r`.
  ///
  /// If this value and `other` are both finite numbers and `other` is nonzero,
  /// the truncating remainder has the same sign as this value and is strictly
  /// smaller in magnitude than `other`. The result is always exact.
  ///
  /// - Parameters:
  ///   - other: The value to use when dividing this value.
  ///   - flags: A value that accumulates decimal floating-point arithmetic
  ///     status flags.
  /// - Returns: The remainder of this value divided by `other` using
  ///   truncating division.
  @inline(always)
  public func truncatingRemainder(
    dividingBy other: Decimal128,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) -> Decimal128 {
    _remainder(truncating: true, dividingBy: other, &flags)
  }

  /// Replaces this value with the remainder of itself divided by the given
  /// value using truncating division.
  ///
  /// Performing truncating division with floating-point values results in a
  /// truncated integer quotient and a remainder. For values `x` and `y` and
  /// their truncated integer quotient `q`, the remainder `r` satisfies
  /// `x == y * q + r`.
  ///
  /// If this value and `other` are both finite numbers and `other` is nonzero,
  /// the truncating remainder has the same sign as this value and is strictly
  /// smaller in magnitude than `other`. The result is always exact.
  ///
  /// - Parameters:
  ///   - other: The value to use when dividing this value.
  @inline(always)
  public mutating func formTruncatingRemainder(dividingBy other: Decimal128) {
    self = truncatingRemainder(dividingBy: other)
  }

  /// Replaces this value with the remainder of itself divided by the given
  /// value using truncating division, accumulating status flags.
  ///
  /// Performing truncating division with floating-point values results in a
  /// truncated integer quotient and a remainder. For values `x` and `y` and
  /// their truncated integer quotient `q`, the remainder `r` satisfies
  /// `x == y * q + r`.
  ///
  /// If this value and `other` are both finite numbers and `other` is nonzero,
  /// the truncating remainder has the same sign as this value and is strictly
  /// smaller in magnitude than `other`. The result is always exact.
  ///
  /// - Parameters:
  ///   - other: The value to use when dividing this value.
  ///   - flags: A value that accumulates decimal floating-point arithmetic
  ///     status flags.
  @inline(always)
  public mutating func formTruncatingRemainder(
    dividingBy other: Decimal128,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) {
    self = truncatingRemainder(dividingBy: other, &flags)
  }

  @usableFromInline
  internal func _squareRoot(
    rounding rule: _DecimalFloatingPointRoundingRule,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) -> Decimal128 {
    guard _isFiniteNonzero else {
      if isNaN {
        if isSignalingNaN { _raise(.invalid, in: &flags) }
        return _quiet._canonical
      }
      if isInfinite {
        if _isSignMinus {
          _raise(.invalid, in: &flags)
          return .nan
        }
        return .infinity
      }
      // Halve the quantum exponent (rounding down) without unbiasing.
      let e = (exponentBitPattern &+ 6176) &>> 1
      let abs = Self(bitPattern: UInt128(truncatingIfNeeded: e) &<< 113)
      return _isSignMinus ? -abs : abs
    }
    if _isSignMinus {
      _raise(.invalid, in: &flags)
      return .nan
    }
    var c = significandBitPattern
    let pe = (Int(exponentBitPattern) &+ 6176) &>> 1

    // FIXME: Include an alternative implementation using integer math
    // that leaves binary floating-point status flags unaffected which
    // could be conditionally compiled in.
    //
    // Assuming other `Double` operations are correctly rounded to nearest,
    // correct rounding is *not* required for `Double.squareRoot()`;
    // we can tolerate an error in that operation up to 5.5 ulp.
    let radicand = (exponentBitPattern & 1) == 0 ? c : c &* 10
    let estimate_ =
      (Double(UInt64(truncatingIfNeeded: radicand &>> 64)) * 0x1p64
        + Double(UInt64(truncatingIfNeeded: radicand))).squareRoot()
      // `Double(radicand).squareRoot()`

    var estimate = UInt128(UInt64(estimate_))
    let difference = Int128(radicand) &- Int128(estimate &* estimate)
    let differenceMagnitude_ =
      Double(UInt64(truncatingIfNeeded: difference.magnitude &>> 64)) * 0x1p64
        + Double(UInt64(truncatingIfNeeded: difference.magnitude))
      // `Double(difference.magnitude)`
    let correction_ =
      (differenceMagnitude_ / (estimate_ + estimate_)).rounded()
    let correction = UInt128(UInt64(correction_))
    if difference < 0 {
      estimate &-= correction
    } else {
      estimate &+= correction
    }
    if estimate &* estimate == radicand {
      // Exact root.
      return Self(
        bitPattern: UInt128(truncatingIfNeeded: pe) &<< 113 | estimate)
    }

    // Scale raw significand to 67 or 68 digits, preserving exponent parity.
    var n = 66 &- c._commonLogarithm
    n &+= (Int(exponentBitPattern) &- n) & 1
    let c_: (high: UInt128, low: UInt128)
    if n > 38 {
      c &*= unsafe ._exp10[unchecked: n &- 38]
      c_ = c._multipliedFullWidth(by1e: 38)
    } else {
      c_ = c._multipliedFullWidth(by1e: n)
    }
    var e = (Int(exponentBitPattern) &+ 6176 &- n) &>> 1

    let scale: UInt128 = unsafe ._exp10[unchecked: n &>> 1]
    let scale_ =
      Double(UInt64(truncatingIfNeeded: scale &>> 64)) * 0x1p64
        + Double(UInt64(truncatingIfNeeded: scale))
      // `Double(scale)`
    let scaled_ = estimate_ * scale_

    // Scale down the root estimate by 2**49 so its high part fits in `UInt64`.
    let scaled = UInt64(scaled_ * 0x1p-49)
    // Scale down the radicand by 2**98 (and take the floor).
    let c__ = (c_.high &<< 30) | (c_.low &>> 98)

    let delta1 = c__ &- UInt128(scaled) &* UInt128(scaled)
    let d1_ = Double(Int64(truncatingIfNeeded: delta1 &>> 32))
    // Correct `scaled` by:
    //
    //            delta1 / (2 * scaled)
    //     ≈ d1_ * 2**32 / (2 * scaled)
    //     = d1_ * 2**31 / scaled
    //     = d1_ * 2**80 / scaled_
    let x_ = 0x1p80 / scaled_
    let high = scaled &+ UInt64(bitPattern: Int64((d1_ * x_).rounded()))

    let delta2 = c__ &- UInt128(high) &* UInt128(high)
    let d2_ = Double(Int64(truncatingIfNeeded: delta2 &>> 1))
    // Compute:
    //
    //       delta2 * 2**49 / (2 * scaled)
    //     ≈    d2_ * 2**49 / scaled
    //     =    d2_ * 2**98 / scaled_
    let low = Int64((d2_ * (0x1p18 * x_)).rounded())

    estimate = (UInt128(high) &<< 49) &+ UInt128(truncatingIfNeeded: low)
    var remainder = c_.low &- estimate &* estimate
    if Int128(bitPattern: remainder) < 0 {
      remainder &+= (estimate &<< 1) &- 1
      estimate &-= 1
    }
    assert(remainder <= estimate &<< 1)

    if remainder == 0 {
      Self._select(
        biasedExponent: &e,
        nonzeroSignificand: &estimate,
        boundedPreferredBiasedExponent: pe)
    } else {
      _raise(.inexact, in: &flags)
      let nextAway: Bool =
        switch rule {
        case .toNearestOrEven, .toNearestOrAwayFromZero:
          remainder > estimate
        case .towardZero, .down:
          false
        case .awayFromZero, .up:
          true
        @unknown default:
          fatalError("Unknown rounding rule.")
        }
      estimate &+= nextAway ? 1 : 0
      if estimate == ._1e34 {
        estimate = ._1e33
        e &+= 1
      }
    }
    return Self(bitPattern: UInt128(truncatingIfNeeded: e) &<< 113 | estimate)
  }

  /// Returns the square root of the value.
  ///
  /// The result is rounded if needed to the nearest representable value
  /// (ties to even).
  ///
  /// This method implements the `squareRoot` operation defined by the
  /// IEEE 754 specification.
  ///
  /// - Returns: The square root of the value, rounded if needed.
  @inline(always)
  public func squareRoot() -> Decimal128 {
    var flags: DecimalFloatingPointStatusFlags = []
    defer { _signal(flags) }
    return _squareRoot(rounding: .toNearestOrEven, &flags)
  }

  /// Returns the square root of the value, accumulating status flags.
  ///
  /// The result is rounded if needed to the nearest representable value
  /// (ties to even).
  ///
  /// This method implements the `squareRoot` operation defined by the
  /// IEEE 754 specification.
  ///
  /// - Parameters:
  ///   - flags: A value that accumulates decimal floating-point arithmetic
  ///     status flags.
  /// - Returns: The square root of the value, rounded if needed.
  @inline(always)
  public func squareRoot(
    _ flags: inout DecimalFloatingPointStatusFlags
  ) -> Decimal128 {
    _squareRoot(rounding: .toNearestOrEven, &flags)
  }

  /// Returns the square root of the value.
  ///
  /// The result is rounded if needed using the given rounding rule.
  ///
  /// This method implements the `squareRoot` operation defined by the
  /// IEEE 754 specification.
  ///
  /// - Parameters:
  ///   - rule: The rounding rule to use for an inexact result.
  /// - Returns: The square root of the value, rounded if needed.
  @inline(always)
  public func squareRoot(
    rounding rule: FloatingPointRoundingRule
  ) -> Decimal128 {
    var flags: DecimalFloatingPointStatusFlags = []
    defer { _signal(flags) }
    return _squareRoot(rounding: .init(rule), &flags)
  }

  /// Returns the square root of the value, accumulating status flags.
  ///
  /// The result is rounded if needed using the given rounding rule.
  ///
  /// This method implements the `squareRoot` operation defined by the
  /// IEEE 754 specification.
  ///
  /// - Parameters:
  ///   - rule: The rounding rule to use for an inexact result.
  ///   - flags: A value that accumulates decimal floating-point arithmetic
  ///     status flags.
  /// - Returns: The square root of the value, rounded if needed.
  @inline(always)
  public func squareRoot(
    rounding rule: FloatingPointRoundingRule,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) -> Decimal128 {
    _squareRoot(rounding: .init(rule), &flags)
  }

  /// Replaces this value with its square root.
  ///
  /// The result is rounded if needed to the nearest representable value
  /// (ties to even).
  @inline(always)
  public mutating func formSquareRoot() {
    self = squareRoot()
  }

  /// Replaces this value with its square root, accumulating status flags.
  ///
  /// The result is rounded if needed to the nearest representable value
  /// (ties to even).
  ///
  /// - Parameters:
  ///   - flags: A value that accumulates decimal floating-point arithmetic
  ///     status flags.
  @inline(always)
  public mutating func formSquareRoot(
    _ flags: inout DecimalFloatingPointStatusFlags
  ) {
    self = squareRoot(&flags)
  }

  /// Replaces this value with its square root.
  ///
  /// The result is rounded if needed using the given rounding rule.
  ///
  /// - Parameters:
  ///   - rule: The rounding rule to use for an inexact result.
  @inline(always)
  public mutating func formSquareRoot(
    rounding rule: FloatingPointRoundingRule
  ) {
    self = squareRoot(rounding: rule)
  }

  /// Replaces this value with its square root, accumulating status flags.
  ///
  /// The result is rounded if needed using the given rounding rule.
  ///
  /// - Parameters:
  ///   - rule: The rounding rule to use for an inexact result.
  ///   - flags: A value that accumulates decimal floating-point arithmetic
  ///     status flags.
  @inline(always)
  public mutating func formSquareRoot(
    rounding rule: FloatingPointRoundingRule,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) {
    self = squareRoot(rounding: rule, &flags)
  }

  @inlinable
  @inline(always)
  internal func _rounded(
    _ rule: _DecimalFloatingPointRoundingRule
  ) -> Decimal128 {
    var flags: DecimalFloatingPointStatusFlags = []
    defer {
      flags.subtract(.inexact)
      _signal(flags)
    }
    return _rounded(rule, &flags)
  }

  /// Returns this value rounded to the nearest integral value
  /// (ties away from zero).
  ///
  /// This method implements the `roundToIntegralTiesToAway` operation defined
  /// by the IEEE 754 specification.
  ///
  /// - Returns: The nearest integral value, rounding ties away from zero.
  @inline(always)
  public func rounded() -> Decimal128 {
    _rounded(.toNearestOrAwayFromZero)
  }

  /// Returns this value rounded to an integral value using the specified
  /// rounding rule.
  ///
  /// For more information about the available rounding rules, see the
  /// `FloatingPointRoundingRule` enumeration. To round a value using the
  /// default "schoolbook rounding" of `.toNearestOrAwayFromZero`, you can use
  /// the shorter `rounded()` method instead.
  ///
  /// This method implements the `roundToIntegralTiesToAway`,
  /// `roundToIntegralTiesToEven`, `roundToIntegralTowardNegative`,
  /// `roundToIntegralTowardPositive`, and `roundToIntegralTowardZero`
  /// operations defined by the IEEE 754 specification.
  ///
  /// - Parameters:
  ///   - rule: The rounding rule to use.
  /// - Returns: The integral value found by rounding using `rule`.
  @inline(always)
  public func rounded(_ rule: FloatingPointRoundingRule) -> Decimal128 {
    _rounded(.init(rule))
  }

  /// Rounds this value to the nearest integral value (ties away from zero).
  @inline(always)
  public mutating func round() {
    self = rounded()
  }

  /// Rounds this value to an integral value using the specified rounding rule.
  ///
  /// For more information about the available rounding rules, see the
  /// `FloatingPointRoundingRule` enumeration. To round a value using the
  /// default "schoolbook rounding" of `.toNearestOrAwayFromZero`, you can use
  /// the shorter `round()` method instead.
  ///
  /// - Parameters:
  ///   - rule: The rounding rule to use.
  @inline(always)
  public mutating func round(_ rule: FloatingPointRoundingRule) {
    self = rounded(rule)
  }

  @usableFromInline
  internal func _rounded(
    _ rule: _DecimalFloatingPointRoundingRule,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) -> Decimal128 {
    guard _isFiniteNonzero else {
      if isSignalingNaN {
        _raise(.invalid, in: &flags)
        return _quiet._canonical
      }
      if exponentBitPattern >= 6176 {
        return _canonical
      }
      return _isSignMinus ? -Self() : Self()
    }

    let e = exponentBitPattern
    if e >= 6176 {
      return self
    }

    let isSignMinus = _isSignMinus
    let n = Int(e) &- 6176
    let c = significandBitPattern
    var q: UInt128
    let r: UInt128
    let half: UInt128

    assert(n < 0)
    if n >= -19 && c < (1 &<< 64) {
      let c_ = UInt64(truncatingIfNeeded: c)
      let x = unsafe UInt64(truncatingIfNeeded: UInt128._exp10[unchecked: -n])
      let (q_, r_) = c_.quotientAndRemainder(dividingBy: x)
      q = UInt128(q_)
      r = UInt128(r_)
      half = r == 0 ? 1 : UInt128(x &>> 1)
    } else if n >= -34 {
      (q, r) = c._quotientAndRemainder(dividingBy1e: -n)
      half = r == 0 ? 1 : unsafe ._exp10[unchecked: -n] &>> 1
    } else {
      q = 0
      r = c
      half = ._1e34
    }
    if r != 0 {
      switch rule {
      case .toNearestOrEven:
        q &+= r &+ (q & 1) > half ? 1 : 0
      case .toNearestOrAwayFromZero:
        q &+= r >= half ? 1 : 0
      case .towardZero:
        break
      case .awayFromZero:
        q &+= 1
      case .down:
        q &+= isSignMinus ? 1 : 0
      case .up:
        q &+= isSignMinus ? 0 : 1
      @unknown default:
        fatalError("Unknown rounding rule.")
      }
      _raise(.inexact, in: &flags)
    }
    let abs = Self(bitPattern: 6176 &<< 113 | q)
    return isSignMinus ? -abs : abs
  }

  /// Returns this value rounded to the nearest integral value
  /// (ties away from zero), accumulating status flags.
  ///
  /// This method implements the `roundToIntegralExact` operation defined by
  /// the IEEE 754 specification. If the result of rounding is inexact, then
  /// `.inexact` will be inserted into `flags`.
  ///
  /// - Parameters:
  ///   - flags: A value that accumulates decimal floating-point arithmetic
  ///     status flags.
  /// - Returns: The nearest integral value, rounding ties away from zero.
  @inline(always)
  public func rounded(
    _ flags: inout DecimalFloatingPointStatusFlags
  ) -> Decimal128 {
    _rounded(.toNearestOrAwayFromZero, &flags)
  }

  /// Returns this value rounded to an integral value using the specified
  /// rounding rule, accumulating status flags.
  ///
  /// For more information about the available rounding rules, see the
  /// `FloatingPointRoundingRule` enumeration.
  ///
  /// This method implements the `roundToIntegralExact` operation defined by
  /// the IEEE 754 specification. If the result of rounding is inexact, then
  /// `.inexact` will be inserted into `flags`.
  ///
  /// - Parameters:
  ///   - rule: The rounding rule to use.
  ///   - flags: A value that accumulates decimal floating-point arithmetic
  ///     status flags.
  /// - Returns: The integral value found by rounding using `rule`.
  @inline(always)
  public func rounded(
    _ rule: FloatingPointRoundingRule,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) -> Decimal128 {
    _rounded(.init(rule), &flags)
  }

  /// Rounds this value to the nearest integral value (ties away from zero),
  /// accumulating status flags.
  ///
  /// If the result of rounding is inexact, then `.inexact` will be inserted
  /// into `flags`.
  ///
  /// - Parameters:
  ///   - flags: A value that accumulates decimal floating-point arithmetic
  ///     status flags.
  @inline(always)
  public mutating func round(_ flags: inout DecimalFloatingPointStatusFlags) {
    self = rounded(&flags)
  }

  /// Rounds this value to an integral value using the specified rounding rule,
  /// accumulating status flags.
  ///
  /// If the result of rounding is inexact, then `.inexact` will be inserted
  /// into `flags`.
  ///
  /// - Parameters:
  ///   - rule: The rounding rule to use.
  ///   - flags: A value that accumulates decimal floating-point arithmetic
  ///     status flags.
  @inline(always)
  public mutating func round(
    _ rule: FloatingPointRoundingRule,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) {
    self = rounded(rule, &flags)
  }
}
