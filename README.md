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

| 'Everyday' operands<br>(ns/op)[^1] | DecimalAnnex<br>`d81020c` | Intel<br>2.0U5 | Boost<br>`215bbf0` | Go fork<br>`5032fd7` | Foundation<br>macOS 26.7 |
|:-----------------------------------|--------------------------:|---------------:|-------------------:|---------------------:|-------------------------:|
| Add                                |                   **2.8** |           28.7 |             18.1   |                6.4   |                    457.6 |
| Subtract                           |                   **2.9** |           29.8 |             18.6   |                6.5   |                    466.2 |
| Multiply                           |                   **1.8** |           27.7 |              5.1   |              **1.8** |                    332.1 |
| Divide                             |                  **10.8** |           53.2 |             86.6   |               14.5   |                    941.7 |
| Fused multiply-add                 |                   **4.1** |           51.9 |             45.1   |               12.2   |                        — |
| Square root                        |                  **33.2** |           98.3 |             35.3   |             1205.0   |                        — |
| IEEE remainder                     |                   **3.6** |           19.6 |             20.8   |               10.9   |                        — |
| Round to integer, ties away        |                   **2.4** |           16.4 |             12.2   |                2.9   |                    311.6 |

| Wide operands<br>(ns/op)[^2]       | DecimalAnnex<br>`d81020c` | Intel<br>2.0U5 | Boost<br>`215bbf0` | Go fork<br>`5032fd7` | Foundation<br>macOS 26.7 |
|:-----------------------------------|--------------------------:|---------------:|-------------------:|---------------------:|-------------------------:|
| Add                                |                  **19.4** |           36.1 |             27.8   |               20.5   |                    697.6 |
| Subtract                           |                  **19.4** |           36.6 |             28.4   |               21.3   |                    702.6 |
| Multiply                           |                    15.6   |           56.1 |             23.5   |             **14.3** |                    972.1 |
| Divide                             |                  **22.1** |           50.3 |             90.9   |               29.4   |                   1102.4 |
| Fused multiply-add                 |                  **30.6** |           90.2 |             62.1   |               35.7   |                        — |
| Square root                        |                  **33.6** |          100.6 |             39.1   |             1331.2   |                        — |
| IEEE remainder                     |                  **22.2** |          197.6 |             38.1   |               38.2   |                        — |
| Round to integer, ties away        |                   **6.8** |           17.9 |             23.6   |               11.3   |                    906.4 |

[^1]: Each operand pool contains 65,536 signed values, with independently shuffled copies for the second and third operands.
      (Square root uses the operand’s magnitude.)
      Tables show median nanoseconds per operation (ns/op) on Apple M2 Pro sampled in full batches of 4,096 operations.
      'Everyday' operands are sampled from: amounts in cents (50%), whole numbers (25%),
      and fractions of magnitude less than one with 2–8 decimal places (25%).
[^2]: Wide operands have 17–34 significand digits.
      In 7/8 of draws, the adjusted exponent is sampled uniformly from −6 through +16;
      in 7/64, the adjusted exponent is sampled uniformly from −24 through +64; and
      in 1/64, the quantum exponent is sampled uniformly from −6176 through +6111.

## Representation

Decimal floating-point values have a *quantum*: the power of ten associated with their integer significand (coefficient).
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
