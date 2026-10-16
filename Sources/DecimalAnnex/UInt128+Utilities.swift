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

  @inlinable
  @inline(always)
  internal func _multipliedFullWidth(
    by1e exponent: Int
  ) -> (high: Self, low: Self) {
    let multiplier: UInt128 = unsafe ._exp10[unchecked: exponent]
    if exponent <= 19 && self <= 0xffff_ffff_ffff_ffff /* UInt64.max */ {
      let (hi, lo) =
        UInt64(truncatingIfNeeded: self).multipliedFullWidth(
          by: UInt64(truncatingIfNeeded: multiplier))
      return (0, UInt128(hi) &<< 64 | UInt128(lo))
    }
    return multipliedFullWidth(by: multiplier)
  }

  // Division by constant integer using multiplication and shift
  // (cf. Granlund and Montgomery, 1994).
  @inlinable
  internal func _quotientAndRemainder(
    dividingBy1e exponent: Int
  ) -> (quotient: Self, remainder: Self) {
    let (multiplier, shift): (UInt128, Int) =
      switch exponent {
      case  1: (0xCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCD,  2)
      case  2: (0xA3D70A3D70A3D70A3D70A3D70A3D70A4,  4)
      case  3: (0x83126E978D4FDF3B645A1CAC083126EA,  6)
      case  4: (0xD1B71758E219652BD3C36113404EA4A9,  9)
      case  5: (0xA7C5AC471B4784230FCF80DC33721D54, 11)
      case  6: (0x8637BD05AF6C69B5A63F9A49C2C1B110, 13)
      case  7: (0xD6BF94D5E57A42BC3D32907604691B4D, 16)
      case  8: (0xABCC77118461CEFCFDC20D2B36BA7C3E, 18)
      case  9: (0x89705F4136B4A59731680A88F8953031, 20)
      case 10: (0xDBE6FECEBDEDD5BEB573440E5A884D1C, 23)
      case 11: (0xAFEBFF0BCB24AAFEF78F69A51539D749, 25)
      case 12: (0x8CBCCC096F5088CBF93F87B7442E45D4, 27)
      case 13: (0xE12E13424BB40E132865A5F206B06FBA, 30)
      case 14: (0xB424DC35095CD80F538484C19EF38C95, 32)
      case 15: (0x901D7CF73AB0ACD90F9D37014BF60A11, 34)
      case 16: (0xE69594BEC44DE15B4C2EBE687989A9B4, 37)
      case 17: (0xB877AA3236A4B44909BEFEB9FAD487C3, 39)
      case 18: (0x9392EE8E921D5D073AFF322E62439FD0, 41)
      case 19: (0xEC1E4A7DB69561A52B31E9E3D06C32E6, 44)
      case 20: (0xBCE5086492111AEA88F4BB1CA6BCF585, 46)
      case 21: (0x971DA05074DA7BEED3F6FC16EBCA5E04, 48)
      case 22: (0xF1C90080BAF72CB15324C68B12DD6339, 51)
      case 23: (0xC16D9A0095928A2775B7053C0F178294, 53)
      case 24: (0x9ABE14CD44753B52C4926A9672793543, 55)
      case 25: (0xF79687AED3EEC5513A83DDBD83F52205, 58)
      case 26: (0xC612062576589DDA95364AFE032A819E, 60)
      case 27: (0x9E74D1B791E07E48775EA264CF55347E, 62)
      case 28: (0xFD87B5F28300CA0D8BCA9D6E188853FD, 65)
      case 29: (0xCAD2F7F5359A3B3E096EE45813A04331, 67)
      case 30: (0xA2425FF75E14FC31A1258379A94D028E, 69)
      case 31: (0x81CEB32C4B43FCF480EACF948770CED8, 71)
      case 32: (0xCFB11EAD453994BA67DE18EDA5814AF3, 74)
      case 33: (0xA6274BBDD0FADD61ECB1AD8AEACDD58F, 76)
      case 34: (0x84EC3C97DA624AB4BD5AF13BEF0B113F, 78)
      case 35: (0xD4AD2DBFC3D07787955E4EC64B44E865, 81)
      case 36: (0xAA242499697392D2DDE50BD1D5D0B9EA, 83)
      case 37: (0x881CEA14545C75757E50D64177DA2E55, 85)
      case 38: (0xD9C7DCED53C7225596E7BD358C904A22, 88)
      default: preconditionFailure()
      }
    let q =
      (self &>> exponent).multipliedFullWidth(by: multiplier).high &>> shift
    let r = unsafe self &- q &* ._exp10[unchecked: exponent]
    return (q, r)
  }

  @inlinable
  internal static func _quotientAndRemainder(
    fullWidth dividend: (high: Self, low: Self),
    dividingBy1e exponent: Int
  ) -> (quotient: Self, remainder: Self) {
    assert(dividend.high < UInt128._exp10[exponent])

    // One round of short division in base `2**128`
    //   (cf. Knuth exercise 4.3.1-16).
    // Requires `e <= 19` and `high < 10**e`,
    //   s.t. `high * r1` overflows at most once.
    @inline(always)
    func _divide(high: Self, low: Self, by1e e: Int) -> (Self, Self) {
      // Since base `2**128` is not a multiple of the divisor `10**e`,
      // we split the base into `q1 * d + r1`.
      let (q1, r1): (UInt128, UInt128) =
        switch e {
        case  1: (34028236692093846346337460743176821145, 6)
        case  2: (3402823669209384634633746074317682114, 56)
        case  3: (340282366920938463463374607431768211, 456)
        case  4: (34028236692093846346337460743176821, 1456)
        case  5: (3402823669209384634633746074317682, 11456)
        case  6: (340282366920938463463374607431768, 211456)
        case  7: (34028236692093846346337460743176, 8211456)
        case  8: (3402823669209384634633746074317, 68211456)
        case  9: (340282366920938463463374607431, 768211456)
        case 10: (34028236692093846346337460743, 1768211456)
        case 11: (3402823669209384634633746074, 31768211456)
        case 12: (340282366920938463463374607, 431768211456)
        case 13: (34028236692093846346337460, 7431768211456)
        case 14: (3402823669209384634633746,  7431768211456) // (sic)
        case 15: (340282366920938463463374, 607431768211456)
        case 16: (34028236692093846346337, 4607431768211456)
        case 17: (3402823669209384634633, 74607431768211456)
        case 18: (340282366920938463463, 374607431768211456)
        case 19: (34028236692093846346, 3374607431768211456)
        default: preconditionFailure()
        }
      // Substituting, the dividend becomes `high * (q1 * d + r1) + low`.
      // Rearranging, `d * (high * q1) + (high * r1 + low)`.
      //
      // The result of full-width flooring division by `d` is then
      // `(high * q1) + ⌊ (high * r1 + low) / d ⌋`, and the remainder is
      // `(high * r1 + low) % d`.
      //
      // Compute `high * r1 + low`, which may overflow by a carry bit
      // (`high * r1` itself can't overflow, since `high < d` and `r1 < d`
      // and `d * d < UInt128.max`):
      let (sum_, carry_) = low.addingReportingOverflow(high &* r1)
      let carry: UInt128 = carry_ ? 1 : 0
      // Compute `⌊ (high * r1 + low) / d ⌋` and `(high * r1 + low) % d`.
      // When there's been a carry, we again use the identity
      // `2**128 = q1 * d + r1`, giving us:
      //
      //     (high * r1 + low) / d
      //   = (sum_ + 2**128) / d
      //   = (sum_ + q1 * d + r1) / d
      //   = (sum_ + r1) / d + q1
      //
      // That is, we add `carry * r1` to the value to be divided by `d`...
      let (q2, r2) =
        (sum_ &+ carry &* r1)._quotientAndRemainder(dividingBy1e: e)
      // ...and we need to add `carry * q1` to the final quotient.
      return (high &* q1 &+ carry &* q1 &+ q2, r2)
    }

    if exponent <= 19 {
      return _divide(high: dividend.high, low: dividend.low, by1e: exponent)
    }
    // First divide by `10**19`, then by `10**(e - 19)`.
    let (q1, r1) = dividend.high._quotientAndRemainder(dividingBy1e: 19)
    let (q2, r2) = _divide(high: r1, low: dividend.low, by1e: 19)
    let (q3, r3) = _divide(high: q1, low: q2, by1e: exponent &- 19)
    return (q3, r3 &* 10_000_000_000_000_000_000 &+ r2)
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
