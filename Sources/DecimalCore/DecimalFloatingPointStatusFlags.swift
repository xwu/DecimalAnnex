/// IEEE 754 status flags for decimal floating-point arithmetic.
@frozen
public struct DecimalFloatingPointStatusFlags:
  OptionSet, BitwiseCopyable, Sendable {
  public let rawValue: UInt8

  @inline(always)
  public init(rawValue: UInt8) {
    self.rawValue = rawValue
  }

  /// Invalid operation.
  ///
  /// This status flag is raised if there is no "usefully definable" result.
  /// For example: 0 × ∞ or ∞ ÷ ∞.
  @inline(always)
  public static var invalid: Self { Self(rawValue: 1) }

  /// Division by zero.
  ///
  /// This status flag is raised for an exact infinite result from finite
  /// operands. For example: 1 ÷ 0.
  @inline(always)
  public static var divisionByZero: Self { Self(rawValue: 2) }

  /// Overflow.
  ///
  /// This status flag is raised when the magnitude of a result would be greater
  /// than the greatest finite magnitude. In accordance with IEEE 754 "default
  /// exception handling" rules, the `.inexact` status flag is also raised.
  ///
  /// Overflow is determined *after* rounding the notional exact result to the
  /// destination precision with unbounded exponent range.
  ///
  /// See also: ``.overflowInexact``
  @inline(always)
  public static var overflow: Self { Self(rawValue: 4) }

  /// Underflow.
  ///
  /// This status flag is raised when the magnitude of an inexact result would
  /// be less than the least normal magnitude. In accordance with IEEE 754
  /// "default exception handling" rules, the `.inexact` status flag is also
  /// raised; note that neither status flag is raised for an exact result.
  ///
  /// Underflow is determined *before* rounding the notional exact result with
  /// unbounded precision and exponent range.
  ///
  /// See also: ``.underflowInexact``
  @inline(always)
  public static var underflow: Self { Self(rawValue: 8) }

  /// Inexact.
  ///
  /// This status flag is raised for a rounded result that differs from the
  /// notional exact result with unbounded precision and exponent range. For
  /// example: the result of 1 ÷ 3.
  @inline(always)
  public static var inexact: Self { Self(rawValue: 16) }

  /// Overflow and inexact.
  ///
  /// See also: ``.overflow``, ``.inexact``
  @inline(always)
  public static var overflowInexact: Self { [.overflow, .inexact] }

  /// Underflow and inexact.
  ///
  /// See also: ``.underflow``, ``.inexact``
  @inline(always)
  public static var underflowInexact: Self { [.underflow, .inexact] }
}

@inlinable
internal func _signal(_: DecimalFloatingPointStatusFlags) {
  // No-op (for now).
}

@inlinable
internal func _signal(
  _ status: DecimalFloatingPointStatusFlags,
  into flags: inout DecimalFloatingPointStatusFlags
) {
  flags.formUnion(status)
}
