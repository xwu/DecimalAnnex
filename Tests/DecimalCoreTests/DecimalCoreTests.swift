import Testing
@testable import DecimalCore

struct DecimalCoreTests {
  @Test
  @available(anyAppleOS 26.0, *)
  func testDPD() {
    let fixture: [(decoded: UInt16, encoded: UInt16)] = [
      // Collated from online sources.
      (decoded:   5, encoded: 0b000_000_0101),
      (decoded:   9, encoded: 0b000_000_1001),
      (decoded:  55, encoded: 0b000_101_0101),
      (decoded:  63, encoded: 0b000_110_0011),
      (decoded:  79, encoded: 0b000_111_1001),
      (decoded:  80, encoded: 0b000_000_1010),
      (decoded:  90, encoded: 0b000_001_1010),
      (decoded:  98, encoded: 0b000_101_1110),
      (decoded:  99, encoded: 0b000_101_1111),
      (decoded: 555, encoded: 0b101_101_0101),
      (decoded: 592, encoded: 0b101_011_1010),
      (decoded: 879, encoded: 0b110_011_1111),
      (decoded: 941, encoded: 0b001_100_1101),
      (decoded: 986, encoded: 0b111_000_1110),
      (decoded: 999, encoded: 0b001_111_1111),
    ]
    for (d, e) in fixture {
      #expect(d == _DPD.decode(e))
      #expect(_DPD.encode(d) == e)
    }

    // Public conversion (cf. dqEncode.decTest).
    let x = Decimal128("-7.50")!
    let pattern: UInt128 = 0xa207_8000_0000_0000_0000_0000_0000_03d0
    #expect(x.decimalEncoding == pattern)
    #expect(Decimal128(decimalEncoding: pattern) == x)
    #expect(Decimal128(decimalEncoding: pattern).hasSameQuantum(as: x))

    let nan: UInt128 = 0xfe00_4000_0000_0000_0000_0000_0000_03ff // Noncanonical.
    #expect(Decimal128(decimalEncoding: nan).bitPattern
            == (-Decimal128(nan: 999, signaling: true)).bitPattern)
    #expect(Decimal128(nan: 1, signaling: true).decimalEncoding
            == 0x7e00_0000_0000_0000_0000_0000_0000_0001)
  }

  @Test
  @available(anyAppleOS 26.0, *)
  func testLog10() {
    for _ in 0...65535 {
      let x = UInt128.random(in: 0...UInt128.max)
      #expect(x._commonLogarithm == String(x).count - 1)
    }
  }

  @Test
  @available(anyAppleOS 26.0, *)
  func testPi() {
    let x = Decimal128.pi
    #expect(x.description == "3.141592653589793238462643383279503")
  }

  @Test
  @available(anyAppleOS 26.0, *)
  func testNextUp() {
    var x: Decimal128 = 1
    #expect(x.nextUp == Decimal128(binaryEncoding: 0x2ffe_314d_c644_8d93_38c1_5b0a_0000_0001))
    #expect(x.nextUp == x + Decimal128("1e-33")!)

    x = Decimal128(signOf: -1, magnitudeOf: 0)
    #expect(x.nextUp == .leastNonzeroMagnitude)

    x = -1
    #expect(x.nextUp == Decimal128(binaryEncoding: 0xaffd_ed09_bead_87c0_378d_8e63_ffff_ffff))
    #expect(x.nextUp == x + Decimal128("1e-34")!)

    x = Decimal128("9999999999999999999999999999999999")!
    #expect(x.nextUp.bitPattern
            == Decimal128("1.000000000000000000000000000000000e34")!.bitPattern)

    #expect(Decimal128.greatestFiniteMagnitude.nextUp == .infinity)
    #expect((-Decimal128.infinity).nextUp == -.greatestFiniteMagnitude)

    let tiny = Decimal128.leastNonzeroMagnitude
    #expect(tiny.floatingPointClass == .positiveSubnormal)
    #expect(tiny.isCanonical)
    #expect(tiny.exponent == -6176)

    let normal = Decimal128("10e-6144")!
    #expect(normal.exponentBitPattern == 6176 - 6144)
    #expect(normal.isNormal)
  }

  @Test
  @available(anyAppleOS 26.0, *)
  func testExponentAndSignificand() {
    #expect(Decimal128("0e-6143")!.exponent == Int.min)
    #expect(Decimal128.infinity.exponent == Int.max)

    #expect(Decimal128("-12.30")!.significand.bitPattern
            == Decimal128("1.230")!.bitPattern)
  }

  @Test
  @available(anyAppleOS 26.0, *)
  func testULP() {
    let x = Decimal128.infinity
    #expect(x.ulp.isNaN)

    let gfm = Decimal128.greatestFiniteMagnitude
    #expect(gfm.ulp == Decimal128("1e6111")!)
    #expect(gfm.nextDown + gfm.ulp == gfm)
  }

  @Test
  @available(anyAppleOS 26.0, *)
  func testEquatableHashable() {
    let x = Decimal128(
      _sign: .minus,
      combinationBitPattern: 6177 << 3,
      trailingSignificandBitPattern: 10)
    let y = Decimal128(
      _sign: .minus,
      combinationBitPattern: 6178 << 3,
      trailingSignificandBitPattern: 1)

    #expect(x == y)
    #expect(!(x == -y))

    let one: Decimal128 = 1
    #expect(Decimal128("1.00")! == one)
    #expect(Decimal128("1.00")!.quantum < one.quantum)

    var set = Set<Decimal128>()
    set.insert(one)
    set.insert(Decimal128("1.00")!)
    #expect(set.count == 1)

    set.insert(0)
    #expect(set.count == 2)
    set.insert(Decimal128(
      sign: .minus,
      exponentBitPattern: 42,
      significandBitPattern: ._1e34)) // Noncanonical zero.
    #expect(set.count == 2)

    let inf = Decimal128(bitPattern: Decimal128.infinity.bitPattern | 1)
    #expect(inf == Decimal128.infinity)
    #expect(inf.hashValue == Decimal128.infinity.hashValue)
  }

  @Test
  @available(anyAppleOS 26.0, *)
  func testComparison() {
    #expect(Decimal128("0.00")! <= Decimal128("-0")!)
    #expect(-2 < Decimal128("-1.00")!)
    #expect(-2 != -Decimal128(nan: 2, signaling: true))
    #expect(-Decimal128.infinity < -1)
    #expect((2 as Decimal128) >= 1)

    let zero = Decimal128(
      sign: .plus,
      exponentBitPattern: 42,
      significandBitPattern: (1 << 113) | 7) // Non-canonical.
    let ninf = Decimal128(bitPattern: (-Decimal128.infinity).bitPattern | 1)
    let nan = -Decimal128(nan: 2, signaling: false)

    // Total order.
    let cases: [(x: Decimal128, y: Decimal128, result: Bool)] = [
      (-1, Decimal128("-1.00")!, true),
      (Decimal128("0.00")!, zero, false),
      (nan, nan, true),
      (Decimal128("1.00")!, 2, true),
      (2, 1, false),
      (.infinity, -.infinity, false),
      (-.infinity, ninf, true),
      (.signalingNaN, .nan, true),
    ]
    for c in cases {
      #expect(c.x.isTotallyOrdered(belowOrEqualTo: c.y) == c.result)
    }
  }

  @Test
  @available(anyAppleOS 26.0, *)
  func testAddingZero() {
    let x = Decimal128(
      _sign: .minus,
      combinationBitPattern: 6177 << 3,
      trailingSignificandBitPattern: 10)
    let y = Decimal128(
      _sign: .minus,
      combinationBitPattern: 6178 << 3,
      trailingSignificandBitPattern: 1)
    #expect(
      x._addingZeroWithLeastQuantum().bitPattern ==
      y._addingZeroWithLeastQuantum().bitPattern)
  }

  @Test
  @available(anyAppleOS 26.0, *)
  func testIntegerLiteral() {
    let x = 0 as Decimal128
    #expect(x.isZero)
  }

  @Test
  @available(anyAppleOS 26.0, *)
  func testAddition() {
    for i in 0..<256 {
      for j in 0..<256 {
        let x = Decimal128(i)
        let y = Decimal128(j)
        #expect(Double(i + j).description == (x + y).description + ".0")
      }
    }

    var x = Decimal128(
      sign: .plus,
      exponentBitPattern: Decimal128().exponentBitPattern,
      significandBitPattern:
        Decimal128.greatestFiniteMagnitude.significandBitPattern)
    // Not the point of the test but it needs to be right:
    #expect(x._significandWidth == 33)
    var y = x + 1/2
    #expect(y == Decimal128("1e34")!)

    x = Decimal128(sign: .plus, exponent: 70, significand: 1)
    y = x - 1
    #expect(y == x)
    y = x.subtracting(1, rounding: .down)
    #expect(y == x.nextDown)

    // Sign of exact zero.
    x = 0
    var flags: DecimalFloatingPointStatusFlags = []
    var result = x.adding(-x, rounding: .down, &flags)
    #expect(result.isZero && result.sign == .minus)
    result = x.adding(-x, &flags)
    #expect(result.isZero && result.sign == .plus)
    #expect(flags.isEmpty)

    typealias Case = (
      x: String,
      y: String,
      rule: FloatingPointRoundingRule,
      result: String,
      flags: DecimalFloatingPointStatusFlags)
    let cases: [Case] = [
      ("-2e35", "6", .up, "-1.999999999999999999999999999999999e35", .inexact),
      ("-6", "-1e35", .down, "-1.000000000000000000000000000000001e35", .inexact),
      ("-9.999999999999999999999999999999999e6144", "-1e6076", .awayFromZero, "-inf", .overflowInexact),
      ("-9.999999999999999999999999999999999e6144", "-1e6110", .down, "-inf", .overflowInexact),
      ("0e-100", "1", .toNearestOrEven, "1.000000000000000000000000000000000", []),
      ("1", "-1.000000000000000000000000000000000e35", .toNearestOrAwayFromZero, "-1.000000000000000000000000000000000e35", .inexact),
      ("1", "-2", .toNearestOrEven, "-1", []),
      ("1e1", "-10", .toNearestOrEven, "0", []),
      ("1e1", "-11", .toNearestOrEven, "-1", []),
      ("1e35", "-6", .toNearestOrEven, "9.999999999999999999999999999999999e34", .inexact),
      ("1e39", "1000000000000000000000000000000000", .toNearestOrEven, "1.000001000000000000000000000000000e39", []),
      ("9999999999999999999999999999999999", "1.5", .awayFromZero, "1.000000000000000000000000000000001e34", .inexact),
      ("9999999999999999999999999999999999", "10", .toNearestOrEven, "1.000000000000000000000000000000001e34", .inexact),
      ("9.999999999999999999999999999999999e6144", "1e6110", .up, "inf", .overflowInexact),
      ("-inf", "-inf", .toNearestOrEven, "-inf", []),
      ("1", "-inf", .toNearestOrEven, "-inf", []),
      ("snan", "snan", .toNearestOrEven, "nan", .invalid),
      ("inf", "-inf", .toNearestOrEven, "nan", .invalid),
      ("9999999999999999999999999999999999", "1.5", .towardZero, "1.000000000000000000000000000000000e34", .inexact),
      ("1e70", "1", .toNearestOrEven, "1.000000000000000000000000000000000e70", .inexact),
      ("1e35", "6", .towardZero, "1.000000000000000000000000000000000e35", .inexact),
      ("-2e35", "6", .towardZero, "-1.999999999999999999999999999999999e35", .inexact),
      ("-2e35", "6", .awayFromZero, "-2.000000000000000000000000000000000e35", .inexact),
    ]
    for c in cases {
      var flags: DecimalFloatingPointStatusFlags = []
      let actual =
        Decimal128(c.x)!.adding(Decimal128(c.y)!, rounding: c.rule, &flags)
      let expected = Decimal128(c.result)!
      if expected.isNaN {
        #expect(actual.isNaN && !actual.isSignalingNaN)
      } else {
        #expect(actual.bitPattern == expected.bitPattern)
      }
      #expect(flags == c.flags)
    }
  }

  @Test
  @available(anyAppleOS 26.0, *)
  func testMultiplication() {
    for i in 0..<256 {
      for j in 0..<256 {
        let x = Decimal128(i)
        let y = Decimal128(j)
        #expect(Double(i * j).description == (x * y).description + ".0")
      }
    }

    var x: Decimal128 = -.leastNonzeroMagnitude
    #expect(x * (1/2) == 0)
    #expect(x.multiplied(by: 1/2, rounding: .down) == x)

    // Directed overflow (cf. woodsbury/decimal128).
    x = Decimal128(binaryEncoding: 0x481e_0000_0000_0000_0000_0000_ffff_ffff)
    let y = Decimal128(binaryEncoding: 0x5ffe_0000_0000_0000_0000_0000_ffff_ffff)
    #expect(x * y == .infinity) // 4294967295e3055 * 4294967295e611.
    var flags: DecimalFloatingPointStatusFlags = []
    let result = x.multiplied(by: y, rounding: .towardZero, &flags)
    #expect(result == .greatestFiniteMagnitude)
    #expect(flags == .overflowInexact)

    typealias Case = (
      x: String,
      y: String,
      rule: FloatingPointRoundingRule,
      result: String,
      flags: DecimalFloatingPointStatusFlags)
    let cases: [Case] = [
      ("1", "inf", .toNearestOrEven, "inf", []),
      ("1", "snan", .toNearestOrEven, "nan", .invalid),
      ("inf", "1", .toNearestOrEven, "inf", []),
      ("snan", "1", .toNearestOrEven, "nan", .invalid),
      ("inf", "0", .toNearestOrEven, "nan", .invalid),
      ("0", "inf", .toNearestOrEven, "nan", .invalid),
    ]
    for c in cases {
      var flags: DecimalFloatingPointStatusFlags = []
      let actual =
        Decimal128(c.x)!.multiplied(
          by: Decimal128(c.y)!, rounding: c.rule, &flags)
      let expected = Decimal128(c.result)!
      if expected.isNaN {
        #expect(actual.isNaN && !actual.isSignalingNaN)
      } else {
        #expect(actual.bitPattern == expected.bitPattern)
      }
      #expect(flags == c.flags)
    }
  }

  @Test
  @available(anyAppleOS 26.0, *)
  func testFMA() {
    // With u = 1e-17, (1 + u)**2 - (1 + 2*u) is u**2.
    var x = Decimal128("1.00000000000000001")!
    var z = -(x + x.quantum)
    #expect(z.addingProduct(x, x) == Decimal128("1e-34")!)

    // The exact product exceeds greatestFiniteMagnitude before cancellation.
    x = 10
    let y = Decimal128("1e6144")!
    z = -y
    #expect(z.addingProduct(x, y) == Decimal128("9e6144")!)

    x = 1 + Decimal128(sign: .plus, exponent: -20, significand: 1)
    z = -1
    #expect(z.addingProduct(x, x) == Decimal128("2e-20")!+Decimal128("1e-40")!)

    #expect((1 as Decimal128).addingProduct(0, .infinity).isNaN)

    typealias Case = (
      z: String,
      x: String,
      y: String,
      rule: FloatingPointRoundingRule,
      result: String,
      flags: DecimalFloatingPointStatusFlags)
    let cases: [Case] = [
      ("-6597176330790615365366253925682318", "-18446744073709551616e-5", "18446744073709551616", .down, "-1.000000000000000000000000000000001e34", .inexact), // The addend's magnitude plus `floor(2**128 / 1e5)` is `1e34`; the product's fractional part remains sticky after the carry.
      ("2", "-1e-51", "1e-51", .towardZero, "1.999999999999999999999999999999999", .inexact),
      ("1e-6143", "-1e-6176", "1e-70", .toNearestOrEven, "1.000000000000000000000000000000000e-6143", .underflowInexact),
      ("-9.999999999999999999999999999999999e6144", "-20e6111", "3.000000000000000000000000000000000e-2", .awayFromZero, "-inf", .overflowInexact),
      ("1e-6143", "-2e-6176", "3e-3", .toNearestOrEven, "1.000000000000000000000000000000000e-6143", .underflowInexact),
      ("-9.999999999999999999999999999999999e6144", "-2e6042", "3", .down, "-inf", .overflowInexact),
      ("0.1", "-4", "5000000000000000000000000000000000", .towardZero, "-1.999999999999999999999999999999999e34", .inexact),
      ("-0.0", "1", "-0.0", .toNearestOrEven, "-0.0", []),
      ("1", "1", "-1", .toNearestOrEven, "0", []),
      ("0", "1", "0", .down, "0", []),
      ("9.999999999999999999999999999999999e133", "1", "1", .up, "1.000000000000000000000000000000000e134", .inexact),
      ("0.1", "10", "9999999999999999999999999999999999", .up, "1.000000000000000000000000000000000e35", .inexact),
      ("1", "1000000000000000000000000000000000", "10", .toNearestOrEven, "1.000000000000000000000000000000000e34", .inexact),
      ("-1.000000000000000000000000000000000e64", "1000000000000000000000000000000000", "1000000000000000000000000000000000", .toNearestOrEven, "9.900000000000000000000000000000000e65", []),
      ("1", "1.000000000000000000000000000000000e-4", "1.000000000000000000000000000000000e-4", .toNearestOrEven, "1.000000010000000000000000000000000", []),
      ("-18446744073709551616.1", "18446744073709551616", "18446744073709551617", .toNearestOrEven, "3.402823669209384634633746074317682e38", .inexact), // With `b = 2**64`, `b * (b + 1) - (b + 0.1)` forces a second borrow.
      ("9999999999999999999999999999999999", "1e-40", "9999999999999999999999999999999999", .up, "1.000000000000000000000000000000000e34", .inexact),
      ("0", "1e-6176", "0.5", .toNearestOrEven, "0e-6176", .underflowInexact),
      ("1e-6176", "1e-6176", "0.5", .toNearestOrEven, "2e-6176", .underflowInexact),
      ("-11e6111", "1e6111", "1e1", .toNearestOrEven, "-1e6111", []),
      ("1e6076", "1e6111", "1e1", .toNearestOrEven, "1.000000000000000000000000000000000e6112", .inexact),
      ("1e69", "2", "-5000000000000000000000000000000000", .toNearestOrAwayFromZero, "1.000000000000000000000000000000000e69", .inexact),
      ("1", "2", "0.00", .toNearestOrEven, "1.00", []),
      ("-0.6", "2", "5000000000000000000000000000000000", .toNearestOrEven, "9999999999999999999999999999999999", .inexact),
      ("9.999999999999999999999999999999999e6144", "20e6111", "3.000000000000000000000000000000000e-2", .up, "inf", .overflowInexact),
      ("9000000000000000000000000000000005", "0.2", "5000000000000000000000000000000000", .toNearestOrEven, "1.000000000000000000000000000000000e34", .inexact),
      ("1e-6176", "2e-6176", "3e-102", .awayFromZero, "2e-6176", .underflowInexact),
      ("1e-6143", "5e-6176", "5e-3", .toNearestOrEven, "1.000000000000000000000000000000000e-6143", .inexact),
      ("-1", "8.000000000000000000000000000000000e-18", "8.000000000000000000000000000000000e-18", .toNearestOrEven, "-0.9999999999999999999999999999999999", .inexact),
      ("5e65", "9999999999999999999999999999999999", "9999999999999999999999999999999999", .toNearestOrEven, "1.005000000000000000000000000000000e68", .inexact),
      ("1", "9.999999999999999999999999999999999e6144", "100001", .toNearestOrEven, "inf", .overflowInexact),
      ("snan", "2", "3", .toNearestOrEven, "nan", .invalid),
      ("-inf", "inf", "-1", .toNearestOrEven, "-inf", []),
      ("1", "snan", "snan", .toNearestOrEven, "nan", .invalid),
      ("-inf", "inf", "1", .toNearestOrEven, "nan", .invalid),
      ("1e110", "1", "1", .toNearestOrEven, "1.000000000000000000000000000000000e110", .inexact),
      ("1", "1e-51", "1e-51", .towardZero, "1.000000000000000000000000000000000", .inexact),
      ("9999999999999999999999999999999999", "20e-35", "3000000000000000000000000000000000", .towardZero, "9999999999999999999999999999999999", .inexact),
    ]
    for c in cases {
      var flags: DecimalFloatingPointStatusFlags = []
      let actual =
        Decimal128(c.z)!.addingProduct(
          Decimal128(c.x)!, Decimal128(c.y)!, rounding: c.rule, &flags)
      let expected = Decimal128(c.result)!
      if expected.isNaN {
        #expect(actual.isNaN && !actual.isSignalingNaN)
      } else {
        #expect(actual.bitPattern == expected.bitPattern)
      }
      #expect(flags == c.flags)
    }
  }

  @Test
  @available(anyAppleOS 26.0, *)
  func testDivision() {
    let one: Decimal128 = 1
    #expect((one / 10).description == "0.1")
    #expect((one / 8).description == "0.125")
    #expect((one / 3).description == "0.3333333333333333333333333333333333")
    #expect((one.quantized(by: 1/1000) / 2).description == "0.500")
    #expect((one / Decimal128(signOf: -1, magnitudeOf: 0)) == -.infinity)

    #expect(Decimal128(UInt128._1e33) / Decimal128(UInt128.max &>> 32)
            == Decimal128("12621.77448353618888658765704468389")!)

    // Directed underflow (cf. woodsbury/decimal128).
    let x = Decimal128(binaryEncoding: 0xffff_ffff)
    let y = Decimal128(binaryEncoding: 0x481e_0000_0000_0000_0000_0000_ffff_ffff)
    #expect(x / y == 0) // 4294967295e-6176 / 4294967295e3055.
    var flags: DecimalFloatingPointStatusFlags = []
    let result = x.divided(by: y, rounding: .up, &flags)
    #expect(result == .leastNonzeroMagnitude)
    #expect(flags == .underflowInexact)

    typealias Case = (
      x: String,
      y: String,
      rule: FloatingPointRoundingRule,
      result: String,
      flags: DecimalFloatingPointStatusFlags)
    let cases: [Case] = [
      ("-0.00", "2", .toNearestOrEven, "-0.00", []),
      ("-1000000000000000000000000000000000e-6144", "6000000000000000000000000000000000", .toNearestOrEven, "-1.6666666666666666666666666666667e-6145", .underflowInexact),
      ("-1", "1234567", .toNearestOrEven, "-8.100005913004316493151040000259200e-7", .inexact),
      ("1", "1", .toNearestOrEven, "1", []),
      ("1e-6176", "3e1", .toNearestOrEven, "0e-6176", .underflowInexact),
      ("9999999999999999999999999999999999", "-11", .toNearestOrEven, "-909090909090909090909090909090909", []),
      ("9999999999999999999999999999999999", "100000000000000000001", .toNearestOrEven, "99999999999999.99999899999999999999", .inexact),
      ("9999999999999999999999999999999999", "10000000000000000000000001", .toNearestOrEven, "999999999.9999999999999998999999999", .inexact),
      ("9e6111", "-11e-37", .toNearestOrEven, "-inf", .overflowInexact),
      ("-inf", "2", .toNearestOrEven, "-inf", []),
      ("-1", "inf", .toNearestOrEven, "-0e-6176", []),
      ("1", "snan", .toNearestOrEven, "nan", .invalid),
      ("snan", "1", .toNearestOrEven, "nan", .invalid),
      ("1e-6176", "1e1", .toNearestOrEven, "0e-6176", .underflowInexact),
      ("inf", "inf", .toNearestOrEven, "nan", .invalid),
      ("0", "0", .toNearestOrEven, "nan", .invalid),
      ("42", "-0.0", .toNearestOrEven, "-inf", .divisionByZero),
      ("126821365506753167360e-6176", "46116860184273879040", .toNearestOrEven, "3e-6176", .underflowInexact), // `(55 * 2**61) / (5 * 2**63)` is `2.75` before the exponent adjustment.
    ]
    for c in cases {
      var flags: DecimalFloatingPointStatusFlags = []
      let actual =
        Decimal128(c.x)!.divided(by: Decimal128(c.y)!, rounding: c.rule, &flags)
      let expected = Decimal128(c.result)!
      if expected.isNaN {
        #expect(actual.isNaN && !actual.isSignalingNaN)
      } else {
        #expect(actual.bitPattern == expected.bitPattern)
      }
      #expect(flags == c.flags)
    }
  }

  @Test
  @available(anyAppleOS 26.0, *)
  func testRemainder() {
    #expect((7 as Decimal128).remainder(dividingBy: 2) == -1)
    #expect((7 as Decimal128).truncatingRemainder(dividingBy: 2) == 1)

    #expect(Decimal128(
              sign: .plus,
              exponent: 200,
              significand: 1).remainder(dividingBy: 6)
            == -2)

    let half: Decimal128 = 1/2
    #expect(((3 as Decimal128) / 2).remainder(dividingBy: 1) == -half)

    typealias Case = (
      x: String,
      y: String,
      truncating: Bool,
      result: String,
      flags: DecimalFloatingPointStatusFlags)
    let cases: [Case] = [
      ("-999999999999999999999999999999999e1", "1000000000000000000000000000000000", false, "10", []),
      ("0", "1", true, "0", []),
      ("10e1", "10", true, "0", []),
      ("4.5", "3", false, "-1.5", []),
      ("7e152", "3", true, "1", []),
      ("98e189", "99", true, "89", []),
      ("9e200", "3", true, "0", []),
      ("1", "snan", true, "nan", .invalid),
      ("snan", "1", true, "nan", .invalid),
      ("1", "0", true, "nan", .invalid),
    ]
    for c in cases {
      var flags: DecimalFloatingPointStatusFlags = []
      let x = Decimal128(c.x)!
      let y = Decimal128(c.y)!
      let actual = c.truncating
        ? x.truncatingRemainder(dividingBy: y, &flags)
        : x.remainder(dividingBy: y, &flags)
      let expected = Decimal128(c.result)!
      if expected.isNaN {
        #expect(actual.isNaN && !actual.isSignalingNaN)
      } else {
        #expect(actual.bitPattern == expected.bitPattern)
      }
      #expect(flags == c.flags)
    }
  }

  @Test
  @available(anyAppleOS 26.0, *)
  func testSquareRoot() {
    var x = Decimal128("4.00")!
    #expect(x.squareRoot().description == "2.0")

    x = 2
    #expect(x.squareRoot().description == "1.414213562373095048801688724209698")
    #expect(x.squareRoot(rounding: .up).description == "1.414213562373095048801688724209699")

    x = .leastNonzeroMagnitude
    #expect(x.squareRoot() == Decimal128("1e-3088")!)

    x = Decimal128("-0.00")!
    #expect(x.squareRoot().description == "-0.0")

    var flags: DecimalFloatingPointStatusFlags = []
    x = -1
    let result = x.squareRoot(&flags)
    #expect(result.isNaN)
    #expect(flags.contains(.invalid))

    x = Decimal128(sign: .plus, exponent: 16, significand: 1) - 1
    #expect((x * x).squareRoot() == x)

    typealias Case = (
      x: String,
      rule: FloatingPointRoundingRule,
      result: String,
      flags: DecimalFloatingPointStatusFlags)
    let cases: [Case] = [
      ("1000000000000000063245553203367587e1", .towardZero, "100000000000000003.1622776601683793", .inexact),
      ("inf", .toNearestOrEven, "inf", []),
      ("snan", .toNearestOrEven, "nan", .invalid),
      ("-inf", .toNearestOrEven, "nan", .invalid),
      ("0.9999999999999999999999999999999999", .awayFromZero, "1.000000000000000000000000000000000", .inexact),
    ]
    for c in cases {
      var flags: DecimalFloatingPointStatusFlags = []
      let actual = Decimal128(c.x)!.squareRoot(rounding: c.rule, &flags)
      let expected = Decimal128(c.result)!
      if expected.isNaN {
        #expect(actual.isNaN && !actual.isSignalingNaN)
      } else {
        #expect(actual.bitPattern == expected.bitPattern)
      }
      #expect(flags == c.flags)
    }
  }

  @Test
  @available(anyAppleOS 26.0, *)
  func testRounding() {
    var x: Decimal128 = 5/2
    #expect(x.rounded() == 3)
    #expect(x.rounded(.toNearestOrEven) == 2)

    x = -1/10
    #expect(x.rounded().isZero && x.rounded().sign == .minus)

    x = 3 + 1/2
    #expect(x.rounded() == 4)
    #expect(x.rounded(.toNearestOrEven) == 4)
    #expect(x.rounded(.down) == 3)

    var flags: DecimalFloatingPointStatusFlags = []
    #expect(Decimal128("1e-100")!.rounded(.up, &flags).bitPattern
            == (1 as Decimal128).bitPattern)
    #expect(flags == .inexact)

    flags = []
    #expect(Decimal128("2.5")!.rounded(.toNearestOrEven, &flags) == 2)
    #expect(flags == .inexact)

    #expect(Decimal128("1e-100")!.rounded(.up) == 1)

    let snan = Decimal128.signalingNaN
    var result = snan.rounded(.toNearestOrEven)
    #expect(result.isNaN && !result.isSignalingNaN)

    flags = []
    result = snan.rounded(.toNearestOrEven, &flags)
    #expect(result.isNaN && !result.isSignalingNaN)
    #expect(flags == .invalid)
  }

  @Test
  @available(anyAppleOS 26.0, *)
  func testScaleB() {
    var x = Decimal128("1.2300")!
    #expect(Decimal128(sign: .plus, exponent: -1, significand: x).description
            == "0.12300")
    #expect(Decimal128(sign: .plus, exponent: 0, significand: x).description
            == "1.2300")
    #expect(Decimal128(sign: .plus, exponent: 2, significand: x).description
            == "123.00")

    // Sign composition, not replacement.
    x.negate()
    #expect(Decimal128(sign: .minus, exponent: 0, significand: x).description
            == "1.2300")

    // Zero.
    x = 0
    #expect(Decimal128("-0.00")!.significand.bitPattern == x.bitPattern)
    var y = Decimal128(sign: .minus, exponent: .max, significand: x)
    #expect(x == y)
    y = Decimal128(sign: .plus, exponent: .max, significand: y)
    #expect(x == y)

    // Boundaries.
    #expect(Decimal128(
              sign: .minus,
              exponent: 1,
              significand: .greatestFiniteMagnitude)
            == -.infinity)
    #expect(Decimal128(
              sign: .plus,
              exponent: -1,
              significand: .leastNormalMagnitude).description
            == "1e-6144")
    #expect(Decimal128(
              sign: .plus,
              exponent: -1,
              significand: .leastNonzeroMagnitude,
              rounding: .up)
            == .leastNonzeroMagnitude)

    var flags: DecimalFloatingPointStatusFlags = []
    #expect(Decimal128(sign: .plus, exponent: .max, significand: 1, &flags)
            == .infinity)
    #expect(flags == .overflowInexact)

    typealias Case = (
      x: Decimal128,
      exponent: Int,
      result: Decimal128,
      flags: DecimalFloatingPointStatusFlags)
    let cases: [Case] = [
      (.leastNonzeroMagnitude, -35, Decimal128("0e-6176")!, .underflowInexact),
      (.infinity, 1, .infinity, []),
      (.nan, 1, .nan, []),
      (.signalingNaN, 1, .nan, .invalid),
    ]
    for c in cases {
      var flags: DecimalFloatingPointStatusFlags = []
      let actual =
        Decimal128(sign: .plus, exponent: c.exponent, significand: c.x, &flags)
      if c.result.isNaN {
        #expect(actual.isNaN && !actual.isSignalingNaN)
      } else {
        #expect(actual.bitPattern == c.result.bitPattern)
      }
      #expect(flags == c.flags)
    }
  }

  @Test
  @available(anyAppleOS 26.0, *)
  func testBinaryIntegerConversion() {
    var x: UInt128 = ._1e34
    #expect(Decimal128(x) == Decimal128(exactly: x))
    #expect(Decimal128(x).quantum == 10)

    x += 1
    #expect(Decimal128(exactly: x) == nil)

    x -= 1 // 1e34.
    typealias _UInt512 = DoubleWidth<DoubleWidth<UInt128>>
    var y = _UInt512(UInt128._exp10[30])
    y *= y
    y *= y // 1e120.
    var z = y * _UInt512(x) + 5 * y // 1e154 + 5e120 (midpoint).
    #expect(Decimal128(z) == Decimal128("1e154")!)
    #expect(Decimal128(z).quantum == Decimal128(y) * 10)
    #expect(Decimal128(exactly: z) == nil)

    z += 1
    #expect(Decimal128(z) == Decimal128("1e154")!.nextUp)

    let midpoint = -(Int128(UInt128._1e34) + 15) // Halfway between `-(10**34 + 10)` and `-(10**34 + 20)`.
    var flags: DecimalFloatingPointStatusFlags = []
    #expect(Decimal128(midpoint, &flags).bitPattern
            == Decimal128("-1.000000000000000000000000000000002e34")!.bitPattern)
    #expect(flags == .inexact)

    let nines = Int128(10 * UInt128._1e34) - 1 // `10**35 - 1`.
    flags = []
    #expect(Decimal128(nines, &flags).bitPattern
            == Decimal128("1.000000000000000000000000000000000e35")!.bitPattern)
    #expect(flags == .inexact)
  }

  @Test
  @available(anyAppleOS 26.0, *)
  func testBinaryFloatingPointConversion() {
    let x = 0.1
    let y: Decimal128 = 1/10
    #expect(Decimal128(nearest: x) != y)
    #expect(Decimal128(nearest: x).description == "0.1000000000000000055511151231257827")
    #expect(Decimal128(shortest: x) == y)
    #expect(Double(nearest: y) == x)
    #expect(MockFloat128(nearest: y).bitPattern == 0x3ffb_9999_9999_9999_9999_9999_9999_999a)

    let a: Float16 = 1.001
    #expect(Decimal128(shortest: a).description == "1.001")
    #expect(Decimal128(nearest: a).description == "1.0009765625") // 1 + 1/1024.
    #expect(Decimal128(nearest: a) == Decimal128(exactly: a))

    let b: Float16 = 1.00048828125 // 1 + 1/2048 (midpoint).
    #expect(Float16(nearest: Decimal128("1.00048828125")!) == b)
    #expect(Float16(nearest: Decimal128("1.00048828126")!) == b.nextUp)

    var flags: DecimalFloatingPointStatusFlags = []
    let c =
      Decimal128(nearest: Float16(bitPattern: 0xfd01) /* -snan(0x1) */, &flags)
    #expect(c.isNaN && !c.isSignalingNaN)
    #expect(c.significandBitPattern & 0xff == 1)
    #expect(flags == .invalid)

    flags = []
    let pow2 = MockFloat128(
      sign: .plus, exponentBitPattern: 16383 + 2062, significandBitPattern: 0)
    #expect(Decimal128(nearest: pow2, &flags).bitPattern
            == Decimal128("5.294818274723595436149125396671685e620")!.bitPattern)
    #expect(flags == .inexact)

    flags = []
    #expect(Decimal128(shortest: (2048 as Float16), &flags) == 2048)
    #expect(flags.isEmpty)

    #expect(MockFloat128(nearest: Decimal128("1e359")!).bitPattern
            == 0x44a7_7c9d_44a5_c17a_6a6d_13b8_a812_51c7)
    #expect(MockFloat128(nearest: Decimal128("-1e-4967")!).bitPattern
            == 1 << 127)
    #expect(Float16(nearest: Decimal128.infinity) == .infinity)
    #expect(Float16(nearest: -Decimal128(nan: 10000, signaling: false)).isNaN)

    let d = Float16(nearest: Decimal128(nan: 1, signaling: true))
    #expect(d.isNaN && !d.isSignalingNaN)
    #expect(d.significandBitPattern & 0xff == 1)

    flags = []
    #expect(Decimal128(nearest: Float16.zero, &flags).bitPattern
            == (0 as Decimal128).bitPattern)
    #expect(flags.isEmpty)

    #expect(Float16(nearest: Decimal128("-0.00")!).bitPattern == 0x8000)

    flags = []
    #expect(Decimal128(shortest: (2 as Float16), &flags) == 2)
    #expect(flags.isEmpty)

    flags = []
    #expect(Decimal128(shortest: Float16.infinity, &flags) == .infinity)
    #expect(flags.isEmpty)
  }

  @Test
  @available(anyAppleOS 26.0, *)
  func testStringConversion() {
    let x = "1.0000000000000000000000000000000005"
    let one: Decimal128 = 1
    #expect(Decimal128(x)! == one)
    #expect(Decimal128(x)!.hasSameQuantum(as: one.nextUp))
    #expect(Decimal128(x, rounding: .toNearestOrAwayFromZero)! == one.nextUp)

    var flags: DecimalFloatingPointStatusFlags = []
    #expect(Decimal128(x + "1", &flags)?.bitPattern == one.nextUp.bitPattern)
    #expect(flags == .inexact)

    flags = []
    #expect(Decimal128("1e-6211", rounding: .up, &flags)?.bitPattern
            == Decimal128.leastNonzeroMagnitude.bitPattern)
    #expect(flags == .underflowInexact)

    var zero = Decimal128("+0E6789")!
    #expect(zero.isZero)
    #expect(zero.hasSameQuantum(as: Decimal128("1e+6111")!))

    zero = Decimal128("-0E-9999")!
    #expect(zero.isZero)
    #expect(zero.hasSameQuantum(as: Decimal128("1e-6176")!))

    zero = Decimal128("+0e18446744073709551616")! // Exponent exceeds 64 bits.
    #expect(zero.isZero)
    #expect(zero.hasSameQuantum(as: Decimal128("1e+6111")!))

    typealias Case = (
      x: String,
      result: Decimal128?,
      flags: DecimalFloatingPointStatusFlags)
    let nines = String(repeating: "9", count: 34)
    let cases: [Case] = [
      ("-sNaN(0X7B)", -Decimal128(nan: 123, signaling: true), []),
      (nines + "501.01", Decimal128("1.000000000000000000000000000000000e37")!, .inexact),
      ("1e-6177", Decimal128("0e-6176")!, .underflowInexact),
      ("9." + nines + "e6144", Decimal128.infinity, .overflowInexact),
      ("nan(08)", nil, []), // Invalid octal payload.
    ]
    for c in cases {
      var flags: DecimalFloatingPointStatusFlags = []
      #expect(Decimal128(c.x, &flags)?.bitPattern == c.result?.bitPattern)
      #expect(flags == c.flags)
    }
  }

  @Test
  @available(anyAppleOS 26.0, *)
  func testDescription() {
    let x = Decimal128(
      sign: .minus,
      exponentBitPattern: 6176,
      significandBitPattern: ._1e34) // Noncanonical zero.
    #expect(x.description == "-0")

    let y = Decimal128(
      _sign: .minus,
      combinationBitPattern: 6176 << 3,
      trailingSignificandBitPattern: 1)
    #expect(y.description == "-1")

    var z = Decimal128(
      _sign: .minus,
      combinationBitPattern: 6177 << 3,
      trailingSignificandBitPattern: 10)
    #expect(z.description == "-1.0e+2")

    z = Decimal128(
      _sign: .minus,
      combinationBitPattern: 6178 << 3,
      trailingSignificandBitPattern: 1)
    #expect(z.description == "-1e+2")
  }

  @Test
  @available(anyAppleOS 26.0, *)
  func testQuantized() {
    #expect(((5 as Decimal128) / 4).quantized(by: 1/10).description == "1.2")

    var x: Decimal128 = Decimal128(sign: .plus, exponent: 34, significand: 1)
    #expect(x.quantized(by: 1).isNaN)

    x = .infinity
    #expect((-x).quantized(by: x) == -x)
    #expect((-x).quantized(by: 1).isNaN)
    var flags: DecimalFloatingPointStatusFlags = []
    #expect((-x).quantum(&flags) == .infinity)
    #expect(flags.isEmpty)

    x = Decimal128("-1e-100")!
    #expect(x.quantized(by: 1, rounding: .down, &flags).bitPattern
            == (-1 as Decimal128).bitPattern)
    #expect(flags == .inexact)

    flags = []
    var result = (1 as Decimal128).quantized(by: .signalingNaN, &flags)
    #expect(result.isNaN && !result.isSignalingNaN)
    #expect(flags == .invalid)

    flags = []
    result = Decimal128.signalingNaN.quantized(by: 1, &flags)
    #expect(result.isNaN && !result.isSignalingNaN)
    #expect(flags == .invalid)

    flags = []
    let quantum = Decimal128.signalingNaN.quantum(&flags)
    #expect(quantum.isNaN && !quantum.isSignalingNaN)
    #expect(flags == .invalid)
  }

  @Test
  @available(anyAppleOS 26.0, *)
  func testNaN() {
    var x = Decimal128(nan: 0xff, signaling: false)
    #expect(x.isNaN && !x.isSignalingNaN && x.sign == .plus)
    #expect(String(reflecting: x) == "nan(0xff)")

    x = -Decimal128(nan: 0x1, signaling: true)
    #expect(x.isNaN && x.isSignalingNaN && x.sign == .minus)
    #expect(String(reflecting: x) == "-snan(0x1)")
    #expect(x.isCanonical)
    #expect(!(x == x))
    #expect(!(x < x))
    #expect(!(x >= 1))
    #expect(!(1 >= x))
    #expect(!(0 <= x))

    let next = x.nextUp
    #expect(next.isNaN && !next.isSignalingNaN)

    var set = Set<Decimal128>()
    set.insert(x)
    set.insert(x)
    #expect(set.count == 2)

    #expect((-Decimal128.signalingNaN).description == "nan")
    #expect((-Decimal128.signalingNaN).debugDescription == "-snan")

    #expect(Decimal128.nan.hasSameQuantum(as: x))
  }

  @Test
  @available(anyAppleOS 26.0, *)
  func testReadme() {
    let x: Decimal128 = 1/10
    let y: Decimal128 = 2/10
    let comparison = x + y == 3/10
    #expect(comparison)

    var flags: DecimalFloatingPointStatusFlags = []
    _ = (1 as Decimal128).divided(by: 3, rounding: .toNearestOrEven, &flags)
    #expect(flags.contains(.inexact))
  }
}
