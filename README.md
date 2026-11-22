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

| 'Everyday' operands<br>(ns/op)[^1] | DecimalAnnex<br>`a6c9786` | Intel<br>2.0U5 | Boost<br>`21bb2ed` | Foundation<br>macOS 26.7 |
|:-----------------------------------|--------------------------:|---------------:|-------------------:|-------------------------:|
| Add                                |                  **16.7** |           40.9 |             25.7   |                    657.4 |
| Subtract                           |                  **17.4** |           42.6 |             26.2   |                    671.3 |
| Multiply                           |                   **4.0** |           38.8 |              7.6   |                    472.6 |
| Divide                             |                  **37.4** |           72.4 |            122.1   |                   1349.0 |
| Fused multiply-add                 |                  **24.5** |           73.6 |             63.7   |                        — |
| Square root                        |                    54.0   |          139.7 |           **49.6** |                        — |
| IEEE remainder                     |                  **21.6** |           28.7 |             29.9   |                        — |
| Round to integer, ties to even     |                   **6.3** |           27.1 |             18.4   |                    451.9 |

| Wide operands<br>(ns/op)[^2]       | DecimalAnnex<br>`a6c9786` | Intel<br>2.0U5 | Boost<br>`21bb2ed` | Foundation<br>macOS 26.7 |
|:-----------------------------------|--------------------------:|---------------:|-------------------:|-------------------------:|
| Add                                |                  **27.7** |           51.3 |             39.5   |                   1004.9 |
| Subtract                           |                  **28.1** |           52.4 |             40.1   |                   1009.1 |
| Multiply                           |                  **24.8** |           82.4 |             33.1   |                   1388.4 |
| Divide                             |                  **66.9** |           71.3 |            128.5   |                   1585.2 |
| Fused multiply-add                 |                  **45.1** |          128.2 |             88.2   |                        — |
| Square root                        |                  **55.3** |          143.2 |           **55.3** |                        — |
| IEEE remainder                     |                  **43.7** |          286.6 |             54.8   |                        — |
| Round to integer, ties to even     |                  **13.3** |           30.3 |             35.1   |                   1311.0 |

[^1]: Each operand pool contains 65,536 signed values, with independently shuffled copies for the second and third operands.
      (Square root uses the operand’s magnitude.)
      Tables show median nanoseconds per operation (ns/op) on Apple M2 Pro sampled in full batches of 4,096 operations.
      'Everyday' operands are sampled from: amounts in cents (50%), whole numbers (25%),
      and fractions of magnitude less than one with two to eight decimal places (25%).
[^2]: Wide operands have 17–34 significand digits.
      In 7/8 of draws, the adjusted exponent is sampled uniformly from −6 through +16;
      in 7/64, the adjusted exponent is sampled uniformly from −24 through +64; and
      in 1/64, the quantum exponent is sampled uniformly from −6176 through +6111.

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
