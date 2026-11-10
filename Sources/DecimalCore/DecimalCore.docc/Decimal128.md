# ``DecimalCore/Decimal128``

## Topics

### Converting Integers

- ``init(_:)-27wig``
- ``init(_:_:)-7g73``
- ``init(_:rounding:)-yvlc``
- ``init(_:rounding:_:)-7x0w``

### Converting Strings

- ``init(_:)-55gla``
- ``init(_:_:)-2hw90``
- ``init(_:rounding:)-21zme``
- ``init(_:rounding:_:)-b01n``

### Describing a Value

- ``description``
- ``debugDescription``
- ``hash(into:)``

### Converting from Floating-Point Values

- ``init(nearest:)``
- ``init(nearest:_:)``
- ``init(nearest:rounding:)``
- ``init(nearest:rounding:_:)``
- ``init(shortest:)-(Float16)``
- ``init(shortest:)-(Float)``
- ``init(shortest:)-(Double)``
- ``init(shortest:_:)-(Float16,_)``
- ``init(shortest:_:)-(Float,_)``
- ``init(shortest:_:)-(Double,_)``
- ``init(sign:exponent:significand:)``
- ``init(sign:exponent:significand:_:)``
- ``init(sign:exponent:significand:rounding:)``
- ``init(sign:exponent:significand:rounding:_:)``
- ``init(signOf:magnitudeOf:)``

### Converting to Floating-Point Values

- ``Swift/BinaryFloatingPoint/init(nearest:)``

### Converting with No Loss of Precision

- ``init(exactly:)-cgyl``
- ``init(exactly:)-6hh27``

### Finding and Changing Sign

- ``sign``
- ``magnitude``
- ``+(_:)``
- ``-(_:)``
- ``negate()``

### Adding

- ``+(_:_:)``
- ``adding(_:_:)``
- ``adding(_:rounding:)``
- ``adding(_:rounding:_:)``
- ``+=(_:_:)``
- ``add(_:_:)``
- ``add(_:rounding:)``
- ``add(_:rounding:_:)``

### Subtracting

- ``-(_:_:)``
- ``subtracting(_:_:)``
- ``subtracting(_:rounding:)``
- ``subtracting(_:rounding:_:)``
- ``-=(_:_:)``
- ``subtract(_:_:)``
- ``subtract(_:rounding:)``
- ``subtract(_:rounding:_:)``

### Multiplying

- ``*(_:_:)``
- ``multiplied(by:_:)``
- ``multiplied(by:rounding:)``
- ``multiplied(by:rounding:_:)``
- ``*=(_:_:)``
- ``multiply(by:_:)``
- ``multiply(by:rounding:)``
- ``multiply(by:rounding:_:)``

### Dividing

- ``/(_:_:)``
- ``divided(by:_:)``
- ``divided(by:rounding:)``
- ``divided(by:rounding:_:)``
- ``/=(_:_:)``
- ``divide(by:_:)``
- ``divide(by:rounding:)``
- ``divide(by:rounding:_:)``

### Fused Multiply–Add

- ``addingProduct(_:_:)``
- ``addingProduct(_:_:_:)``
- ``addingProduct(_:_:rounding:)``
- ``addingProduct(_:_:rounding:_:)``
- ``addProduct(_:_:)``
- ``addProduct(_:_:_:)``
- ``addProduct(_:_:rounding:)``
- ``addProduct(_:_:rounding:_:)``

### Remainder

- ``remainder(dividingBy:)``
- ``remainder(dividingBy:_:)``
- ``truncatingRemainder(dividingBy:)``
- ``truncatingRemainder(dividingBy:_:)``
- ``formRemainder(dividingBy:)``
- ``formRemainder(dividingBy:_:)``
- ``formTruncatingRemainder(dividingBy:)``
- ``formTruncatingRemainder(dividingBy:_:)``

### Square Root

- ``squareRoot()``
- ``squareRoot(_:)``
- ``squareRoot(rounding:)``
- ``squareRoot(rounding:_:)``
- ``formSquareRoot()``
- ``formSquareRoot(_:)``
- ``formSquareRoot(rounding:)``
- ``formSquareRoot(rounding:_:)``

### Rounding

- ``rounded()``
- ``rounded(_:)-5f9pf``
- ``rounded(_:)-19o7f``
- ``rounded(_:_:)``
- ``round()``
- ``round(_:)-51h0h``
- ``round(_:)-40pdh``
- ``round(_:_:)``

### Comparing Values

- ``==(_:_:)``
- ``!=(_:_:)``
- ``<(_:_:)``
- ``<=(_:_:)``
- ``>(_:_:)``
- ``>=(_:_:)``
- ``isEqual(to:)``
- ``isLess(than:)``
- ``isLessThanOrEqualTo(_:)``
- ``isTotallyOrdered(belowOrEqualTo:)``

### Floating-Point Properties

- ``floatingPointClass``
- ``isCanonical``
- ``isZero``
- ``isSubnormal``
- ``isNormal``
- ``isFinite``
- ``isInfinite``
- ``isNaN``
- ``isSignalingNaN``
- ``exponent``
- ``significand``
- ``nextUp``
- ``nextDown``
- ``ulp``

### Working with Quantum

- ``quantum``
- ``quantum(_:)``
- ``quantized(by:)``
- ``quantized(by:_:)``
- ``quantized(by:rounding:)``
- ``quantized(by:rounding:_:)``
- ``quantize(by:)``
- ``quantize(by:_:)``
- ``quantize(by:rounding:)``
- ``quantize(by:rounding:_:)``
- ``hasSameQuantum(as:)``

### Numeric Constants

- ``zero``
- ``leastNonzeroMagnitude``
- ``leastNormalMagnitude``
- ``ulpOfOne``
- ``pi``
- ``greatestFiniteMagnitude``
- ``infinity``
- ``nan``
- ``signalingNaN``

### Working with Representation

- ``bitPattern``
- ``binaryEncoding``
- ``decimalEncoding``
- ``exponentBitPattern``
- ``significandBitPattern``
- ``radix``
- ``init(bitPattern:)``
- ``init(binaryEncoding:)``
- ``init(decimalEncoding:)``
- ``init(sign:exponentBitPattern:significandBitPattern:)``
- ``init(nan:signaling:)``

### Encoding and Decoding

- ``encode(to:)``
- ``init(from:)``

### Infrequently Used Functionality

- ``init()``
- ``init(integerLiteral:)``
- ``advanced(by:)``
- ``distance(to:)``
