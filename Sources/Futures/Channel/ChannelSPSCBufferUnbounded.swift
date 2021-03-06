//
//  ChannelSPSCBufferUnbounded.swift
//  Futures
//
//  Copyright © 2019 Akis Kesoglou. Licensed under the MIT license.
//

import FuturesSync

extension Channel._Private {
    public struct SPSCBufferUnbounded<Item>: _ChannelBufferImplProtocol {
        @usableFromInline let _buffer = AtomicUnboundedSPSCQueue<Item>()

        @inlinable
        init() {}

        @inlinable
        public static var isPassthrough: Bool {
            return false
        }

        @inlinable
        public static var isBounded: Bool {
            return false
        }

        @inlinable
        public var capacity: Int {
            return Int.max
        }

        @inlinable
        public func push(_ item: Item) {
            _buffer.push(item)
        }

        @inlinable
        public func pop() -> Item? {
            return _buffer.pop()
        }
    }
}
