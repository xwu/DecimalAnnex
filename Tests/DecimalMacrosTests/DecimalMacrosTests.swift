import Testing
import SwiftSyntaxMacrosTestSupport
import DecimalMacros

struct DecimalMacrosTests {
  @Test(arguments: [
    "~",
    "!",
  ])
  func `arbitrary prefix operator rejected`(_ op: String) {
    let source = """
      prefix func \(op)(_ value: Double) -> Double { value }
      #Decimal128(\(op)42)
      """
    assertMacroExpansion(
      source,
      expandedSource: source,
      diagnostics: [
        DiagnosticSpec(
          message: "Expected decimal float or integer literal optionally preceded by '+' or '-'",
          line: 2,
          column: 1)
      ],
      macros: ["Decimal128": Decimal128LiteralMacro.self])
  }

  @Test(arguments: [
    "#Decimal128(1 + 2 + 3)",
    "#Decimal128(((12.34)))",
  ])
  func `non-literal expression rejected`(_ source: String) {
    assertMacroExpansion(
      source,
      expandedSource: source,
      diagnostics: [
        DiagnosticSpec(
          message: "Expected decimal float or integer literal",
          line: 1,
          column: 1)
      ],
      macros: ["Decimal128": Decimal128LiteralMacro.self])
  }

  @Test(arguments: [
    "#Decimal128(0x10)",
    "#Decimal128(0o10)",
    "#Decimal128(0b10)",
    "#Decimal128(0x1.2p3)",
  ])
  func `non-decimal literal rejected`(_ source: String) {
    assertMacroExpansion(
      source,
      expandedSource: source,
      diagnostics: [
        DiagnosticSpec(
          message: "Expected decimal float or integer literal",
          line: 1,
          column: 1)
      ],
      macros: ["Decimal128": Decimal128LiteralMacro.self])
  }
}
