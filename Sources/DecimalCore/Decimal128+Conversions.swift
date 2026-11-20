@available(anyAppleOS 26.0, *)
extension FixedWidthInteger {
  @inlinable
  internal static func _convert(
    _ source: Decimal128
  ) -> (value: Self, inexact: Bool)? {
    guard source._isFiniteNonzero else {
      if !source.isFinite { return nil }
      return (0, false)
    }

    let isSignMinus = source._isSignMinus
    var unbiasedExponent = Int(source.exponentBitPattern) &- 6176
    var c = source.significandBitPattern
    var inexact = false
    if unbiasedExponent < -33 {
      return (0, true)
    } else if unbiasedExponent < 0 {
      let r: UInt128
      (c, r) = c._quotientAndRemainder(dividingBy1e: -unbiasedExponent)
      inexact = r != 0
      if c == 0 {
        return (0, inexact)
      }
      unbiasedExponent = 0
    }
    guard
      (Self.isSigned || !isSignMinus) && unbiasedExponent < Self.bitWidth,
      var magnitude = Magnitude(exactly: c)
    else { return nil }

    if unbiasedExponent > 0 && unbiasedExponent <= 38 {
      guard let x =
        unsafe Magnitude(exactly: UInt128._exp10[unchecked: unbiasedExponent])
      else { return nil }
      let overflow: Bool
      (magnitude, overflow) = magnitude.multipliedReportingOverflow(by: x)
      guard !overflow else { return nil }
    } else if unbiasedExponent > 38 {
      guard Self.bitWidth > 128 else { return nil }
      var n = unbiasedExponent % 38
      if n != 0 {
        let x = unsafe Magnitude(UInt128._exp10[unchecked: n])
        let overflow: Bool
        (magnitude, overflow) = magnitude.multipliedReportingOverflow(by: x)
        guard !overflow else { return nil }
      }
      // Exponentiation by squaring.
      n = unbiasedExponent / 38
      var power = unsafe Magnitude(UInt128._exp10[unchecked: 38])
      while n != 0 {
        if n & 1 != 0 {
          let overflow: Bool
          (magnitude, overflow) =
            magnitude.multipliedReportingOverflow(by: power)
          guard !overflow else { return nil }
        }
        n &>>= 1
        if n != 0 {
          let overflow: Bool
          (power, overflow) = power.multipliedReportingOverflow(by: power)
          guard !overflow else { return nil }
        }
      }
    }

    guard magnitude <= (isSignMinus ? Self.min.magnitude : Self.max.magnitude)
    else { return nil }
    return (
      isSignMinus
        ? 0 &- Self(truncatingIfNeeded: magnitude)
        : Self(truncatingIfNeeded: magnitude),
      inexact)
  }

  /// Creates an integer from the given decimal floating-point value,
  /// rounding toward zero.
  ///
  /// Any fractional part of the value passed as `source` is removed,
  /// rounding the value toward zero.
  ///
  ///     let x = Int8(#Decimal128(127.5))
  ///     // x == 127
  ///     let y = UInt(#Decimal128(-0.75))
  ///     // y == 0
  ///
  /// If `source` is outside the bounds of this type after rounding toward zero,
  /// a runtime error may occur.
  ///
  /// - Parameter source: The decimal floating-point value to convert.
  ///   `source` must be representable in this type after rounding toward zero.
  @inline(always)
  public init(_ source: Decimal128) {
    guard let result = Self._convert(source) else {
      fatalError("Value cannot be converted because it is unrepresentable.")
    }
    self = result.value
  }

  /// Creates an integer from the given decimal floating-point value,
  /// if it can be represented exactly.
  ///
  /// If the value passed as `source` is not representable exactly, the result
  /// is `nil`.
  ///
  ///     Int8(exactly: #Decimal128(127.0))  // Optional(127)
  ///     Int8(exactly: #Decimal128(126.5))  // nil
  ///     Int8(exactly: #Decimal128(128.0))  // nil
  ///
  /// - Parameter source: The decimal floating-point value to convert.
  @inline(always)
  public init?(exactly source: Decimal128) {
    guard let result = Self._convert(source), !result.inexact else {
      return nil
    }
    self = result.value
  }
}

@available(anyAppleOS 26.0, *)
extension Decimal128 {
  @inlinable
  internal init<T: BinaryInteger>(
    _ source: T,
    _rounding rule: _DecimalFloatingPointRoundingRule,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) {
    let magnitude = source.magnitude
    let isSignMinus = source < (0 as T)

    if magnitude.bitWidth < 113 || magnitude < T.Magnitude(UInt128._1e34) {
      bitPattern = UInt128(truncatingIfNeeded: magnitude)
      bitPattern |= Self().bitPattern
      if isSignMinus { negate() }
      return
    }
    if let c = UInt128(exactly: magnitude) {
      let n = c._commonLogarithm &- 33
      var e = 6176 &+ n
      var (q, r) = c._quotientAndRemainder(dividingBy1e: n)
      if r != 0 {
        let half: UInt128 = unsafe ._exp10[unchecked: n] &>> 1
        let nextAway = Self._roundsAway(
          isSignMinus: isSignMinus,
          significand: q,
          digit: r >= half ? 5 : 0,
          sticky: r != half,
          rule)
        q &+= nextAway ? 1 : 0
        if q == ._1e34 {
          q = ._1e33
          e &+= 1
        }
        _signal(.inexact, into: &flags)
      }
      let abs = Self(bitPattern: UInt128(truncatingIfNeeded: e) &<< 113 | q)
      self = isSignMinus ? -abs : abs
      return
    }

    // Determine bit width, excluding leading zero bits, using public APIs.
    var bits = ((magnitude.bitWidth &- 1) / UInt.bitWidth) * UInt.bitWidth
    var highWord = UInt(truncatingIfNeeded: magnitude >> bits)
    while highWord == 0 {
      bits &-= UInt.bitWidth
      highWord = UInt(truncatingIfNeeded: magnitude >> bits)
    }
    bits += (UInt.bitWidth &- highWord.leadingZeroBitCount)

    guard bits <= 20414 else {
      self = ._overflow(isSignMinus: isSignMinus, rule, &flags)
      return
    }
    // Underestimate floor(log10), off by at most one, then choose `k`, a
    // multiple of 32 such that `magnitude / 10**k` retains 35 to 67 digits.
    let underestimate = (1233 &* (bits &- 1)) &>> 12
    let k = (underestimate &- 34) & ~31
    // Build `5**k` from `5**32` using exponentiation by squaring.
    var n = k &>> 5 // `k / 32`.
    var divisor: T.Magnitude = 1
    var power = T.Magnitude(UInt128._exp10[32] &>> 32) // `5**32`.
    while n != 0 {
      if n & 1 != 0 { divisor *= power }
      n &>>= 1
      if n != 0 { power *= power }
    }
    // Compute `magnitude / 10**k = (magnitude >> k) / 5**k`.
    let (q, r) = (magnitude >> k).quotientAndRemainder(dividingBy: divisor)
    let sticky = r != 0 || magnitude.trailingZeroBitCount < k
    self = ._pack(
      isSignMinus: isSignMinus,
      biasedExponent: 6176 &+ k,
      significand:
        (UInt128(truncatingIfNeeded: q >> 128), UInt128(truncatingIfNeeded: q)),
      sticky: sticky,
      preferredBiasedExponent: 6176,
      rule,
      &flags)
  }

  /// Creates a new value from the given integer, rounding to the nearest
  /// representable value (ties to even) if needed.
  ///
  /// For an exact result, the represented exponent is as close to zero as
  /// possible without changing the value.
  ///
  /// This initializer implements the `convertFromInt` operation defined by the
  /// IEEE 754 specification.
  ///
  /// - Parameters:
  ///   - source: The integer to convert.
  @inline(always)
  public init<T: BinaryInteger>(_ source: T) {
    var flags: DecimalFloatingPointStatusFlags = []
    self.init(source, _rounding: .toNearestOrEven, &flags)
  }

  /// Creates a new value from the given integer, rounding to the nearest
  /// representable value (ties to even) if needed and accumulating status
  /// flags.
  ///
  /// For an exact result, the represented exponent is as close to zero as
  /// possible without changing the value.
  ///
  /// This initializer implements the `convertFromInt` operation defined by the
  /// IEEE 754 specification.
  ///
  /// - Parameters:
  ///   - source: The integer to convert.
  ///   - flags: A value that accumulates decimal floating-point arithmetic
  ///     status flags.
  @inline(always)
  public init<T: BinaryInteger>(
    _ source: T,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) {
    self.init(source, _rounding: .toNearestOrEven, &flags)
  }

  /// Creates a new value from the given integer, rounding to a representable
  /// value using the given rounding rule if needed.
  ///
  /// For an exact result, the represented exponent is as close to zero as
  /// possible without changing the value.
  ///
  /// This initializer implements the `convertFromInt` operation defined by the
  /// IEEE 754 specification.
  ///
  /// - Parameters:
  ///   - source: The integer to convert.
  ///   - rule: The rounding rule to use for an inexact result.
  @inline(always)
  public init<T: BinaryInteger>(
    _ source: T,
    rounding rule: FloatingPointRoundingRule
  ) {
    var flags: DecimalFloatingPointStatusFlags = []
    self.init(source, _rounding: .init(rule), &flags)
  }

  /// Creates a new value from the given integer, rounding to a representable
  /// value using the given rounding rule if needed and accumulating status
  /// flags.
  ///
  /// For an exact result, the represented exponent is as close to zero as
  /// possible without changing the value.
  ///
  /// This initializer implements the `convertFromInt` operation defined by the
  /// IEEE 754 specification.
  ///
  /// - Parameters:
  ///   - source: The integer to convert.
  ///   - rule: The rounding rule to use for an inexact result.
  ///   - flags: A value that accumulates decimal floating-point arithmetic
  ///     status flags.
  @inline(always)
  public init<T: BinaryInteger>(
    _ source: T,
    rounding rule: FloatingPointRoundingRule,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) {
    self.init(source, _rounding: .init(rule), &flags)
  }
}

@available(anyAppleOS 26.0, *)
extension BinaryFloatingPoint {
  @inlinable
  @inline(always)
  internal static var _format: (precision: Int, emin: Int, emax: Int) {
    let precision = Self.significandBitCount &+ 1
    guard
      precision > 1 && precision <= 113,
      let tiny = Int(exactly: Self.leastNonzeroMagnitude.exponent),
      let emin = Int(exactly: Self.leastNormalMagnitude.exponent),
      let emax = Int(exactly: Self.greatestFiniteMagnitude.exponent),
      tiny == emin &- (precision &- 1) && emin >= -16382 && emax <= 16383
    else {
      preconditionFailure("Unsupported binary floating-point format.")
    }
    return (precision, emin, emax)
  }

  /// Returns this value's magnitude as `m * 2**e`, with the highest bit of `m`
  /// always set. The value must be finite and nonzero.
  @inlinable
  internal func _unpack(precision: Int) -> (m: UInt128, e: Int) {
    assert(isFinite && !isZero)
    assert(precision == Self.significandBitCount &+ 1)
    let shift = 128 &- precision
    let m = 1 &<< 127 | (UInt128(significand.significandBitPattern) &<< shift)
    return (m, Int(exponent) &- 127)
  }

  /// Creates a new binary floating-point value from the given decimal
  /// floating-point value, rounding to the nearest representable value
  /// (ties to even) if needed.
  ///
  /// This initializer implements the `convertFormat` operation defined by the
  /// IEEE 754 specification (other than reporting status flags).
  ///
  /// - Parameters:
  ///   - source: The decimal floating-point value to convert.
  /// - Precondition: The binary format has 2 through 113 bits of significand
  ///   precision, normal exponent range within `-16382...16383`, and gradual
  ///   underflow.
  @inlinable
  public init(nearest source: Decimal128) {
    let format = Self._format
    guard source._isFiniteNonzero else {
      if source.isNaN {
#if CompliantPayload
        // IEEE standard convention.
        let mask = UInt128(
          truncatingIfNeeded: Self.greatestFiniteMagnitude.significandBitPattern
            & ~Self.nan.significandBitPattern)
#else
        // Swift convention, masking out an additional bit.
        let mask = UInt128(
          truncatingIfNeeded: Self.greatestFiniteMagnitude.significandBitPattern
            & ~(Self.nan.significandBitPattern
              | Self.signalingNaN.significandBitPattern))
#endif
        let payload = source._trailingSignificandBitPattern
        guard payload < ._1e33 && payload & ~mask == 0 else {
          self = source._isSignMinus ? -.nan : .nan
          return
        }
        self.init(
          sign: source.sign,
          exponentBitPattern: Self.nan.exponentBitPattern,
          significandBitPattern:
            Self.nan.significandBitPattern | .init(truncatingIfNeeded: payload))
        return
      }
      if source.isInfinite {
        self = source._isSignMinus ? -.infinity : .infinity
        return
      }
      self = source._isSignMinus ? -.zero : .zero
      return
    }
    let abs: Self
    (abs, _) = _Cox.parse(
      source.significandBitPattern,
      Int(source.exponentBitPattern) &- 6176,
      precision: format.precision,
      emin: format.emin,
      emax: format.emax)
    self = source._isSignMinus ? -abs : abs
  }
}

@available(anyAppleOS 26.0, *)
extension Decimal128 {
  @inlinable
  internal init?<T: BinaryFloatingPoint>(
    _shortest source: T,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) {
    let format = T._format
    guard source.isFinite && !source.isZero else {
      self.init(nearest: source, &flags)
      return
    }
    let (m, e) = source._unpack(precision: format.precision)
    let (d, p, inexact) =
      _Cox.short(m, e, precision: format.precision, emin: format.emin)
    guard d < ._1e34 && p >= -6176 && p <= 6111 else { return nil }
    if let inexact {
      if inexact { _signal(.inexact, into: &flags) }
    } else {
      // This is a somewhat costly check.
      let u = _Cox.uscale(m, _Cox.prescale(e, -p))
      if u != d &<< 2 { _signal(.inexact, into: &flags) }
    }
    self.init(
      sign: source.sign,
      exponentBitPattern: UInt(p &+ 6176),
      significandBitPattern: d)
  }

#if !((os(macOS) || targetEnvironment(macCatalyst)) && arch(x86_64))
  /// Creates a new decimal floating-point value with the fewest significant
  /// digits that converts back to the given binary floating-point value with
  /// rounding to the nearest representable value (ties to even).
  ///
  /// The result need not equal `source` exactly. To obtain instead a decimal
  /// floating-point value that is the nearest possible representable value to
  /// `source`, use `init(nearest:)`.
  ///
  ///     // `0.1` can't be represented exactly as `Double`;
  ///     // instead, it's rounded from a repeating binary fraction.
  ///     let x: Double = 0.1
  ///     Decimal128(shortest: x)  // 0.1
  ///     Decimal128(nearest: x)   // 0.1000000000000000055511151231257827
  ///
  /// - Parameters:
  ///   - source: The binary floating-point value to convert.
  @inline(always)
  public init(shortest source: Float16) {
    var flags: DecimalFloatingPointStatusFlags = []
    self.init(_shortest: source, &flags)!
  }

  /// Creates a new decimal floating-point value with the fewest significant
  /// digits that converts back to the given binary floating-point value with
  /// rounding to the nearest representable value (ties to even), accumulating
  /// status flags.
  ///
  /// The result need not equal `source` exactly. To obtain instead a decimal
  /// floating-point value that is the nearest possible representable value to
  /// `source`, use `init(nearest:)`.
  ///
  ///     // `0.1` can't be represented exactly as `Double`;
  ///     // instead, it's rounded from a repeating binary fraction.
  ///     let x: Double = 0.1
  ///     Decimal128(shortest: x)  // 0.1
  ///     Decimal128(nearest: x)   // 0.1000000000000000055511151231257827
  ///
  /// - Parameters:
  ///   - source: The binary floating-point value to convert.
  ///   - flags: A value that accumulates decimal floating-point arithmetic
  ///     status flags.
  @inline(always)
  public init(
    shortest source: Float16,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) {
    self.init(_shortest: source, &flags)!
  }
#endif

  /// Creates a new decimal floating-point value with the fewest significant
  /// digits that converts back to the given binary floating-point value with
  /// rounding to the nearest representable value (ties to even).
  ///
  /// The result need not equal `source` exactly. To obtain instead a decimal
  /// floating-point value that is the nearest possible representable value to
  /// `source`, use `init(nearest:)`.
  ///
  ///     // `0.1` can't be represented exactly as `Double`;
  ///     // instead, it's rounded from a repeating binary fraction.
  ///     let x: Double = 0.1
  ///     Decimal128(shortest: x)  // 0.1
  ///     Decimal128(nearest: x)   // 0.1000000000000000055511151231257827
  ///
  /// - Parameters:
  ///   - source: The binary floating-point value to convert.
  @inline(always)
  public init(shortest source: Float) {
    var flags: DecimalFloatingPointStatusFlags = []
    self.init(_shortest: source, &flags)!
  }

  /// Creates a new decimal floating-point value with the fewest significant
  /// digits that converts back to the given binary floating-point value with
  /// rounding to the nearest representable value (ties to even), accumulating
  /// status flags.
  ///
  /// The result need not equal `source` exactly. To obtain instead a decimal
  /// floating-point value that is the nearest possible representable value to
  /// `source`, use `init(nearest:)`.
  ///
  ///     // `0.1` can't be represented exactly as `Double`;
  ///     // instead, it's rounded from a repeating binary fraction.
  ///     let x: Double = 0.1
  ///     Decimal128(shortest: x)  // 0.1
  ///     Decimal128(nearest: x)   // 0.1000000000000000055511151231257827
  ///
  /// - Parameters:
  ///   - source: The binary floating-point value to convert.
  ///   - flags: A value that accumulates decimal floating-point arithmetic
  ///     status flags.
  @inline(always)
  public init(
    shortest source: Float,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) {
    self.init(_shortest: source, &flags)!
  }

  /// Creates a new decimal floating-point value with the fewest significant
  /// digits that converts back to the given binary floating-point value with
  /// rounding to the nearest representable value (ties to even).
  ///
  /// The result need not equal `source` exactly. To obtain instead a decimal
  /// floating-point value that is the nearest possible representable value to
  /// `source`, use `init(nearest:)`.
  ///
  ///     // `0.1` can't be represented exactly as `Double`;
  ///     // instead, it's rounded from a repeating binary fraction.
  ///     let x: Double = 0.1
  ///     Decimal128(shortest: x)  // 0.1
  ///     Decimal128(nearest: x)   // 0.1000000000000000055511151231257827
  ///
  /// - Parameters:
  ///   - source: The binary floating-point value to convert.
  @inline(always)
  public init(shortest source: Double) {
    var flags: DecimalFloatingPointStatusFlags = []
    self.init(_shortest: source, &flags)!
  }

  /// Creates a new decimal floating-point value with the fewest significant
  /// digits that converts back to the given binary floating-point value with
  /// rounding to the nearest representable value (ties to even), accumulating
  /// status flags.
  ///
  /// The result need not equal `source` exactly. To obtain instead a decimal
  /// floating-point value that is the nearest possible representable value to
  /// `source`, use `init(nearest:)`.
  ///
  ///     // `0.1` can't be represented exactly as `Double`;
  ///     // instead, it's rounded from a repeating binary fraction.
  ///     let x: Double = 0.1
  ///     Decimal128(shortest: x)  // 0.1
  ///     Decimal128(nearest: x)   // 0.1000000000000000055511151231257827
  ///
  /// - Parameters:
  ///   - source: The binary floating-point value to convert.
  ///   - flags: A value that accumulates decimal floating-point arithmetic
  ///     status flags.
  @inline(always)
  public init(
    shortest source: Double,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) {
    self.init(_shortest: source, &flags)!
  }
}

@available(anyAppleOS 26.0, *)
extension Decimal128 {
  @inlinable
  internal init<T: BinaryFloatingPoint>(
    _nearest source: T,
    rounding rule: _DecimalFloatingPointRoundingRule,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) {
    let format = T._format
    if source.isNaN {
      if source.isSignalingNaN { _signal(.invalid, into: &flags) }
#if CompliantPayload
      // IEEE standard convention.
      let mask = ~T.nan.significandBitPattern
#else
      // Swift convention, masking out an additional bit.
      let mask =
        ~(T.nan.significandBitPattern | T.signalingNaN.significandBitPattern)
#endif
      let payload =
        UInt128(truncatingIfNeeded: source.significandBitPattern & mask)
      self.init(nan: payload < ._1e33 ? payload : 0, signaling: false)
      if source.sign == .minus { negate() }
      return
    }
    if source.isInfinite {
      self = source.sign == .minus ? -.infinity : .infinity
      return
    }
    if source.isZero {
      self = source.sign == .minus ? -Self() : Self()
      return
    }
    let (m, e) = source._unpack(precision: format.precision)
    var d: UInt128
    let p: Int
    let inexact: Bool
    (d, p, inexact) =
      _Cox.fixed(width: 34, isSignMinus: source.sign == .minus, m, e, rule)
    var biasedExponent = p &+ 6176
    if inexact {
      _signal(.inexact, into: &flags)
    } else {
      Self._select(
        biasedExponent: &biasedExponent,
        nonzeroSignificand: &d,
        boundedPreferredBiasedExponent: 6176)
    }
    self.init(
      sign: source.sign,
      exponentBitPattern: UInt(biasedExponent),
      significandBitPattern: d)
  }

  /// Creates a new decimal floating-point value from the given binary
  /// floating-point value, rounding to the nearest representable value
  /// (ties to even) if needed.
  ///
  /// For an exact finite result, the represented exponent is as close to zero
  /// as possible without changing the value.
  ///
  /// This initializer implements the `convertFormat` operation defined by
  /// the IEEE 754 specification.
  ///
  /// To obtain instead a decimal floating-point value with the fewest
  /// significant digits that converts back to `source`, use `init(shortest:)`
  /// with an argument of type `Float16`, `Float`, or `Double`.
  ///
  ///     // `0.1` can't be represented exactly as `Double`;
  ///     // instead, it's rounded from a repeating binary fraction.
  ///     let x: Double = 0.1
  ///     Decimal128(nearest: x)   // 0.1000000000000000055511151231257827
  ///     Decimal128(shortest: x)  // 0.1
  ///
  /// - Parameters:
  ///   - source: The binary floating-point value to convert.
  /// - Precondition: The binary format has 2 through 113 bits of significand
  ///   precision, normal exponent range within `-16382...16383`, and gradual
  ///   underflow.
  @inline(always)
  public init<T: BinaryFloatingPoint>(nearest source: T) {
    var flags: DecimalFloatingPointStatusFlags = []
    self.init(_nearest: source, rounding: .toNearestOrEven, &flags)
  }

  /// Creates a new decimal floating-point value from the given binary
  /// floating-point value, rounding to the nearest representable value
  /// (ties to even) if needed and accumulating status flags.
  ///
  /// For an exact finite result, the represented exponent is as close to zero
  /// as possible without changing the value.
  ///
  /// This initializer implements the `convertFormat` operation defined by
  /// the IEEE 754 specification.
  ///
  /// To obtain instead a decimal floating-point value with the fewest
  /// significant digits that converts back to `source`, use `init(shortest:)`
  /// with an argument of type `Float16`, `Float`, or `Double`.
  ///
  ///     // `0.1` can't be represented exactly as `Double`;
  ///     // instead, it's rounded from a repeating binary fraction.
  ///     let x: Double = 0.1
  ///     Decimal128(nearest: x)   // 0.1000000000000000055511151231257827
  ///     Decimal128(shortest: x)  // 0.1
  ///
  /// - Parameters:
  ///   - source: The binary floating-point value to convert.
  ///   - flags: A value that accumulates decimal floating-point arithmetic
  ///     status flags.
  /// - Precondition: The binary format has 2 through 113 bits of significand
  ///   precision, normal exponent range within `-16382...16383`, and gradual
  ///   underflow.
  @inline(always)
  public init<T: BinaryFloatingPoint>(
    nearest source: T,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) {
    self.init(_nearest: source, rounding: .toNearestOrEven, &flags)
  }

  /// Creates a new decimal floating-point value from the given binary
  /// floating-point value, rounding to a representable value using the given
  /// rounding rule if needed.
  ///
  /// For an exact finite result, the represented exponent is as close to zero
  /// as possible without changing the value.
  ///
  /// This initializer implements the `convertFormat` operation defined by
  /// the IEEE 754 specification.
  ///
  /// To obtain instead a decimal floating-point value with the fewest
  /// significant digits that converts back to `source`, use `init(shortest:)`
  /// with an argument of type `Float16`, `Float`, or `Double`.
  ///
  ///     // `0.1` can't be represented exactly as `Double`;
  ///     // instead, it's rounded from a repeating binary fraction.
  ///     let x: Double = 0.1
  ///     Decimal128(nearest: x)   // 0.1000000000000000055511151231257827
  ///     Decimal128(shortest: x)  // 0.1
  ///
  /// - Parameters:
  ///   - source: The binary floating-point value to convert.
  ///   - rule: The rounding rule to use for an inexact result.
  /// - Precondition: The binary format has 2 through 113 bits of significand
  ///   precision, normal exponent range within `-16382...16383`, and gradual
  ///   underflow.
  @inlinable
  public init<T: BinaryFloatingPoint>(
    nearest source: T,
    rounding rule: FloatingPointRoundingRule
  ) {
    var flags: DecimalFloatingPointStatusFlags = []
    self.init(_nearest: source, rounding: .init(rule), &flags)
  }

  /// Creates a new decimal floating-point value from the given binary
  /// floating-point value, rounding to a representable value using the given
  /// rounding rule if needed and accumulating status flags.
  ///
  /// For an exact finite result, the represented exponent is as close to zero
  /// as possible without changing the value.
  ///
  /// This initializer implements the `convertFormat` operation defined by
  /// the IEEE 754 specification.
  ///
  /// To obtain instead a decimal floating-point value with the fewest
  /// significant digits that converts back to `source`, use `init(shortest:)`
  /// with an argument of type `Float16`, `Float`, or `Double`.
  ///
  ///     // `0.1` can't be represented exactly as `Double`;
  ///     // instead, it's rounded from a repeating binary fraction.
  ///     let x: Double = 0.1
  ///     Decimal128(nearest: x)   // 0.1000000000000000055511151231257827
  ///     Decimal128(shortest: x)  // 0.1
  ///
  /// - Parameters:
  ///   - source: The binary floating-point value to convert.
  ///   - rule: The rounding rule to use for an inexact result.
  ///   - flags: A value that accumulates decimal floating-point arithmetic
  ///     status flags.
  /// - Precondition: The binary format has 2 through 113 bits of significand
  ///   precision, normal exponent range within `-16382...16383`, and gradual
  ///   underflow.
  @inlinable
  public init<T: BinaryFloatingPoint>(
    nearest source: T,
    rounding rule: FloatingPointRoundingRule,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) {
    self.init(_nearest: source, rounding: .init(rule), &flags)
  }

  /// Creates a new decimal floating-point value from the given binary
  /// floating-point value, if it can be represented exactly.
  ///
  /// For an exact finite result, the represented exponent is as close to zero
  /// as possible without changing the value. If `source` is NaN or can't be
  /// represented exactly after conversion, the result is `nil`.
  ///
  /// - Parameters:
  ///   - source: The binary floating-point value to convert.
  /// - Precondition: The binary format has 2 through 113 bits of significand
  ///   precision, normal exponent range within `-16382...16383`, and gradual
  ///   underflow.
  @inline(always)
  public init?<T: BinaryFloatingPoint>(exactly source: T) {
    if source.isNaN { return nil } 
    var flags: DecimalFloatingPointStatusFlags = []
    self.init(nearest: source, &flags)
    if flags.contains(.inexact) { return nil }
  }
}

@available(anyAppleOS 26.0, *)
extension UInt64 {
  @usableFromInline
  internal static let _asciiDigits: [100 of (UInt8, UInt8)] = [
    (0x30, 0x30), (0x30, 0x31), (0x30, 0x32), (0x30, 0x33), (0x30, 0x34),
    (0x30, 0x35), (0x30, 0x36), (0x30, 0x37), (0x30, 0x38), (0x30, 0x39),
    (0x31, 0x30), (0x31, 0x31), (0x31, 0x32), (0x31, 0x33), (0x31, 0x34),
    (0x31, 0x35), (0x31, 0x36), (0x31, 0x37), (0x31, 0x38), (0x31, 0x39),
    (0x32, 0x30), (0x32, 0x31), (0x32, 0x32), (0x32, 0x33), (0x32, 0x34),
    (0x32, 0x35), (0x32, 0x36), (0x32, 0x37), (0x32, 0x38), (0x32, 0x39),
    (0x33, 0x30), (0x33, 0x31), (0x33, 0x32), (0x33, 0x33), (0x33, 0x34),
    (0x33, 0x35), (0x33, 0x36), (0x33, 0x37), (0x33, 0x38), (0x33, 0x39),
    (0x34, 0x30), (0x34, 0x31), (0x34, 0x32), (0x34, 0x33), (0x34, 0x34),
    (0x34, 0x35), (0x34, 0x36), (0x34, 0x37), (0x34, 0x38), (0x34, 0x39),
    (0x35, 0x30), (0x35, 0x31), (0x35, 0x32), (0x35, 0x33), (0x35, 0x34),
    (0x35, 0x35), (0x35, 0x36), (0x35, 0x37), (0x35, 0x38), (0x35, 0x39),
    (0x36, 0x30), (0x36, 0x31), (0x36, 0x32), (0x36, 0x33), (0x36, 0x34),
    (0x36, 0x35), (0x36, 0x36), (0x36, 0x37), (0x36, 0x38), (0x36, 0x39),
    (0x37, 0x30), (0x37, 0x31), (0x37, 0x32), (0x37, 0x33), (0x37, 0x34),
    (0x37, 0x35), (0x37, 0x36), (0x37, 0x37), (0x37, 0x38), (0x37, 0x39),
    (0x38, 0x30), (0x38, 0x31), (0x38, 0x32), (0x38, 0x33), (0x38, 0x34),
    (0x38, 0x35), (0x38, 0x36), (0x38, 0x37), (0x38, 0x38), (0x38, 0x39),
    (0x39, 0x30), (0x39, 0x31), (0x39, 0x32), (0x39, 0x33), (0x39, 0x34),
    (0x39, 0x35), (0x39, 0x36), (0x39, 0x37), (0x39, 0x38), (0x39, 0x39),
  ]

  @unsafe
  @inlinable
  @inline(always)
  @discardableResult
  internal func _ascii(
    _ span: inout MutableRawSpan,
    uncheckedEndOffset: Int? = nil
  ) -> Int {
    var value = self
    var offset = uncheckedEndOffset ?? span.byteCount
    if value == 0 {
      offset &-= 1
      unsafe span.storeBytes(
        of: 0x30 /* '0' */,
        toUncheckedByteOffset: offset,
        as: UInt8.self)
    } else {
      while value >= 10 {
        offset &-= 2
        let r: Self
        (value, r) = value.quotientAndRemainder(dividingBy: 100)
        unsafe span.storeBytes(
          of: Self._asciiDigits[unchecked: Int(truncatingIfNeeded: r)],
          toUncheckedByteOffset: offset,
          as: (UInt8, UInt8).self)
      }
      if value != 0 {
        offset &-= 1
        unsafe span.storeBytes(
          of: UInt8(truncatingIfNeeded: value) | 0x30,
          toUncheckedByteOffset: offset,
          as: UInt8.self)
      }
    }
    return offset
  }
}

@available(anyAppleOS 26.0, *)
extension Decimal128: CustomStringConvertible {
  @inlinable
  internal func _description(_ buffer: inout MutableRawSpan) -> Range<Int> {
    precondition(isFinite && buffer.byteCount >= 46)
    // The longest description requires only 42 bytes,
    // but we reserve six bytes before the significand for prefix '-0.000'
    // and we reserve six bytes after it for the exponent (e.g., 'e+6144').
    //
    // It is the caller's responsibility to prefill the first 46 bytes of
    // `buffer` with ASCII '0'.
    assert((0..<46).allSatisfy { offset in buffer[offset] == 48 /* '0' */ })

    let g = _combinationBitPattern
    var c = bitPattern & (1 &<< 113 &- 1)
    // Noncanonical zero (cf. `_canonical`).
    if g >= 0x18000 || c >= ._1e34 { c = 0 }

    var endOffset = 40
    var startOffset: Int
    if c <= 0xFFFF_FFFF_FFFF_FFFF /* UInt64.max */ {
      startOffset = unsafe UInt64(truncatingIfNeeded: c)
        ._ascii(&buffer, uncheckedEndOffset: endOffset)
    } else {
      let (q, r) = c._quotientAndRemainder(dividingBy1e: 19)
      unsafe UInt64(truncatingIfNeeded: r)
        ._ascii(&buffer, uncheckedEndOffset: endOffset)
      startOffset = unsafe UInt64(truncatingIfNeeded: q)
        ._ascii(&buffer, uncheckedEndOffset: endOffset &- 19)
    }
    let count = endOffset &- startOffset
    let quantumExponent = Int(exponentBitPattern) &- 6176
    let exponent = quantumExponent &+ count &- 1
    let separatorOffset: Int?
    if quantumExponent <= 0 && exponent >= 0 && exponent < 16 {
      separatorOffset = quantumExponent == 0 ? nil : startOffset &+ exponent
    } else if exponent >= -4 && exponent < 0 {
      startOffset &+= exponent &- 1
      unsafe buffer[unchecked: startOffset &+ 1] = 46 /* '.' */
      separatorOffset = nil
    } else {
      // Scientific notation.
      separatorOffset = count == 1 ? nil : startOffset
      unsafe buffer[unchecked: endOffset] = 101 /* 'e' */
      unsafe buffer[unchecked: endOffset &+ 1] =
        exponent < 0 ? 45 /* '-' */ : 43 /* '+' */
      let x = UInt64(exponent.magnitude)
      endOffset &+=
        3 &+ (x >= 10 ? 1 : 0) &+ (x >= 100 ? 1 : 0) &+ (x >= 1000 ? 1 : 0)
      unsafe x._ascii(&buffer, uncheckedEndOffset: endOffset)
    }
    if let separatorOffset {
      for i in startOffset...separatorOffset {
        unsafe buffer[unchecked: i &- 1] = buffer[unchecked: i]
      }
      startOffset &-= 1
      unsafe buffer[unchecked: separatorOffset] = 46 /* '.' */
    }
    if _isSignMinus {
      startOffset &-= 1
      unsafe buffer[unchecked: startOffset] = 45 /* '-' */
    }
    return startOffset..<endOffset
  }

  /// A textual representation of this value.
  ///
  /// Finite values retain their quantum, including trailing zeros.
  ///
  /// This property implements the `convertToDecimalCharacter` operation
  /// defined by the IEEE 754 specification.
  @inlinable
  public var description: String {
    if isNaN {
      if isSignalingNaN { _signal(.invalid) }
      return "nan"
    }
    if isInfinite {
      return _isSignMinus ? "-inf" : "inf"
    }
    if magnitude.bitPattern == Self().bitPattern {
      return _isSignMinus ? "-0" : "0"
    }
    var scratch = [46 of UInt8](repeating: 48 /* '0' */)
    var buffer_ = scratch.mutableSpan
    var buffer = buffer_.mutableBytes
    let range = _description(&buffer)
    _ = consume buffer
    let utf8 = unsafe UTF8Span(
      unchecked: buffer_.span.extracting(range),
      isKnownASCII: true)
    return String(copying: utf8)
  }
}

@available(anyAppleOS 26.0, *)
extension Decimal128: CustomDebugStringConvertible {
  /// A textual representation of this value, suitable for debugging.
  ///
  /// Finite values retain their quantum, including trailing zeros.
  /// This property distinguishes quiet and signaling NaNs, preserves their
  /// sign, and includes any nonzero canonical payload.
  ///
  /// This property implements the `convertToDecimalCharacter` operation
  /// defined by the IEEE 754 specification.
  @inlinable
  public var debugDescription: String {
    if isNaN {
      let t = _trailingSignificandBitPattern
      if t == 0 || t >= ._1e33 {
        if isSignalingNaN {
          return _isSignMinus ? "-snan" : "snan"
        }
        return _isSignMinus ? "-nan" : "nan"
      }
      return withTemporaryAllocation(of: UInt8.self, capacity: 37) { output in
        if _isSignMinus {
          output.append( 45 /* '-' */)
        }
        if isSignalingNaN {
          output.append(115 /* 's' */)
        }
        output.append(  110 /* 'n' */)
        output.append(   97 /* 'a' */)
        output.append(  110 /* 'n' */)
        output.append(   40 /* '(' */)
        output.append(   48 /* '0' */)
        output.append(  120 /* 'x' */)
        var i = (127 &- t.leadingZeroBitCount) & ~3
        repeat {
          let x = UInt8(truncatingIfNeeded: t &>> i) & 15
          output.append(x &+ (x < 10 ? 48 : 87))
          i &-= 4
        } while i >= 0
        output.append(   41 /* ')' */)
        let utf8 = unsafe UTF8Span(unchecked: output.span, isKnownASCII: true)
        return String(copying: utf8)
      }
    }
    return description
  }
}

@available(anyAppleOS 26.0, *)
extension Decimal128: LosslessStringConvertible {
  @usableFromInline
  internal static func _parse(
    utf8: Span<UInt8>,
    rounding rule: _DecimalFloatingPointRoundingRule,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) -> Decimal128? {
    let count = utf8.count
    guard count != 0 else { return nil }
    guard count <= (Int.max / 10) &- 6256 else { return nil }
    // See `limit` below for derivation of this upper bound.
    // TODO: Consider if we want to support ludicrously large strings.
    var index = 0

    // Get the sign.
    var isSignMinus = false
    var codeUnit = unsafe utf8[unchecked: index]
    if codeUnit == 43 /* '+' */ || codeUnit == 45 /* '-' */ {
      isSignMinus = codeUnit == 45
      index &+= 1
      guard index != count else { return nil }
      codeUnit = unsafe utf8[unchecked: index]
    }

    // Handle infinity and NaN.
    codeUnit |= 0x20
    if codeUnit == 105 || codeUnit == 110 || codeUnit == 115 /* 'i' 'n' 's' */ {
      @inline(always)
      func starts(with prefix: StaticString) -> Bool {
        prefix.withUTF8Buffer {
          guard count &- index >= $0.count else { return false }
          for i in 0..<$0.count {
            if unsafe (utf8[unchecked: index &+ i] | 0x20) != $0[i] {
              return false
            }
          }
          return true
        }
      }
      let abs: Self
      if codeUnit == 105 {
        guard
          (count &- index == 3 && starts(with: "inf")) ||
          (count &- index == 8 && starts(with: "infinity"))
        else {
          return nil
        }
        abs = .infinity
      } else {
        let signaling: Bool
        if starts(with: "nan") {
          signaling = false
          index &+= 3
        } else if starts(with: "snan") {
          signaling = true
          index &+= 4
        } else {
          return nil
        }
        var payload: UInt128 = 0
        if index != count {
          guard
            count &- index >= 2,
            unsafe utf8[unchecked: index] == 40 /* '(' */,
            unsafe utf8[unchecked: count &- 1] == 41 /* ')' */
          else {
            return nil
          }
          index &+= 1
          let end = count &- 1
          var radix: UInt8 = 10
          if end &- index >= 2, unsafe utf8[unchecked: index] == 48 /* '0' */ {
            if unsafe (utf8[unchecked: index &+ 1] | 0x20) == 120 /* 'x' */ {
              radix = 16
              index &+= 2
            } else {
              radix = 8
              index &+= 1
            }
          }
          let (a, b) = radix > 10 ? (9, radix &- 11) : (radix &- 1, 0)
          while index != end {
            codeUnit = unsafe utf8[unchecked: index]
            var digit = codeUnit &- 48 /* '0' */
            if digit > a {
              if radix > 10 {
                digit = (codeUnit | 0x20) &- 97 /* 'a' */
                if digit > b {
                  return nil
                }
                digit &+= 10
              } else {
                return nil
              }
            }
            payload = min(._1e33, payload &* UInt128(radix) &+ UInt128(digit))
            index &+= 1
          }
        }
        abs = Self(nan: payload == ._1e33 ? 0 : payload, signaling: signaling)
      }
      return isSignMinus ? -abs : abs
    }

    // Build the significand and exponent.
    var digitCount = 0
    var significand: UInt128
    var guardDigit: UInt8
    var sticky = false
    var biasedExponent = 6176

    @inline(always)
    func read() -> UInt32? {
      guard count &- index >= 4 else { return nil }
      let tetrad = unsafe utf8.bytes.unsafeLoadUnaligned(
        fromUncheckedByteOffset: index,
        as: UInt32.self)
      // Little endian only by policy.
      assert(tetrad == UInt32(littleEndian: tetrad))
      // Ensure all bytes of the tetrad are contained in '0'...'9'.
      guard
        ((tetrad &+ 0x4646_4646) | (tetrad &- 0x3030_3030)) & 0x8080_8080 == 0
      else { return nil }
      index &+= 4
      return tetrad
    }

    @inline(always)
    func consumeDigits(into chunk: inout UInt64, limit: Int, fraction: Bool) {
      while digitCount <= limit &- 4, let tetrad = read() {
        // Obtain all four digits represented by `tetrad` at once.
        // If the digits represented by `tetrad` are "1234", then:
        //
        //     x = 0x04_03_02_01
        //            |  |  |  |
        //            d  c  b  a
        let x = tetrad &- 0x3030_3030 /* '0000' */
        // Compute `ab = 10 * a + b` and `cd = 10 * c + d` in bytes 0 and 2.
        //
        //     y = 0x00_22_00_0c
        let y = ((x &* 0x0a01) &>> 8) & 0x00ff_00ff
        // Compute `digits = 100 * ab + cd`.
        let digits = UInt64((y &* 0x0064_0001) &>> 16)
        chunk = chunk &* 10000 &+ digits
        if digitCount != 0 {
          digitCount &+= 4
        } else if digits != 0 {
          // Ignore initial leading zeros.
          digitCount = digits >= 100
            ? digits >= 1000 ? 4 : 3
            : digits >=   10 ? 2 : 1
        }
        // Decrement exponent for each fractional digit.
        if fraction { biasedExponent &-= 4 }
      }
    }

    @inline(always)
    func digit(_ codeUnit: UInt8) -> UInt8? {
      let digit = codeUnit &- 48 /* '0' */
      return digit < 10 ? digit : nil
    }

    if count &- index <= 19 {
      var significand_: UInt64 = 0

      let anchor = index
      consumeDigits(into: &significand_, limit: 19, fraction: false)
      while index != count, let d = digit(unsafe utf8[unchecked: index]) {
        index &+= 1
        if digitCount == 0 && d == 0 { continue }
        significand_ = significand_ &* 10 &+ UInt64(d)
        digitCount &+= 1
      }
      let hasIntegerPart = index != anchor
      if index != count, unsafe utf8[unchecked: index] == 46 /* '.' */ {
        index &+= 1
        let anchor = index
        consumeDigits(into: &significand_, limit: 19, fraction: true)
        while index != count, let d = digit(unsafe utf8[unchecked: index]) {
          index &+= 1
          // Decrement exponent if a fractional digit.
          biasedExponent &-= 1
          if digitCount == 0 && d == 0 { continue }
          significand_ = significand_ &* 10 &+ UInt64(d)
          digitCount &+= 1
        }
        let hasFractionalPart = index != anchor
        guard hasIntegerPart || hasFractionalPart else { return nil }
      } else {
        guard hasIntegerPart else { return nil }
      }
      significand = UInt128(significand_)
      guardDigit = 0
    } else {
      var leading: UInt64 = 0
      var trailing: UInt64 = 0
      var next: UInt8? = nil

      @inline(always)
      func consume(_ digit: UInt8, into chunk: inout UInt64, fraction: Bool) {
        // Decrement exponent if a fractional digit.
        if fraction { biasedExponent &-= 1 }
        if digitCount == 0 && digit == 0 { return }
        chunk = chunk &* 10 &+ UInt64(digit)
        digitCount &+= 1
      }

      let anchor = index
      integer: do {
        consumeDigits(into: &leading, limit: 19, fraction: false)
        while digitCount < 19 {
          guard index != count, let d = digit(unsafe utf8[unchecked: index])
          else { break integer }
          consume(d, into: &leading, fraction: false)
          index &+= 1
        }
        consumeDigits(into: &trailing, limit: 34, fraction: false)
        while digitCount < 34 {
          guard index != count, let d = digit(unsafe utf8[unchecked: index])
          else { break integer }
          consume(d, into: &trailing, fraction: false)
          index &+= 1
        }
        if next == nil {
          guard index != count, let d = digit(unsafe utf8[unchecked: index])
          else { break integer }
          next = d
          biasedExponent &+= 1
          index &+= 1
        }
        let anchor = index
        while let tetrad = read() {
          if tetrad != 0x3030_3030 /* '0000' */ { sticky = true }
        }
        while index != count, let d = digit(unsafe utf8[unchecked: index]) {
          if d != 0 { sticky = true }
          index &+= 1
        }
        biasedExponent &+= index &- anchor
      }
      let hasIntegerPart = index != anchor
      if index != count, unsafe utf8[unchecked: index] == 46 /* '.' */ {
        index &+= 1
        let anchor = index
        fractional: do {
          consumeDigits(into: &leading, limit: 19, fraction: true)
          while digitCount < 19 {
            guard index != count, let d = digit(unsafe utf8[unchecked: index])
            else { break fractional }
            consume(d, into: &leading, fraction: true)
            index &+= 1
          }
          consumeDigits(into: &trailing, limit: 34, fraction: true)
          while digitCount < 34 {
            guard index != count, let d = digit(unsafe utf8[unchecked: index])
            else { break fractional }
            consume(d, into: &trailing, fraction: true)
            index &+= 1
          }
          if next == nil {
            guard index != count, let d = digit(unsafe utf8[unchecked: index])
            else { break fractional }
            next = d
            index &+= 1
          }
          while let tetrad = read() {
            if tetrad != 0x3030_3030 /* '0000' */ { sticky = true }
          }
          while index != count, let d = digit(unsafe utf8[unchecked: index]) {
            if d != 0 { sticky = true }
            index &+= 1
          }
        }
        let hasFractionalPart = index != anchor
        guard hasIntegerPart || hasFractionalPart else { return nil }
      } else {
        guard hasIntegerPart else { return nil }
      }
      if digitCount <= 19 {
        significand = UInt128(leading)
      } else {
        significand =
          unsafe UInt128(leading) &* ._exp10[unchecked: digitCount &- 19]
            &+ UInt128(trailing)
      }
      guardDigit = next ?? 0
    }

    if index != count, unsafe (utf8[unchecked: index] | 0x20) == 101 /* 'e' */ {
      index &+= 1
      var isExponentSignMinus = false
      if index != count {
        codeUnit = unsafe utf8[unchecked: index]
        if codeUnit == 43 /* '+' */ || codeUnit == 45 /* '-' */ {
          isExponentSignMinus = codeUnit == 45
          index &+= 1
        }
      }
      // A limit sufficient for saturation to guarantee overflow or underflow.
      let limit = count &+ 6255
      let anchor = index
      var x = 0
      while index != count, let d = digit(unsafe utf8[unchecked: index]) {
        x = min(limit, x &* 10 &+ Int(d))
        index &+= 1
      }
      guard index != anchor else { return nil }
      if isExponentSignMinus {
        biasedExponent &-= x
      } else {
        biasedExponent &+= x
      }
    }
    guard index == count else { return nil }

    if digitCount == 0 {
      biasedExponent = min(12287, max(biasedExponent, 0))
      let abs =
        Self(bitPattern: UInt128(truncatingIfNeeded: biasedExponent) &<< 113)
      return isSignMinus ? -abs : abs
    }

    var isKnownTiny = false
    if biasedExponent < -34 {
      isKnownTiny = true
      significand = 0
      guardDigit = 0
      sticky = true
      biasedExponent = 0
    } else if biasedExponent < 0 {
      isKnownTiny = true
      let n = -biasedExponent
      let r: UInt128
      (significand, r) = significand._quotientAndRemainder(dividingBy1e: n)
      let half: UInt128 = unsafe ._exp10[unchecked: n] &>> 1
      if guardDigit != 0 || (r != 0 && r != half) {
        sticky = true
      }
      guardDigit = r >= half ? 5 : 0
      biasedExponent = 0
    } else if biasedExponent > 12287 {
      let n = biasedExponent &- 12287
      guard n <= 34 &- digitCount else {
        return ._overflow(isSignMinus: isSignMinus, rule, &flags)
      }
      significand &*= unsafe ._exp10[unchecked: n]
      assert(guardDigit == 0 && !sticky)
      biasedExponent = 12287
    }

    if guardDigit != 0 || sticky {
      // Inexact.
      if Self._roundsAway(
        isSignMinus: isSignMinus,
        significand: significand,
        digit: guardDigit,
        sticky: sticky,
        rule
      ) {
        if significand == ._1e34 &- 1 {
          if biasedExponent == 12287 {
            _signal(.overflowInexact, into: &flags)
            return isSignMinus ? -.infinity : .infinity
          }
          significand = ._1e33
          biasedExponent &+= 1
        } else {
          significand &+= 1
        }
      }
      // `isKnownTiny == true` for all *inexact* tiny values.
      if isKnownTiny {
        _signal(.underflowInexact, into: &flags)
      } else {
        _signal(.inexact, into: &flags)
      }
    }
    let abs = Self(
      bitPattern: UInt128(truncatingIfNeeded: biasedExponent) &<< 113
        | significand)
    return isSignMinus ? -abs : abs
  }

  @inlinable
  internal init?<T: StringProtocol>(
    _ description: borrowing T,
    _rounding rule: _DecimalFloatingPointRoundingRule,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) {
    let x: Self?? = description.utf8.withContiguousStorageIfAvailable {
      unsafe ._parse(utf8: $0.span, rounding: rule, &flags)
    }
    let y: Self?
    if let x {
      y = x
    } else {
      var string = String(copy description)
      y = string.withUTF8 {
        unsafe ._parse(utf8: $0.span, rounding: rule, &flags)
      }
    }
    if let y {
      self = y
      return
    }
    return nil
  }

  /// Creates a new value from the given string representation,
  /// rounding to the nearest representable value (ties to even) if needed.
  ///
  /// The string passed as `description` may begin with an optional plus (`+`)
  /// or hyphen-minus (`-`) sign character, followed by a significand that must
  /// have at least one numeric digit (`0`-`9`) and may have a decimal separator
  /// period (`.`), followed optionally by an exponent introduced by `e` or `E`.
  ///
  /// Case-insensitive `inf` (or `infinity`), `nan`, and `snan` are also
  /// accepted following an optional sign character (denoting infinity, quiet
  /// NaN, and signaling NaN, respectively). NaN payloads may be specified in
  /// parentheses.
  ///
  /// If `description` is in an invalid format, the result is `nil`.
  /// For an exact finite result, the written quantum is retained when possible.
  ///
  /// This initializer implements the `convertFromDecimalCharacter` operation
  /// defined by the IEEE 754 specification.
  ///
  /// - Parameters:
  ///   - description: The ASCII string representation to convert.
  @inline(always)
  public init?<T: StringProtocol>(_ description: T) {
    var flags: DecimalFloatingPointStatusFlags = []
    self.init(description, _rounding: .toNearestOrEven, &flags)
  }

  /// Creates a new value from the given string representation,
  /// rounding to the nearest representable value (ties to even) if needed
  /// and accumulating status flags.
  ///
  /// The string passed as `description` may begin with an optional plus (`+`)
  /// or hyphen-minus (`-`) sign character, followed by a significand that must
  /// have at least one numeric digit (`0`-`9`) and may have a decimal separator
  /// period (`.`), followed optionally by an exponent introduced by `e` or `E`.
  ///
  /// Case-insensitive `inf` (or `infinity`), `nan`, and `snan` are also
  /// accepted following an optional sign character (denoting infinity, quiet
  /// NaN, and signaling NaN, respectively). NaN payloads may be specified in
  /// parentheses.
  ///
  /// If `description` is in an invalid format, the result is `nil`.
  /// For an exact finite result, the written quantum is retained when possible.
  ///
  /// This initializer implements the `convertFromDecimalCharacter` operation
  /// defined by the IEEE 754 specification.
  ///
  /// - Parameters:
  ///   - description: The ASCII string representation to convert.
  ///   - flags: A value that accumulates decimal floating-point arithmetic
  ///     status flags.
  @inline(always)
  public init?<T: StringProtocol>(
    _ description: T,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) {
    self.init(description, _rounding: .toNearestOrEven, &flags)
  }

  /// Creates a new value from the given string representation,
  /// rounding to a representable value using the given rounding rule if needed.
  ///
  /// The string passed as `description` may begin with an optional plus (`+`)
  /// or hyphen-minus (`-`) sign character, followed by a significand that must
  /// have at least one numeric digit (`0`-`9`) and may have a decimal separator
  /// period (`.`), followed optionally by an exponent introduced by `e` or `E`.
  ///
  /// Case-insensitive `inf` (or `infinity`), `nan`, and `snan` are also
  /// accepted following an optional sign character (denoting infinity, quiet
  /// NaN, and signaling NaN, respectively). NaN payloads may be specified in
  /// parentheses.
  ///
  /// If `description` is in an invalid format, the result is `nil`.
  /// For an exact finite result, the written quantum is retained when possible.
  ///
  /// This initializer implements the `convertFromDecimalCharacter` operation
  /// defined by the IEEE 754 specification.
  ///
  /// - Parameters:
  ///   - description: The ASCII string representation to convert.
  ///   - rule: The rounding rule to use for an inexact result.
  @inline(always)
  public init?<T: StringProtocol>(
    _ description: T,
    rounding rule: FloatingPointRoundingRule
  ) {
    var flags: DecimalFloatingPointStatusFlags = []
    self.init(description, _rounding: .init(rule), &flags)
  }

  /// Creates a new value from the given string representation,
  /// rounding to a representable value using the given rounding rule if needed
  /// and accumulating status flags.
  ///
  /// The string passed as `description` may begin with an optional plus (`+`)
  /// or hyphen-minus (`-`) sign character, followed by a significand that must
  /// have at least one numeric digit (`0`-`9`) and may have a decimal separator
  /// period (`.`), followed optionally by an exponent introduced by `e` or `E`.
  ///
  /// Case-insensitive `inf` (or `infinity`), `nan`, and `snan` are also
  /// accepted following an optional sign character (denoting infinity, quiet
  /// NaN, and signaling NaN, respectively). NaN payloads may be specified in
  /// parentheses.
  ///
  /// If `description` is in an invalid format, the result is `nil`.
  /// For an exact finite result, the written quantum is retained when possible.
  ///
  /// This initializer implements the `convertFromDecimalCharacter` operation
  /// defined by the IEEE 754 specification.
  ///
  /// - Parameters:
  ///   - description: The ASCII string representation to convert.
  ///   - rule: The rounding rule to use for an inexact result.
  ///   - flags: A value that accumulates decimal floating-point arithmetic
  ///     status flags.
  @inline(always)
  public init?<T: StringProtocol>(
    _ description: T,
    rounding rule: FloatingPointRoundingRule,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) {
    self.init(description, _rounding: .init(rule), &flags)
  }
}
