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

  // TODO: Test `nextUp`.

  @Test
  @available(anyAppleOS 26.0, *)
  func testULP() {
    let x = Decimal128.infinity
    #expect(x.ulp.isNaN)
  }

  @Test
  @available(anyAppleOS 26.0, *)
  func testEquatable() {
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
    let x: Decimal128 = .infinity
    #expect((-x).quantized(by: x) == -x)
    #expect((-x).quantized(by: 1).isNaN)
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
