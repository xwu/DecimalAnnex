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
        if Self._roundsAway(
          isSignMinus: isSignMinus,
          significand: q,
          digit: r >= half ? 5 : 0,
          sticky: r != half,
          rule
        ) {
          if q == ._1e34 &- 1 {
            q = ._1e33
            e &+= 1
          } else {
            q &+= 1
          }
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

  @inline(always)
  public init<T: BinaryInteger>(_ source: T) {
    var flags: DecimalFloatingPointStatusFlags = []
    self.init(source, _rounding: .toNearestOrEven, &flags)
  }

  @inline(always)
  public init<T: BinaryInteger>(
    _ source: T,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) {
    self.init(source, _rounding: .toNearestOrEven, &flags)
  }

  @inline(always)
  public init<T: BinaryInteger>(
    _ source: T,
    rounding rule: FloatingPointRoundingRule
  ) {
    var flags: DecimalFloatingPointStatusFlags = []
    self.init(source, _rounding: .init(rule), &flags)
  }

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
extension Decimal128 {
#if false
  public init?(exactly source: Float16) {
    if source.isNaN {
      if source.isSignalingNaN { _signal(.invalid) }
      return nil
    }
    if source.isInfinite {
      self = source < 0 ? -.infinity : .infinity
      return
    }
    if source.isZero {
      self = source.sign == .minus ? -Self() : Self()
      return
    }

    if source.isSubnormal {
      // ...
    }
    fatalError("Not implemented")
  }

  public init?(exactly source: Float) {
    fatalError("Not implemented")
  }

  public init?(exactly source: Double) {
    fatalError("Not implemented")
  }
#endif

  public init?<T: BinaryFloatingPoint>(exactly source: T) {
    fatalError("Not implemented")
  }

#if false
  public init(_ source: Float16) {
    fatalError("Not implemented")
  }

  public init(_ source: Float) {
    fatalError("Not implemented")
  }

  public init(_ source: Double) {
    fatalError("Not implemented")
  }
#endif

  public init<T: BinaryFloatingPoint>(_ source: T) {
    fatalError("Not implemented")
  }

  // TODO: Conversion from `Decimal128` to floating point.
}

@available(anyAppleOS 26.0, *)
extension Decimal128: CustomStringConvertible {
  public var description: String {
    guard _isFiniteNonzero else {
      if isSignalingNaN {
        _signal(.invalid)
        return _isSignMinus ? "-nan" : "nan"
      }

      if isNaN {
        return _isSignMinus ? "-nan" : "nan"
      }

      if isInfinite {
        return _isSignMinus ? "-inf" : "inf"
      }

      // TODO: Decide if we want to preserve quantum.
      return _isSignMinus ? "-0." : "0."
    }

    // TODO: Re-implement.
    return String(unsafeUninitializedCapacity: 42) { buffer in
      // We'll keep track of the index of the first uninitialized element, which
      // we'll need to eventually return as the intiailized count.
      var index: Int

      if _isSignMinus {
        unsafe buffer.initializeElement(at: 0, to: 45 /* '-' */)
        index = 1
      } else {
        index = 0
      }

      // Since noncanonical significands are treated as zero, and values where
      // the combination field begins `11...` have noncanonical significands,
      // by this point we know that the represented significand is in the lower
      // 113 bits.
      var string = String(bitPattern & (1 &<< 113 &- 1))
      let count = string.utf8.count

      // We compute the exponent right away to determine if we need special
      // handling for the significand.
      let exponent = Int(_combinationBitPattern &>> 3) - 6176 + count - 1

      if exponent >= 0 && exponent < min(count, 16) {
        let x = exponent + 1
        string.withUTF8 {
          index = unsafe buffer[index...].initialize(fromContentsOf: $0[..<x])
          unsafe buffer.initializeElement(at: index, to: 46 /* '.' */)
          if x == count {
            index += 1
          } else {
            index =
              unsafe buffer[(index + 1)...].initialize(fromContentsOf: $0[x...])
          }
        }
        return index
      }

      if exponent < 0 && exponent >= -4 {
        unsafe buffer.initializeElement(at: index, to: 48 /* '0' */)
        unsafe buffer.initializeElement(at: index + 1, to: 46 /* '.' */)
        index =
          unsafe buffer[(index + 2)...].initialize(
            fromContentsOf: repeatElement(48 /* '0' */, count: -(exponent + 1)))
        string.withUTF8 {
          index = unsafe buffer[index...].initialize(fromContentsOf: $0)
        }
        return index
      }

      string.withUTF8 {
        unsafe buffer.initializeElement(at: index, to: $0[0])
        if count == 1 {
          index += 1
        } else {
          unsafe buffer.initializeElement(at: index + 1, to: 46 /* '.' */)
          index =
            unsafe buffer[(index + 2)...].initialize(fromContentsOf: $0[1...])
        }
      }
      unsafe buffer.initializeElement(at: index, to: 101 /* 'e' */)
      unsafe buffer.initializeElement(
        at: index + 1,
        to: exponent < 0 ? 45 /* '-' */ : 43 /* '+' */)
      string = String(abs(exponent))
      string.withUTF8 {
        index = unsafe buffer[(index + 2)...].initialize(fromContentsOf: $0)
      }
      return index
    }
  }
}

@available(anyAppleOS 26.0, *)
extension Decimal128: LosslessStringConvertible {
  @inlinable
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
    func digit(_ codeUnit: UInt8) -> UInt8? {
      let digit = codeUnit &- 48 /* '0' */
      return digit < 10 ? digit : nil
    }

    if count &- index <= 19 {
      var significand_: UInt64 = 0

      let anchor = index
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
        while digitCount < 19 {
          guard index != count, let d = digit(unsafe utf8[unchecked: index])
          else { break integer }
          consume(d, into: &leading, fraction: false)
          index &+= 1
        }
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
          while digitCount < 19 {
            guard index != count, let d = digit(unsafe utf8[unchecked: index])
            else { break fractional }
            consume(d, into: &leading, fraction: true)
            index &+= 1
          }
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
    _ description: T,
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
      var string = String(description)
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

  @inline(always)
  public init?<T: StringProtocol>(_ description: T) {
    var flags: DecimalFloatingPointStatusFlags = []
    self.init(description, _rounding: .toNearestOrEven, &flags)
  }

  @inline(always)
  public init?<T: StringProtocol>(
    _ description: T,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) {
    self.init(description, _rounding: .toNearestOrEven, &flags)
  }

  @inline(always)
  public init?<T: StringProtocol>(
    _ description: T,
    rounding rule: FloatingPointRoundingRule
  ) {
    var flags: DecimalFloatingPointStatusFlags = []
    self.init(description, _rounding: .init(rule), &flags)
  }

  @inline(always)
  public init?<T: StringProtocol>(
    _ description: T,
    rounding rule: FloatingPointRoundingRule,
    _ flags: inout DecimalFloatingPointStatusFlags
  ) {
    self.init(description, _rounding: .init(rule), &flags)
  }
}
