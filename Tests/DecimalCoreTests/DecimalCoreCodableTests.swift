import Foundation
import Testing
import DecimalCore

@Test
@available(anyAppleOS 26.0, *)
func `plist encoding supported`() throws {
  let values = [
    Decimal128("-7.50")!,
    Decimal128("-0.00")!,
    -Decimal128(nan: 42, signaling: true),
  ]

  let encoder = PropertyListEncoder()
  encoder.outputFormat = .binary
  let plist = try encoder.encode(values)

  let decoder = PropertyListDecoder()
  let strings = try decoder.decode([String].self, from: plist)
  #expect(strings == ["-7.50", "-0.00", "-snan(0x2a)"])

  let decoded = try decoder.decode([Decimal128].self, from: plist)
  // Guaranteed for canonical values.
  #expect(decoded.map(\.bitPattern) == values.map(\.bitPattern))
}
