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

  @Test
  func `inexact literal replacement`() {
    let description = "1.234567890123456789012345678901234e+34"
    let expansion = ".init(bitPattern: 64146869958229383979654763996863967218)"
    assertMacroExpansion(
      "#Decimal128(\(description))",
      expandedSource: expansion,
      macros: ["Decimal128": Decimal128LiteralMacro.self])
    assertMacroExpansion(
      "#Decimal128(12345678901234567890123456789012345)",
      expandedSource: expansion,
      diagnostics: [
        DiagnosticSpec(
          message: "Literal as 'Decimal128' rounds to '\(description)'",
          line: 1,
          column: 13,
          severity: .warning,
          fixIts: [FixItSpec(message: "Replace with '\(description)'")])
      ],
      macros: ["Decimal128": Decimal128LiteralMacro.self],
      fixedSource: "#Decimal128(\(description))")
  }
}
