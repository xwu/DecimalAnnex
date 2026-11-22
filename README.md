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

| 'Everyday' operands<br>(ns/op)[^1] | DecimalAnnex<br>0.3.0 | Intel<br>2.0U5 | Boost<br>`21bb2ed` | Foundation<br>macOS 26.7 |
|:-----------------------------------|----------------------:|---------------:|-------------------:|-------------------------:|
| Add                                |              **12.0** |           28.8 |             18.5   |                    463.9 |
| Subtract                           |              **12.3** |           29.8 |             18.7   |                    458.4 |
| Multiply                           |               **2.8** |           26.9 |              5.4   |                    330.7 |
| Divide                             |              **26.1** |           53.3 |             87.1   |                    959.8 |
| Fused multiply-add                 |              **17.5** |           50.4 |             44.8   |                        — |
| Square root                        |                37.0   |           96.2 |           **35.4** |                        — |
| IEEE remainder                     |              **15.2** |           20.9 |             20.8   |                        — |
| Round to integer, ties to even     |               **4.5** |           19.2 |             13.4   |                    315.1 |

| Wide operands<br>(ns/op)[^2]       | DecimalAnnex<br>0.3.0 | Intel<br>2.0U5 | Boost<br>`21bb2ed` | Foundation<br>macOS 26.7 |
|:-----------------------------------|----------------------:|---------------:|-------------------:|-------------------------:|
| Add                                |              **20.1** |           36.5 |             28.5   |                    692.0 |
| Subtract                           |              **19.9** |           36.7 |             28.4   |                    711.8 |
| Multiply                           |              **17.8** |           56.0 |             23.2   |                    974.1 |
| Divide                             |              **47.2** |           49.5 |             90.6   |                   1095.4 |
| Fused multiply-add                 |              **30.8** |           89.6 |             60.2   |                        — |
| Square root                        |              **38.6** |          101.9 |           **38.4** |                        — |
| IEEE remainder                     |              **31.4** |          193.4 |             39.5   |                        — |
| Round to integer, ties to even     |               **9.5** |           21.3 |             25.2   |                    928.6 |

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
