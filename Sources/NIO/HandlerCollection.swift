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

import Foundation

/// An attempt to not allocate when setting up a collection of channel handlers
internal struct HandlerCollection: Collection {
    private var c0: ChannelHandler?
    private var c1: ChannelHandler?
    private var c2: ChannelHandler?
    private var c3: ChannelHandler?
    private var c4: ChannelHandler?
    private var c5: ChannelHandler?
    private var c6: ChannelHandler?
    private var c7: ChannelHandler?

    private var _count: Int

    private static let maxSize = 8

    internal init(source: ChannelHandler...) {
        let sourceCount = source.count
        precondition(sourceCount <= HandlerCollection.maxSize)

        self.c0 = sourceCount > 0 ? source[0] : nil
        self.c1 = sourceCount > 1 ? source[1] : nil
        self.c2 = sourceCount > 2 ? source[2] : nil
        self.c3 = sourceCount > 3 ? source[3] : nil
        self.c4 = sourceCount > 4 ? source[4] : nil
        self.c5 = sourceCount > 5 ? source[5] : nil
        self.c6 = sourceCount > 6 ? source[6] : nil
        self.c7 = sourceCount > 7 ? source[7] : nil
        self._count = sourceCount
    }

    public subscript(position: Int) -> ChannelHandler {
        precondition(position >= 0)
        precondition(position < self._count)
        
        switch position {
        case 0: return self.c0!
        case 1: return self.c1!
        case 2: return self.c2!
        case 3: return self.c3!
        case 4: return self.c4!
        case 5: return self.c5!
        case 6: return self.c6!
        default: return self.c7!
        }
    }

    var startIndex: Int { return 0 }

    var endIndex: Int { return self._count }

    func index(after: Int) -> Int {
        return after + 1
    }

    struct IndexOutOfBounds: Error { }
}
