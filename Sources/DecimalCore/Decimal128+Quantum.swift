@available(anyAppleOS 26.0, *)
extension Decimal128 {
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
        _signal(.invalid, into: &flags)
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

  @inlinable
  internal func _quantized(
    by other: Decimal128,
    rounding rule: _DecimalFloatingPointRoundingRule,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) -> Decimal128 {
    guard isFinite && other.isFinite else {
      if isSignalingNaN {
        _signal(.invalid, into: &flags)
        return _quiet._canonical
      }
      if other.isSignalingNaN {
        _signal(.invalid, into: &flags)
        return other._quiet._canonical
      }

      if isNaN {
        return _canonical
      }
      if other.isNaN {
        return other._canonical
      }

      if isInfinite && other.isInfinite {
        return _isSignMinus ? -.infinity : .infinity
      }
      _signal(.invalid, into: &flags)
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
        _signal(.invalid, into: &flags)
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
      assert(c < ._1e34) // `c` has been divided by at least 10.
      if digit_ != 0 || sticky { _signal(.inexact, into: &flags) }
    }
    return Self(sign: sign, exponentBitPattern: oe, significandBitPattern: c)
  }

  /// Returns this value with the same quantum as the given value,
  /// rounding to the nearest representable value (ties to even) if needed.
  ///
  /// For finite operands, the result has the same represented exponent as
  /// `other` and the same sign as this value. If the requested exponent would
  /// require a significand with more than 34 decimal digits, the result is NaN.
  ///
  /// If both operands are infinite, the result is infinity with the sign of
  /// this value. If exactly one operand is infinite, the result is NaN.
  ///
  /// This method implements the `quantize` operation defined by the
  /// IEEE 754 specification.
  ///
  /// - Parameters:
  ///   - other: The value whose quantum to use for the result.
  /// - Returns: This value with the quantum of `other`, rounded if needed.
  @inline(always)
  public func quantized(by other: Decimal128) -> Decimal128 {
    var flags: DecimalFloatingPointStatusFlags = []
    return _quantized(by: other, rounding: .toNearestOrEven, &flags)
  }

  /// Returns this value with the same quantum as the given value,
  /// rounding to the nearest representable value (ties to even) if needed
  /// and accumulating status flags.
  ///
  /// For finite operands, the result has the same represented exponent as
  /// `other` and the same sign as this value. If the requested exponent would
  /// require a significand with more than 34 decimal digits, the result is NaN.
  ///
  /// If both operands are infinite, the result is infinity with the sign of
  /// this value. If exactly one operand is infinite, the result is NaN.
  ///
  /// This method implements the `quantize` operation defined by the
  /// IEEE 754 specification.
  ///
  /// - Parameters:
  ///   - other: The value whose quantum to use for the result.
  ///   - flags: A value that accumulates decimal floating-point arithmetic
  ///     status flags.
  /// - Returns: This value with the quantum of `other`, rounded if needed.
  @inline(always)
  public func quantized(
    by other: Decimal128,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) -> Decimal128 {
    _quantized(by: other, rounding: .toNearestOrEven, &flags)
  }

  /// Returns this value with the same quantum as the given value,
  /// rounding using the given rounding rule if needed.
  ///
  /// For finite operands, the result has the same represented exponent as
  /// `other` and the same sign as this value. If the requested exponent would
  /// require a significand with more than 34 decimal digits, the result is NaN.
  ///
  /// If both operands are infinite, the result is infinity with the sign of
  /// this value. If exactly one operand is infinite, the result is NaN.
  ///
  /// This method implements the `quantize` operation defined by the
  /// IEEE 754 specification.
  ///
  /// - Parameters:
  ///   - other: The value whose quantum to use for the result.
  ///   - rule: The rounding rule to use for an inexact result.
  /// - Returns: This value with the quantum of `other`, rounded if needed.
  @inline(always)
  public func quantized(
    by other: Decimal128,
    rounding rule: FloatingPointRoundingRule
  ) -> Decimal128 {
    var flags: DecimalFloatingPointStatusFlags = []
    return _quantized(by: other, rounding: .init(rule), &flags)
  }

  /// Returns this value with the same quantum as the given value,
  /// rounding using the given rounding rule if needed and accumulating
  /// status flags.
  ///
  /// For finite operands, the result has the same represented exponent as
  /// `other` and the same sign as this value. If the requested exponent would
  /// require a significand with more than 34 decimal digits, the result is NaN.
  ///
  /// If both operands are infinite, the result is infinity with the sign of
  /// this value. If exactly one operand is infinite, the result is NaN.
  ///
  /// This method implements the `quantize` operation defined by the
  /// IEEE 754 specification.
  ///
  /// - Parameters:
  ///   - other: The value whose quantum to use for the result.
  ///   - rule: The rounding rule to use for an inexact result.
  ///   - flags: A value that accumulates decimal floating-point arithmetic
  ///     status flags.
  /// - Returns: This value with the quantum of `other`, rounded if needed.
  @inline(always)
  public func quantized(
    by other: Decimal128,
    rounding rule: FloatingPointRoundingRule,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) -> Decimal128 {
    _quantized(by: other, rounding: .init(rule), &flags)
  }

  /// Changes this value to have the same quantum as the given value,
  /// rounding to the nearest representable value (ties to even) if needed.
  ///
  /// For finite operands, the result has the same represented exponent as
  /// `other` and the same sign as this value. If the requested exponent would
  /// require a significand with more than 34 decimal digits, the result is NaN.
  ///
  /// If both operands are infinite, the result is infinity with the sign of
  /// this value. If exactly one operand is infinite, the result is NaN.
  ///
  /// - Parameters:
  ///   - other: The value whose quantum to use for the result.
  @inline(always)
  public mutating func quantize(by other: Decimal128) {
    self = quantized(by: other)
  }

  /// Changes this value to have the same quantum as the given value,
  /// rounding to the nearest representable value (ties to even) if needed
  /// and accumulating status flags.
  ///
  /// For finite operands, the result has the same represented exponent as
  /// `other` and the same sign as this value. If the requested exponent would
  /// require a significand with more than 34 decimal digits, the result is NaN.
  ///
  /// If both operands are infinite, the result is infinity with the sign of
  /// this value. If exactly one operand is infinite, the result is NaN.
  ///
  /// - Parameters:
  ///   - other: The value whose quantum to use for the result.
  ///   - flags: A value that accumulates decimal floating-point arithmetic
  ///     status flags.
  @inline(always)
  public mutating func quantize(
    by other: Decimal128,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) {
    self = quantized(by: other, &flags)
  }

  /// Changes this value to have the same quantum as the given value,
  /// rounding using the given rounding rule if needed.
  ///
  /// For finite operands, the result has the same represented exponent as
  /// `other` and the same sign as this value. If the requested exponent would
  /// require a significand with more than 34 decimal digits, the result is NaN.
  ///
  /// If both operands are infinite, the result is infinity with the sign of
  /// this value. If exactly one operand is infinite, the result is NaN.
  ///
  /// - Parameters:
  ///   - other: The value whose quantum to use for the result.
  ///   - rule: The rounding rule to use for an inexact result.
  @inline(always)
  public mutating func quantize(
    by other: Decimal128,
    rounding rule: FloatingPointRoundingRule
  ) {
    self = quantized(by: other, rounding: rule)
  }

  /// Changes this value to have the same quantum as the given value,
  /// rounding using the given rounding rule if needed and accumulating status
  /// flags.
  ///
  /// For finite operands, the result has the same represented exponent as
  /// `other` and the same sign as this value. If the requested exponent would
  /// require a significand with more than 34 decimal digits, the result is NaN.
  ///
  /// If both operands are infinite, the result is infinity with the sign of
  /// this value. If exactly one operand is infinite, the result is NaN.
  ///
  /// - Parameters:
  ///   - other: The value whose quantum to use for the result.
  ///   - rule: The rounding rule to use for an inexact result.
  ///   - flags: A value that accumulates decimal floating-point arithmetic
  ///     status flags.
  @inline(always)
  public mutating func quantize(
    by other: Decimal128,
    rounding rule: FloatingPointRoundingRule,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) {
    self = quantized(by: other, rounding: rule, &flags)
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
}
