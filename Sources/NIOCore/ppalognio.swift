import Foundation


#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
import Darwin
#elseif os(Windows)
import MSVCRT
#else
import Glibc
#endif

// Prevent name clashes
#if os(macOS) || os(tvOS) || os(iOS) || os(watchOS)
let systemStderr = Darwin.stderr
let systemStdout = Darwin.stdout
#elseif os(Windows)
let systemStderr = MSVCRT.stderr
let systemStdout = MSVCRT.stdout
#else
let systemStderr = Glibc.stderr!
let systemStdout = Glibc.stdout!
#endif

public func ppalognio(_ message: String) {
    let fullMsg = "@@@ \(message) @@@"
    fullMsg.withCString { ptr in
        _ = fputs(ptr, systemStderr)
    }
    _ = fflush(systemStderr)
}

