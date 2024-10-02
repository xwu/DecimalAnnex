import XCTest
@testable import DecimalAnnex

final class DecimalAnnexTests: XCTestCase {
  func testDPD() throws {
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
      XCTAssertEqual(d, _DPD.decode(e))
      XCTAssertEqual(_DPD.encode(d), e)
    }
  }

  func testUInt256() throws {
    guard #available (macOS 15.0, *) else { return }
    do {
      let lhs = _UInt256("2369676578372158364766242369061213561181961479062237766620")!
      let rhs = _UInt256("102797312405202436815976773795958969482")!
      XCTAssertEqual(String(lhs / rhs), "23051931251193218442")
    }
    do {
      let lhs = _UInt256("96467201117289166187766181030232879447148862859323917044548749804018359008044")!
      let rhs = _UInt256("4646260627574879223760172113656436161581617773435991717024")!
      XCTAssertEqual(String(lhs / rhs), "20762331011904583253")
    }
  }

  func testLog10() throws {
    guard #available (macOS 15.0, *) else { return }

    for _ in 0...65535 {
      let x = UInt128.random(in: 0...UInt128.max)
      XCTAssertEqual(x._commonLogarithm, String(x).count - 1)
    }
  }

  func testPi() throws {
    guard #available (macOS 15.0, *) else { return }

    let x = Decimal128.pi
    XCTAssertEqual(x.description, "3.141592653589793238462643383279502")
  }

  func testEquatable() throws {
    guard #available(macOS 15.0, *) else { return }
    
    let x = Decimal128(
      _sign: .minus,
      combinationBitPattern: 6177 << 3,
      trailingSignificandBitPattern: 10)
    let y = Decimal128(
      _sign: .minus,
      combinationBitPattern: 6178 << 3,
      trailingSignificandBitPattern: 1)

    XCTAssertTrue(x == y)
    XCTAssertFalse(x == -y)
  }

  func testAddingZero() throws {
    guard #available(macOS 15.0, *) else { return }

    let x = Decimal128(
      _sign: .minus,
      combinationBitPattern: 6177 << 3,
      trailingSignificandBitPattern: 10)
    let y = Decimal128(
      _sign: .minus,
      combinationBitPattern: 6178 << 3,
      trailingSignificandBitPattern: 1)
    XCTAssertEqual(x._addingZeroWithLeastQuantum().bitPattern, y._addingZeroWithLeastQuantum().bitPattern)
  }

  func testIntegerLiteral() throws {
    guard #available(macOS 15.0, *) else { return }

    let x = 0 as Decimal128
    XCTAssertTrue(x.isZero)
  }

  func testMultiplication() throws {
    guard #available(macOS 15.0, *) else { return }

    for i in 0..<256 {
      for j in 0..<256 {
        let x = Decimal128(integerLiteral: Int128(i))
        let y = Decimal128(integerLiteral: Int128(j))
        XCTAssertEqual(Double(i * j).description, (x * y).description)
      }
    }
  }

  func testDescription() throws {
    guard #available(macOS 15.0, *) else { return }

    // As a concession to the idiosyncrasies of float literals, we will write
    // an extra ".0" at the end of integral values in order to hint that these
    // are floating-point values, even when there's not actually that extra
    // significant figure in the encoding.
    let y = Decimal128(
      _sign: .minus,
      combinationBitPattern: 6176 << 3,
      trailingSignificandBitPattern: 1)
    XCTAssertEqual(y.description, "-1.0")

    // Otherwise, though, we don't take the special code paths to avoid
    // scientific notation if there's not enough significant figures, and we
    // also don't add phantom significant figures when we're using scientific
    // notation.
    var z = Decimal128(
      _sign: .minus,
      combinationBitPattern: 6177 << 3,
      trailingSignificandBitPattern: 10)
    XCTAssertEqual(z.description, "-1.0e+2")

    z = Decimal128(
      _sign: .minus,
      combinationBitPattern: 6178 << 3,
      trailingSignificandBitPattern: 1)
    XCTAssertEqual(z.description, "-1e+2")
  }
}
