@available(anyAppleOS 26.0, *)
extension Decimal128: SignedNumeric {
  @inline(always)
  public mutating func negate() {
    bitPattern ^= 1 &<< 127
  }

  @inline(always)
  public static prefix func - (operand: Decimal128) -> Decimal128 {
    var result = operand
    result.negate()
    return result
  }
}

@usableFromInline
@objc
internal enum _DecimalFloatingPointRoundingRule: UInt8 {
  case toNearestOrEven = 0
  case toNearestOrAwayFromZero = 1
  case towardZero = 2
  case awayFromZero = 3
  case down = 4
  case up = 5

  @inlinable
  @inline(always)
  internal init(_ rule: FloatingPointRoundingRule) {
    self =
      switch rule {
      case .toNearestOrEven: .toNearestOrEven
      case .toNearestOrAwayFromZero: .toNearestOrAwayFromZero
      case .towardZero: .towardZero
      case .awayFromZero: .awayFromZero
      case .down: .down
      case .up: .up
      @unknown default: fatalError("Unknown rounding rule.")
      }
  }
}

@available(anyAppleOS 26.0, *)
extension Decimal128 {
  @inlinable
  @inline(always)
  internal static func _roundsAway(
    isSignMinus: Bool,
    significand: UInt128,
    digit: UInt8,
    sticky: Bool,
    _ rule: _DecimalFloatingPointRoundingRule
  ) -> Bool {
    assert(digit < 10)
    guard digit != 0 || sticky else { return false }
    switch rule {
    case .toNearestOrEven:
      return digit > 5 || (digit == 5 && (sticky || (significand & 1) != 0))
    case .toNearestOrAwayFromZero:
      return digit >= 5
    case .towardZero:
      return false
    case .awayFromZero:
      return true
    case .down:
      return isSignMinus
    case .up:
      return !isSignMinus
    @unknown default:
      fatalError("Unknown rounding rule.")
    }
  }

  /// Select the cohort member with exponent closest to the preferred exponent
  /// without changing the represented value.
  @inlinable
  @inline(always)
  internal static func _select(
    biasedExponent e: inout Int,
    nonzeroSignificand quo: inout UInt128,
    boundedPreferredBiasedExponent pe: Int
  ) {
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
      let n = min(e &- pe, max(0, 33 &- quo._commonLogarithm))
      quo &*= unsafe ._exp10[unchecked: n]
      e &-= n
    }
  }

  @inlinable
  @inline(always)
  internal static func _overflow(
    isSignMinus: Bool,
    _ rule: _DecimalFloatingPointRoundingRule,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) -> Decimal128 {
    let infinite: Bool =
      switch rule {
      case .toNearestOrEven: true
      case .toNearestOrAwayFromZero: true
      case .towardZero: false
      case .awayFromZero: true
      case .down: isSignMinus
      case .up: !isSignMinus
      @unknown default: fatalError("Unknown rounding rule.")
      }
    let magnitude: Self = infinite ? .infinity : .greatestFiniteMagnitude
    _raise(.overflowInexact, in: &flags)
    return isSignMinus ? -magnitude : magnitude
  }

  /// Returns the given intermediate result packed into a `Decimal128`,
  /// handling exponent limits and rounding according to the given rule.
  ///
  /// For exact results, the cohort member is selected with biased exponent
  /// closest to `preferredBiasedExponent ?? biasedExponent` (after clamping to
  /// the encodable exponent range).
  ///
  /// - Precondition: `significand` is less than `1e69`; if `sticky` is `true`,
  ///   `significand` is at least `1e34`.
  @usableFromInline
  internal static func _pack(
      isSignMinus: Bool,
      biasedExponent: Int,
      significand: (high: UInt128, low: UInt128),
      sticky: Bool = false,
      preferredBiasedExponent: Int? = nil,
      _ rule: _DecimalFloatingPointRoundingRule,
      _ flags: inout DecimalFloatingPointStatusFlags
  ) -> Decimal128 {
    var e = biasedExponent
    let pe = min(12287, max(0, preferredBiasedExponent ?? e))
    let (hi, lo) = significand
    assert(!sticky || (hi, lo) >= (0, ._1e34))
    assert((hi, lo) < UInt128._1e34.multipliedFullWidth(by: ._exp10[35]))
    if (hi, lo) == (0, 0) {
      let abs = Self(bitPattern: UInt128(truncatingIfNeeded: pe) &<< 113)
      return isSignMinus ? -abs : abs
    }
    if e > 12320 {
      return _overflow(isSignMinus: isSignMinus, rule, &flags)
    }
    if e < -69 {
      let nextAway = _roundsAway(
        isSignMinus: isSignMinus,
        significand: 0,
        digit: 0,
        sticky: true,
        rule)
      let abs = Self(bitPattern: nextAway ? 1 : 0)
      _raise(.underflowInexact, in: &flags)
      return isSignMinus ? -abs : abs
    }

    // Per IEEE 754, detect tininess (i.e., underflow) before rounding.
    let isTiny: Bool = if e < -35 {
      true
    } else if e < -5 {
      unsafe hi == 0 || (hi, lo) <
        UInt128._exp10[unchecked: -e]._multipliedFullWidth(by: ._1e33)
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
        let (q, r) =
          UInt128._quotientAndRemainder(fullWidth: (hi, lo), dividingBy1e: 38)
        if r != 0 { sticky = true }
        let n = -e &- 38
        divisor = ._exp10[n]
        (quo, rem) = q._quotientAndRemainder(dividingBy1e: n)
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
    } else if hi != 0 || lo >= ._1e34 {
      // See explanatory comment in `UInt128._commonLogarithm`.
      // Note that here we underestimate using a closer approximation.
      let x = hi != 0
        ? 255 &- hi.leadingZeroBitCount
        : 127 &- lo.leadingZeroBitCount
      let n = ((1233 &* x) &>> 12) &- 33
      divisor = unsafe ._exp10[unchecked: n]
      (quo, rem) = hi != 0
        ? UInt128._quotientAndRemainder(fullWidth: (hi, lo), dividingBy1e: n)
        : lo._quotientAndRemainder(dividingBy1e: n)
      e &+= n
      if quo >= ._1e34 {
        let digit: UInt128
        (quo, digit) = quo.quotientAndRemainder(dividingBy: 10)
        rem &+= digit &* divisor
        divisor &*= 10
        e &+= 1
      }
    } else {
      divisor = 1
      (quo, rem) = (lo, 0)
    }

    let inexact = rem != 0 || sticky
    if !inexact {
      // Select exact cohort before checking for overflow.
      _select(
        biasedExponent: &e,
        nonzeroSignificand: &quo,
        boundedPreferredBiasedExponent: pe)
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
    let half = divisor &>> 1
    switch rule {
    case .toNearestOrEven:
      quo &+= rem &+ (sticky || (quo & 1) != 0 ? 1 : 0) > half ? 1 : 0
    case .toNearestOrAwayFromZero:
      quo &+= rem >= half ? 1 : 0
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
    if quo == ._1e34 {
      if e == 12287 {
        _raise(.overflowInexact, in: &flags)
        return isSignMinus ? -.infinity : .infinity
      }
      quo = ._1e33
      e &+= 1
    }
    if isTiny {
      _raise(.underflowInexact, in: &flags)
    } else {
      _raise(.inexact, in: &flags)
    }
    let abs = Self(bitPattern: UInt128(truncatingIfNeeded: e) &<< 113 | quo)
    return isSignMinus ? -abs : abs
  }
}

@available(anyAppleOS 26.0, *)
extension Decimal128: AdditiveArithmetic {
  @usableFromInline
  internal func _adding(
    _ rhs: Decimal128,
    rounding rule: _DecimalFloatingPointRoundingRule,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) -> Decimal128 {
    var lhs = self, rhs = rhs

    // A fast path for certain 'everyday' values. Purely an optimization.
    do {
      // See `exponentBitPattern`:
      let le = Int(truncatingIfNeeded: lhs.bitPattern &>> 113) & 0x3fff
      let re = Int(truncatingIfNeeded: rhs.bitPattern &>> 113) & 0x3fff
      let delta = le &- re
      // See `significandBitPattern`:
      if (lhs.bitPattern | rhs.bitPattern) & ((1 &<< 113) &- 1) <= 0xffff_ffff
        && max(le, re) <= 0x2fff // Neither combination field starts `0b11...`.
        && delta.magnitude <= 9
      {
        let x = Int64(UInt32(truncatingIfNeeded: lhs.bitPattern))
        let y = Int64(UInt32(truncatingIfNeeded: rhs.bitPattern))
        let x_ = lhs._isSignMinus ? 0 &- x : x
        let y_ = rhs._isSignMinus ? 0 &- y : y
        let (hi, lo) = delta < 0 ? (y_, x_) : (x_, y_)
        let scale = unsafe Int64(
          truncatingIfNeeded: UInt128._exp10[unchecked: abs(delta)])
        let sum = hi &* scale &+ lo
        if sum != 0 {
          return Self(
            sign: sum < 0 ? .minus : .plus,
            exponentBitPattern: UInt(min(le, re)),
            significandBitPattern: UInt128(sum.magnitude))
        }
        let isSignMinus = lhs._isSignMinus == rhs._isSignMinus
          ? lhs._isSignMinus
          : rule == .down
        let abs = Self(bitPattern: UInt128(min(le, re)) &<< 113)
        return isSignMinus ? -abs : abs
      }
    }

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
        let isSignMinus = lhs._isSignMinus
        if rhs.isInfinite && isSignMinus != rhs._isSignMinus {
          _raise(.invalid, in: &flags)
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
      let n = min(e1 &- e2, UInt(max(0, 33 &- c1._commonLogarithm)))
      c1 &*= unsafe ._exp10[unchecked: Int(n)]
      e1 &-= n
      return Self(
        sign: lhs.sign, exponentBitPattern: e1, significandBitPattern: c1)
    }

    var (e1, e2) = (lhs.exponentBitPattern, rhs.exponentBitPattern)

    if e1 == e2 {
      var c1 = lhs.significandBitPattern
      let c2 = rhs.significandBitPattern
      // Compute `c1 + c2` if same sign,
      // or `abs(c1 - c2) = abs(~(~c1 + c2))` if not.
      let mask: UInt128 = lhs._isSignMinus == rhs._isSignMinus ? 0 : .max
      c1 = ((c1 ^ mask) &+ c2) ^ mask
      let complement = Int128(bitPattern: c1) < 0
      if complement { c1 = 0 &- c1 }
      let isSignMinus = c1 == 0
        ? rule == .down  // Exact zero. See IEEE 754 §6.3.
        : lhs._isSignMinus != complement
      if c1 >= ._1e34 {
        guard e1 < 12287 else {
          return ._overflow(isSignMinus: isSignMinus, rule, &flags)
        }
        let r: UInt128
        (c1, r) = c1.quotientAndRemainder(dividingBy: 10)
        e1 &+= 1
        if r != 0 {
          switch rule {
          case .toNearestOrEven:
            c1 &+= r &+ (c1 & 1) > 5 ? 1 : 0
          case .toNearestOrAwayFromZero:
            c1 &+= r >= 5 ? 1 : 0
          case .towardZero:
            break
          case .awayFromZero:
            c1 &+= 1
          case .down:
            c1 &+= isSignMinus ? 1 : 0
          case .up:
            c1 &+= isSignMinus ? 0 : 1
          @unknown default:
            fatalError("Unknown rounding rule.")
          }
          _raise(.inexact, in: &flags)
        }
      }
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
    let c2 = rhs.significandBitPattern

    if n <= 34 && c1 >= ._1e33 {
      // `lhs > rhs`, given `e1 > e2` and `c1` has 34 digits.
      var e = e1
      var divisor: UInt128 = unsafe ._exp10[unchecked: n]
      var (q, r) = c2 < divisor
        ? (0, c2)
        : c2._quotientAndRemainder(dividingBy1e: n)
      if isSignMinus == rhs._isSignMinus {
        q = c1 &+ q
      } else {
        q = c1 &- q
        if r != 0 {
          q &-= 1
          r = divisor &- r
        }
      }
      let sticky: Bool
      if q >= ._1e34 {
        sticky = r != 0
        (q, r) = q.quotientAndRemainder(dividingBy: 10)
        divisor = 10
        e &+= 1
      } else {
        sticky = false
        // Recover one digit if necessary.
        if q < ._1e33 {
          let digit: UInt128
          (digit, r) = r._quotientAndRemainder(dividingBy1e: n &- 1)
          q = q &* 10 &+ digit
          divisor = unsafe ._exp10[unchecked: n &- 1]
          e &-= 1
        }
      }
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

    let logc1 = c1._commonLogarithm
    let logc2 = c2._commonLogarithm
    let delta = n &+ (logc1 &- logc2)
    if delta > 34 {
      // Inexact.
      if logc1 < 33 {
        let n_ = UInt(33 &- logc1)
        c1 &*= unsafe ._exp10[unchecked: Int(n_)]
        e1 &-= n_
      }
      assert(e1 >= 2) // Never tiny.
      if isSignMinus == rhs._isSignMinus {
        let nextAway: Bool =
          switch rule {
          case .toNearestOrEven, .toNearestOrAwayFromZero:
            false
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
          if c1 == ._1e34 &- 1 {
            if e1 == 12287 {
              _raise(.overflowInexact, in: &flags)
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
          case .toNearestOrEven, .toNearestOrAwayFromZero:
            unsafe delta == 35 &&
              c1 == ._1e33 && c2 > 5 &* ._exp10[unchecked: logc2]
          case .towardZero:
            true
          case .awayFromZero:
            false
          case .down:
            !isSignMinus
          case .up:
            isSignMinus
          @unknown default:
            fatalError("Unknown rounding rule.")
          }
        if nextToward {
          if c1 == ._1e33 {
            c1 = ._1e34 &- 1
            e1 &-= 1
          } else {
            c1 &-= 1
          }
        }
      }
      let abs = Self(bitPattern: UInt128(truncatingIfNeeded: e1) &<< 113 | c1)
      _raise(.inexact, in: &flags)
      return isSignMinus ? -abs : abs
    }

    // Compute the intermediate result.
    assert(n != 0)
    var (hi, lo) = n <= 38
      ? c1._multipliedFullWidth(by1e: n)
      : (c1 * ._exp10[n &- 34])._multipliedFullWidth(by: ._1e34)
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

    if hi == 0 && lo < ._1e34 {
      // Exact.
      let abs = Self(bitPattern: UInt128(truncatingIfNeeded: e2) &<< 113 | lo)
      return isSignMinus ? -abs : abs
    }
    return ._pack(
      isSignMinus: isSignMinus,
      biasedExponent: Int(e2),
      significand: (hi, lo),
      rule,
      &flags)
  }

  /// Adds two values and produces their sum.
  ///
  /// The result is rounded if needed to the nearest representable value
  /// (ties to even).
  ///
  /// This method implements the `addition` operation defined by the
  /// IEEE 754 specification.
  ///
  /// - Parameters:
  ///   - lhs: The first value to add.
  ///   - rhs: The second value to add.
  /// - Returns: The sum of `lhs` and `rhs`, rounded if needed.
  @inline(always)
  public static func + (lhs: Decimal128, rhs: Decimal128) -> Decimal128 {
    var flags: DecimalFloatingPointStatusFlags = []
    defer { _signal(flags) }
    return lhs._adding(rhs, rounding: .toNearestOrEven, &flags)
  }

  /// Returns the result of adding the given value to this value,
  /// accumulating status flags.
  ///
  /// The result is rounded if needed to the nearest representable value
  /// (ties to even).
  ///
  /// This method implements the `addition` operation defined by the
  /// IEEE 754 specification.
  ///
  /// - Parameters:
  ///   - rhs: The value to add to this value.
  ///   - flags: A value that accumulates decimal floating-point arithmetic
  ///     status flags.
  /// - Returns: The sum of this value and `rhs`, rounded if needed.
  @inline(always)
  public func adding(
    _ rhs: Decimal128,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) -> Decimal128 {
    _adding(rhs, rounding: .toNearestOrEven, &flags)
  }

  /// Returns the result of adding the given value to this value.
  ///
  /// The result is rounded if needed using the given rounding rule.
  ///
  /// This method implements the `addition` operation defined by the
  /// IEEE 754 specification.
  ///
  /// - Parameters:
  ///   - rhs: The value to add to this value.
  ///   - rule: The rounding rule to use for an inexact result.
  /// - Returns: The sum of this value and `rhs`, rounded if needed.
  @inline(always)
  public func adding(
    _ rhs: Decimal128,
    rounding rule: FloatingPointRoundingRule
  ) -> Decimal128 {
    var flags: DecimalFloatingPointStatusFlags = []
    defer { _signal(flags) }
    return _adding(rhs, rounding: .init(rule), &flags)
  }

  /// Returns the result of adding the given value to this value,
  /// accumulating status flags.
  ///
  /// The result is rounded if needed using the given rounding rule.
  ///
  /// This method implements the `addition` operation defined by the
  /// IEEE 754 specification.
  ///
  /// - Parameters:
  ///   - rhs: The value to add to this value.
  ///   - rule: The rounding rule to use for an inexact result.
  ///   - flags: A value that accumulates decimal floating-point arithmetic
  ///     status flags.
  /// - Returns: The sum of this value and `rhs`, rounded if needed.
  @inline(always)
  public func adding(
    _ rhs: Decimal128,
    rounding rule: FloatingPointRoundingRule,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) -> Decimal128 {
    _adding(rhs, rounding: .init(rule), &flags)
  }

  /// Adds two values and stores the result in the left-hand-side variable.
  ///
  /// The result is rounded if needed to the nearest representable value
  /// (ties to even).
  ///
  /// - Parameters:
  ///   - lhs: The first value to add.
  ///   - rhs: The second value to add.
  @inline(always)
  public static func += (lhs: inout Decimal128, rhs: Decimal128) {
    lhs = lhs + rhs
  }

  /// Adds the given value to this value in place, accumulating status flags.
  ///
  /// The result is rounded if needed to the nearest representable value
  /// (ties to even).
  ///
  /// - Parameters:
  ///   - rhs: The value to add to this value.
  ///   - flags: A value that accumulates decimal floating-point arithmetic
  ///     status flags.
  @inline(always)
  public mutating func add(
    _ rhs: Decimal128,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) {
    self = adding(rhs, &flags)
  }

  /// Adds the given value to this value in place.
  ///
  /// The result is rounded if needed using the given rounding rule.
  ///
  /// - Parameters:
  ///   - rhs: The value to add to this value.
  ///   - rule: The rounding rule to use for an inexact result.
  @inline(always)
  public mutating func add(
    _ rhs: Decimal128,
    rounding rule: FloatingPointRoundingRule
  ) {
    self = adding(rhs, rounding: rule)
  }

  /// Adds the given value to this value in place, accumulating status flags.
  ///
  /// The result is rounded if needed using the given rounding rule.
  ///
  /// - Parameters:
  ///   - rhs: The value to add to this value.
  ///   - rule: The rounding rule to use for an inexact result.
  ///   - flags: A value that accumulates decimal floating-point arithmetic
  ///     status flags.
  @inline(always)
  public mutating func add(
    _ rhs: Decimal128,
    rounding rule: FloatingPointRoundingRule,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) {
    self = adding(rhs, rounding: rule, &flags)
  }

  /// Subtracts one value from another and produces their difference.
  ///
  /// The result is rounded if needed to the nearest representable value
  /// (ties to even).
  ///
  /// This method implements the `subtraction` operation defined by the
  /// IEEE 754 specification.
  ///
  /// - Parameters:
  ///   - lhs: A numeric value.
  ///   - rhs: The value to subtract from `lhs`.
  /// - Returns: The result of subtracting `rhs` from `lhs`, rounded if needed.
  @inline(always)
  public static func - (lhs: Decimal128, rhs: Decimal128) -> Decimal128 {
    var flags: DecimalFloatingPointStatusFlags = []
    defer { _signal(flags) }
#if ConsensusNaN
    return lhs._adding(
      rhs.isNaN ? rhs : -rhs,
      rounding: .toNearestOrEven,
      &flags)
#else
    return lhs._adding(-rhs, rounding: .toNearestOrEven, &flags)
#endif
  }

  /// Returns the result of subtracting the given value from this value,
  /// accumulating status flags.
  ///
  /// The result is rounded if needed to the nearest representable value
  /// (ties to even).
  ///
  /// This method implements the `subtraction` operation defined by the
  /// IEEE 754 specification.
  ///
  /// - Parameters:
  ///   - rhs: The value to subtract from this value.
  ///   - flags: A value that accumulates decimal floating-point arithmetic
  ///     status flags.
  /// - Returns: The result of subtracting `rhs` from this value,
  ///   rounded if needed.
  @inline(always)
  public func subtracting(
    _ rhs: Decimal128,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) -> Decimal128 {
#if ConsensusNaN
    _adding(rhs.isNaN ? rhs : -rhs, rounding: .toNearestOrEven, &flags)
#else
    _adding(-rhs, rounding: .toNearestOrEven, &flags)
#endif
  }

  /// Returns the result of subtracting the given value from this value.
  ///
  /// The result is rounded if needed using the given rounding rule.
  ///
  /// This method implements the `subtraction` operation defined by the
  /// IEEE 754 specification.
  ///
  /// - Parameters:
  ///   - rhs: The value to subtract from this value.
  ///   - rule: The rounding rule to use for an inexact result.
  /// - Returns: The result of subtracting `rhs` from this value,
  ///   rounded if needed.
  @inline(always)
  public func subtracting(
    _ rhs: Decimal128,
    rounding rule: FloatingPointRoundingRule
  ) -> Decimal128 {
    var flags: DecimalFloatingPointStatusFlags = []
    defer { _signal(flags) }
#if ConsensusNaN
    return _adding(rhs.isNaN ? rhs : -rhs, rounding: .init(rule), &flags)
#else
    return _adding(-rhs, rounding: .init(rule), &flags)
#endif
  }

  /// Returns the result of subtracting the given value from this value,
  /// accumulating status flags.
  ///
  /// The result is rounded if needed using the given rounding rule.
  ///
  /// This method implements the `subtraction` operation defined by the
  /// IEEE 754 specification.
  ///
  /// - Parameters:
  ///   - rhs: The value to subtract from this value.
  ///   - rule: The rounding rule to use for an inexact result.
  ///   - flags: A value that accumulates decimal floating-point arithmetic
  ///     status flags.
  /// - Returns: The result of subtracting `rhs` from this value,
  ///   rounded if needed.
  @inline(always)
  public func subtracting(
    _ rhs: Decimal128,
    rounding rule: FloatingPointRoundingRule,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) -> Decimal128 {
#if ConsensusNaN
    _adding(rhs.isNaN ? rhs : -rhs, rounding: .init(rule), &flags)
#else
    _adding(-rhs, rounding: .init(rule), &flags)
#endif
  }

  /// Subtracts the second value from the first
  /// and stores the difference in the left-hand-side variable.
  ///
  /// The result is rounded if needed to the nearest representable value
  /// (ties to even).
  ///
  /// - Parameters:
  ///   - lhs: A numeric value.
  ///   - rhs: The value to subtract from `lhs`.
  @inline(always)
  public static func -= (lhs: inout Decimal128, rhs: Decimal128) {
    lhs = lhs - rhs
  }

  /// Subtracts the given value from this value in place,
  /// accumulating status flags.
  ///
  /// The result is rounded if needed to the nearest representable value
  /// (ties to even).
  ///
  /// - Parameters:
  ///   - rhs: The value to subtract from this value.
  ///   - flags: A value that accumulates decimal floating-point arithmetic
  ///     status flags.
  @inline(always)
  public mutating func subtract(
    _ rhs: Decimal128,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) {
    self = subtracting(rhs, &flags)
  }

  /// Subtracts the given value from this value in place.
  ///
  /// The result is rounded if needed using the given rounding rule.
  ///
  /// - Parameters:
  ///   - rhs: The value to subtract from this value.
  ///   - rule: The rounding rule to use for an inexact result.
  @inline(always)
  public mutating func subtract(
    _ rhs: Decimal128,
    rounding rule: FloatingPointRoundingRule
  ) {
    self = subtracting(rhs, rounding: rule)
  }

  /// Subtracts the given value from this value in place,
  /// accumulating status flags.
  ///
  /// The result is rounded if needed using the given rounding rule.
  ///
  /// - Parameters:
  ///   - rhs: The value to subtract from this value.
  ///   - rule: The rounding rule to use for an inexact result.
  ///   - flags: A value that accumulates decimal floating-point arithmetic
  ///     status flags.
  @inline(always)
  public mutating func subtract(
    _ rhs: Decimal128,
    rounding rule: FloatingPointRoundingRule,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) {
    self = subtracting(rhs, rounding: rule, &flags)
  }
}

@available(anyAppleOS 26.0, *)
extension Decimal128: Numeric {
  @usableFromInline
  internal func _multiplied(
    by rhs: Decimal128,
    rounding rule: _DecimalFloatingPointRoundingRule,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) -> Decimal128 {
    var lhs = self, rhs = rhs
    let isSignMinus = lhs._isSignMinus != rhs._isSignMinus

    // See `exponentBitPattern`:
    let le = Int(truncatingIfNeeded: lhs.bitPattern &>> 113) & 0x3fff
    let re = Int(truncatingIfNeeded: rhs.bitPattern &>> 113) & 0x3fff
    // See `significandBitPattern`:
    let lc = lhs.bitPattern & ((1 &<< 113) &- 1)
    let rc = rhs.bitPattern & ((1 &<< 113) &- 1)
    let lte = (lc | rc) <= 0xffff_ffff_ffff_ffff /* UInt64.max */
    guard /* lhs.isFinite && lhs.isCanonical && rhs.isFinite && rhs.isCanonical */
      max(le, re) <= 0x2fff // Neither combination field starts `0b11...`.
      && (lte || (lc < ._1e34 && rc < ._1e34))
    else {
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
        if rhs.isZero {
          _raise(.invalid, in: &flags)
          return .nan
        }
        return isSignMinus ? -.infinity : .infinity
      }
      if rhs.isInfinite {
        if lhs.isZero {
          _raise(.invalid, in: &flags)
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
    // (Note that we admit canonical zero here.)
    let e = le &+ re &- 6176
    let product: (high: UInt128, low: UInt128)
    if lte {
      let (hi, lo) =
        UInt64(truncatingIfNeeded: lc).multipliedFullWidth(
          by: UInt64(truncatingIfNeeded: rc))
      product = (0, UInt128(hi) &<< 64 | UInt128(lo))
    } else {
      product = lc._multipliedFullWidth(by: rc)
    }
    if product.high == 0 && product.low < ._1e34 && e >= 0 && e <= 12287 {
      let abs = Self(
        bitPattern: UInt128(truncatingIfNeeded: e) &<< 113 | product.low)
      return isSignMinus ? -abs : abs
    }
    return ._pack(
      isSignMinus: isSignMinus,
      biasedExponent: e,
      significand: product,
      rule,
      &flags)
  }

  /// Multiplies two values and produces their product.
  ///
  /// The result is rounded if needed to the nearest representable value
  /// (ties to even).
  ///
  /// This method implements the `multiplication` operation defined by the
  /// IEEE 754 specification.
  ///
  /// - Parameters:
  ///   - lhs: The first value to multiply.
  ///   - rhs: The second value to multiply.
  /// - Returns: The product of `lhs` and `rhs`, rounded if needed.
  @inline(always)
  public static func * (lhs: Decimal128, rhs: Decimal128) -> Decimal128 {
    var flags: DecimalFloatingPointStatusFlags = []
    defer { _signal(flags) }
    return lhs._multiplied(by: rhs, rounding: .toNearestOrEven, &flags)
  }

  /// Returns the result of multiplying this value by the given value,
  /// accumulating status flags.
  ///
  /// The result is rounded if needed to the nearest representable value
  /// (ties to even).
  ///
  /// This method implements the `multiplication` operation defined by the
  /// IEEE 754 specification.
  ///
  /// - Parameters:
  ///   - rhs: The value by which to multiply this value.
  ///   - flags: A value that accumulates decimal floating-point arithmetic
  ///     status flags.
  /// - Returns: The product of this value and `rhs`, rounded if needed.
  @inline(always)
  public func multiplied(
    by rhs: Decimal128,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) -> Decimal128 {
    _multiplied(by: rhs, rounding: .toNearestOrEven, &flags)
  }

  /// Returns the result of multiplying this value by the given value.
  ///
  /// The result is rounded if needed using the given rounding rule.
  ///
  /// This method implements the `multiplication` operation defined by the
  /// IEEE 754 specification.
  ///
  /// - Parameters:
  ///   - rhs: The value by which to multiply this value.
  ///   - rule: The rounding rule to use for an inexact result.
  /// - Returns: The product of this value and `rhs`, rounded if needed.
  @inline(always)
  public func multiplied(
    by rhs: Decimal128,
    rounding rule: FloatingPointRoundingRule
  ) -> Decimal128 {
    var flags: DecimalFloatingPointStatusFlags = []
    defer { _signal(flags) }
    return _multiplied(by: rhs, rounding: .init(rule), &flags)
  }

  /// Returns the result of multiplying this value by the given value,
  /// accumulating status flags.
  ///
  /// The result is rounded if needed using the given rounding rule.
  ///
  /// This method implements the `multiplication` operation defined by the
  /// IEEE 754 specification.
  ///
  /// - Parameters:
  ///   - rhs: The value by which to multiply this value.
  ///   - rule: The rounding rule to use for an inexact result.
  ///   - flags: A value that accumulates decimal floating-point arithmetic
  ///     status flags.
  /// - Returns: The product of this value and `rhs`, rounded if needed.
  @inline(always)
  public func multiplied(
    by rhs: Decimal128,
    rounding rule: FloatingPointRoundingRule,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) -> Decimal128 {
    _multiplied(by: rhs, rounding: .init(rule), &flags)
  }

  /// Multiplies two values
  /// and stores the result in the left-hand-side variable.
  ///
  /// The result is rounded if needed to the nearest representable value
  /// (ties to even).
  ///
  /// - Parameters:
  ///   - lhs: The first value to multiply.
  ///   - rhs: The second value to multiply.
  @inline(always)
  public static func *= (lhs: inout Decimal128, rhs: Decimal128) {
    lhs = lhs * rhs
  }

  /// Multiplies this value by the given value in place,
  /// accumulating status flags.
  ///
  /// The result is rounded if needed to the nearest representable value
  /// (ties to even).
  ///
  /// - Parameters:
  ///   - rhs: The value by which to multiply this value.
  ///   - flags: A value that accumulates decimal floating-point arithmetic
  ///     status flags.
  @inline(always)
  public mutating func multiply(
    by rhs: Decimal128,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) {
    self = multiplied(by: rhs, &flags)
  }

  /// Multiplies this value by the given value in place.
  ///
  /// The result is rounded if needed using the given rounding rule.
  ///
  /// - Parameters:
  ///   - rhs: The value by which to multiply this value.
  ///   - rule: The rounding rule to use for an inexact result.
  @inline(always)
  public mutating func multiply(
    by rhs: Decimal128,
    rounding rule: FloatingPointRoundingRule
  ) {
    self = multiplied(by: rhs, rounding: rule)
  }

  /// Multiplies this value by the given value in place,
  /// accumulating status flags.
  ///
  /// The result is rounded if needed using the given rounding rule.
  ///
  /// - Parameters:
  ///   - rhs: The value by which to multiply this value.
  ///   - rule: The rounding rule to use for an inexact result.
  ///   - flags: A value that accumulates decimal floating-point arithmetic
  ///     status flags.
  @inline(always)
  public mutating func multiply(
    by rhs: Decimal128,
    rounding rule: FloatingPointRoundingRule,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) {
    self = multiplied(by: rhs, rounding: rule, &flags)
  }

  /// Creates a new value from the given integer, if it can be represented
  /// exactly.
  ///
  /// For an exact result, the represented (quantum) exponent is
  /// as close to zero as possible without changing the value.
  /// If `source` can't be represented exactly after conversion,
  /// the result is `nil`.
  ///
  /// - Parameters:
  ///   - source: The integer to convert.
  @inline(always)
  public init?<T: BinaryInteger>(exactly source: T) {
    var flags: DecimalFloatingPointStatusFlags = []
    self.init(source, _rounding: .toNearestOrEven, &flags)
    if flags.contains(.inexact) { return nil }
  }
}
