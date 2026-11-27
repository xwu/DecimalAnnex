@available(anyAppleOS 26.0, *)
extension UInt128 {
  @inlinable
  @inline(always)
  internal static var _1e33: Self {
    1_000_000_000_000_000_000_000_000_000_000_000
  }

  @inlinable
  @inline(always)
  internal static var _1e34: Self {
    10_000_000_000_000_000_000_000_000_000_000_000
  }

  @usableFromInline
  internal static let _exp10: [39 of Self] = [
                                                        1,    //  0
                                                       10,    //  1
                                                      100,    //  2
                                                    1_000,    //  3
                                                   10_000,    //  4
                                                  100_000,    //  5
                                                1_000_000,    //  6
                                               10_000_000,    //  7
                                              100_000_000,    //  8
                                            1_000_000_000,    //  9
                                           10_000_000_000,    // 10
                                          100_000_000_000,    // 11
                                        1_000_000_000_000,    // 12
                                       10_000_000_000_000,    // 13
                                      100_000_000_000_000,    // 14
                                    1_000_000_000_000_000,    // 15
                                   10_000_000_000_000_000,    // 16
                                  100_000_000_000_000_000,    // 17
                                1_000_000_000_000_000_000,    // 18
                               10_000_000_000_000_000_000,    // 19
                              100_000_000_000_000_000_000,    // 20
                            1_000_000_000_000_000_000_000,    // 21
                           10_000_000_000_000_000_000_000,    // 22
                          100_000_000_000_000_000_000_000,    // 23
                        1_000_000_000_000_000_000_000_000,    // 24
                       10_000_000_000_000_000_000_000_000,    // 25
                      100_000_000_000_000_000_000_000_000,    // 26
                    1_000_000_000_000_000_000_000_000_000,    // 27
                   10_000_000_000_000_000_000_000_000_000,    // 28
                  100_000_000_000_000_000_000_000_000_000,    // 29
                1_000_000_000_000_000_000_000_000_000_000,    // 30
               10_000_000_000_000_000_000_000_000_000_000,    // 31
              100_000_000_000_000_000_000_000_000_000_000,    // 32
            1_000_000_000_000_000_000_000_000_000_000_000,    // 33
           10_000_000_000_000_000_000_000_000_000_000_000,    // 34
          100_000_000_000_000_000_000_000_000_000_000_000,    // 35
        1_000_000_000_000_000_000_000_000_000_000_000_000,    // 36
       10_000_000_000_000_000_000_000_000_000_000_000_000,    // 37
      100_000_000_000_000_000_000_000_000_000_000_000_000,    // 38
  ]

  /// Pre-computed reciprocal multiplication constants for division by `10**n`.
  ///
  /// Specifically, `shift = ⌊log2(5**n)⌋` and
  /// `multiplier = ⌈2**(128 + shift) / 5**n⌉`.
  @usableFromInline
  internal static let _divisionBy1e: [39 of (multiplier: Self, shift: Int)] = [
    (0, 0), // Unused: exponent must be in `1...38`.
    (0xCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCD,  2), //  1
    (0xA3D70A3D70A3D70A3D70A3D70A3D70A4,  4), //  2
    (0x83126E978D4FDF3B645A1CAC083126EA,  6), //  3
    (0xD1B71758E219652BD3C36113404EA4A9,  9), //  4
    (0xA7C5AC471B4784230FCF80DC33721D54, 11), //  5
    (0x8637BD05AF6C69B5A63F9A49C2C1B110, 13), //  6
    (0xD6BF94D5E57A42BC3D32907604691B4D, 16), //  7
    (0xABCC77118461CEFCFDC20D2B36BA7C3E, 18), //  8
    (0x89705F4136B4A59731680A88F8953031, 20), //  9
    (0xDBE6FECEBDEDD5BEB573440E5A884D1C, 23), // 10
    (0xAFEBFF0BCB24AAFEF78F69A51539D749, 25), // 11
    (0x8CBCCC096F5088CBF93F87B7442E45D4, 27), // 12
    (0xE12E13424BB40E132865A5F206B06FBA, 30), // 13
    (0xB424DC35095CD80F538484C19EF38C95, 32), // 14
    (0x901D7CF73AB0ACD90F9D37014BF60A11, 34), // 15
    (0xE69594BEC44DE15B4C2EBE687989A9B4, 37), // 16
    (0xB877AA3236A4B44909BEFEB9FAD487C3, 39), // 17
    (0x9392EE8E921D5D073AFF322E62439FD0, 41), // 18
    (0xEC1E4A7DB69561A52B31E9E3D06C32E6, 44), // 19
    (0xBCE5086492111AEA88F4BB1CA6BCF585, 46), // 20
    (0x971DA05074DA7BEED3F6FC16EBCA5E04, 48), // 21
    (0xF1C90080BAF72CB15324C68B12DD6339, 51), // 22
    (0xC16D9A0095928A2775B7053C0F178294, 53), // 23
    (0x9ABE14CD44753B52C4926A9672793543, 55), // 24
    (0xF79687AED3EEC5513A83DDBD83F52205, 58), // 25
    (0xC612062576589DDA95364AFE032A819E, 60), // 26
    (0x9E74D1B791E07E48775EA264CF55347E, 62), // 27
    (0xFD87B5F28300CA0D8BCA9D6E188853FD, 65), // 28
    (0xCAD2F7F5359A3B3E096EE45813A04331, 67), // 29
    (0xA2425FF75E14FC31A1258379A94D028E, 69), // 30
    (0x81CEB32C4B43FCF480EACF948770CED8, 71), // 31
    (0xCFB11EAD453994BA67DE18EDA5814AF3, 74), // 32
    (0xA6274BBDD0FADD61ECB1AD8AEACDD58F, 76), // 33
    (0x84EC3C97DA624AB4BD5AF13BEF0B113F, 78), // 34
    (0xD4AD2DBFC3D07787955E4EC64B44E865, 81), // 35
    (0xAA242499697392D2DDE50BD1D5D0B9EA, 83), // 36
    (0x881CEA14545C75757E50D64177DA2E55, 85), // 37
    (0xD9C7DCED53C7225596E7BD358C904A22, 88), // 38
  ]

  // The standard library's default implementation,
  // specialized for `UInt128` and always inlined.
  @inlinable
  @inline(always)
  internal func _multipliedFullWidth(
    by other: Self
  ) -> (high: Self, low: Self) {
    let mask: Self = 0xffff_ffff_ffff_ffff /* UInt64.max */
    let (x1, x0) = (self &>> 64, self & mask)
    let (y1, y0) = (other &>> 64, other & mask)
    let p00 = x0 &* y0
    let p01 = x1 &* y0 &+ (p00 &>> 64)
    let p10 = x0 &* y1 &+ (p01 & mask)
    let p11 = x1 &* y1 &+ (p01 &>> 64) &+ (p10 &>> 64)
    return (p11, p10 &<< 64 | p00 & mask)
  }

  @inlinable
  @inline(always)
  internal func _multipliedFullWidth(
    by1e exponent: Int
  ) -> (high: Self, low: Self) {
    let multiplier: UInt128 = ._exp10[exponent]
    if exponent <= 19 && self <= 0xffff_ffff_ffff_ffff /* UInt64.max */ {
      let x = UInt64(truncatingIfNeeded: self)
      let y = UInt64(truncatingIfNeeded: multiplier)
      return (0, UInt128(x) &* UInt128(y) /* self &* multiplier */)
    }
    return _multipliedFullWidth(by: multiplier)
  }

  // Division by constant integer using multiplication and shift
  // (cf. Granlund and Montgomery, 1994).
  @inlinable
  internal func _quotientAndRemainder(
    dividingBy1e exponent: Int
  ) -> (quotient: Self, remainder: Self) {
    guard exponent != 0 else {
      return (self, 0)
    }
    let (multiplier, shift): (UInt128, Int) = UInt128._divisionBy1e[exponent]
    let q =
      (self &>> exponent)._multipliedFullWidth(by: multiplier).high &>> shift
    let r = unsafe self &- q &* ._exp10[unchecked: exponent]
    return (q, r)
  }

  @inlinable
  internal static func _quotientAndRemainder(
    fullWidth dividend: (high: Self, low: Self),
    dividingBy1e exponent: Int
  ) -> (quotient: Self, remainder: Self) {
    guard exponent != 0 else {
      precondition(dividend.high == 0)
      return (dividend.low, 0)
    }
    let divisor: UInt128 = ._exp10[exponent]
    precondition(dividend.high < divisor)

    var (multiplier, shift): (UInt128, Int) =
      unsafe UInt128._divisionBy1e[unchecked: exponent]
    // In this case, we want `⌊2**(128 + shift) / 5**exponent⌋` to underestimate
    // the quotient (and overestimate the remainder).
    multiplier &-= 1
    // Rather than shift the dividend up front by `exponent` and then shift the
    // quotient finally by `shift` as in the helper above, we shift the quotient
    // by `shift + exponent`, since `divisor` is a multiple of `2**exponent`.
    shift &+= exponent
    var (hi, mid) = dividend.high._multipliedFullWidth(by: multiplier)
    let (mid_, _) = dividend.low._multipliedFullWidth(by: multiplier)
    let carry: Bool
    (mid, carry) = mid.addingReportingOverflow(mid_)
    if carry { hi &+= 1 }
    let q = (hi &<< (128 &- shift)) | (mid &>> shift)
    // With `multiplier` rounded down, we lose up to one `dividend` from the
    // computed product. After lower limb truncation, our underestimate is off
    // by at most `dividend.high + 1 <= divisor`. Since right shift computes
    // division by `2**shift` and `shift` selects the largest power of two that
    // does not exceed `divisor`, `q` underestimates the true flooring quotient
    // by at most `divisor / 2**shift <= 2`.

    // Since the actual `remainder` must be less than `divisor`, we know our
    // overestimate `r` must be representable in `UInt128` because it is at most
    // `remainder + divisor * 2 < 3 * (10**38) < UInt128.max`, and therefore
    // the high limb of the following subtraction must cancel.
    let r = dividend.low &- q &* divisor
    // Correct `r` if needed.
    if r >= divisor {
      let dd = divisor &<< 1 // `divisor * 2`.
      return r >= dd ? (q &+ 2, r &- dd) : (q &+ 1, r &- divisor)
    }
    return (q, r)
  }

  // Exact division by a constant (cf. Granlund and Montgomery, 1994 §9).
  @inlinable
  @inline(always)
  internal func _quotientIfExactDividingBy10() -> Self? {
    let m = 0xCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCD as UInt128 // Inverse of 5 (mod 2**128).
    let p = self &* m
    let q = p &>> 1 | p &<< 127
    guard q <= 34028236692093846346337460743176821145 /* .max / 10 */ else {
      return nil
    }
    return q
  }

  @inlinable
  @inline(always)
  internal func _quotientIfExactDividingBy100() -> Self? {
    let m = 0x28F5C28F5C28F5C28F5C28F5C28F5C29 as UInt128 // Inverse of 5**2 (mod 2**128).
    let p = self &* m
    let q = p &>> 2 | p &<< 126
    guard q <= 3402823669209384634633746074317682114 /* .max / 100 */ else {
      return nil
    }
    return q
  }

  @inlinable
  @inline(always)
  internal func _quotientIfExactDividingBy10000() -> Self? {
    let m = 0x495182A9930BE0DED288CE703AFB7E91 as UInt128 // Inverse of 5**4 (mod 2**128).
    let p = self &* m
    let q = p &>> 4 | p &<< 124
    guard q <= 34028236692093846346337460743176821 /* .max / 10**4 */ else {
      return nil
    }
    return q
  }

  @inlinable
  @inline(always)
  internal func _quotientIfExactDividingBy1e8() -> Self? {
    let m = 0xF36B7213EE9F5A78C767074B22E90E21 as UInt128 // Inverse of 5**8 (mod 2**128).
    let p = self &* m
    let q = p &>> 8 | p &<< 120
    guard q <= 3402823669209384634633746074317 /* .max / 10**8 */ else {
      return nil
    }
    return q
  }

  @inlinable
  @inline(always)
  internal func _quotientIfExactDividingBy1e16() -> Self? {
    let m = 0xF60B3275305C1066E4A4D1417CD9A041 as UInt128 // Inverse of 5**16 (mod 2**128).
    let p = self &* m
    let q = p &>> 16 | p &<< 112
    guard q <= 34028236692093846346337 /* .max / 10**16 */ else { return nil }
    return q
  }

  @inlinable
  @inline(always)
  internal func _quotientIfExactDividingBy1e32() -> Self? {
    let m = 0x62B42691AD836EB116590F420A835081 as UInt128 // Inverse of 5**32 (mod 2**128).
    let p = self &* m
    let q = p &>> 32 | p &<< 96
    guard q <= 3402823 /* .max / 10**32 */ else { return nil }
    return q
  }

  @inlinable
  @inline(always)
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
    return unsafe self >= ._exp10[unchecked: estimate]
      ? estimate
      : estimate &- 1
  }
}

@available(anyAppleOS 26.0, *)
extension UInt128 {
  // Reciprocal-based long division of a full-width dividend by a variable
  // divisor. A `Decimal128` integer significand needs only two 57-bit quotient
  // chunks. (An optional leading 14-bit chunk handles larger quotients.)
  @inlinable
  internal static func __quotientAndRemainder(
    fullWidth dividend: (high: Self, low: Self),
    dividingBy divisor: Self
  ) -> (quotient: Self, remainder: Self) {
    precondition(dividend.high < divisor && divisor < ._1e34)
    if divisor <= 0xffff_ffff /* UInt32.max */ {
      let d = UInt64(truncatingIfNeeded: divisor)
      if (dividend.high | (dividend.low &>> 64)) == 0 { // Expressed so as to emit only one branch.
        let x = UInt64(truncatingIfNeeded: dividend.low)
        let (q, r) = x.quotientAndRemainder(dividingBy: d)
        return (UInt128(q), UInt128(r))
      }
      var r = UInt64(truncatingIfNeeded: dividend.high)
      var q = dividend.low
      for _ in 0..<4 {
        let x = r &<< 32 | UInt64(truncatingIfNeeded: q &>> 96)
        let q_: UInt64
        (q_, r) = x.quotientAndRemainder(dividingBy: d)
        q = q &<< 32 | UInt128(q_)
      }
      return (q, UInt128(r))
    }

    // Normalize the divisor so that it's in `2**125 ..< 2**126`.
    // Two leading zero bits balance precision of `dh` and `reciprocal` below.
    let shift = divisor.leadingZeroBitCount &- 2
    let divisor = divisor &<< shift
    let high = (dividend.high &<< shift) | (dividend.low &>> (128 &- shift))
    let low = dividend.low &<< shift

    let dh = UInt64(truncatingIfNeeded: divisor &>> 64)
    // Compute an underestimate of the scaled reciprocal `2**121 / (dh + 1)`.
    var reciprocal = (UInt64.max / ((dh &>> 30) &+ 1)) &<< 27
    // Note flooring division and `... &+ 1` in the denominator,
    // both serving to bias the estimate downward.
    //
    // Now correct with a single Newton step.
    let error: UInt128 = (1 &<< 121) &- UInt128(reciprocal) &* UInt128(dh &+ 1)
    reciprocal &+= UInt64(truncatingIfNeeded: error &>> 32)
      .multipliedFullWidth(by: reciprocal).high &>> 25

    let mask: UInt128 = (1 &<< 57) &- 1
    var q2: UInt64
    var r2: UInt128
    if high < (divisor &>> 14) {
      q2 = 0
      r2 = (high &<< 14) | (low &>> 114)
    } else {
      q2 = UInt64(truncatingIfNeeded: high &>> 64)
        .multipliedFullWidth(by: reciprocal).high &>> 43
      r2 = ((high &<< 14) | (low &>> 114)) &- UInt128(q2) &* divisor
      if r2 >= divisor {
        q2 &+= 1
        r2 = r2 &- divisor
      }
    }
    var q1 = UInt64(truncatingIfNeeded: r2 &>> 64)
      .multipliedFullWidth(by: reciprocal).high
    var r1 = ((r2 &<< 57) | ((low &>> 57) & mask)) &- UInt128(q1) &* divisor
    if r1 >= divisor {
      q1 &+= 1
      r1 = r1 &- divisor
    }
    var q0 = UInt64(truncatingIfNeeded: r1 &>> 64)
      .multipliedFullWidth(by: reciprocal).high
    var r0 = ((r1 &<< 57) | (low & mask)) &- UInt128(q0) &* divisor
    if r0 >= divisor {
      q0 &+= 1
      r0 = r0 &- divisor
    }
    return (
      UInt128(q2) &<< 114 | UInt128(q1) &<< 57 | UInt128(q0),
      r0 &>> shift)
  }

  // Wrapper for reciprocal-based long division of a full-width dividend by a
  // variable divisor that uses a single-width division when it's cheaper than
  // setting up a reciprocal.
  @inlinable
  @inline(always)
  internal static func _quotientAndRemainder(
    fullWidth dividend: (high: Self, low: Self),
    dividingBy divisor: Self
  ) -> (quotient: Self, remainder: Self) {
    if dividend.high == 0 && (
      divisor <= 0xffff_ffff_ffff_ffff /* UInt64.max */ ||
        (dividend.low &>> 10) < divisor /* Empirically derived crossover. */
    ) {
      precondition(divisor != 0 && divisor < ._1e34)
      return dividend.low.quotientAndRemainder(dividingBy: divisor)
    }
    return __quotientAndRemainder(fullWidth: dividend, dividingBy: divisor)
  }
}
