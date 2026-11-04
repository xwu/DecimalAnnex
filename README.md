# DecimalAnnex

This module provides `Decimal128`, a decimal floating-point type based on the IEEE 754 decimal128 format with 34 significant decimal digits in 128 bits.

```swift
import DecimalAnnex

let x: Decimal128 = 1/10
let y: Decimal128 = 2/10

x + y == 3/10  // true
```

`Decimal128` provides the usual arithmetic operators and conforms to the `FloatingPoint` protocol, making it usable in generic floating-point algorithms.
It supports signed zeros, subnormal values, infinities, and NaNs, along with familiar operations for classification, comparison, and rounding.

The implementation is written in native Swift. It requires no decimal floating-point hardware and has no dependency on Foundation.

> [!NOTE]
> This project is still at an early stage of development. Fused multiply-add, remainder, and square root operations are unimplemented.
> Other operations, however, are expected to be usable, correct, and performant. Documentation and test cases lag.

## Representation

Decimal floating-point values carry a *quantum*: the power of ten associated with their integer coefficient.
This distinguishes representations such as `1.0` and `1.00` that compare equal to each other and hash identically.
Arithmetic operations follow IEEE 754 "preferred exponent" rules to determine the representation of their result,
while `quantized(by:rounding:)` selects a quantum explicitly.

To avoid loss of decimal precision and preserve meaningful trailing zeros,
`Decimal128` doesn't conform to `ExpressibleByFloatLiteral`,
but values can be created straightforwardly using decimal float literals by calling a macro.

```swift
let a = #Decimal128(1.0)
let b = #Decimal128(1.00)

print(a)                // 1.0
print(b)                // 1.00
a == b                  // true
a.quantum == b.quantum  // false
```

The macro diagnoses literal expressions that have to be rounded with a warning and, if the rounded value is finite, a fix-it.

## Rounding direction and status flags

Operations that may round their result can take a `FloatingPointRoundingRule` for non-default rounding direction.

Callers can also supply an `inout DecimalFloatingPointStatusFlags` value to accumulate IEEE floating-point arithmetic status flags.
The flags distinguish invalid operations, division by zero, overflow, underflow, and inexact results.

```swift
var flags: DecimalFloatingPointStatusFlags = []
_ = (1 as Decimal128).divided(by: 3, rounding: .toNearestOrEven, &flags)

flags.contains(.inexact)  // true
```
