import XCTest
@testable import DecimalAnnex

final class DecimalAnnexTests: XCTestCase {
  func testLog10() throws {
    guard #available (macOS 15.0, *) else { return }

    for _ in 0...65535 {
      let x = UInt128.random(in: 0...UInt128.max)
      XCTAssertEqual(x._log10, String(x).count - 1)
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
