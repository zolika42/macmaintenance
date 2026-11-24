import Foundation
import NativeMove

enum NativeExclusiveMove {
    static func move(source: String, destination: String, device: UInt64, inode: UInt64) throws {
        guard !source.utf8.contains(0), !destination.utf8.contains(0), source != destination else {
            throw ScanError.unsafePath
        }
        let result = source.withCString { src in
            destination.withCString { dst in mm_exclusive_move(src, dst, device, inode) }
        }
        if result != 0 { throw POSIXError(POSIXErrorCode(rawValue: result) ?? .EIO) }
    }
}
