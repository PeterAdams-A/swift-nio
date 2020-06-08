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

// MARK: ServerBootstrap - Server
extension ServerBootstrap {
    /// Specifies some `ChannelOption`s to be applied to the `ServerSocketChannel`.
    /// - See: serverChannelOption
    /// - Parameter options: Set of shorthand options to apply.
    /// - Returns: The updated server bootstrap (`self` being mutated)
    public func serverOptions(_ options: NIOTCPServerShorthandOptions) -> ServerBootstrap {
        let applier = ServerBootstrapServer_Applier(contained: self)
        return options.applyFallbackMapping(applier).contained
    }
    
    fileprivate struct ServerBootstrapServer_Applier: NIOChannelOptionAppliable {
        var contained: ServerBootstrap

        func applyOption<Option: ChannelOption>(_ option: Option, value: Option.Value) -> ServerBootstrapServer_Applier {
            return ServerBootstrapServer_Applier(contained: contained.serverChannelOption(option, value: value))
        }
    }
}

// MARK: ServerBootstrap - Child
extension ServerBootstrap {
    /// Specifies some `ChannelOption`s to be applied to the accepted `SocketChannel`s.
    /// - See: childChannelOption
    /// - Parameter options: Set of shorthand options to apply.
    /// - Returns: The update server bootstrap (`self` being mutated)
    public func childOptions(_ options: NIOTCPShorthandOptions) -> ServerBootstrap {
        let applier = ServerBootstrapChild_Applier(contained: self)
        return options.applyFallbackMapping(applier).contained
    }
    
    fileprivate struct ServerBootstrapChild_Applier: NIOChannelOptionAppliable {
        var contained: ServerBootstrap

        func applyOption<Option: ChannelOption>(_ option: Option, value: Option.Value) -> ServerBootstrapChild_Applier {
            return ServerBootstrapChild_Applier(contained: contained.childChannelOption(option, value: value))
        }
    }
}

// MARK: ClientBootstrap
extension ClientBootstrap {
    /// Specifies some `ChannelOption`s to be applied to the `SocketChannel`.
    /// - See: channelOption
    /// - Parameter options: Set of shorthand options to apply.
    /// - Returns: The updated client bootstrap (`self` being mutated)
    public func options(_ options: NIOTCPShorthandOptions) -> ClientBootstrap {
        let applier = ClientBootstrap_Applier(contained: self)
        return options.applyFallbackMapping(applier).contained
    }
    
    fileprivate struct ClientBootstrap_Applier: NIOChannelOptionAppliable {
        var contained: ClientBootstrap
        
        func applyOption<Option: ChannelOption>(_ option: Option, value: Option.Value) -> ClientBootstrap_Applier {
            return ClientBootstrap_Applier(contained: contained.channelOption(option, value: value))
        }
    }
}

// MARK: DatagramBootstrap
extension DatagramBootstrap {
    /// Specifies some `ChannelOption`s to be applied to the `DatagramChannel`.
    /// - See: channelOption
    /// - Parameter options: Set of shorthand options to apply.
    /// - Returns: The updated datagram bootstrap (`self` being mutated)
    public func options(_ options: NIOUDPShorthandOptions) -> DatagramBootstrap {
        let applier = DatagramBootstrap_Applier(contained: self)
        return options.applyFallbackMapping(applier).contained
    }
    
    fileprivate struct DatagramBootstrap_Applier: NIOChannelOptionAppliable {
        var contained: DatagramBootstrap
        
        func applyOption<Option: ChannelOption>(_ option: Option, value: Option.Value) -> DatagramBootstrap_Applier {
            return DatagramBootstrap_Applier(contained: contained.channelOption(option, value: value))
        }
    }
}

// MARK: NIOPipeBootstrap
extension NIOPipeBootstrap {
    /// Specifies some `ChannelOption`s to be applied to the `PipeChannel`.
    /// - See: channelOption
    /// - Parameter options: Set of shorthand options to apply.
    /// - Returns: The updated pipe bootstrap (`self` being mutated)
    public func options(_ options: NIOPipeShorthandOptions) -> NIOPipeBootstrap {
        let applier = NIOPipeBootstrap_Applier(contained: self)
        return options.applyFallbackMapping(applier).contained
    }
    
    fileprivate struct NIOPipeBootstrap_Applier: NIOChannelOptionAppliable {
        var contained: NIOPipeBootstrap
        
        func applyOption<Option: ChannelOption>(_ option: Option, value: Option.Value) -> NIOPipeBootstrap_Applier {
            return NIOPipeBootstrap_Applier(contained: contained.channelOption(option, value: value))
        }
    }
}

// MARK:  Universal Client Bootstrap
extension NIOClientTCPBootstrapProtocol {
    /// Apply any understood shorthand options to the bootstrap, removing them from the set of options if they are consumed.
    /// - parameters:
    ///     - options:  The options to try applying - the options applied should be consumed from here.
    /// - returns: The updated bootstrap with and options applied.
    public func _applyOptions(_ options: inout NIOTCPShorthandOptions) -> Self {
        // Default is to consume no options and not update self.
        return self
    }
}

extension NIOClientTCPBootstrap {
    /// Specifies some `ChannelOption`s to be applied to the channel.
    /// - See: channelOption
    /// - Parameter options: Set of shorthand options to apply.
    /// - Returns: The updated bootstrap (`self` being mutated)
    public func options(_ options: NIOTCPShorthandOptions) -> NIOClientTCPBootstrap {
        var optionsRemaining = options
        // First give the underlying a chance to consume options.
        let withUnderlyingOverrides =
            NIOClientTCPBootstrap(self, withUpdated: underlyingBootstrap._applyOptions(&optionsRemaining))
        // Default apply any remaining options.
        let applier = NIOClientTCPBootstrap_Applier(contained: withUnderlyingOverrides)
        return optionsRemaining.applyFallbackMapping(applier).contained
    }
    
    struct NIOClientTCPBootstrap_Applier: NIOChannelOptionAppliable {
        var contained: NIOClientTCPBootstrap
        
        func applyOption<Option: ChannelOption>(_ option: Option, value: Option.Value) -> NIOClientTCPBootstrap_Applier {
            return NIOClientTCPBootstrap_Applier(contained: contained.channelOption(option, value: value))
        }
    }
}

// MARK: Utility
/// An object which can have a 'ChannelOption' applied to it and will return an appropriately updated version of itself.
protocol NIOChannelOptionAppliable {
    /// Apply a ChannelOption and return an updated version of self.
    func applyOption<Option: ChannelOption>(_ option: Option, value: Option.Value) -> Self
}

/// An updater which works by appending to channelOptionsStorage.
private struct NIOChannelOptionsStorageApplier: NIOChannelOptionAppliable {
    /// The storage - the contents of this will be updated.
    var channelOptionsStorage: ChannelOptions.Storage
    
    public func applyOption<Option: ChannelOption>(_ option: Option, value: Option.Value) -> NIOChannelOptionsStorageApplier {
        var s = channelOptionsStorage
        s.append(key: option, value: value)
        return NIOChannelOptionsStorageApplier(channelOptionsStorage: s)
    }
}

/// Has an option been set?
/// Option has a value of generic type T.
public enum NIOOptionValue<T> {
    /// The option was not set.
    case notSet
    /// The option was set with a value of type T.
    case set(T)
}

public extension NIOOptionValue where T == () {
    /// Convenience method working with bool options as bool values for set.
    var isSet: Bool {
        get {
            switch self {
            case .notSet:
                return false
            case .set(()):
                return true
            }
        }
    }
}

private extension NIOOptionValue where T == () {
    init(flag: Bool) {
        if flag {
            self = .set(())
        } else {
            self = .notSet
        }
    }
}

// MARK: TCP - data
/// A TCP channel option which can be applied to a bootstrap using shorthand notation.
public struct NIOTCPShorthandOption: Hashable {
    fileprivate var data: ShorthandOption
    
    private init(_ data: ShorthandOption) {
        self.data = data
    }
    
    fileprivate enum ShorthandOption: Hashable {
        case reuseAddr
        case disableAutoRead
        case allowRemoteHalfClosure
    }
}

/// Approved shorthand options.
extension NIOTCPShorthandOption {
    /// Allow immediately reusing a local address.
    public static let allowImmediateLocalEndpointAddressReuse = NIOTCPShorthandOption(.reuseAddr)
    
    /// The user will manually call `Channel.read` once all the data is read from the transport.
    public static let disableAutoRead = NIOTCPShorthandOption(.disableAutoRead)
    
    /// Allows users to configure whether the `Channel` will close itself when its remote
    /// peer shuts down its send stream, or whether it will remain open. If set to `false` (the default), the `Channel`
    /// will be closed automatically if the remote peer shuts down its send stream. If set to true, the `Channel` will
    /// not be closed: instead, a `ChannelEvent.inboundClosed` user event will be sent on the `ChannelPipeline`,
    /// and no more data will be received.
    public static let allowRemoteHalfClosure =
        NIOTCPShorthandOption(.allowRemoteHalfClosure)
}

/// A set of `NIOTCPShorthandOption`s
public struct NIOTCPShorthandOptions : ExpressibleByArrayLiteral, Hashable {
    var allowImmediateLocalEndpointAddressReuse = false
    var disableAutoRead = false
    var allowRemoteHalfClosure = false
    
    /// Construct from an array literal.
    @inlinable
    public init(arrayLiteral elements: NIOTCPShorthandOption...) {
        for element in elements {
            add(element)
        }
    }
    
    @usableFromInline
    mutating func add(_ element: NIOTCPShorthandOption) {
        switch element.data {
        case .reuseAddr:
            self.allowImmediateLocalEndpointAddressReuse = true
        case .allowRemoteHalfClosure:
            self.allowRemoteHalfClosure = true
        case .disableAutoRead:
            self.disableAutoRead = true
        }
    }
    
    /// Caller is consuming the knowledge that allowImmediateLocalEndpointAddressReuse was set or not.
    /// The setting will nolonger be set after this call.
    /// - Returns: If allowImmediateLocalEndpointAddressReuse was set.
    public mutating func consumeAllowImmediateLocalEndpointAddressReuse() -> NIOOptionValue<Void> {
        defer {
            self.allowImmediateLocalEndpointAddressReuse = false
        }
        return NIOOptionValue<Void>(flag: self.allowImmediateLocalEndpointAddressReuse)
    }
    
    /// Caller is consuming the knowledge that disableAutoRead was set or not.
    /// The setting will nolonger be set after this call.
    /// - Returns: If disableAutoRead was set.
    public mutating func consumeDisableAutoRead() -> NIOOptionValue<Void> {
        defer {
            self.disableAutoRead = false
        }
        return NIOOptionValue<Void>(flag: self.disableAutoRead)
    }
    
    /// Caller is consuming the knowledge that allowRemoteHalfClosure was set or not.
    /// The setting will nolonger be set after this call.
    /// - Returns: If allowRemoteHalfClosure was set.
    public mutating func consumeAllowRemoteHalfClosure() -> NIOOptionValue<Void> {
        defer {
            self.allowRemoteHalfClosure = false
        }
        return NIOOptionValue<Void>(flag: self.allowRemoteHalfClosure)
    }
    
    /// Apply the contained option to the supplied ChannelOptions.Storage using the default mapping.
    /// - Parameter to: The storage to append this option to.
    /// - Returns: ChannelOptions.storage with option added.
    public func applyFallbackMapping(to storage: ChannelOptions.Storage) -> ChannelOptions.Storage {
        let applier = NIOChannelOptionsStorageApplier(channelOptionsStorage: storage)
        return self.applyFallbackMapping(applier).channelOptionsStorage
    }
    
    func applyFallbackMapping<OptionApplier: NIOChannelOptionAppliable>(_ optionApplier: OptionApplier) -> OptionApplier {
        var result = optionApplier
        if self.allowImmediateLocalEndpointAddressReuse {
            result = result.applyOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
        }
        if self.allowRemoteHalfClosure {
            result = result.applyOption(ChannelOptions.allowRemoteHalfClosure, value: true)
        }
        if self.disableAutoRead {
            result = result.applyOption(ChannelOptions.autoRead, value: false)
        }
        return result
    }
}

// MARK: TCP - server
/// A channel option which can be applied to bootstrap using shorthand notation.
public struct NIOTCPServerShorthandOption: Hashable {
    fileprivate var data: ShorthandOption
    
    private init(_ data: ShorthandOption) {
        self.data = data
    }
    
    fileprivate enum ShorthandOption: Hashable {
        case reuseAddr
        case disableAutoRead
        case backlog(Int32)
    }
}

/// Approved shorthand server options.
extension NIOTCPServerShorthandOption {
    /// Allow immediately reusing a local address.
    public static let allowImmediateLocalEndpointAddressReuse = NIOTCPServerShorthandOption(.reuseAddr)
    
    /// The user will manually call `Channel.read` once all the data is read from the transport.
    public static let disableAutoRead = NIOTCPServerShorthandOption(.disableAutoRead)
    
    /// Allows users to configure the maximum number of connections waiting to be accepted.
    /// This is possibly advisory and exact resuilts will depend on the underlying implementation.
    public static func maximumUnacceptedConnectionBacklog(_ value: ChannelOptions.Types.BacklogOption.Value) ->
        NIOTCPServerShorthandOption {
        return NIOTCPServerShorthandOption(.backlog(value))
    }
}

/// A set of `NIOTCPServerShorthandOption`s
public struct NIOTCPServerShorthandOptions : ExpressibleByArrayLiteral, Hashable {
    var allowImmediateLocalEndpointAddressReuse = false
    var disableAutoRead = false
    var maximumUnacceptedConnectionBacklog : Int32? = nil
    
    /// Construct from an array literal.
    @inlinable
    public init(arrayLiteral elements: NIOTCPServerShorthandOption...) {
        for element in elements {
            add(element)
        }
    }
    
    @usableFromInline
    mutating func add(_ element: NIOTCPServerShorthandOption) {
        switch element.data {
        case .reuseAddr:
            self.allowImmediateLocalEndpointAddressReuse = true
        case .disableAutoRead:
            self.disableAutoRead = true
        case .backlog(let value):
            self.maximumUnacceptedConnectionBacklog = value
        }
    }
    
    /// Caller is consuming the knowledge that allowImmediateLocalEndpointAddressReuse was set or not.
    /// The setting will nolonger be set after this call.
    /// - Returns: If allowImmediateLocalEndpointAddressReuse was set.
    public mutating func consumeAllowImmediateLocalEndpointAddressReuse() -> NIOOptionValue<Void> {
        defer {
            self.allowImmediateLocalEndpointAddressReuse = false
        }
        return NIOOptionValue<Void>(flag: self.allowImmediateLocalEndpointAddressReuse)
    }
    
    /// Caller is consuming the knowledge that disableAutoRead was set or not.
    /// The setting will nolonger be set after this call.
    /// - Returns: If disableAutoRead was set.
    public mutating func consumeDisableAutoRead() -> NIOOptionValue<Void> {
        defer {
            self.disableAutoRead = false
        }
        return NIOOptionValue<Void>(flag: self.disableAutoRead)
    }
    
    /// Caller is consuming the knowledge that maximumUnacceptedConnectionBacklog was set or not.
    /// The setting will nolonger be set after this call.
    /// - Returns: If maximumUnacceptedConnectionBacklog was set.
    public mutating func consumeMaximumUnacceptedConnectionBacklog() -> NIOOptionValue<Int32> {
        defer {
            self.maximumUnacceptedConnectionBacklog = nil
        }
        if let value = self.maximumUnacceptedConnectionBacklog {
            return .set(value)
        } else {
            return .notSet
        }
    }
    
    /// Apply the contained option to the supplied ChannelOptions.Storage using the default mapping.
    /// - Parameter to: The storage to append this option to.
    /// - Returns: ChannelOptions.storage with option added.
    public func applyFallbackMapping(to storage: ChannelOptions.Storage) -> ChannelOptions.Storage {
        let applier = NIOChannelOptionsStorageApplier(channelOptionsStorage: storage)
        return self.applyFallbackMapping(applier).channelOptionsStorage
    }
    
    func applyFallbackMapping<OptionApplier: NIOChannelOptionAppliable>(_ optionApplier: OptionApplier) -> OptionApplier {
        var result = optionApplier
        if self.allowImmediateLocalEndpointAddressReuse {
            result = result.applyOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
        }
        if let value = self.maximumUnacceptedConnectionBacklog {
            result = result.applyOption(ChannelOptions.backlog, value: value)
        }
        if self.disableAutoRead {
            result = result.applyOption(ChannelOptions.autoRead, value: false)
        }
        return result
    }
}

// MARK: UDP
/// A channel option which can be applied to a UDP based bootstrap using shorthand notation.
/// - See: DatagramBootstrap.options(_ options: [Option])
public struct NIOUDPShorthandOption: Hashable {
    fileprivate var data: ShorthandOption
    
    private init(_ data: ShorthandOption) {
        self.data = data
    }
    
    fileprivate enum ShorthandOption: Hashable {
        case reuseAddr
        case disableAutoRead
    }
}

/// Approved shorthand datagram channel options.
extension NIOUDPShorthandOption {
    /// Allow immediately reusing a local address.
    public static let allowImmediateLocalEndpointAddressReuse =
            NIOUDPShorthandOption(.reuseAddr)
    
    /// The user will manually call `Channel.read` once all the data is read from the transport.
    public static let disableAutoRead = NIOUDPShorthandOption(.disableAutoRead)
}

/// A set of `NIOUDPShorthandOption`s
public struct NIOUDPShorthandOptions : ExpressibleByArrayLiteral, Hashable {
    var allowImmediateLocalEndpointAddressReuse = false
    var disableAutoRead = false
    
    /// Construct from an array literal.
    @inlinable
    public init(arrayLiteral elements: NIOUDPShorthandOption...) {
        for element in elements {
            add(element)
        }
    }
    
    @usableFromInline
    mutating func add(_ element: NIOUDPShorthandOption) {
        switch element.data {
        case .reuseAddr:
            self.allowImmediateLocalEndpointAddressReuse = true
        case .disableAutoRead:
            self.disableAutoRead = true
        }
    }
    
    /// Caller is consuming the knowledge that allowImmediateLocalEndpointAddressReuse was set or not.
    /// The setting will nolonger be set after this call.
    /// - Returns: If allowImmediateLocalEndpointAddressReuse was set.
    public mutating func consumeAllowImmediateLocalEndpointAddressReuse() -> NIOOptionValue<Void> {
        defer {
            self.allowImmediateLocalEndpointAddressReuse = false
        }
        return NIOOptionValue<Void>(flag: self.allowImmediateLocalEndpointAddressReuse)
    }
    
    /// Caller is consuming the knowledge that disableAutoRead was set or not.
    /// The setting will nolonger be set after this call.
    /// - Returns: If disableAutoRead was set.
    public mutating func consumeDisableAutoRead() -> NIOOptionValue<Void> {
        defer {
            self.disableAutoRead = false
        }
        return NIOOptionValue<Void>(flag: self.disableAutoRead)
    }
    
    /// Apply the contained option to the supplied ChannelOptions.Storage using the default mapping.
    /// - Parameter to: The storage to append this option to.
    /// - Returns: ChannelOptions.storage with option added.
    public func applyFallbackMapping(to storage: ChannelOptions.Storage) -> ChannelOptions.Storage {
        let applier = NIOChannelOptionsStorageApplier(channelOptionsStorage: storage)
        return self.applyFallbackMapping(applier).channelOptionsStorage
    }
    
    func applyFallbackMapping<OptionApplier: NIOChannelOptionAppliable>(_ optionApplier: OptionApplier) -> OptionApplier {
        var result = optionApplier
        if self.allowImmediateLocalEndpointAddressReuse {
            result = result.applyOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
        }
        if self.disableAutoRead {
            result = result.applyOption(ChannelOptions.autoRead, value: false)
        }
        return result
    }
}

// MARK: Pipe
/// A channel option which can be applied to pipe bootstrap using shorthand notation.
/// - See: NIOPipeBootstrap.options(_ options: [Option])
public struct NIOPipeShorthandOption: Hashable {
    fileprivate let data: ShorthandOption
    
    private init(_ data: ShorthandOption) {
        self.data = data
    }
    
    fileprivate enum ShorthandOption: Hashable {
        case disableAutoRead
        case allowRemoteHalfClosure
    }
}

/// Approved shorthand datagram channel options.
extension NIOPipeShorthandOption {
    /// The user will manually call `Channel.read` once all the data is read from the transport.
    public static let disableAutoRead = NIOPipeShorthandOption(.disableAutoRead)
    
    /// Allows users to configure whether the `Channel` will close itself when its remote
    /// peer shuts down its send stream, or whether it will remain open. If set to `false` (the default), the `Channel`
    /// will be closed automatically if the remote peer shuts down its send stream. If set to true, the `Channel` will
    /// not be closed: instead, a `ChannelEvent.inboundClosed` user event will be sent on the `ChannelPipeline`,
    /// and no more data will be received.
    public static let allowRemoteHalfClosure =
        NIOPipeShorthandOption(.allowRemoteHalfClosure)
}

/// A set of `NIOPipeShorthandOption`s
public struct NIOPipeShorthandOptions : ExpressibleByArrayLiteral, Hashable {
    var allowRemoteHalfClosure = false
    var disableAutoRead = false
    
    /// Construct from an array literal.
    @inlinable
    public init(arrayLiteral elements: NIOPipeShorthandOption...) {
        for element in elements {
            add(element)
        }
    }
    
    @usableFromInline
    mutating func add(_ element: NIOPipeShorthandOption) {
        switch element.data {
        case .allowRemoteHalfClosure:
            self.allowRemoteHalfClosure = true
        case .disableAutoRead:
            self.disableAutoRead = true
        }
    }
    
    /// Caller is consuming the knowledge that allowRemoteHalfClosure was set or not.
    /// The setting will nolonger be set after this call.
    /// - Returns: If allowRemoteHalfClosure was set.
    public mutating func consumeAllowRemoteHalfClosure() -> NIOOptionValue<Void> {
        defer {
            self.allowRemoteHalfClosure = false
        }
        return NIOOptionValue<Void>(flag: self.allowRemoteHalfClosure)
    }
    
    /// Caller is consuming the knowledge that disableAutoRead was set or not.
    /// The setting will nolonger be set after this call.
    /// - Returns: If disableAutoRead was set.
    public mutating func consumeDisableAutoRead() -> NIOOptionValue<Void> {
        defer {
            self.disableAutoRead = false
        }
        return NIOOptionValue<Void>(flag: self.disableAutoRead)
    }
    
    /// Apply the contained option to the supplied ChannelOptions.Storage using the default mapping.
    /// - Parameter to: The storage to append this option to.
    /// - Returns: ChannelOptions.storage with option added.
    public func applyFallbackMapping(to storage: ChannelOptions.Storage) -> ChannelOptions.Storage {
        let applier = NIOChannelOptionsStorageApplier(channelOptionsStorage: storage)
        return self.applyFallbackMapping(applier).channelOptionsStorage
    }
    
    func applyFallbackMapping<OptionApplier: NIOChannelOptionAppliable>(_ optionApplier: OptionApplier) -> OptionApplier {
        var result = optionApplier
        if self.allowRemoteHalfClosure {
            result = result.applyOption(ChannelOptions.allowRemoteHalfClosure, value: true)
        }
        if self.disableAutoRead {
            result = result.applyOption(ChannelOptions.autoRead, value: false)
        }
        return result
    }
}
