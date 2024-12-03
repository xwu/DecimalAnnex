@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension UInt128 {
  @inlinable
  internal var _commonLogarithm: Int {
    // See discussion at:
    // https://lemire.me/blog/2021/05/28/computing-the-number-of-digits-of-an-integer-quickly/
    //
    // To approximate `1 / log2(10)`, we must use 19/64 (expressed here as
    // `(19 &* ...) &>> 6`) instead of 9/32. This is so that the estimate (after
    // adding one) is at least the true floor log10.
    //
    // Meanwhile, we avoid using an even more precise approximation such as
    // 77/256, because if we overestimate `(UInt128.max)._commonLogarithm` then
    // we'll end up trying to compute `10 ** 39` while checking if our estimate
    // is off by one, which results in overflow.
    let estimate = ((19 &* (127 &- (self|1).leadingZeroBitCount)) &>> 6) &+ 1
    return self >= UInt128._exp10(estimate) ? estimate : estimate &- 1
  }

  @inlinable
  internal static func _exp10(_ n: Int) -> Self {
    let table: [UInt64] = [
                               1,
                              10,
                             100,
                           1_000,
                          10_000,
                         100_000,
                       1_000_000,
                      10_000_000,
                     100_000_000,
                   1_000_000_000,
                  10_000_000_000,
                 100_000_000_000,
               1_000_000_000_000,
              10_000_000_000_000,
             100_000_000_000_000,
           1_000_000_000_000_000,
          10_000_000_000_000_000,
         100_000_000_000_000_000,
       1_000_000_000_000_000_000,
      10_000_000_000_000_000_000
    ]
    if n <= 19 { return n < 0 ? 0 : UInt128(table[n]) }
    return 10_000_000_000_000_000_000 &* UInt128(table[n &- 19])
  }

  @inlinable
  internal func _quotientAndRemainderDividingBy1e18()
  -> (quotient: Self, remainder: Self) {
    // See Granlund & Montgomery (1994); in particular, theorem 4.2.
    //
    // Here, we right shift the dividend by 18, then compute unsigned division
    // by 5**18 using multiplication and shift. Note, therefore, that the max
    // dividend is only 110 bits wide.
    let m: Self = 748288838313422294120286634350737
    let q = (self &>> 18).multipliedFullWidth(by: m).high &>> 23
    let r = self &- q &* 1_000_000_000_000_000_000
    return (q, r)
  }
}
