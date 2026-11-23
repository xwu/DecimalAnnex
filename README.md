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

| 'Everyday' operands<br>(ns/op)[^1] | DecimalAnnex<br>`d7784c8` | Intel<br>2.0U5 | Boost<br>`215bbf0` | Go fork<br>`5032fd7` | Foundation<br>macOS 26.7 |
|:-----------------------------------|--------------------------:|---------------:|-------------------:|---------------------:|-------------------------:|
| Add                                |                   **2.9** |           29.4 |             18.4   |                6.5   |                    471.9 |
| Subtract                           |                   **2.9** |           30.2 |             18.7   |                6.7   |                    473.6 |
| Multiply                           |                   **1.8** |           28.2 |              5.5   |              **1.8** |                    337.6 |
| Divide                             |                  **12.1** |           52.8 |             87.6   |               14.5   |                    964.5 |
| Fused multiply-add                 |                   **4.4** |           52.4 |             46.1   |               12.2   |                        — |
| Square root                        |                    38.9   |           99.8 |           **35.7** |             1231.0   |                        — |
| IEEE remainder                     |                    15.4   |           20.4 |             21.3   |             **11.1** |                        — |
| Round to integer, ties to even     |                     4.5   |           19.4 |             13.2   |              **3.3** |                    322.6 |

| Wide operands<br>(ns/op)[^2]       | DecimalAnnex<br>`d7784c8` | Intel<br>2.0U5 | Boost<br>`215bbf0` | Go fork<br>`5032fd7` | Foundation<br>macOS 26.7 |
|:-----------------------------------|--------------------------:|---------------:|-------------------:|---------------------:|-------------------------:|
| Add                                |                  **19.6** |           37.1 |             28.1   |               20.8   |                    713.8 |
| Subtract                           |                  **19.6** |           37.7 |             28.9   |               21.4   |                    722.6 |
| Multiply                           |                    16.2   |           58.8 |             23.7   |             **15.2** |                    990.1 |
| Divide                             |                  **23.0** |           51.9 |             93.8   |               29.9   |                   1135.4 |
| Fused multiply-add                 |                  **31.1** |           92.3 |             63.0   |               36.6   |                        — |
| Square root                        |                    39.8   |          102.9 |           **39.2** |             1352.2   |                        — |
| IEEE remainder                     |                  **31.5** |          202.8 |             39.1   |               39.2   |                        — |
| Round to integer, ties to even     |                   **9.5** |           21.6 |             24.8   |               12.1   |                    930.8 |

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
