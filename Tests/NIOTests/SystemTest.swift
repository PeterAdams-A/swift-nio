//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2017-2018 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import XCTest
@testable import NIO

class SystemTest: XCTestCase {
    func testSystemCallWrapperPerformance() throws {
        try runSystemCallWrapperPerformanceTest(testAssertFunction: XCTAssert,
                                                debugModeAllowed: true)
    }

    func testErrorsWorkCorrectly() throws {
        try withPipe { readFD, writeFD in
            var randomBytes: UInt8 = 42
            do {
                _ = try withUnsafePointer(to: &randomBytes) { ptr in
                    try readFD.withUnsafeFileDescriptor { readFD in
                        try Posix.setsockopt(socket: readFD, level: -1, optionName: -1, optionValue: ptr, optionLen: 0)
                    }
                }
                XCTFail("success even though the call was invalid")
            } catch let e as IOError {
                XCTAssertEqual(ENOTSOCK, e.errnoCode)
                XCTAssert(e.description.contains("setsockopt"))
                XCTAssert(e.description.contains("\(ENOTSOCK)"))
                XCTAssert(e.localizedDescription.contains("\(ENOTSOCK)"), "\(e.localizedDescription)")
            } catch let e {
                XCTFail("wrong error thrown: \(e)")
            }
            return [readFD, writeFD]
        }
    }
    
    // Example twin data options on apple. - TOS and TTL
    private static let cmsghdrExample: [UInt8] = [0x10, 0x00, 0x00, 0x00,
                                                  0x00, 0x00, 0x00, 0x00,
                                                  0x07, 0x00, 0x00, 0x00,
                                                  0x7F, 0x00, 0x00, 0x01,
                                                  0x0D, 0x00, 0x00, 0x00,
                                                  0x00, 0x00, 0x00, 0x00,
                                                  0x1B, 0x00, 0x00, 0x00,
                                                  0x01, 0x00, 0x00, 0x00]

    func testCmsgFirstHeader() {
        var exampleCmsgHrd = SystemTest.cmsghdrExample
        XCTAssertNoThrow(try {
            try exampleCmsgHrd.withUnsafeMutableBytes { pCmsgHdr in
                var msgHdr = msghdr()
                msgHdr.msg_control = pCmsgHdr.baseAddress
                msgHdr.msg_controllen = socklen_t(pCmsgHdr.count)

                try withUnsafePointer(to: msgHdr) { pMsgHdr in
                    let result = try Posix.cmsgFirstHeader(inside: pMsgHdr)
                    XCTAssertEqual(pCmsgHdr.baseAddress, result)
                }
            }
        }())
    }
    
    func testCMsgNextHeader() {
        var exampleCmsgHrd = SystemTest.cmsghdrExample
        XCTAssertNoThrow(try {
            try exampleCmsgHrd.withUnsafeMutableBytes { pCmsgHdr in
                var msgHdr = msghdr()
                msgHdr.msg_control = pCmsgHdr.baseAddress
                msgHdr.msg_controllen = socklen_t(pCmsgHdr.count)

                try withUnsafePointer(to: msgHdr) { pMsgHdr in
                    let first = try Posix.cmsgFirstHeader(inside: pMsgHdr)
                    let second = try Posix.cmsgNextHeader(inside: pMsgHdr, from: first)
                    let expectedSecondSlice = UnsafeMutableRawBufferPointer(rebasing: pCmsgHdr[16...])
                    XCTAssertEqual(expectedSecondSlice.baseAddress, second)
                    let third = try Posix.cmsgNextHeader(inside: pMsgHdr, from: second)
                    XCTAssertEqual(third, nil)
                }
            }
        }())
    }
}
