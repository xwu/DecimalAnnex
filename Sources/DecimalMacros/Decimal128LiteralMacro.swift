import DecimalCore
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct Decimal128LiteralMacro: ExpressionMacro {
  public static func expansion(
    of node: some FreestandingMacroExpansionSyntax,
    in context: some MacroExpansionContext
  ) throws -> ExprSyntax {
    guard
      node.arguments.count == 1,
      let arg = node.arguments.first,
      arg.label == nil
    else {
      throw MacroExpansionErrorMessage(
        "Expected decimal float or integer literal as single unlabeled argument")
    }
    let literal = try _normalize(arg.expression)
    guard #available(anyAppleOS 26.0, *) else {
      throw MacroExpansionErrorMessage(
        "'#Decimal128' macro expansion on host anyAppleOS requires version 26.0 or later")
    }
    guard let value = DecimalCore::Decimal128(literal) else {
      throw MacroExpansionErrorMessage(
        "Unable to initialize 'Decimal128' value from specified literal")
    }
    return ".init(bitPattern: \(raw: String(value.bitPattern)))"
  }

  internal static func _normalize(_ argument: ExprSyntax) throws -> String {
    let sign: String
    let expr: ExprSyntax
    if let prefix = argument.as(PrefixOperatorExprSyntax.self) {
      sign = prefix.operator.text
      guard sign == "+" || sign == "-" else {
        throw MacroExpansionErrorMessage(
          "Expected decimal float or integer literal optionally preceded by '+' or '-'")
      }
      expr = prefix.expression
    } else {
      sign = ""
      expr = argument
    }
    let digits: String
    if let literal = expr.as(FloatLiteralExprSyntax.self) {
      digits = literal.literal.text
    } else if let literal = expr.as(IntegerLiteralExprSyntax.self) {
      digits = literal.literal.text
    } else {
      throw MacroExpansionErrorMessage(
        "Expected decimal float or integer literal")
    }
    let lower = digits.lowercased()
    guard
      !lower.hasPrefix("0x") && !lower.hasPrefix("0o") && !lower.hasPrefix("0b")
    else {
      throw MacroExpansionErrorMessage(
        "Expected decimal float or integer literal")
    }
    return sign + digits.filter { $0 != "_" }
  }
}
