@_exported import DecimalCore

/// Constructs a decimal value from the given literal at compile time.
///
/// Accepts an integer or float literal optionally preceded by `+` or `-`.
/// The expansion embeds the value's bit pattern; no parsing occurs at runtime.
@available(anyAppleOS 26.0, *)
@freestanding(expression)
public macro Decimal128(_ literal: Double) -> Decimal128 =
  #externalMacro(module: "DecimalMacros", type: "Decimal128LiteralMacro")
