@available(macOS 15.0, *)
extension UInt128 {
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

@frozen
public enum _DPD { }

extension _DPD {
  @inlinable
  public static func decode(_ declet: UInt16) -> UInt16 {
    precondition(declet < 1024)

    // We'll refer to the bits of the encoded value as follows:
    //
    //    MSB                                 LSB
    //   ┌───┬───┬───┬───┬───┬───┬───┬───┬───┬───┐
    //   │ p │ q │ r │ s │ t │ u │ v │ w │ x │ y │
    //   └───┴───┴───┴───┴───┴───┴───┴───┴───┴───┘

    let pqr = declet &>> 7
    let stu = (declet &>> 4) & 7
    let vwxy = declet & 15

    // When v == 0 or vwx == 0b100, the encoded value is
    // pqr * 100 + stu * 10 + vwxy.
    if vwxy <= 0b1001 {
        return pqr &* 100 &+ stu &* 10 &+ vwxy
    }

    // For all remaining values, v == 1.
    // We'll use pqstwx as an index to look up the partial result in a table,
    // then add r * 100 + u * 10 + y.
    let index = Int(((pqr & 6) &<< 3) | ((stu & 6) &<< 1) | ((vwxy & 6) &>> 1))
    let table: [UInt16] = [
        8,  80, 800, 880,
       28,  82, 820, 808,
       48,  84, 840,  88,
       68,  86, 860, 888,
      208, 280, 802, 882,
      228, 282, 822, 828,
      248, 284, 842, 288,
      268, 286, 862, 888,
      408, 480, 804, 884,
      428, 482, 824, 848,
      448, 484, 844, 488,
      468, 486, 864, 888,
      608, 680, 806, 886,
      628, 682, 826, 868,
      648, 684, 846, 688,
      668, 686, 866, 888,
    ]
    return table[index] &+ (pqr & 1) &* 100 &+ (stu & 1) &* 10 &+ (vwxy & 1)
  }

  @available(macOS 15.0, *)
  @inlinable
  public static func decode(_ significand: UInt128) -> UInt128 {
    // FIXME: Tighten this precondition so that 'a' cannot exceed 9.
    precondition(significand < (1 as UInt128) &<< 114)

    // We'll refer to declets as follows:
    //
    //     Bit index                                   LSB
    //     110 100  90  80  70  60  50  40  30  20  10   0
    //       ╎   ╎   ╎   ╎   ╎   ╎   ╎   ╎   ╎   ╎   ╎   ╎
    //     113 109  99  89  79  69  59  49  39  29  19   9
    //     ─── ─── ─── ─── ─── ─── ─── ─── ─── ─── ─── ───
    //      a   b   c   d   e   f   g   h   i   j   k   m

    let abcdef = UInt64(truncatingIfNeeded: significand &>> 60)
    let ghijkm = UInt64(truncatingIfNeeded: significand & ((1 &<< 60) &- 1))

    let abc = UInt32(truncatingIfNeeded: abcdef &>> 30)
    let def = UInt32(truncatingIfNeeded: abcdef & ((1 &<< 30) &- 1))
    let ghi = UInt32(truncatingIfNeeded: ghijkm &>> 30)
    let jkm = UInt32(truncatingIfNeeded: ghijkm & ((1 &<< 30) &- 1))

    // We will deal with 'a' separately later, since it's got only 4 bits.
    let b = UInt16(truncatingIfNeeded: (abc &>> 10) & 1023)
    let c = UInt16(truncatingIfNeeded: abc & 1023)
    let d = UInt16(truncatingIfNeeded: def &>> 20)
    let e = UInt16(truncatingIfNeeded: (def &>> 10) & 1023)
    let f = UInt16(truncatingIfNeeded: def & 1023)

    let highest =
      (abc &>> 20)      &* 1_000_000 &+
      UInt32(decode(b)) &* 1_000 &+
      UInt32(decode(c))
    let higher =
      UInt32(decode(d)) &* 1_000_000 &+
      UInt32(decode(e)) &* 1_000 &+
      UInt32(decode(f))
    let high = UInt64(highest) &* 1_000_000_000 &+ UInt64(higher)

    let g = UInt16(truncatingIfNeeded: ghi &>> 20)
    let h = UInt16(truncatingIfNeeded: (ghi &>> 10) & 1023)
    let i = UInt16(truncatingIfNeeded: ghi & 1023)
    let j = UInt16(truncatingIfNeeded: jkm &>> 20)
    let k = UInt16(truncatingIfNeeded: (jkm &>> 10) & 1023)
    let m = UInt16(truncatingIfNeeded: jkm & 1023)

    let lower =
      UInt32(decode(g)) &* 1_000_000 &+
      UInt32(decode(h)) &* 1_000 &+
      UInt32(decode(i))
    let lowest =
      UInt32(decode(j)) &* 1_000_000 &+
      UInt32(decode(k)) &* 1_000 &+
      UInt32(decode(m))
    let low = UInt64(lower) &* 1_000_000_000 &+ UInt64(lowest)

    return UInt128(high) &* 1_000_000_000_000_000_000 &+ UInt128(low)
  }

  @inlinable
  public static func encode(_ integer: UInt16) -> UInt16 {
    precondition(integer < 1000)

    let (hnds, remainder) = integer.quotientAndRemainder(dividingBy: 100)
    let (tens, ones) = remainder.quotientAndRemainder(dividingBy: 10)

    // We'll refer to the bits of the binary coded decimal (before compression)
    // as follows:
    //
    //    Hundreds        Tens            Ones
    //   ┌───┬───┬───┬───╥───┬───┬───┬───╥───┬───┬───┬───┐
    //   │ a │ b │ c │ d ║ e │ f │ g │ h ║ i │ j │ k │ m │
    //   └───┴───┴───┴───╨───┴───┴───┴───╨───┴───┴───┴───┘

    // Using abc, efg, and ijk, we'll compute an index to look up the partial
    // result in a table, then copy over bits d, h, and m.
    let index: Int
    if hnds < 8 {
      // When the hundreds digit and tens digit are both less than 8,
      // the encoding is straightforward, and we exit early instead.
      if tens < 8 { return (hnds &<< 7) | (tens &<< 4) | ones }
      index = Int(5 &* (hnds &>> 1) &+ (ones &>> 1))
    } else {
      index = Int(20 &+ 5 &* (tens &>> 1) &+ (ones &>> 1))
    }
    let table: [UInt16] = [
      0b000_000_1010 /* 000d_100h_000m */, 0b000_010_1010 /* 000d_100h_001m */,
      0b000_100_1010 /* 000d_100h_010m */, 0b000_110_1010 /* 000d_100h_011m */,
      0b000_100_1110 /* 000d_100h_100m */,
      0b010_000_1010 /* 001d_100h_000m */, 0b010_010_1010 /* 001d_100h_001m */,
      0b010_100_1010 /* 001d_100h_010m */, 0b010_110_1010 /* 001d_100h_011m */,
      0b010_100_1110 /* 001d_100h_100m */,
      0b100_000_1010 /* 010d_100h_000m */, 0b100_010_1010 /* 010d_100h_001m */,
      0b100_100_1010 /* 010d_100h_010m */, 0b100_110_1010 /* 010d_100h_011m */,
      0b100_100_1110 /* 010d_100h_100m */,
      0b110_000_1010 /* 011d_100h_000m */, 0b110_010_1010 /* 011d_100h_001m */,
      0b110_100_1010 /* 011d_100h_010m */, 0b110_110_1010 /* 011d_100h_011m */,
      0b110_100_1110 /* 011d_100h_100m */,
      0b000_000_1100 /* 100d_000h_000m */, 0b010_000_1100 /* 100d_000h_001m */,
      0b100_000_1100 /* 100d_000h_010m */, 0b110_000_1100 /* 100d_000h_011m */,
      0b000_010_1110 /* 100d_000h_100m */,
      0b000_010_1100 /* 100d_001h_000m */, 0b010_010_1100 /* 100d_001h_001m */,
      0b100_010_1100 /* 100d_001h_010m */, 0b110_010_1100 /* 100d_001h_011m */,
      0b010_010_1110 /* 100d_001h_100m */,
      0b000_100_1100 /* 100d_010h_000m */, 0b010_100_1100 /* 100d_010h_001m */,
      0b100_100_1100 /* 100d_010h_010m */, 0b110_100_1100 /* 100d_010h_011m */,
      0b100_010_1110 /* 100d_010h_100m */,
      0b000_110_1100 /* 100d_011h_000m */, 0b010_110_1100 /* 100d_011h_001m */,
      0b100_110_1100 /* 100d_011h_010m */, 0b110_110_1100 /* 100d_011h_011m */,
      0b110_010_1110 /* 100d_011h_100m */,
      0b000_000_1110 /* 100d_100h_000m */, 0b010_000_1110 /* 100d_100h_001m */,
      0b100_000_1110 /* 100d_100h_010m */, 0b110_000_1110 /* 100d_100h_011m */,
      0b000_110_1110 /* 100d_100h_100m */,
    ]
    return table[index] | ((hnds & 1) &<< 7) | ((tens & 1) &<< 4) | (ones & 1)
  }

  @available(macOS 15.0, *)
  @inlinable
  public static func encode(_ significand: UInt128) -> UInt128 {
    precondition(significand <= 9_999_999_999_999_999_999_999_999_999_999_999 as UInt128)

    // We'll refer to groups of digits as follows:
    //
    //     9_999_999_999_999_999_999_999_999_999_999_999
    //     ─ ─── ─── ─── ─── ─── ─── ─── ─── ─── ─── ───
    //     a  b   c   d   e   f   g   h   i   j   k   m
    //
    // See also:
    // https://lemire.me/blog/2021/11/18/converting-integers-to-fix-digit-representations-quickly/

    let (abcdef, ghijkm) = significand._quotientAndRemainderDividingBy1e18()

    let (abc, def) =
      UInt64(truncatingIfNeeded: abcdef)
        .quotientAndRemainder(dividingBy: 1_000_000_000)
    let (ghi, jkm) =
      UInt64(truncatingIfNeeded: ghijkm)
        .quotientAndRemainder(dividingBy: 1_000_000_000)

    let (a, bc) =
      UInt32(truncatingIfNeeded: abc).quotientAndRemainder(dividingBy: 1_000_000)
    let (b, c) = bc.quotientAndRemainder(dividingBy: 1_000)
    let (d, ef) =
      UInt32(truncatingIfNeeded: def).quotientAndRemainder(dividingBy: 1_000_000)
    let (e, f) = ef.quotientAndRemainder(dividingBy: 1_000)

    var high = UInt64(encode(UInt16(truncatingIfNeeded: f)))
    high |= UInt64(encode(UInt16(truncatingIfNeeded: e))) &<< 10
    high |= UInt64(encode(UInt16(truncatingIfNeeded: d))) &<< 20
    high |= UInt64(encode(UInt16(truncatingIfNeeded: c))) &<< 30
    high |= UInt64(encode(UInt16(truncatingIfNeeded: b))) &<< 40
    high |= UInt64(a) /* It's always a single digit. */   &<< 50

    let (g, hi) =
      UInt32(truncatingIfNeeded: ghi).quotientAndRemainder(dividingBy: 1_000_000)
    let (h, i) = hi.quotientAndRemainder(dividingBy: 1_000)
    let (j, km) =
      UInt32(truncatingIfNeeded: jkm).quotientAndRemainder(dividingBy: 1_000_000)
    let (k, m) = km.quotientAndRemainder(dividingBy: 1_000)

    var low = UInt64(encode(UInt16(truncatingIfNeeded: m)))
    low |= UInt64(encode(UInt16(truncatingIfNeeded: k))) &<< 10
    low |= UInt64(encode(UInt16(truncatingIfNeeded: j))) &<< 20
    low |= UInt64(encode(UInt16(truncatingIfNeeded: i))) &<< 30
    low |= UInt64(encode(UInt16(truncatingIfNeeded: h))) &<< 40
    low |= UInt64(encode(UInt16(truncatingIfNeeded: g))) &<< 50

    return (UInt128(high) &<< 60) | UInt128(low)
  }
}
