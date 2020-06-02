//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2020 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

// This file contains a syscall abstraction layer (SAL) which hooks the Selector and the Socket in a way that we can
// play the kernel whilst NIO thinks it's running on a real OS.

@testable import NIO
import NIOConcurrencyHelpers
import XCTest

internal enum SAL {
    fileprivate static let defaultTimeout: Double = 5
    private static let debugTests: Bool = false
    fileprivate static func printIfDebug(_ item: Any) {
        if debugTests {
            print(item)
        }
    }
}

final class LockedBox<T> {
    struct TimeoutError: Error {
        var description: String
        init(_ description: String) {
            self.description = description
        }
    }
    struct ExpectedEmptyBox: Error {}

    private let condition = ConditionLock(value: 0)
    private let description: String
    private let didSet: (T?) -> Void
    private var _value: T? {
        didSet {
            self.didSet(self._value)
        }
    }

    init(_ value: T? = nil,
         description: String? = nil,
         file: StaticString = fullFilePath(),
         line: UInt = #line,
         didSet: @escaping (T?) -> Void = { _ in }) {
        self._value = value
        self.didSet = didSet
        self.description = description ?? "\(file):\(line)"
    }

    internal var value: T? {
        get {
            self.condition.lock()
            defer {
                self.condition.unlock()
            }
            return self._value
        }

        set {
            self.condition.lock()
            if let value = newValue {
                self._value = value
                self.condition.unlock(withValue: 1)
            } else {
                self._value = nil
                self.condition.unlock(withValue: 0)
            }
        }
    }

    func waitForEmptyAndSet(_ value: T) throws {
        if self.condition.lock(whenValue: 0, timeoutSeconds: SAL.defaultTimeout) {
            defer {
                self.condition.unlock(withValue: 1)
            }
            self._value = value
        } else {
            throw TimeoutError(self.description)
        }
    }

    func takeValue() throws -> T {
        if self.condition.lock(whenValue: 1, timeoutSeconds: SAL.defaultTimeout) {
            defer {
                self.condition.unlock(withValue: 0)
            }
            let value = self._value!
            self._value = nil
            return value
        } else {
            throw TimeoutError(self.description)
        }
    }

    func waitForValue() throws -> T {
        if self.condition.lock(whenValue: 1, timeoutSeconds: SAL.defaultTimeout) {
            defer {
                self.condition.unlock(withValue: 1)
            }
            return self._value!
        } else {
            throw TimeoutError(self.description)
        }
    }
}

enum UserToKernel {
    case localAddress
    case remoteAddress
    case connect(SocketAddress)
    case read(Int)
    case close(CInt)
    case register(Selectable, SelectorEventSet, NIORegistration)
    case reregister(Selectable, SelectorEventSet)
    case deregister(Selectable)
    case whenReady(SelectorStrategy)
    case disableSIGPIPE(CInt)
    case write(CInt, ByteBuffer)
    case writev(CInt, [ByteBuffer])
}

enum KernelToUser {
    case returnSocketAddress(SocketAddress)
    case returnBool(Bool)
    case returnBytes(ByteBuffer)
    case returnVoid
    case returnSelectorEvent(SelectorEvent<NIORegistration>?)
    case returnIOResultInt(IOResult<Int>)
    case error(IOError)
}

struct UnexpectedKernelReturn: Error {
    private var ret: KernelToUser

    init(_ ret: KernelToUser) {
        self.ret = ret
    }
}

struct UnexpectedSyscall: Error {
    private var syscall: UserToKernel

    init(_ syscall: UserToKernel) {
        self.syscall = syscall
    }
}

private protocol UserKernelInterface {
    var userToKernel: LockedBox<UserToKernel> { get }
    var kernelToUser: LockedBox<KernelToUser> { get }
}

extension UserKernelInterface {
    fileprivate func waitForKernelReturn() throws -> KernelToUser {
        let value = try self.kernelToUser.takeValue()
        if case .error(let error) = value {
            throw error
        } else {
            return value
        }
    }
}

internal class HookedSelector: NIO.Selector<NIORegistration>, UserKernelInterface {
    fileprivate let userToKernel: LockedBox<UserToKernel>
    fileprivate let kernelToUser: LockedBox<KernelToUser>
    fileprivate let wakeups: LockedBox<()>

    init(userToKernel: LockedBox<UserToKernel>, kernelToUser: LockedBox<KernelToUser>, wakeups: LockedBox<()>) throws {
        self.userToKernel = userToKernel
        self.kernelToUser = kernelToUser
        self.wakeups = wakeups
        try super.init()
    }

    override func register<S: Selectable>(selectable: S,
                                          interested: SelectorEventSet,
                                          makeRegistration: (SelectorEventSet) -> NIORegistration) throws {
        try self.userToKernel.waitForEmptyAndSet(.register(selectable, interested, makeRegistration(interested)))
        let ret = try self.waitForKernelReturn()
        if case .returnVoid = ret {
            return
        } else {
            throw UnexpectedKernelReturn(ret)
        }
    }

    override func reregister<S: Selectable>(selectable: S, interested: SelectorEventSet) throws {
        try self.userToKernel.waitForEmptyAndSet(.reregister(selectable, interested))
        let ret = try self.waitForKernelReturn()
        if case .returnVoid = ret {
            return
        } else {
            throw UnexpectedKernelReturn(ret)
        }
    }

    override func whenReady(strategy: SelectorStrategy, _ body: (SelectorEvent<NIORegistration>) throws -> Void) throws -> Void {
        try self.userToKernel.waitForEmptyAndSet(.whenReady(strategy))
        let ret = try self.waitForKernelReturn()
        if case .returnSelectorEvent(let event) = ret {
            if let event = event {
                try body(event)
            }
            return
        } else {
            throw UnexpectedKernelReturn(ret)
        }
    }

    override func deregister<S: Selectable>(selectable: S) throws {
        try self.userToKernel.waitForEmptyAndSet(.deregister(selectable))
        let ret = try self.waitForKernelReturn()
        if case .returnVoid = ret {
            return
        } else {
            throw UnexpectedKernelReturn(ret)
        }
    }

    override func wakeup() throws {
        SAL.printIfDebug("WAKEUP")
        try self.wakeups.waitForEmptyAndSet(())
    }
}


class HookedSocket: Socket, UserKernelInterface {
    fileprivate let userToKernel: LockedBox<UserToKernel>
    fileprivate let kernelToUser: LockedBox<KernelToUser>

    init(userToKernel: LockedBox<UserToKernel>, kernelToUser: LockedBox<KernelToUser>, descriptor: CInt) throws {
        self.userToKernel = userToKernel
        self.kernelToUser = kernelToUser
        try super.init(descriptor: descriptor)
    }

    override func ignoreSIGPIPE() throws {
        try self.withUnsafeHandle { fd in
            try self.userToKernel.waitForEmptyAndSet(.disableSIGPIPE(fd))
            let ret = try self.waitForKernelReturn()
            if case .returnVoid = ret {
                return
            } else {
                throw UnexpectedKernelReturn(ret)
            }
        }
    }

    override func localAddress() throws -> SocketAddress {
        try self.userToKernel.waitForEmptyAndSet(.localAddress)
        let ret = try self.waitForKernelReturn()
        if case .returnSocketAddress(let address) = ret {
            return address
        } else {
            throw UnexpectedKernelReturn(ret)
        }
    }

    override func remoteAddress() throws -> SocketAddress {
        try self.userToKernel.waitForEmptyAndSet(.remoteAddress)
        let ret = try self.waitForKernelReturn()
        if case .returnSocketAddress(let address) = ret {
            return address
        } else {
            throw UnexpectedKernelReturn(ret)
        }
    }

    override func connect(to address: SocketAddress) throws -> Bool {
        try self.userToKernel.waitForEmptyAndSet(.connect(address))
        let ret = try self.waitForKernelReturn()
        if case .returnBool(let success) = ret {
            return success
        } else {
            throw UnexpectedKernelReturn(ret)
        }
    }

    override func read(pointer: UnsafeMutableRawBufferPointer) throws -> IOResult<Int> {
        try self.userToKernel.waitForEmptyAndSet(.read(pointer.count))
        let ret = try self.waitForKernelReturn()
        if case .returnBytes(let buffer) = ret {
            assert(buffer.readableBytes <= pointer.count)
            pointer.copyBytes(from: buffer.readableBytesView)
            return .processed(buffer.readableBytes)
        } else {
            throw UnexpectedKernelReturn(ret)
        }
    }

    override func write(pointer: UnsafeRawBufferPointer) throws -> IOResult<Int> {
        return try self.withUnsafeHandle { fd in
            var buffer = ByteBufferAllocator().buffer(capacity: pointer.count)
            buffer.writeBytes(pointer)
            try self.userToKernel.waitForEmptyAndSet(.write(fd, buffer))
            let ret = try self.waitForKernelReturn()
            if case .returnIOResultInt(let result) = ret {
                return result
            } else {
                throw UnexpectedKernelReturn(ret)
            }
        }
    }

    override func writev(iovecs: UnsafeBufferPointer<IOVector>) throws -> IOResult<Int> {
        return try self.withUnsafeHandle { fd in
            let buffers = iovecs.map { iovec -> ByteBuffer in
                var buffer = ByteBufferAllocator().buffer(capacity: iovec.iov_len)
                buffer.writeBytes(UnsafeRawBufferPointer(start: iovec.iov_base, count: iovec.iov_len))
                return buffer
            }

            try self.userToKernel.waitForEmptyAndSet(.writev(fd, buffers))
            let ret = try self.waitForKernelReturn()
            if case .returnIOResultInt(let result) = ret {
                return result
            } else {
                throw UnexpectedKernelReturn(ret)
            }
        }
    }

    override func close() throws {
        let fd = try self.takeDescriptorOwnership()

        try self.userToKernel.waitForEmptyAndSet(.close(fd))
        let ret = try self.waitForKernelReturn()
        if case .returnVoid = ret {
            return
        } else {
            throw UnexpectedKernelReturn(ret)
        }
    }
}

extension HookedSelector {
    func assertSyscallAndReturn(_ result: KernelToUser,
                                file: StaticString = fullFilePath(),
                                line: UInt = #line,
                                matcher: (UserToKernel) throws -> Bool) throws {
        let syscall = try self.userToKernel.takeValue()
        if try matcher(syscall) {
            try self.kernelToUser.waitForEmptyAndSet(result)
        } else {
            XCTFail("unexpected syscall \(syscall)", file: file, line: line)
            throw UnexpectedSyscall(syscall)
        }
    }

    func assertWakeup(file: StaticString = fullFilePath(), line: UInt = #line) throws {
        SAL.printIfDebug("\(#function)")
        try self.assertSyscallAndReturn(.returnSelectorEvent(nil), file: file, line: line) { syscall in
            if case .whenReady(.block) = syscall {
                return true
            } else {
                return false
            }
        }
        try self.wakeups.takeValue()
    }

}

extension EventLoop {
    internal func runSAL<T>(syscallAssertions: () throws -> Void = {},
                            file: StaticString = fullFilePath(),
                            line: UInt = #line,
                            _ body: @escaping () throws -> T) throws -> T {
        let hookedSelector = ((self as! SelectableEventLoop)._selector as! HookedSelector)
        let box = LockedBox<Result<T, Error>>()
        self.execute {
            do {
                try box.waitForEmptyAndSet(.init(catching: body))
            } catch {
                box.value = .failure(error)
            }
        }
        try hookedSelector.assertWakeup(file: file, line: line)
        try syscallAssertions()
        return try box.takeValue().get()
    }
}

extension EventLoopFuture {
    /// This works like `EventLoopFuture.wait()` but can be used together with the SAL.
    ///
    /// Using a plain `EventLoopFuture.wait()` together with the SAL would require you to spin the `EventLoop` manually
    /// which is error prone and hard.
    internal func salWait() throws -> Value {
        assert(Thread.isMainThread)
        let box = LockedBox<Result<Value, Error>>()
        let hookedSelector = ((self.eventLoop as! SelectableEventLoop)._selector as! HookedSelector)

        self.eventLoop.execute {
            self.whenComplete { result in
                do {
                    try box.waitForEmptyAndSet(result)
                } catch {
                    box.value = .failure(error)
                }
            }
        }
        try hookedSelector.assertWakeup()
        return try box.takeValue().get()
    }
}

protocol SALTest: AnyObject {
    var group: MultiThreadedEventLoopGroup! { get set }
    var wakeups: LockedBox<()>! { get set }
    var userToKernelBox: LockedBox<UserToKernel>! { get set }
    var kernelToUserBox: LockedBox<KernelToUser>! { get set }
}

extension SALTest {
    private var selector: HookedSelector {
        precondition(Array(self.group.makeIterator()).count == 1)
        return self.loop._selector as! HookedSelector
    }

    private var loop: SelectableEventLoop {
        precondition(Array(self.group.makeIterator()).count == 1)
        return ((self.group!.next()) as! SelectableEventLoop)
    }

    func setUpSAL() {
        XCTAssertNil(self.group)
        XCTAssertNil(self.kernelToUserBox)
        XCTAssertNil(self.userToKernelBox)
        XCTAssertNil(self.wakeups)
        self.kernelToUserBox = .init(description: "k2u") { newValue in
            if let newValue = newValue {
                SAL.printIfDebug("K --> U: \(newValue)")
            }
        }
        self.userToKernelBox = .init(description: "u2k") { newValue in
            if let newValue = newValue {
                SAL.printIfDebug("U --> K: \(newValue)")
            }
        }
        self.wakeups = .init(description: "wakeups")
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1) {
            try HookedSelector(userToKernel: self.userToKernelBox,
                               kernelToUser: self.kernelToUserBox,
                               wakeups: self.wakeups)
        }
    }

    private func makeSocketChannel(eventLoop: SelectableEventLoop,
                                   file: StaticString = fullFilePath(), line: UInt = #line) throws -> SocketChannel {
        let channel = try eventLoop.runSAL(syscallAssertions: {
            try self.assertdisableSIGPIPE(expectedFD: .max, result: .success(()))
            try self.assertLocalAddress(address: nil)
            try self.assertRemoteAddress(address: nil)
        }) {
            try SocketChannel(socket: HookedSocket(userToKernel: self.userToKernelBox,
                                                   kernelToUser: self.kernelToUserBox,
                                                   descriptor: .max),
                              eventLoop: eventLoop)
        }
        try self.assertParkedRightNow()
        return channel
    }

    func makeSocketChannelInjectingFailures(disableSIGPIPEFailure: IOError?) throws -> SocketChannel {
        let channel = try self.loop.runSAL(syscallAssertions: {
            try self.assertdisableSIGPIPE(expectedFD: .max,
                                         result: disableSIGPIPEFailure.map {
                                            Result<Void, IOError>.failure($0)
                                         } ?? .success(()))
            guard disableSIGPIPEFailure == nil else {
                // if F_NOSIGPIPE failed, we shouldn't see other syscalls.
                return
            }
            try self.assertLocalAddress(address: nil)
            try self.assertRemoteAddress(address: nil)
        }) {
            try SocketChannel(socket: HookedSocket(userToKernel: self.userToKernelBox,
                                                   kernelToUser: self.kernelToUserBox,
                                                   descriptor: .max),
                              eventLoop: self.loop)
        }
        try self.assertParkedRightNow()
        return channel
    }

    func makeConnectedSocketChannel(localAddress: SocketAddress?,
                                    remoteAddress: SocketAddress,
                                    file: StaticString = fullFilePath(),
                                    line: UInt = #line) throws -> SocketChannel {
        let channel = try self.makeSocketChannel(eventLoop: self.loop)
        let connectFuture = try channel.eventLoop.runSAL(syscallAssertions: {
            try self.assertConnect(result: true, { $0 == remoteAddress })
            try self.assertLocalAddress(address: localAddress)
            try self.assertRemoteAddress(address: remoteAddress)
            try self.assertRegister { selectable, eventSet, registration in
                if case .socketChannel(let channel, let registrationEventSet) = registration {
                    XCTAssertEqual(localAddress, channel.localAddress)
                    XCTAssertEqual(remoteAddress, channel.remoteAddress)
                    XCTAssertEqual(eventSet, registrationEventSet)
                    XCTAssertEqual(.reset, eventSet)
                    return true
                } else {
                    return false
                }
            }
            try self.assertReregister { selectable, eventSet in
                XCTAssertEqual([.reset, .readEOF], eventSet)
                return true
            }
            // because autoRead is on by default
            try self.assertReregister { selectable, eventSet in
                XCTAssertEqual([.reset, .readEOF, .read], eventSet)
                return true
            }
        }) {
            channel.register().flatMap {
                channel.connect(to: remoteAddress)
            }
        }
        XCTAssertNoThrow(try connectFuture.salWait())
        return channel
    }

    func tearDownSAL() {
        SAL.printIfDebug("=== TEAR DOWN ===")
        XCTAssertNotNil(self.kernelToUserBox)
        XCTAssertNotNil(self.userToKernelBox)
        XCTAssertNotNil(self.wakeups)
        XCTAssertNotNil(self.group)

        let group = DispatchGroup()
        group.enter()
        XCTAssertNoThrow(self.group.shutdownGracefully(queue: DispatchQueue.global()) { error in
            XCTAssertNil(error, "unexpected error: \(error!)")
            group.leave()
        })
        // We're in a slightly tricky situation here. We don't know if the EventLoop thread enters `whenReady` again
        // or not. If it has, we have to wake it up, so let's just put a return value in the 'kernel to user' box, just
        // in case :)
        XCTAssertNoThrow(try self.kernelToUserBox.waitForEmptyAndSet(.returnSelectorEvent(nil)))
        group.wait()

        self.group = nil
        self.kernelToUserBox = nil
        self.userToKernelBox = nil
        self.wakeups = nil
    }

    func assertParkedRightNow(file: StaticString = fullFilePath(), line: UInt = #line) throws {
        SAL.printIfDebug("\(#function)")
        let syscall = try self.userToKernelBox.waitForValue()
        if case .whenReady = syscall {
            return
        } else {
            XCTFail("unexpected syscall \(syscall)", file: file, line: line)
        }
    }

    func assertWaitingForNotification(result: SelectorEvent<NIORegistration>?,
                                      file: StaticString = fullFilePath(), line: UInt = #line) throws {
        SAL.printIfDebug("\(#function)(result: \(result.debugDescription))")
        try self.selector.assertSyscallAndReturn(.returnSelectorEvent(result),
                                                 file: file, line: line) { syscall in
            if case .whenReady = syscall {
                return true
            } else {
                return false
            }
        }
    }

    func assertWakeup(file: StaticString = fullFilePath(), line: UInt = #line) throws {
        try self.selector.assertWakeup(file: file, line: line)
    }

    func assertdisableSIGPIPE(expectedFD: CInt,
                             result: Result<Void, IOError>,
                             file: StaticString = fullFilePath(), line: UInt = #line) throws {
        SAL.printIfDebug("\(#function)")
        let ret: KernelToUser
        switch result {
        case .success:
            ret = .returnVoid
        case .failure(let error):
            ret = .error(error)
        }
        try self.selector.assertSyscallAndReturn(ret, file: file, line: line) { syscall in
            if case .disableSIGPIPE(expectedFD) = syscall {
                return true
            } else {
                return false
            }
        }
    }


    func assertLocalAddress(address: SocketAddress?, file: StaticString = fullFilePath(), line: UInt = #line) throws {
        SAL.printIfDebug("\(#function)")
        try self.selector.assertSyscallAndReturn(address.map { .returnSocketAddress($0) } ??
            /*                                */ .error(.init(errnoCode: EOPNOTSUPP, reason: "nil passed")),
                                                 file: file, line: line) { syscall in
            if case .localAddress = syscall {
                return true
            } else {
                return false
            }
        }
    }

    func assertRemoteAddress(address: SocketAddress?, file: StaticString = fullFilePath(), line: UInt = #line) throws {
        SAL.printIfDebug("\(#function)")
        try self.selector.assertSyscallAndReturn(address.map { .returnSocketAddress($0) } ??
            /*                                */ .error(.init(errnoCode: EOPNOTSUPP, reason: "nil passed")),
                                                 file: file, line: line) { syscall in
            if case .remoteAddress = syscall {
                return true
            } else {
                return false
            }
        }
    }

    func assertConnect(result: Bool, file: StaticString = fullFilePath(), line: UInt = #line, _ matcher: (SocketAddress) -> Bool = { _ in true }) throws {
        SAL.printIfDebug("\(#function)")
        try self.selector.assertSyscallAndReturn(.returnBool(result), file: file, line: line) { syscall in
            if case .connect(let address) = syscall {
                return matcher(address)
            } else {
                return false
            }
        }
    }

    func assertClose(expectedFD: CInt, file: StaticString = fullFilePath(), line: UInt = #line) throws {
        SAL.printIfDebug("\(#function)")
        try self.selector.assertSyscallAndReturn(.returnVoid, file: file, line: line) { syscall in
            if case .close(let fd) = syscall {
                XCTAssertEqual(expectedFD, fd, file: file, line: line)
                return true
            } else {
                return false
            }
        }
    }


    func assertRegister(file: StaticString = fullFilePath(), line: UInt = #line, _ matcher: (Selectable, SelectorEventSet, NIORegistration) throws -> Bool) throws {
        SAL.printIfDebug("\(#function)")
        try self.selector.assertSyscallAndReturn(.returnVoid, file: file, line: line) { syscall in
            if case .register(let selectable, let eventSet, let registration) = syscall {
                return try matcher(selectable, eventSet, registration)
            } else {
                return false
            }
        }
    }

    func assertReregister(file: StaticString = fullFilePath(), line: UInt = #line, _ matcher: (Selectable, SelectorEventSet) throws -> Bool) throws {
        SAL.printIfDebug("\(#function)")
        try self.selector.assertSyscallAndReturn(.returnVoid, file: file, line: line) { syscall in
            if case .reregister(let selectable, let eventSet) = syscall {
                return try matcher(selectable, eventSet)
            } else {
                return false
            }
        }
    }

    func assertDeregister(file: StaticString = fullFilePath(), line: UInt = #line, _ matcher: (Selectable) throws -> Bool) throws {
        SAL.printIfDebug("\(#function)")
        try self.selector.assertSyscallAndReturn(.returnVoid, file: file, line: line) { syscall in
            if case .deregister(let selectable) = syscall {
                return try matcher(selectable)
            } else {
                return false
            }
        }
    }

    func assertWrite(expectedFD: CInt, expectedBytes: ByteBuffer, return: IOResult<Int>, file: StaticString = fullFilePath(), line: UInt = #line) throws {
        SAL.printIfDebug("\(#function)")
        try self.selector.assertSyscallAndReturn(.returnIOResultInt(`return`), file: file, line: line) { syscall in
            if case .write(let actualFD, let actualBytes) = syscall {
                return expectedFD == actualFD && expectedBytes == actualBytes
            } else {
                return false
            }
        }
    }

    func assertWritev(expectedFD: CInt, expectedBytes: [ByteBuffer], return: IOResult<Int>, file: StaticString = fullFilePath(), line: UInt = #line) throws {
        SAL.printIfDebug("\(#function)")
        try self.selector.assertSyscallAndReturn(.returnIOResultInt(`return`), file: file, line: line) { syscall in
            if case .writev(let actualFD, let actualBytes) = syscall {
                return expectedFD == actualFD && expectedBytes == actualBytes
            } else {
                return false
            }
        }
    }

    func assertRead(expectedFD: CInt, expectedBufferSpace: Int, return: ByteBuffer,
                    file: StaticString = fullFilePath(), line: UInt = #line) throws {
        SAL.printIfDebug("\(#function)")
        try self.selector.assertSyscallAndReturn(.returnBytes(`return`),
                                                 file: file, line: line) { syscall in
            if case .read(let amount) = syscall {
                XCTAssertEqual(expectedBufferSpace, amount, file: file, line: line)
                return true
            } else {
                return false
            }
        }
    }

    func waitForNextSyscall() throws -> UserToKernel {
        return try self.userToKernelBox.waitForValue()
    }
}
