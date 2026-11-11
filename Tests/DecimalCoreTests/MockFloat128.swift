@available(anyAppleOS 26.0, *)
struct MockFloat128: BinaryFloatingPoint {
  var bitPattern: UInt128

  init(bitPattern: UInt128) {
    self.bitPattern = bitPattern
  }
}

@available(anyAppleOS 26.0, *)
extension MockFloat128 {
  typealias RawExponent = UInt
  typealias RawSignificand = UInt128
  typealias Exponent = Int
  typealias Stride = Self

  static let significandBitCount = 112

  private static let _exponentBias: UInt = 16383
  private static let _specialExponent: UInt = 0x7fff
  private static let _fractionMask: UInt128 = (1 << significandBitCount) - 1
  private static let _signMask: UInt128 = 1 << (UInt128.bitWidth - 1)
  private static let _quietNaNBit: UInt128 = 1 << (significandBitCount - 1)

  init(
    sign: FloatingPointSign,
    exponentBitPattern: UInt,
    significandBitPattern: UInt128
  ) {
    let signBits = sign == .minus ? Self._signMask : 0
    let exponentBits = UInt128(exponentBitPattern & Self._specialExponent)
    bitPattern =
      signBits
      | (exponentBits << Self.significandBitCount)
      | (significandBitPattern & Self._fractionMask)
  }

  // `_Cox.parse` uses an integer literal for underflow to zero.
  init(integerLiteral value: Int) {
    guard value == 0 else {
      fatalError("Not implemented.")
    }
    self.init(bitPattern: 0)
  }

  var sign: FloatingPointSign {
    bitPattern & Self._signMask == 0 ? .plus : .minus
  }

  var exponentBitPattern: UInt {
    UInt(bitPattern >> Self.significandBitCount) & Self._specialExponent
  }

  var significandBitPattern: UInt128 {
    bitPattern & Self._fractionMask
  }

  static let infinity =
    Self(
      sign: .plus,
      exponentBitPattern: _specialExponent,
      significandBitPattern: 0)

  static let nan = Self(bitPattern: infinity.bitPattern | _quietNaNBit)

  static let signalingNaN =
    Self(bitPattern: infinity.bitPattern | (_quietNaNBit >> 1))

  static let leastNonzeroMagnitude = Self(bitPattern: 1)

  static let leastNormalMagnitude = Self(bitPattern: 1 << significandBitCount)

  static let greatestFiniteMagnitude =
    Self(
      sign: .plus,
      exponentBitPattern: _specialExponent - 1,
      significandBitPattern: _fractionMask)

  var isFinite: Bool { exponentBitPattern != Self._specialExponent }

  var isZero: Bool { (bitPattern & ~Self._signMask) == 0 }

  var isInfinite: Bool { !isFinite && significandBitPattern == 0 }

  var isNaN: Bool { !isFinite && significandBitPattern != 0 }

  var isSignalingNaN: Bool {
    isNaN && (significandBitPattern & Self._quietNaNBit) == 0
  }

  private var _subnormalShift: Int {
    let topBit =
      UInt128.bitWidth - 1 - significandBitPattern.leadingZeroBitCount
    return Self.significandBitCount - topBit
  }

  // We need implementations of these properties only for finite nonzero values.
  var exponent: Int {
    guard isFinite && !isZero else {
      fatalError("Not implemented.")
    }
    if exponentBitPattern == 0 {
      return 1 - Int(Self._exponentBias) - _subnormalShift
    }
    return Int(exponentBitPattern) - Int(Self._exponentBias)
  }

  var significand: Self {
    guard isFinite && !isZero else {
      fatalError("Not implemented.")
    }
    let fraction = exponentBitPattern == 0
      ? significandBitPattern << _subnormalShift
      : significandBitPattern
    // The initializer masks off the implicit leading 1 after a subnormal shift.
    return Self(
      sign: .plus,
      exponentBitPattern: Self._exponentBias,
      significandBitPattern: fraction)
  }

  mutating func negate() {
    bitPattern ^= Self._signMask
  }
}

@available(anyAppleOS 26.0, *)
extension MockFloat128 {
  init(floatLiteral value: Double) {
    fatalError("Not implemented.")
  }
  init(_ value: Int) {
    fatalError("Not implemented.")
  }
  init(_ value: Float) {
    fatalError("Not implemented.")
  }
  init(_ value: Double) {
    fatalError("Not implemented.")
  }
  init<T: BinaryInteger>(_ value: T) {
    fatalError("Not implemented.")
  }
  init?<T: BinaryInteger>(exactly value: T) {
    fatalError("Not implemented.")
  }
  init<T: BinaryFloatingPoint>(_ value: T) {
    fatalError("Not implemented.")
  }
  init?<T: BinaryFloatingPoint>(exactly value: T) {
    fatalError("Not implemented.")
  }
  init(sign: FloatingPointSign, exponent: Int, significand: Self) {
    fatalError("Not implemented.")
  }

  static var exponentBitCount: Int { fatalError("Not implemented.") }
  static var pi: Self { fatalError("Not implemented.") }
  var ulp: Self { fatalError("Not implemented.") }
  var nextUp: Self { fatalError("Not implemented.") }
  var magnitude: Self { fatalError("Not implemented.") }
  var binade: Self { fatalError("Not implemented.") }
  var significandWidth: Int { fatalError("Not implemented.") }
  var isNormal: Bool { fatalError("Not implemented.") }
  var isSubnormal: Bool { fatalError("Not implemented.") }
  var isCanonical: Bool { fatalError("Not implemented.") }

  static func + (lhs: Self, rhs: Self) -> Self {
    fatalError("Not implemented.")
  }
  static func - (lhs: Self, rhs: Self) -> Self {
    fatalError("Not implemented.")
  }
  static func * (lhs: Self, rhs: Self) -> Self {
    fatalError("Not implemented.")
  }
  static func / (lhs: Self, rhs: Self) -> Self {
    fatalError("Not implemented.")
  }
  static func *= (lhs: inout Self, rhs: Self) {
    fatalError("Not implemented.")
  }
  static func /= (lhs: inout Self, rhs: Self) {
    fatalError("Not implemented.")
  }
  mutating func formRemainder(dividingBy other: Self) {
    fatalError("Not implemented.")
  }
  mutating func formTruncatingRemainder(dividingBy other: Self) {
    fatalError("Not implemented.")
  }
  mutating func formSquareRoot() {
    fatalError("Not implemented.")
  }
  mutating func addProduct(_ lhs: Self, _ rhs: Self) {
    fatalError("Not implemented.")
  }
  mutating func round(_ rule: FloatingPointRoundingRule) {
    fatalError("Not implemented.")
  }

  func isEqual(to other: Self) -> Bool {
    fatalError("Not implemented.")
  }
  func isLess(than other: Self) -> Bool {
    fatalError("Not implemented.")
  }
  func isLessThanOrEqualTo(_ other: Self) -> Bool {
    fatalError("Not implemented.")
  }
  func hash(into hasher: inout Hasher) {
    fatalError("Not implemented.")
  }
  func distance(to other: Self) -> Self {
    fatalError("Not implemented.")
  }
  func advanced(by distance: Self) -> Self {
    fatalError("Not implemented.")
  }
}
