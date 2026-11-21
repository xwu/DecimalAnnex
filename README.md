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
It has been tested (outside this repository) against published corpora, and it benchmarks favorably against reference implementations.

| Operation<br>('everyday' operands)[^1] | DecimalAnnex<br>0.2.1 | Intel<br>2.0U5 | Boost<br>`21bb2ed` | Foundation<br>macOS 26.7 |
|:---------------------------------------|----------------------:|---------------:|-------------------:|-------------------------:|
| Add                                    |               **6.3** |         11.9   |             16.1   |                    466.6 |
| Subtract                               |               **6.4** |         14.1   |             16.3   |                    445.6 |
| Multiply                               |               **3.2** |         23.5   |              5.4   |                    358.8 |
| Divide                                 |              **27.8** |         46.5   |             83.4   |                   1682.6 |
| Fused multiply-add                     |              **17.8** |         38.3   |             40.1   |                        — |
| Round to integer, ties to even         |               **3.9** |         11.0   |            **4.8** |                    540.8 |
| Convert text to decimal                |              **16.7** |         20.8   |             24.6   |                    545.3 |
| Convert decimal to text[^2]            |                29.2   |       **10.1** |             24.0   |                   1654.3 |

[^1]: Median ns/operation benchmarked on Apple M2 Pro using a generated harness.
      Mixture of 'everyday' operands included: signed values to two decimal places (50%), small-integer right-hand side (31.25%).
[^2]: Conversion to text includes initialization of a `String` value for DecimalAnnex and Foundation only.

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
