import Darwin
import Foundation

// Same-volume rename which refuses any existing destination, including symlinks.
guard CommandLine.arguments.count == 3 else { exit(2) }
let source = CommandLine.arguments[1]
let destination = CommandLine.arguments[2]
let result = source.withCString { s in
    destination.withCString { d in renamex_np(s, d, UInt32(RENAME_EXCL)) }
}
if result != 0 {
    let failure = errno
    FileHandle.standardError.write(Data("Exclusive rename failed (errno \(failure))\n".utf8))
    exit(1)
}
