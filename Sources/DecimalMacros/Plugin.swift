#if Macros
import SwiftSyntaxMacros
import SwiftCompilerPlugin

@main
struct DecimalPlugin: CompilerPlugin {
  let providingMacros: [Macro.Type] = [
    Decimal128LiteralMacro.self
  ]
}
#else
@main
struct DecimalPlugin {
  static func main() { }
}
#endif
