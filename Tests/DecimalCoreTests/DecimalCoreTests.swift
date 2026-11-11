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
  }

  @Test
  @available(anyAppleOS 26.0, *)
  func testULP() {
    let x = Decimal128.infinity
    #expect(x.ulp.isNaN)
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

    // Sign of exact zero.
    let x: Decimal128 = 0
    var flags: DecimalFloatingPointStatusFlags = []
    var result = x.adding(-x, rounding: .down, &flags)
    #expect(result.isZero && result.sign == .minus)
    result = x.adding(-x, &flags)
    #expect(result.isZero && result.sign == .plus)
    #expect(flags.isEmpty)
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

    // Directed overflow (cf. woodsbury/decimal128).
    let x = Decimal128(binaryEncoding: 0x481e_0000_0000_0000_0000_0000_ffff_ffff)
    let y = Decimal128(binaryEncoding: 0x5ffe_0000_0000_0000_0000_0000_ffff_ffff)
    #expect(x * y == .infinity) // 4294967295e3055 * 4294967295e611.
    var flags: DecimalFloatingPointStatusFlags = []
    let result = x.multiplied(by: y, rounding: .towardZero, &flags)
    #expect(result == .greatestFiniteMagnitude)
    #expect(flags == .overflowInexact)
  }

  @Test
  @available(anyAppleOS 26.0, *)
  func testFMA() {
    var x = Decimal128("1.00000000000000001")!
    var z = -(x + x.quantum)
    #expect(z.addingProduct(x, x) == Decimal128("1e-34")!)

    x = 10
    let y = Decimal128("1e6144")!
    z = -y
    #expect(z.addingProduct(x, y) == Decimal128("9e6144")!)

    #expect((1 as Decimal128).addingProduct(0, .infinity).isNaN)
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

    // Directed underflow (cf. woodsbury/decimal128).
    let x = Decimal128(binaryEncoding: 0xffff_ffff)
    let y = Decimal128(binaryEncoding: 0x481e_0000_0000_0000_0000_0000_ffff_ffff)
    #expect(x / y == 0) // 4294967295e-6176 / 4294967295e3055.
    var flags: DecimalFloatingPointStatusFlags = []
    let result = x.divided(by: y, rounding: .up, &flags)
    #expect(result == .leastNonzeroMagnitude)
    #expect(flags == .underflowInexact)
  }

  @Test
  @available(anyAppleOS 26.0, *)
  func testRemainder() {
    #expect((7 as Decimal128).remainder(dividingBy: 2) == -1)
    #expect((7 as Decimal128).truncatingRemainder(dividingBy: 2) == 1)
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
  }

  @Test
  @available(anyAppleOS 26.0, *)
  func testRounding() {
    var x: Decimal128 = 5/2
    #expect(x.rounded() == 3)
    #expect(x.rounded(.toNearestOrEven) == 2)

    x = -1/10
    #expect(x.rounded().isZero && x.rounded().sign == .minus)
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
  }

  @Test
  @available(anyAppleOS 26.0, *)
  func testStringConversion() {
    let x = "1.0000000000000000000000000000000005"
    let one: Decimal128 = 1
    #expect(Decimal128(x)! == one)
    #expect(Decimal128(x)!.hasSameQuantum(as: one.nextUp))
    #expect(Decimal128(x, rounding: .toNearestOrAwayFromZero)! == one.nextUp)

    var zero = Decimal128("+0E6789")!
    #expect(zero.isZero)
    #expect(zero.hasSameQuantum(as: Decimal128("1e+6111")!))

    zero = Decimal128("-0E-9999")!
    #expect(zero.isZero)
    #expect(zero.hasSameQuantum(as: Decimal128("1e-6176")!))
  }

  @Test
  @available(anyAppleOS 26.0, *)
  func testDescription() {
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

    let x: Decimal128 = .infinity
    #expect((-x).quantized(by: x) == -x)
    #expect((-x).quantized(by: 1).isNaN)
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
