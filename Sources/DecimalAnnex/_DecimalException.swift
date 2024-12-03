@frozen
public struct _DecimalException: OptionSet {
  public let rawValue: UInt8

  public init(rawValue: UInt8) {
    self.rawValue = rawValue
  }

  public static let invalid: _DecimalException          = Self(rawValue:  1)
  public static let divisionByZero: _DecimalException   = Self(rawValue:  2)
  public static let overflow: _DecimalException         = Self(rawValue:  4)
  public static let underflow: _DecimalException        = Self(rawValue:  8)
  public static let inexact: _DecimalException          = Self(rawValue: 16)

  public static let overflowInexact: _DecimalException  = [.overflow, .inexact]
  public static let underflowInexact: _DecimalException = [.underflow, .inexact]
}

@inlinable
internal func _signal(_: _DecimalException) {
  // No-op (for now).
}

@inlinable
internal func _signal(_: _DecimalException, `default`: Bool) -> Bool {
  // No-op (for now).
  return `default`
}

@inlinable
internal func _signal(_: _DecimalException, `default`: String) -> String {
  // No-op (for now).
  return `default`
}

@inlinable
internal func _signal<T: Numeric>(_: _DecimalException, `default`: T) -> T {
  // No-op (for now).
  return `default`
}
