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

## Representation

Decimal floating-point values carry a *quantum*: the power of ten associated with their integer coefficient.
This distinguishes representations such as `1.0` and `1.00` that compare equal to each other and hash identically.
Arithmetic follows IEEE 754 "preferred exponent" rules, and `quantized(by:rounding:)` selects a particular quantum explicitly.

Although `Decimal128` uses the IEEE binary integer decimal (BID) encoding internally,
you can use the `decimalEncoding` property and `init(decimalEncoding:)` to work with the densely packed decimal (DPD) interchange encoding.

## Rounding direction and status flags

Operations that may round their result can take a `FloatingPointRoundingRule` for non-default rounding direction.

Callers can also supply an `inout DecimalFloatingPointStatusFlags` value to accumulate IEEE floating-point arithmetic status flags.
The flags distinguish invalid operations, division by zero, overflow, underflow, and inexact results.

```swift
var flags: DecimalFloatingPointStatusFlags = []
_ = (1 as Decimal128).divided(by: 3, rounding: .toNearestOrEven, &flags)
flags.contains(.inexact)  // true
```
