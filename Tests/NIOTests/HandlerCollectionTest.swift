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

final class HandlerCollectionTest : XCTestCase {
    private final class HandlerWithCount: ChannelInboundHandler {
        typealias InboundIn = NIOAny

        let value: Int

        init(_ value: Int) {
            self.value = value
        }
    }

    func testCreateEmpty() {
        let collection = HandlerCollection()
        XCTAssertEqual(collection.count, 0)
    }

    func testCreateSome() {
        let collection = HandlerCollection(source: HandlerWithCount(0), HandlerWithCount(1), HandlerWithCount(2))
        XCTAssertEqual(collection.count, 3)
    }

    // TODO:  Should probably make safe if ever make public.
    /* func testTooBig() {
        let collection = HandlerCollection(source: HandlerWithCount(0),
                                           HandlerWithCount(1),
                                           HandlerWithCount(3),
                                           HandlerWithCount(4),
                                           HandlerWithCount(5),
                                           HandlerWithCount(6),
                                           HandlerWithCount(7),
                                           HandlerWithCount(8),
                                           HandlerWithCount(9),
                                           HandlerWithCount(10))
    }*/

    func testLookup() {
        func testCreateSome() {
            let collection = HandlerCollection(source: HandlerWithCount(0), HandlerWithCount(1), HandlerWithCount(2))
            XCTAssertEqual((collection[1] as! HandlerWithCount).value, 1)
        }
    }

    func testIteration() {
        let collection = HandlerCollection(source: HandlerWithCount(0), HandlerWithCount(1), HandlerWithCount(2))
        var i = 0
        for handler in collection {
            XCTAssertEqual((handler as! HandlerWithCount).value, i)
            i = i + 1
        }
    }
}
