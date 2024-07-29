import Numerics

@available(macOS 15.0, *)
@frozen
public struct Decimal128: Sendable {
  @usableFromInline @inline(__always)
  internal var _binaryEncoding: UInt128

  @_transparent
  public init() {
    _binaryEncoding = 0
  }

  @_transparent
  public init(bitPattern: UInt128) {
    _binaryEncoding = bitPattern
  }
}

@available(macOS 15.0, *)
extension Decimal128 {
  @_transparent
  public var bitPattern: UInt128 { _binaryEncoding }

  @inlinable
  public static var exponentBitCount: Int { 14 }

  @inlinable
  public static var trailingSignificandBitCount: Int { 110 }

  @inlinable

}

@available(macOS 15.0, *)
extension Decimal128: CustomStringConvertible {
  public var description: String {
    "NA"
  }
}
