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
  /// For more information about the available rounding rules, see the
  /// `FloatingPointRoundingRule` enumeration.
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
