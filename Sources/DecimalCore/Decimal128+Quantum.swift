@available(anyAppleOS 26.0, *)
extension Decimal128 {
  /// The quantum of this value.
  ///
  /// If `x` is finite, then `x.quantum` is the floating-point value with
  /// positive sign and the same represented (quantum) exponent as this value,
  /// but with an integer significand of 1. For example:
  ///
  ///     let x = Decimal128("-1.2")!
  ///     let y = Decimal128("-1.20")!
  ///     x.quantum  // 0.1
  ///     y.quantum  // 0.01
  ///
  /// If `x` is infinite, then `x.quantum` is positive `infinity`.
  ///
  /// This property implements the `quantum` operation defined by the IEEE 754
  /// specification. Unlike `BinaryFloatingPoint.binade`, the result of this
  /// operation is always positive unless NaN.
  @inline(always)
  public var quantum: Decimal128 {
    guard isFinite else {
      if isSignalingNaN {
        _signal(.invalid)
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

  @usableFromInline
  internal func _quantized(
    by other: Decimal128,
    rounding rule: _DecimalFloatingPointRoundingRule,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) -> Decimal128 {
    guard isFinite && other.isFinite else {
      if isSignalingNaN {
        _raise(.invalid, in: &flags)
        return _quiet._canonical
      }
      if other.isSignalingNaN {
        _raise(.invalid, in: &flags)
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
      _raise(.invalid, in: &flags)
      return .nan
    }
    let oe = other.exponentBitPattern
    if isZero {
      return Self(sign: sign, exponentBitPattern: oe, significandBitPattern: 0)
    }
    let n = Int(exponentBitPattern) - Int(oe)
    if n == 0 {
      return self
    }
    var c = significandBitPattern
    if n > 0 {
      guard unsafe n < 34 && c < ._exp10[unchecked: 34 &- n] else {
        _raise(.invalid, in: &flags)
        return .nan
      }
      c &*= unsafe ._exp10[unchecked: n]
    } else {
      let r: UInt128
      let half: UInt128
      if n < -34 {
        r = c
        half = ._1e34
        c = 0
      } else {
        (c, r) = c._quotientAndRemainder(dividingBy1e: -n)
        half = unsafe ._exp10[unchecked: -n] &>> 1
      }
      if r != 0 {
        switch rule {
        case .toNearestOrEven:
          c &+= r &+ (c & 1) > half ? 1 : 0
        case .toNearestOrAwayFromZero:
          c &+= r >= half ? 1 : 0
        case .towardZero:
          break
        case .awayFromZero:
          c &+= 1
        case .down:
          c &+= _isSignMinus ? 1 : 0
        case .up:
          c &+= _isSignMinus ? 0 : 1
        @unknown default:
          fatalError("Unknown rounding rule.")
        }
        _raise(.inexact, in: &flags)
      }
    }
    return Self(sign: sign, exponentBitPattern: oe, significandBitPattern: c)
  }

  /// Returns this value with the same quantum as the given value.
  ///
  /// The result is rounded if needed to the nearest representable value
  /// with the requested quantum (ties to even).
  ///
  /// For finite operands, the result has the represented (quantum) exponent
  /// `other.quantum.exponent` and the same sign as this value.
  /// If the requested exponent would require an integer significand with
  /// more than 34 decimal digits, the result is NaN.
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
    defer { _signal(flags) }
    return _quantized(by: other, rounding: .toNearestOrEven, &flags)
  }

  /// Returns this value with the same quantum as the given value,
  /// accumulating status flags.
  ///
  /// The result is rounded if needed to the nearest representable value
  /// with the requested quantum (ties to even).
  ///
  /// For finite operands, the result has the represented (quantum) exponent
  /// `other.quantum.exponent` and the same sign as this value.
  /// If the requested exponent would require an integer significand with
  /// more than 34 decimal digits, the result is NaN.
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

  /// Returns this value with the same quantum as the given value.
  ///
  /// The result is rounded if needed using the given rounding rule.
  ///
  /// For finite operands, the result has the represented (quantum) exponent
  /// `other.quantum.exponent` and the same sign as this value.
  /// If the requested exponent would require an integer significand with
  /// more than 34 decimal digits, the result is NaN.
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
    defer { _signal(flags) }
    return _quantized(by: other, rounding: .init(rule), &flags)
  }

  /// Returns this value with the same quantum as the given value,
  /// accumulating status flags.
  ///
  /// The result is rounded if needed using the given rounding rule.
  ///
  /// For finite operands, the result has the represented (quantum) exponent
  /// `other.quantum.exponent` and the same sign as this value.
  /// If the requested exponent would require an integer significand with
  /// more than 34 decimal digits, the result is NaN.
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

  /// Changes this value to have the same quantum as the given value.
  ///
  /// The result is rounded if needed to the nearest representable value
  /// with the requested quantum (ties to even).
  ///
  /// For finite operands, the result has the represented (quantum) exponent
  /// `other.quantum.exponent` and the same sign as this value.
  /// If the requested exponent would require an integer significand with
  /// more than 34 decimal digits, the result is NaN.
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
  /// accumulating status flags.
  ///
  /// The result is rounded if needed to the nearest representable value
  /// with the requested quantum (ties to even).
  ///
  /// For finite operands, the result has the represented (quantum) exponent
  /// `other.quantum.exponent` and the same sign as this value.
  /// If the requested exponent would require an integer significand with
  /// more than 34 decimal digits, the result is NaN.
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

  /// Changes this value to have the same quantum as the given value.
  ///
  /// The result is rounded if needed using the given rounding rule.
  ///
  /// For finite operands, the result has the represented (quantum) exponent
  /// `other.quantum.exponent` and the same sign as this value.
  /// If the requested exponent would require an integer significand with
  /// more than 34 decimal digits, the result is NaN.
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
  /// accumulating status flags.
  ///
  /// The result is rounded if needed using the given rounding rule.
  ///
  /// For finite operands, the result has the represented (quantum) exponent
  /// `other.quantum.exponent` and the same sign as this value.
  /// If the requested exponent would require an integer significand with
  /// more than 34 decimal digits, the result is NaN.
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
