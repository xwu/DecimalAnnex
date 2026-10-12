@frozen
public struct DecimalFloatingPointStatusFlags:
  OptionSet, BitwiseCopyable, Sendable {
  public let rawValue: UInt8

  public init(rawValue: UInt8) {
    self.rawValue = rawValue
  }

  public static let invalid: Self          = Self(rawValue:  1)
  public static let divisionByZero: Self   = Self(rawValue:  2)
  public static let overflow: Self         = Self(rawValue:  4)
  public static let underflow: Self        = Self(rawValue:  8)
  public static let inexact: Self          = Self(rawValue: 16)

  public static let overflowInexact: Self  = [.overflow, .inexact]
  public static let underflowInexact: Self = [.underflow, .inexact]
}

@inlinable
internal func _signal(_: DecimalFloatingPointStatusFlags) {
  // No-op (for now).
}

@inlinable
internal func _signal(_: DecimalFloatingPointStatusFlags, `default`: Bool) -> Bool {
  // No-op (for now).
  return `default`
}

@inlinable
internal func _signal(_: DecimalFloatingPointStatusFlags, `default`: String) -> String {
  // No-op (for now).
  return `default`
}

@inlinable
internal func _signal<T: Numeric>(_: DecimalFloatingPointStatusFlags, `default`: T) -> T {
  // No-op (for now).
  return `default`
}
