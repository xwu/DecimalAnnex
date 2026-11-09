@available(anyAppleOS 26.0, *)
extension Decimal128: Strideable {
  @inlinable
  public func distance(to other: Decimal128) -> Decimal128 { other - self }

  @inlinable
  public func advanced(by n: Decimal128) -> Decimal128 { self + n }
}

@available(anyAppleOS 26.0, *)
extension Decimal128: FloatingPoint {
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
      if isNaN { return .nan }
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

  @inlinable
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
        _signal(.invalid, into: &flags)
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
      let digit: UInt8
      let sticky: Bool
      if e < -34 {
        c = 0
        digit = 0
        sticky = true
      } else {
        let n = -e
        let r: UInt128
        (c, r) = c._quotientAndRemainder(dividingBy1e: n)
        let half: UInt128 = unsafe ._exp10[unchecked: n] &>> 1
        digit = r >= half ? 5 : 0
        sticky = r != 0 && r != half
      }
      if Self._roundsAway(
        isSignMinus: isSignMinus,
        significand: c,
        digit: digit,
        sticky: sticky,
        rule
      ) {
        c &+= 1
      }
      // Every such inexact result is tiny before rounding.
      if digit != 0 || sticky { _signal(.underflowInexact, into: &flags) }
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

  @inline(always)
  public init(sign: FloatingPointSign, exponent: Int, significand: Decimal128) {
    var flags: DecimalFloatingPointStatusFlags = []
    self.init(
      _sign: sign,
      exponent: exponent,
      significand: significand,
      rounding: .toNearestOrEven,
      &flags)
  }

  /// Creates a new value from the given sign, exponent, and significand,
  /// rounding to the nearest representable value (ties to even) if needed
  /// and accumulating status flags.
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
    self.init(
      _sign: sign,
      exponent: exponent,
      significand: significand,
      rounding: .toNearestOrEven,
      &flags)
  }

  /// Creates a new value from the given sign, exponent, and significand,
  /// rounding to a representable value using the given rounding rule if needed.
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
    var flags: DecimalFloatingPointStatusFlags = []
    self.init(
      _sign: sign,
      exponent: exponent,
      significand: significand,
      rounding: .init(rule),
      &flags)
  }

  /// Creates a new value from the given sign, exponent, and significand,
  /// rounding to a representable value using the given rounding rule if needed
  /// and accumulating status flags.
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

  @inlinable
  internal func _addingProduct(
    _ lhs: Decimal128, _ rhs: Decimal128,
    rounding rule: _DecimalFloatingPointRoundingRule,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) -> Decimal128 {
    var z = self, x = lhs, y = rhs

    guard z.isFinite && x._isFiniteNonzero && y._isFiniteNonzero else {
      if z.isSignalingNaN {
        _signal(.invalid, into: &flags)
        z = z._quiet
      }
      if x.isSignalingNaN {
        _signal(.invalid, into: &flags)
        x = x._quiet
      }
      if y.isSignalingNaN {
        _signal(.invalid, into: &flags)
        y = y._quiet
      }
      let invalid = (x.isZero && y.isInfinite) || (y.isZero && x.isInfinite)
      if invalid {
        _signal(.invalid, into: &flags)
      }
      if z.isNaN { return z._canonical }
      if x.isNaN { return x._canonical }
      if y.isNaN { return y._canonical }
      if invalid { return .nan }

      if x.isInfinite || y.isInfinite {
        let isSignMinus = x._isSignMinus != y._isSignMinus
        if z.isInfinite && z._isSignMinus != isSignMinus {
          _signal(.invalid, into: &flags)
          return .nan
        }
        return isSignMinus ? -.infinity : .infinity
      }
      if z.isInfinite {
        return z._canonical
      }

      // `b.isZero || c.isZero`.
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
    let cz = z.isZero ? 0 : z.significandBitPattern
    let exy = Int(x.exponentBitPattern) &- 6176 &+ Int(y.exponentBitPattern)
    let cxy: (high: UInt128, low: UInt128)
    let sxy = x._isSignMinus != y._isSignMinus
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
                  _signal(.overflowInexact, into: &flags)
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
                let cx = x.significandBitPattern
                let cy = y.significandBitPattern
                nextToward = cx > _5e33 && cy > _5e33 &&
                  cx.multipliedFullWidth(by: cy) >
                    _5e33.multipliedFullWidth(by: ._1e34)
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
            _signal(.underflowInexact, into: &flags)
          } else {
            _signal(.inexact, into: &flags)
          }
          return z._isSignMinus ? -abs : abs
        }
      }
    }

    let cx = x.significandBitPattern
    let cy = y.significandBitPattern
    if cx <= 0xFFFF_FFFF_FFFF_FFFF && cy <= 0xFFFF_FFFF_FFFF_FFFF {
      let (hi, lo) =
        UInt64(truncatingIfNeeded: cx).multipliedFullWidth(
          by: UInt64(truncatingIfNeeded: cy))
      cxy = (0, UInt128(hi) &<< 64 | UInt128(lo))
    } else {
      cxy = cx.multipliedFullWidth(by: cy)
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
    if ez == exy {
      e = pe
      if sameSign {
        let carry: Bool
        (c.low, carry) = cxy.low.addingReportingOverflow(cz)
        c.high = cxy.high &+ (carry ? 1 : 0)
        isSignMinus = sxy
      } else if cxy.high != 0 || cxy.low >= cz {
        let borrow: Bool
        (c.low, borrow) = cxy.low.subtractingReportingOverflow(cz)
        c.high = cxy.high &- (borrow ? 1 : 0)
        isSignMinus = c == (0, 0)
          ? rule == .down // Exact zero. See IEEE 754 §6.3.
          : sxy
      } else {
        c = (0, cz &- cxy.low)
        isSignMinus = z._isSignMinus
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

    let logcz = cz._commonLogarithm
    var n: Int
    var divisor: UInt128 = 0
    if cxy.high == 0 {
      n = cxy.low._commonLogarithm &- 33
      if n > 0 {
        divisor = unsafe ._exp10[unchecked: n]
      }
    } else {
      // See explanatory comment in `UInt128._commonLogarithm`.
      // Note that here we underestimate.
      n = ((77 &* (255 &- cxy.high.leadingZeroBitCount)) &>> 8) &- 33
      divisor = unsafe UInt128._exp10[unchecked: n]
      if cxy >= divisor.multipliedFullWidth(by: ._1e34) {
        n &+= 1
        divisor &*= 10
      }
    }
    if n > 0 && ez &+ logcz < exy {
      // Inexact.
      var (quo, rem) = cxy.high == 0
        ? cxy.low._quotientAndRemainder(dividingBy1e: n)
        : UInt128._quotientAndRemainder(fullWidth: cxy, dividingBy1e: n)
      e = exy &+ n
      if rem != 0 || sameSign {
        let nextAway: Bool =
          switch rule {
          case .toNearestOrEven, .toNearestOrAwayFromZero:
            sameSign ? rem >= (divisor &>> 1) : rem > (divisor &>> 1)
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
          if quo == ._1e34 &- 1 {
            quo = ._1e33
            e &+= 1
          } else {
            quo &+= 1
          }
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
      _signal(.inexact, into: &flags)
      return sxy ? -abs : abs
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
          let nextAway: Bool =
            switch rule {
            case .toNearestOrEven:
              r > half || (r == half && (sticky || (q & 1) != 0))
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
          if nextAway {
            if q == ._1e34 &- 1 {
              if e == 12287 {
                _signal(.overflowInexact, into: &flags)
                return isSignMinus ? -.infinity : .infinity
              }
              q = ._1e33
              e &+= 1
            } else {
              q &+= 1
            }
          }
          _signal(.inexact, into: &flags)
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
          cz_ = p.multipliedFullWidth(by: ._1e34)
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
          cz_ = p.multipliedFullWidth(by: ._1e34)
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

  /// Returns the result of adding the product of the two given values to this
  /// value, computed without intermediate rounding, finally rounding to the
  /// nearest representable value (ties to even) if needed.
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
    return _addingProduct(lhs, rhs, rounding: .toNearestOrEven, &flags)
  }

  /// Returns the result of adding the product of the two given values to this
  /// value, computed without intermediate rounding, finally rounding to the
  /// nearest representable value (ties to even) if needed and accumulating
  /// status flags.
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

  /// Returns the result of adding the product of the two given values to this
  /// value, computed without intermediate rounding, finally rounding to a
  /// representable value using the given rounding rule if needed.
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
    return _addingProduct(lhs, rhs, rounding: .init(rule), &flags)
  }

  /// Returns the result of adding the product of the two given values to this
  /// value, computed without intermediate rounding, finally rounding to a
  /// representable value using the given rounding rule if needed and
  /// accumulating status flags.
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

  /// Adds the product of the two given values to this value in place, computed
  /// without intermediate rounding, finally rounding to the nearest
  /// representable value (ties to even) if needed.
  ///
  /// - Parameters:
  ///   - lhs: One of the values to multiply before adding to this value.
  ///   - rhs: The other value to multiply.
  @inline(always)
  public mutating func addProduct(_ lhs: Decimal128, _ rhs: Decimal128) {
    self = addingProduct(lhs, rhs)
  }

  /// Adds the product of the two given values to this value in place, computed
  /// without intermediate rounding, finally rounding to the nearest
  /// representable value (ties to even) if needed and accumulating status
  /// flags.
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

  /// Adds the product of the two given values to this value in place, computed
  /// without intermediate rounding, finally rounding to a representable value
  /// using the given rounding rule if needed.
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

  /// Adds the product of the two given values to this value in place, computed
  /// without intermediate rounding, finally rounding to a representable value
  /// using the given rounding rule if needed and accumulating status flags.
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

  @inlinable
  internal func _divided(
    by rhs: Decimal128,
    rounding rule: _DecimalFloatingPointRoundingRule,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) -> Decimal128 {
    var lhs = self, rhs = rhs
    let isSignMinus = lhs._isSignMinus != rhs._isSignMinus

    guard lhs._isFiniteNonzero && rhs._isFiniteNonzero else {
      if lhs.isSignalingNaN {
        _signal(.invalid, into: &flags)
        lhs = lhs._quiet
      }
      if rhs.isSignalingNaN {
        _signal(.invalid, into: &flags)
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
          _signal(.invalid, into: &flags)
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
          _signal(.invalid, into: &flags)
          return .nan
        }
        _signal(.divisionByZero, into: &flags)
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

    let n: Int
    var quo: UInt128
    let rem: UInt128
    // Fast path for division by powers of ten.
    let ctz = UInt64(truncatingIfNeeded: rc).trailingZeroBitCount
    if unsafe ctz <= 33 && rc == ._exp10[unchecked: ctz] {
      n = ctz
      (quo, rem) = (lc, 0)
    } else if lc >= rc {
      let q, r: UInt128
      if lc &- rc < rc {
        (q, r) = (1, lc &- rc)
      } else {
        // Compute the high half of each significand.
        let lh = UInt64(truncatingIfNeeded: lc &>> 64)
        let rh = UInt64(truncatingIfNeeded: rc &>> 64)
        // If the mathematical product `rh * (rh + 2)` exceeds `lh`, then
        // `lh / rh` is either exactly the true flooring quotient or it
        // overestimates by one.
        //
        // Since `lc < 10**34`, `lh <= 542_101_086_242_752`.
        // Thus, `rh >= 23_283_064` satisfies the above inequality for all
        // possible `lh`.
        if rh >= 23_283_064 || rh &* (rh &+ 2) > lh {
          var overestimate = UInt128(lh / rh)
          // `overestimate` is either exact or off by 1.
          var product = overestimate &* rc
          if product > lc {
            product &-= rc
            overestimate &-= 1
          }
          (q, r) = (overestimate, lc &- product)
        } else {
          // Retain up to 64 significant bits of `lc`,
          // shifting `rc` by the same amount.
          let shift = max(0, 64 &- lc.leadingZeroBitCount)
          let lh = UInt64(truncatingIfNeeded: lc &>> shift)
          let rh = UInt64(truncatingIfNeeded: rc &>> shift)
          if shift == 0 {
            let q_ = lh / rh
            (q, r) = (UInt128(q_), UInt128(lh &- q_ &* rh))
          } else if rh >= 0x1_0000_0000 // Avoid overflow in the following product.
              || rh &* (rh &+ 2) > lh {
            var overestimate = UInt128(lh / rh)
            var product = overestimate &* rc
            if product > lc {
              product &-= rc
              overestimate &-= 1
            }
            (q, r) = (overestimate, lc &- product)
          } else if rc <= 0xFFFF_FFFF_FFFF_FFFF /* UInt64.max */ {
            (q, r) = lc.quotientAndRemainder(dividingBy: rc)
          } else {
            // Avoid less-than-ideal intrinsic performance,
            // using `Double` to estimate.

            // FIXME: Include an alternative implementation using integer math
            // that leaves binary floating-point status flags unaffected which
            // could be conditionally compiled in.
            let x =
              Double(UInt64(truncatingIfNeeded: lc &>> 64)) * 0x1p64
                + Double(UInt64(truncatingIfNeeded: lc))
            let y =
              Double(UInt64(truncatingIfNeeded: rc &>> 64)) * 0x1p64
                + Double(UInt64(truncatingIfNeeded: rc))
            // Since the quotient is less than `2**49`, the integer part of the
            // estimate needs at most one correction in either direction.
            var q_ = UInt128(UInt64(x / y))
            var p = q_ &* rc
            if p > lc {
              q_ &-= 1
              p &-= rc
            }
            var r_ = lc &- p
            if r_ >= rc {
              q_ &+= 1
              r_ &-= rc
            }
            (q, r) = (q_, r_)
          }
        }
      }
      if r == 0 {
        if e >= 0 && e <= 12287 {
          let abs = Self(bitPattern: UInt128(truncatingIfNeeded: e) &<< 113 | q)
          return isSignMinus ? -abs : abs
        }
        return ._pack(
          isSignMinus: isSignMinus,
          biasedExponent: e,
          significand: (0, q),
          rule,
          &flags)
      }
      n = q < 10 ? 33 : 33 &- q._commonLogarithm
      (quo, rem) = UInt128._quotientAndRemainder(
        fullWidth: r._multipliedFullWidth(by1e: n), dividingBy: rc)
      quo &+= unsafe q &* ._exp10[unchecked: n]
    } else if lc >= ._1e33 {
      n = 34
      (quo, rem) = UInt128._quotientAndRemainder(
        fullWidth: lc._multipliedFullWidth(by1e: n), dividingBy: rc)
    } else {
      let delta = rc._commonLogarithm &- lc._commonLogarithm
      n = unsafe 33 &+ delta &+ (lc &* ._exp10[unchecked: delta] < rc ? 1 : 0)
      let dividend = n <= 38
        ? lc._multipliedFullWidth(by1e: n)
        : (lc * ._exp10[n &- 34]).multipliedFullWidth(by: ._1e34)
      (quo, rem) = UInt128._quotientAndRemainder(
        fullWidth: dividend, dividingBy: rc)
    }
    let pe = e // Hang on to the preferred exponent for later.
    e &-= n

    if rem == 0 {
      if e >= 0 && e <= 12287 {
        let pe = min(12287, pe)
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
      if Self._roundsAway(
        isSignMinus: isSignMinus,
        significand: quo,
        digit: rr >= rc ? 5 : 0,
        // A proxy guard digit (5 if midpoint or above; else 0).
        sticky: rr != rc,
        rule
      ) {
        if quo == ._1e34 &- 1 {
          if e == 12287 {
            _signal(.overflowInexact, into: &flags)
            return isSignMinus ? -.infinity : .infinity
          }
          quo = ._1e33
          e &+= 1
        } else {
          quo &+= 1
        }
      }
      _signal(.inexact, into: &flags)
      let abs = Self(bitPattern: UInt128(truncatingIfNeeded: e) &<< 113 | quo)
      return isSignMinus ? -abs : abs
    }
    // Inexact underflow.
    let digit: UInt8 // A proxy guard digit (5 if midpoint or above; else 0).
    if e < -34 {
      quo = 0
      digit = 0
    } else {
      let r: UInt128
      (quo, r) = quo._quotientAndRemainder(dividingBy1e: -e)
      digit = unsafe r >= (._exp10[unchecked: -e] &>> 1) ? 5 : 0
    }
    if Self._roundsAway(
      isSignMinus: isSignMinus,
      significand: quo,
      digit: digit,
      sticky: true,
      rule
    ) {
      quo &+= 1
    }
    _signal(.underflowInexact, into: &flags)
    let abs = Self(bitPattern: quo)
    return isSignMinus ? -abs : abs
  }

  /// Returns the quotient of dividing the first value by the second,
  /// rounding to the nearest representable value (ties to even) if needed.
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
    return lhs._divided(by: rhs, rounding: .toNearestOrEven, &flags)
  }

  /// Returns the result of dividing this value by the given value,
  /// rounding to the nearest representable value (ties to even) if needed
  /// and accumulating status flags.
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

  /// Returns the result of dividing this value by the given value,
  /// rounding to a representable value using the given rounding rule if needed.
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
    return _divided(by: rhs, rounding: .init(rule), &flags)
  }

  /// Returns the result of dividing this value by the given value,
  /// rounding to a representable value using the given rounding rule if needed
  /// and accumulating status flags.
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

  /// Divides the first value by the second and stores the quotient in the
  /// left-hand-side variable, rounding to the nearest representable value
  /// (ties to even) if needed.
  ///
  /// - Parameters:
  ///   - lhs: The value to divide.
  ///   - rhs: The value by which to divide `lhs`.
  @inline(always)
  public static func /= (lhs: inout Decimal128, rhs: Decimal128) {
    lhs = lhs / rhs
  }

  /// Divides this value by the given value in place,
  /// rounding to the nearest representable value (ties to even) if needed
  /// and accumulating status flags.
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

  /// Divides this value by the given value in place,
  /// rounding to a representable value using the given rounding rule if needed.
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

  /// Divides this value by the given value in place,
  /// rounding to a representable value using the given rounding rule if needed
  /// and accumulating status flags.
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

  @inlinable
  internal func _remainder(
    truncating: Bool,
    dividingBy divisor: Decimal128,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) -> Decimal128 {
    var x = self, y = divisor
    guard x._isFiniteNonzero && y._isFiniteNonzero else {
      if x.isSignalingNaN {
        _signal(.invalid, into: &flags)
        x = x._quiet
      }
      if y.isSignalingNaN {
        _signal(.invalid, into: &flags)
        y = y._quiet
      }
      if x.isNaN {
        return x._canonical
      }
      if y.isNaN {
        return y._canonical
      }

      if x.isInfinite || y.isZero {
        _signal(.invalid, into: &flags)
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
        if residue > complement || (residue == complement && (quo & 1) != 0) {
          residue = complement
          isSignMinus.toggle()
        }
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
          if residue > complement || (residue == complement && (quo & 1) != 0) {
            residue = complement
            isSignMinus.toggle()
          }
        }
      }
    } else {
      e = y.exponentBitPattern
      var cx_ = cx
      if shift > 0 {
        // See explanatory comment in `UInt128._commonLogarithm`.
        // Note that here we underestimate.
        let n = min(shift, (77 &* cx.leadingZeroBitCount) &>> 8)
        cx_ = unsafe cx &* ._exp10[unchecked: n]
        shift &-= n
        if shift > 0 && cx_ <= .max / 10 {
          cx_ &*= 10
          shift &-= 1
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
          if residue > complement || (residue == complement && (quo & 1) != 0) {
            residue = complement
            isSignMinus.toggle()
          }
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
              fullWidth: residue.multipliedFullWidth(by: power),
              dividingBy: cy).remainder
          }
          n &>>= 1
          if n != 0 && residue != 0 {
            power = ._quotientAndRemainder(
              fullWidth: power.multipliedFullWidth(by: power),
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

  @inline(always)
  public func remainder(dividingBy other: Decimal128) -> Decimal128 {
    var flags: DecimalFloatingPointStatusFlags = []
    return _remainder(truncating: false, dividingBy: other, &flags)
  }

  @inline(always)
  public func remainder(
    dividingBy other: Decimal128,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) -> Decimal128 {
    _remainder(truncating: false, dividingBy: other, &flags)
  }

  @inline(always)
  public mutating func formRemainder(dividingBy other: Decimal128) {
    self = remainder(dividingBy: other)
  }

  @inline(always)
  public mutating func formRemainder(
    dividingBy other: Decimal128,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) {
    self = remainder(dividingBy: other, &flags)
  }

  @inline(always)
  public func truncatingRemainder(dividingBy other: Decimal128) -> Decimal128 {
    var flags: DecimalFloatingPointStatusFlags = []
    return _remainder(truncating: true, dividingBy: other, &flags)
  }

  @inline(always)
  public func truncatingRemainder(
    dividingBy other: Decimal128,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) -> Decimal128 {
    _remainder(truncating: true, dividingBy: other, &flags)
  }

  @inline(always)
  public mutating func formTruncatingRemainder(dividingBy other: Decimal128) {
    self = truncatingRemainder(dividingBy: other)
  }

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
    fatalError("Not implemented")
  }

  @inline(always)
  public func squareRoot() -> Decimal128 {
    var flags: DecimalFloatingPointStatusFlags = []
    return _squareRoot(rounding: .toNearestOrEven, &flags)
  }

  @inline(always)
  public func squareRoot(
    _ flags: inout DecimalFloatingPointStatusFlags
  ) -> Decimal128 {
    _squareRoot(rounding: .toNearestOrEven, &flags)
  }

  @inline(always)
  public func squareRoot(
    rounding rule: FloatingPointRoundingRule
  ) -> Decimal128 {
    var flags: DecimalFloatingPointStatusFlags = []
    return _squareRoot(rounding: .init(rule), &flags)
  }

  @inline(always)
  public func squareRoot(
    rounding rule: FloatingPointRoundingRule,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) -> Decimal128 {
    _squareRoot(rounding: .init(rule), &flags)
  }

  @inline(always)
  public mutating func formSquareRoot() {
    self = squareRoot()
  }

  @inline(always)
  public mutating func formSquareRoot(
    _ flags: inout DecimalFloatingPointStatusFlags
  ) {
    self = squareRoot(&flags)
  }

  @inline(always)
  public mutating func formSquareRoot(
    rounding rule: FloatingPointRoundingRule
  ) {
    self = squareRoot(rounding: rule)
  }

  @inline(always)
  public mutating func formSquareRoot(
    rounding rule: FloatingPointRoundingRule,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) {
    self = squareRoot(rounding: rule, &flags)
  }

  @inlinable
  internal func _rounded(
    _ rule: _DecimalFloatingPointRoundingRule
  ) -> Decimal128 {
    if isSignalingNaN {
      _signal(.invalid)
      return _quiet._canonical
    }
    if exponentBitPattern >= 6176 { return _canonical }
    if isZero { return _isSignMinus ? -Self() : Self() }

    let n = Int(exponentBitPattern) &- 6176
    var c = significandBitPattern
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
    if Self._roundsAway(
      isSignMinus: _isSignMinus,
      significand: c,
      digit: UInt8(digit),
      sticky: sticky,
      rule
    ) {
      c &+= 1
    }
    return Self(sign: sign, exponentBitPattern: 6176, significandBitPattern: c)
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

  @inlinable
  internal func _rounded(
    _ rule: _DecimalFloatingPointRoundingRule,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) -> Decimal128 {
    if isSignalingNaN {
      _signal(.invalid, into: &flags)
      return _quiet._canonical
    }
    if exponentBitPattern >= 6176 { return _canonical }
    if isZero { return _isSignMinus ? -Self() : Self() }

    let n = Int(exponentBitPattern) &- 6176
    var c = significandBitPattern
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
    if digit != 0 || sticky { _signal(.inexact, into: &flags) }
    return Self(sign: sign, exponentBitPattern: 6176, significandBitPattern: c)
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
