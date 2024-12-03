// Adapted from `DoubleWidth`.
//
// Copyright (c) 2017-2024 Apple Inc. and the Swift project authors.
// Licensed under Apache License v2.0 with Runtime Library Exception.

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
@frozen
public struct _UInt256: Sendable {
  @usableFromInline
  internal var _storage: (high: UInt128, low: UInt128)

  @_transparent
  public init(_ value: (high: UInt128, low: UInt128)) {
    _storage = value
  }

  @_transparent
  public init() {
    _storage = (0, 0)
  }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension _UInt256 {
  @_transparent
  public var high: UInt128 { _storage.high }

  @_transparent
  public var low: UInt128 { _storage.low }

  @_transparent
  public init(_ high: UInt128, _ low: UInt128) {
    self.init((high, low))
  }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension _UInt256: ExpressibleByIntegerLiteral {
  @_transparent
  public init(integerLiteral x: UInt128) {
    self.init((0, x))
  }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension _UInt256: CustomStringConvertible {
  @_transparent
  @usableFromInline
  internal func _quotientAndRemainderDividingBy10()
  -> (quotient: Self, remainder: Self) {
    let m = Self(
      (0xCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC, 0xCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCD))
    let q = multipliedFullWidth(by: m).high &>> 3
    let r = self &- q &* 10
    return (q, r)
  }

  @inlinable
  public var description: String {
    if high == 0 && low == 0 { return "0" }
    return withUnsafeTemporaryAllocation(of: UInt8.self, capacity: 78) { buff in
      var value = self, count = 0
      while value != 0 {
        let (q, r) = value._quotientAndRemainderDividingBy10()
        buff.initializeElement(
          at: count,
          to: 48 /* '0' */ &+ UInt8(truncatingIfNeeded: r.low))
        count += 1
        value = q
      }
      // Reverse the initialized elements of `buff`.
      var a = 0, b = count &- 1
      while a < b {
        buff.swapAt(a, b)
        b -= 1
        a += 1
      }
      return String(unsafeUninitializedCapacity: count) {
        return $0.initialize(fromContentsOf: buff[..<count])
      }
    }
  }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension _UInt256: CustomDebugStringConvertible {
  @inlinable
  public var debugDescription: String { "(\(high), \(low))" }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension _UInt256: Equatable {
  @_transparent
  public static func == (lhs: Self, rhs: Self) -> Bool {
    return lhs.high == rhs.high && lhs.low == rhs.low
  }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension _UInt256: Hashable {
  @inlinable
  public func hash(into hasher: inout Hasher) {
    hasher.combine(high)
    hasher.combine(low)
  }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension _UInt256: Comparable {
  @_transparent
  public static func < (lhs: Self, rhs: Self) -> Bool {
    return lhs.high < rhs.high || (lhs.high == rhs.high && lhs.low < rhs.low)
  }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension _UInt256: Numeric {
  @_transparent
  public var magnitude: Self { self }

  @_transparent
  public init<T: BinaryInteger>(_ source: T) {
    guard let result = Self(exactly: source) else {
      preconditionFailure("Value is outside representable range")
    }
    self = result
  }

  @_transparent
  public init?<T: BinaryInteger>(exactly source: T) {
    guard source >= (0 as T) else { return nil }

    if let low = UInt128(exactly: source) {
      self.init(0, low)
    } else {
      guard let high = UInt128(exactly: source >> 128) else { return nil }
      let low = UInt128(source & T(UInt128.max))
      self.init(high, low)
    }
  }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension _UInt256 {
  @frozen
  public struct Words: Sendable {
    @usableFromInline
    internal var _value: _UInt256

    @_transparent
    public init(_ value: _UInt256) {
      precondition(Int.bitWidth <= 128, "Access to words is unsupported on this platform")
      _value = value
    }
  }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension _UInt256.Words: RandomAccessCollection {
  @_transparent
  public var startIndex: Int { 0 }

  @_transparent
  public var endIndex: Int { count }

  @_transparent
  public var count: Int { (255 &+ UInt.bitWidth) / UInt.bitWidth }

  public subscript(_ i: Int) -> UInt {
    @_transparent get {
      precondition(i >= 0 && i < endIndex, "Index out of range")
      var value = _value
      value &>>= _UInt256(0, UInt128(i &* UInt.bitWidth))
      return UInt(truncatingIfNeeded: value.low)
    }
  }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension _UInt256: FixedWidthInteger {
  @_transparent
  public static var bitWidth: Int { 256 }

  @_transparent
  public static var isSigned: Bool { false }

  @_transparent
  public static var max: Self { Self(UInt128.max, UInt128.max) }

  @_transparent
  public static var min: Self { Self() }

  @_transparent
  public func addingReportingOverflow(
    _ other: Self
  ) -> (partialValue: Self, overflow: Bool) {
    let (sum0, overflow0) = low.addingReportingOverflow(other.low)
    let (sum1, overflow1) = high.addingReportingOverflow(other.high)
    let result = (sum1 &+ (overflow0 ? 1 : 0), sum0)
    let overflow = overflow1 || sum1 == UInt128.max && overflow0
    return (partialValue: Self(result), overflow: overflow)
  }

  @_transparent
  public func subtractingReportingOverflow(
    _ other: Self
  ) -> (partialValue: Self, overflow: Bool) {
    let (diff0, overflow0) = low.subtractingReportingOverflow(other.low)
    let (diff1, overflow1) = high.subtractingReportingOverflow(other.high)
    let result = (diff1 &- (overflow0 ? 1 : 0), diff0)
    let overflow = overflow1 || diff1 == 0 && overflow0
    return (partialValue: Self(result), overflow: overflow)
  }

  @_transparent
  public func multipliedReportingOverflow(
    by other: Self
  ) -> (partialValue: Self, overflow: Bool) {
    let (carry, partialValue) = multipliedFullWidth(by: other)
    return (partialValue, carry != 0)
  }

  @inlinable
  public func quotientAndRemainder(
    dividingBy other: Self
  ) -> (quotient: Self, remainder: Self) {
    guard other != 0 else { fatalError("Division by zero") }

    guard other < self else {
      return other == self ? (1, 0) : (0, self)
    }

    guard high != 0 else {
      let (q, r) = low.quotientAndRemainder(dividingBy: other.low)
      return (Self(0, q), Self(0, r))
    }

    guard other.high != 0 else {
      let (q1, r1) = high.quotientAndRemainder(dividingBy: other.low)
      let (q0, r0) = r1 == 0
        ? low.quotientAndRemainder(dividingBy: other.low)
        : other.low.dividingFullWidth((r1, low))
      return (Self(q1, q0), Self(0, r0))
    }

    // Left shift both operands, then divide and right shift the remainder:
    let shift = other.leadingZeroBitCount
    guard shift != 0 else {
      return (1, self &- other)
    }

    let u2 = (self &>> (256 &- shift)).low, u1u0 = self &<< shift
    let v = other &<< shift
    // Estimate the quotient.
    var quotient = u2 == v.high
      ? UInt128.max
      : v.high.dividingFullWidth((u2, u1u0.high)).quotient
    // Compute quotient * rhs.
    let p00 = quotient.multipliedFullWidth(by: v.low)
    let p01 = quotient.multipliedFullWidth(by: v.high)
    let (sum, overflow) = p00.high.addingReportingOverflow(p01.low)
    let product =
      (high: Self(0, p01.high &+ (overflow ? 1 : 0)), low: Self(sum, p00.low))
    // Compute the remainder after decrementing quotient as necessary.
    var remainder = (high: Self(0, u2), low: u1u0)
    while remainder < product {
      quotient &-= 1
      let (low, overflow) = remainder.low.addingReportingOverflow(v)
      remainder.low = low
      if overflow { remainder.high &+= 1 }
    }
    do {
      let (low, overflow) =
        remainder.low.subtractingReportingOverflow(product.low)
      remainder = (remainder.high &- product.high &- (overflow ? 1 : 0), low)
    }
    return (Self(0, quotient), remainder.low &>> shift)
  }

  @_transparent
  public func dividedReportingOverflow(
    by other: Self
  ) -> (partialValue: Self, overflow: Bool) {
    return other == 0
      ? (self, true)
      : (quotientAndRemainder(dividingBy: other).quotient, false)
  }

  @_transparent
  public func remainderReportingOverflow(
    dividingBy other: Self
  ) -> (partialValue: Self, overflow: Bool) {
    return other == 0
      ? (self, true)
      : (quotientAndRemainder(dividingBy: other).remainder, false)
  }

  @_transparent
  public func multipliedFullWidth(
    by other: Self
  ) -> (high: Self, low: Self) {
    let p00 = low.multipliedFullWidth(by: other.low)
    let p10 = high.multipliedFullWidth(by: other.low)
    let p01 = low.multipliedFullWidth(by: other.high)
    let p11 = high.multipliedFullWidth(by: other.high)

    let (sum1, overflow1) = p00.high.addingReportingOverflow(p10.low)
    let (sum2, overflow2) = sum1.addingReportingOverflow(p01.low)
    let low = Self(sum2, p00.low)
    // Given `let x = Self(UInt128.max)`, then `x + x + (x * x) == Self.max`.
    // Thus, `Self(p00.high) + Self(p10.low) + Self(p01)` can never overflow,
    // and so neither can the following sum:
    let sum3 = p01.high &+ (overflow1 ? 1 : 0) &+ (overflow2 ? 1 : 0)
    let (sum4, overflow4) = sum3.addingReportingOverflow(p10.high)
    let (sum5, overflow5) = sum4.addingReportingOverflow(p11.low)
    let sum6 = p11.high &+ (overflow4 ? 1 : 0) &+ (overflow5 ? 1 : 0)
    let high = Self(sum6, sum5)

    return (high, low)
  }

  public func dividingFullWidth(
    _ dividend: (high: Self, low: Self)
  ) -> (quotient: Self, remainder: Self) {
    fatalError("Not implemented")
  }

  @_transparent
  public static func &= (lhs: inout Self, rhs: Self) {
    lhs._storage.low &= rhs.low
    lhs._storage.high &= rhs.high
  }

  @_transparent
  public static func |= (lhs: inout Self, rhs: Self) {
    lhs._storage.low |= rhs.low
    lhs._storage.high |= rhs.high
  }

  @_transparent
  public static func ^= (lhs: inout Self, rhs: Self) {
    lhs._storage.low ^= rhs.low
    lhs._storage.high ^= rhs.high
  }

  @_transparent
  public static func <<= (lhs: inout Self, rhs: Self) {
    if rhs.high != 0 || rhs.low >= 256 {
      lhs = 0
      return
    }
    lhs &<<= rhs
  }

  @_transparent
  public static func >>= (lhs: inout Self, rhs: Self) {
    if rhs.high != 0 || rhs.low >= 256 {
      lhs = 0
      return
    }
    lhs &>>= rhs
  }

  @_transparent
  public static func &<<= (lhs: inout Self, rhs: Self) {
    let shift = rhs.low & 255
    guard shift < 128 else {
      lhs._storage.high = lhs.low &<< (shift &- 128)
      lhs._storage.low = 0
      return
    }
    guard shift != 0 else { return }
    lhs._storage.high &<<= shift
    lhs._storage.high |= lhs.low &>> (128 &- shift)
    lhs._storage.low &<<= shift
  }

  @_transparent
  public static func &>>= (lhs: inout Self, rhs: Self) {
    let shift = rhs.low & 255
    guard shift < 128 else {
      lhs._storage.low = lhs.high &>> (shift &- 128)
      lhs._storage.high = 0
      return
    }
    guard shift != 0 else { return }
    lhs._storage.low &>>= shift
    lhs._storage.low |= lhs.high &<< (128 &- shift)
    lhs._storage.high &>>= shift
  }

  @_transparent
  public static func + (lhs: Self, rhs: Self) -> Self {
    var lhs = lhs
    lhs += rhs
    return lhs
  }

  @_transparent
  public static func += (lhs: inout Self, rhs: Self) {
    let (result, overflow) = lhs.addingReportingOverflow(rhs)
    precondition(!overflow, "Overflow in +=")
    lhs = result
  }

  @_transparent
  public static func - (lhs: Self, rhs: Self) -> Self {
    var lhs = lhs
    lhs -= rhs
    return lhs
  }

  @_transparent
  public static func -= (lhs: inout Self, rhs: Self) {
    let (result, overflow) = lhs.subtractingReportingOverflow(rhs)
    precondition(!overflow, "Overflow in -=")
    lhs = result
  }

  @_transparent
  public static func * (lhs: Self, rhs: Self) -> Self {
    var lhs = lhs
    lhs *= rhs
    return lhs
  }

  @_transparent
  public static func *= (lhs: inout Self, rhs: Self) {
    let (result, overflow) = lhs.multipliedReportingOverflow(by:rhs)
    precondition(!overflow, "Overflow in *=")
    lhs = result
  }

  @_transparent
  public static func / (lhs: Self, rhs: Self) -> Self {
    var lhs = lhs
    lhs /= rhs
    return lhs
  }

  @_transparent
  public static func /= (lhs: inout Self, rhs: Self) {
    let (result, overflow) = lhs.dividedReportingOverflow(by: rhs)
    precondition(!overflow, "Overflow in /=")
    lhs = result
  }

  @_transparent
  public static func % (lhs: Self, rhs: Self) -> Self {
    var lhs = lhs
    lhs %= rhs
    return lhs
  }

  @_transparent
  public static func %= (lhs: inout Self, rhs: Self) {
    let (result, overflow) = lhs.remainderReportingOverflow(dividingBy: rhs)
    precondition(!overflow, "Overflow in %=")
    lhs = result
  }

  @_transparent
  public static func &+ (lhs: Self, rhs: Self) -> Self {
    let (low, carry) = lhs.low.addingReportingOverflow(rhs.low)
    let high = lhs.high &+ rhs.high &+ (carry ? 1 : 0)
    return Self(high, low)
  }

  @_transparent
  public static func &- (lhs: Self, rhs: Self) -> Self {
    let (low, borrow) = lhs.low.subtractingReportingOverflow(rhs.low)
    let high = lhs.high &- rhs.high &- (borrow ? 1 : 0)
    return Self(high, low)
  }

  @_transparent
  public static func &* (lhs: Self, rhs: Self) -> Self {
    let p00 = lhs.low.multipliedFullWidth(by: rhs.low)
    let p10 = lhs.high &* rhs.low
    let p01 = lhs.low &* rhs.high
    return Self(p10 &+ p01 &+ p00.high, p00.low)
  }

  @_transparent
  public var leadingZeroBitCount: Int {
    return high == 0
      ? 128 &+ low.leadingZeroBitCount
      : high.leadingZeroBitCount
  }

  @_transparent
  public var trailingZeroBitCount: Int {
    return low == 0
      ? 128 &+ high.trailingZeroBitCount
      : low.trailingZeroBitCount
  }

  @_transparent
  public var nonzeroBitCount: Int {
    return high.nonzeroBitCount &+ low.nonzeroBitCount
  }

  @_transparent
  public var byteSwapped: Self { Self(low.byteSwapped, high.byteSwapped) }

  @_transparent
  public var words: Words { Words(self) }

  @_transparent
  public init(_truncatingBits bits: UInt) {
    _storage.low = UInt128(_truncatingBits: bits)
    _storage.high = UInt128(_truncatingBits: bits >> 128)
  }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension _UInt256: UnsignedInteger { }

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension _UInt256 {
  @inlinable
  internal var _commonLogarithm: Int {
    // See comment in `UInt128._commonLogarithm`.
    let estimate = ((77 &* (255 &- (self|1).leadingZeroBitCount)) &>> 8) &+ 1
    return self >= _UInt256._exp10(estimate) ? estimate : estimate &- 1
  }

  @inlinable
  internal static func _exp10(_ n: Int) -> Self {
    precondition(n < 78, "Overflow in _exp10")
    let table: [UInt64] = [
                               1,
                              10,
                             100,
                           1_000,
                          10_000,
                         100_000,
                       1_000_000,
                      10_000_000,
                     100_000_000,
                   1_000_000_000,
                  10_000_000_000,
                 100_000_000_000,
               1_000_000_000_000,
              10_000_000_000_000,
             100_000_000_000_000,
           1_000_000_000_000_000,
          10_000_000_000_000_000,
         100_000_000_000_000_000,
       1_000_000_000_000_000_000,
      10_000_000_000_000_000_000
    ]
    var n = n
    var m = 1 as _UInt256
    while n > 19 {
      n &-= 19
      m &*= 10_000_000_000_000_000_000
    }
    return n < 0 ? 0 : m &* _UInt256(0, UInt128(table[n]))
  }

  @inlinable
  internal func _quotientAndRemainderDividingBy1e38()
  -> (quotient: Self, remainder: Self) {
    let m = Self(0x3671F73B54F1C89565B9EF4, 0xD632412884B32926857A281A0E6A841B)
    let q = (self &>> 38).multipliedFullWidth(by: m).high &>> 50
    let r = self &- q &* 100_000_000_000_000_000_000_000_000_000_000_000_000
    return (q, r)
  }
}
