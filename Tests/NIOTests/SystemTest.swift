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
    
    #if os(macOS)
    // Example twin data options on apple.
    private static let cmsghdrExample: [UInt8] = [0x10, 0x00, 0x00, 0x00, // Length 16 including header
                                                  0x00, 0x00, 0x00, 0x00, // IPPROTO_IP
                                                  0x07, 0x00, 0x00, 0x00, // IP_RECVDSTADDR???
                                                  0x7F, 0x00, 0x00, 0x01, // 127.0.0.1
                                                  0x0D, 0x00, 0x00, 0x00, // Length 13 including header
                                                  0x00, 0x00, 0x00, 0x00, // IPPROTO_IP
                                                  0x1B, 0x00, 0x00, 0x00, // IP_RECVTOS
                                                  0x01, 0x00, 0x00, 0x00] // ECT-1 (1 byte)

    func testCmsgFirstHeader() {
        var exampleCmsgHrd = SystemTest.cmsghdrExample
        exampleCmsgHrd.withUnsafeMutableBytes { pCmsgHdr in
            var msgHdr = msghdr()
            msgHdr.msg_control = pCmsgHdr.baseAddress
            msgHdr.msg_controllen = socklen_t(pCmsgHdr.count)

            withUnsafePointer(to: msgHdr) { pMsgHdr in
                let result = Posix.cmsgFirstHeader(inside: pMsgHdr)
                XCTAssertEqual(pCmsgHdr.baseAddress, result)
            }
        }
    }
    
    func testCMsgNextHeader() {
        var exampleCmsgHrd = SystemTest.cmsghdrExample
        exampleCmsgHrd.withUnsafeMutableBytes { pCmsgHdr in
            var msgHdr = msghdr()
            msgHdr.msg_control = pCmsgHdr.baseAddress
            msgHdr.msg_controllen = socklen_t(pCmsgHdr.count)

            withUnsafeMutablePointer(to: &msgHdr) { pMsgHdr in
                let first = Posix.cmsgFirstHeader(inside: pMsgHdr)
                let second = Posix.cmsgNextHeader(inside: pMsgHdr, from: first)
                let expectedSecondSlice = UnsafeMutableRawBufferPointer(rebasing: pCmsgHdr[16...])
                XCTAssertEqual(expectedSecondSlice.baseAddress, second)
                let third = Posix.cmsgNextHeader(inside: pMsgHdr, from: second)
                XCTAssertEqual(third, nil)
            }
        }
    }
    
    func testCMsgData() {
        var exampleCmsgHrd = SystemTest.cmsghdrExample
        exampleCmsgHrd.withUnsafeMutableBytes { pCmsgHdr in
            var msgHdr = msghdr()
            msgHdr.msg_control = pCmsgHdr.baseAddress
            msgHdr.msg_controllen = socklen_t(pCmsgHdr.count)

            withUnsafePointer(to: msgHdr) { pMsgHdr in
                let first = Posix.cmsgFirstHeader(inside: pMsgHdr)
                let firstData = Posix.cmsgData(for: first)
                let expecedFirstData = UnsafeRawBufferPointer(rebasing: pCmsgHdr[12..<16])
                XCTAssertEqual(expecedFirstData.baseAddress, firstData)
            }
        }
    }
    #endif
}
