import Foundation

/// A secret value in memory. Holds its own buffer and zeroes it when it goes
/// away, so a revealed key doesn't linger in freed heap memory for longer
/// than it has to. Best-effort only (threat model T8): anything that copies the
/// bytes into a `String` or a SwiftUI `Text` is outside this class's reach,
/// so callers keep the `String` form as short-lived as possible.
///
/// `@unchecked Sendable`: the buffer is written once in `init` and only ever
/// read afterwards (and zeroed in `deinit`, when no other reference exists).
public final class SecretBytes: @unchecked Sendable {
    private let buffer: UnsafeMutableRawBufferPointer

    public var count: Int { buffer.count }

    public init(_ data: Data) {
        buffer = .allocate(byteCount: data.count, alignment: 1)
        data.copyBytes(to: buffer)
    }

    public convenience init(_ string: String) {
        self.init(Data(string.utf8))
    }

    deinit {
        wipe()
        buffer.deallocate()
    }

    public func withUnsafeBytes<T>(_ body: (UnsafeRawBufferPointer) throws -> T) rethrows -> T {
        try body(UnsafeRawBufferPointer(buffer))
    }

    /// A `Data` copy for APIs that need one (HPKE seal, the clipboard). The
    /// copy is the caller's to drop promptly.
    public var data: Data { Data(buffer) }

    /// UTF-8 decode for display. Same caveat as `data`.
    public var string: String { String(decoding: buffer, as: UTF8.self) }

    public func isEqual(to other: SecretBytes) -> Bool {
        buffer.count == other.buffer.count && buffer.elementsEqual(other.buffer)
    }

    /// `memset_s`, not `memset`: the compiler is allowed to drop a plain
    /// memset whose buffer is never read again, which is exactly this case.
    func wipe() {
        guard buffer.count > 0 else { return }
        _ = memset_s(buffer.baseAddress, buffer.count, 0, buffer.count)
    }
}
