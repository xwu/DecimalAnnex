# DecimalAnnex

This module provides `Decimal128`, a 128-bit decimal floating-point type with 34 significant decimal digits defined by the [IEEE 754] specification.

[IEEE 754]: https://ieeexplore.ieee.org/document/8766229

```swift
import DecimalAnnex

let x: Decimal128 = 1/10
let y: Decimal128 = 2/10

x + y == 3/10  // true
```

`Decimal128` supports signed zeros, subnormal values, infinities, and NaNs, along with familiar operations for classification, comparison, and rounding.
It conforms to the standard library `FloatingPoint` protocol, making it usable in generic floating-point algorithms.

The implementation is written in native Swift and has no dependency on Foundation.
It has been tested (outside this repository) against published corpora, and it benchmarks favorably against reference implementations:

| Operation                      | DecimalAnnex<br>0.2.0 | Intel<br>2.0U5 | Boost<br>`21bb2ed` | Foundation<br>macOS 26.7 |
|--------------------------------|----------------------:|---------------:|-------------------:|-------------------------:|
| Add                            |               **5.7** |         11.1   |             15.7   |                    424.0 |
| Subtract                       |               **5.7** |         12.5   |             16.3   |                    406.0 |
| Multiply                       |               **2.9** |         21.1   |              5.8   |                    327.4 |
| Divide                         |              **24.7** |         40.8   |             77.5   |                   1522.8 |
| Fused multiply-add             |              **15.7** |         34.1   |             37.4   |                        — |
| Round to integer, ties to even |                 7.9   |         10.0   |            **6.2** |                    495.4 |
| Convert text to decimal        |              **14.9** |         17.9   |             21.5   |                    478.7 |
| Convert decimal to text        |                26.3   |       **10.0** |             22.6   |                   1462.3 |

> *Median ns/operation for mixture of 'everyday' operands (50% signed values to two decimal places).
> Benchmarked on Apple M2 Pro using generated harness.  
> Conversion to text includes initialization of a `String` value for DecimalAnnex and Foundation only.*

## Representation

Decimal floating-point values have a *quantum*: the power of ten associated with their integer coefficient.
This distinguishes representations such as `1.0` and `1.00` that compare equal to each other and hash identically.
For arithmetic operations, IEEE 754 "preferred exponent" rules determine the representation of their results;
use `quantized(by:)` to select a quantum explicitly.

To avoid loss of precision and preserve meaningful trailing zeros, `Decimal128` doesn't conform to `ExpressibleByFloatLiteral`.
Instead, values can be created using decimal float literals by calling a macro,
which will also warn if creating a value from the literal argument requires inexact rounding.

```swift
let a = #Decimal128(1.0)
let b = #Decimal128(1.00)

print(a)                // 1.0
print(b)                // 1.00
a == b                  // true
a.quantum == b.quantum  // false
```

You can omit the macro (and its dependencies) by disabling the package trait `Macros`.

## Rounding direction and status flags

Operations that may round their result can take a `FloatingPointRoundingRule` argument for non-default rounding direction.
Callers can also provide an `inout` value to accumulate IEEE floating-point arithmetic status flags.
The flags distinguish invalid operations, division by zero, overflow, underflow, and inexact results.

```swift
var flags: DecimalFloatingPointStatusFlags = []
_ = (1 as Decimal128).divided(by: 3, rounding: .toNearestOrEven, &flags)

flags.contains(.inexact)  // true
```
