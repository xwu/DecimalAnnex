@frozen
public struct DecimalFloatingPointStatusFlags:
  OptionSet, BitwiseCopyable, Sendable {
  public let rawValue: UInt8

  @inline(always)
  public init(rawValue: UInt8) {
    self.rawValue = rawValue
  }

  @inline(always)
  public static var invalid: Self { Self(rawValue: 1) }

  @inline(always)
  public static var divisionByZero: Self { Self(rawValue: 2) }

  @inline(always)
  public static var overflow: Self { Self(rawValue: 4) }

  @inline(always)
  public static var underflow: Self { Self(rawValue: 8) }

  @inline(always)
  public static var inexact: Self { Self(rawValue: 16) }

  @inline(always)
  public static var overflowInexact: Self { [.overflow, .inexact] }

  @inline(always)
  public static var underflowInexact: Self { [.underflow, .inexact] }
}

@inlinable
internal func _signal(_: DecimalFloatingPointStatusFlags) {
  // No-op (for now).
}
