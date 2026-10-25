import SwiftSyntaxMacros
import SwiftCompilerPlugin

@main
struct DecimalPlugin: CompilerPlugin {
  let providingMacros: [Macro.Type] = [
    Decimal128LiteralMacro.self
  ]
}
