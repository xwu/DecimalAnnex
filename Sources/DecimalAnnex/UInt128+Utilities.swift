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

  @inlinable
  @inline(always)
  internal func _multipliedFullWidth(
    by1e exponent: Int
  ) -> (high: Self, low: Self) {
    let multiplier: UInt128 = ._exp10[exponent]
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
    guard exponent != 0 else {
      return (self, 0)
    }
    let (multiplier, shift): (UInt128, Int) = UInt128._divisionBy1e[exponent]
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
    var (hi, mid) = dividend.high.multipliedFullWidth(by: multiplier)
    let (mid_, _) = dividend.low.multipliedFullWidth(by: multiplier)
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
  // Division of a full-width dividend by a variable divisor
  // (cf. Knuth, Algorithm D; Möller and Granlund, 2011, Algorithm 4).
  @inlinable
  internal static func _quotientAndRemainder(
    fullWidth dividend: (high: Self, low: Self),
    dividingBy divisor: Self
  ) -> (quotient: Self, remainder: Self) {
    precondition(dividend.high < divisor && divisor < ._1e34)
    if dividend.high == 0 && divisor <= 0xffff_ffff_ffff_ffff /* UInt64.max */ {
      return dividend.low.quotientAndRemainder(dividingBy: divisor)
    }

    // Normalize so that the divisor's most significant bit is set.
    // Since `0 < divisor < 10**34 < 2**113`, `shift` is in `15...127`;
    // `128 &- shift` is never 128, which a masking shift would treat as 0.
    let shift = divisor.leadingZeroBitCount
    let divisor = divisor &<< shift
    let high = dividend.high &<< shift | dividend.low &>> (128 &- shift)
    let low = dividend.low &<< shift
    // Compute high and low halves of the normalized divisor (Knuth's `v`).
    let vh = UInt64(truncatingIfNeeded: divisor &>> 64)
    let vl = UInt64(truncatingIfNeeded: divisor)
    // Compute `⌊(2**128 - 1) / vh⌋ - 2**64` once for both quotient words.
    // The actual approximation to `1 / vh` is `(2**64 + reciprocal) / 2**128`;
    // the leading `2**64` is implicit and we store the remaining 64 bits.
    let reciprocal = vh.dividingFullWidth((~vh, .max)).quotient

    // Divides `high << 64 | low` by `divisor`, where `high < divisor`,
    // returning the quotient word and the remainder.
    @inline(always)
    func divide(_ high: UInt128, _ low: UInt64) -> (UInt64, UInt128) {
      // Compute the high and low halves of `high`.
      let hh = UInt64(truncatingIfNeeded: high &>> 64)
      let hl = UInt64(truncatingIfNeeded: high)
      var q: UInt64
      var r: UInt128
      if hh == vh {
        // The quotient of `high` divided by `vh` would overflow `UInt64`.
        q = .max
        r = UInt128(hl) &+ UInt128(vh)
      } else {
        // Divide `high` by `vh` using `reciprocal`
        // (accounting for the implicit leading `2**64`).
        let product = hh.multipliedFullWidth(by: reciprocal)
        // `sum` is the low half of the estimate `product + high`.
        let (sum, carry) = product.low.addingReportingOverflow(hl)
        q = product.high &+ hh &+ (carry ? 1 : 0) &+ 1
        // `... &+ 1` selects the middle candidate of three for correction.
        var r_ = hl &- q &* vh
        // Negative mathematical remainders wrap to values greater than `sum`.
        if r_ > sum {
          q &-= 1
          r_ &+= vh
        }
        // A second correction may undo an unnecessary first correction.
        if r_ >= vh {
          q &+= 1
          r_ &-= vh
        }
        r = UInt128(r_)
      }
      // Account for the low half of the normalized divisor, decreasing `q` by
      // at most two. A remainder above `UInt64.max` needs no correction.
      while r <= 0xffff_ffff_ffff_ffff /* UInt64.max */ &&
          UInt128(q) &* UInt128(vl) > (r &<< 64 | UInt128(low)) {
        q &-= 1
        r &+= UInt128(vh)
      }
      // Although `r` may have 65 bits, we know the remainder fits in `UInt128`,
      // so the following computation preserves the correct result even when
      // shifting `r` discards a bit.
      return (q, (r &<< 64 | UInt128(low)) &- UInt128(q) &* UInt128(vl))
    }

    let (qh, r_) = divide(high, UInt64(truncatingIfNeeded: low &>> 64))
    let (ql, r) = divide(r_, UInt64(truncatingIfNeeded: low))
    return (UInt128(qh) &<< 64 | UInt128(ql), r &>> shift)
  }
}
