//
//  Thread.swift
//  Futures
//
//  Copyright © 2019 Akis Kesoglou. Licensed under the MIT license.
//

// This is largely copied from swift-nio: https://github.com/apple/swift-nio

#if canImport(Darwin)
import Darwin.POSIX.pthread
#else
import Glibc
#endif

public struct ThreadLocal<T> {
    public typealias Constructor = () -> T

    @usableFromInline let _key = _Key()
    @usableFromInline let _constructor: Constructor

    @inlinable
    public init(_ constructor: @escaping Constructor) {
        _constructor = constructor
    }

    @inlinable
    public init<W>() where T == W? {
        _constructor = { nil }
    }

    @inlinable
    public var value: T {
        _getBox().value
    }

    @inlinable
    @inline(__always)
    public func withNewValue<R>(_ newValue: T, perform: () throws -> R) rethrows -> R {
        let box = _getBox()
        let currentValue = box.value
        box.value = newValue
        defer { box.value = currentValue }
        return try perform()
    }

    @inlinable
    public func reset() {
        _destroyBox()
    }

    @inlinable
    public func destroy() {
        _key.destroy()
    }

    // MARK: Private

    @usableFromInline struct _Key {
        @usableFromInline let handle: pthread_key_t

        @inlinable
        init() {
            var key = pthread_key_t()
            let rc = pthread_key_create(&key) { ptr in
                Unmanaged<AnyObject>
                    // Casting as optional to resolve platform differences
                    // swiftlint:disable:next force_unwrapping
                    .fromOpaque((ptr as UnsafeMutableRawPointer?)!)
                    .release()
            }
            precondition(rc == 0, "Could not create TLS key: \(rc)")
            handle = key
        }

        @inlinable
        func destroy() {
            let rc = pthread_key_delete(handle)
            precondition(rc == 0, "Could not destroy TLS key: \(rc)")
        }
    }

    @usableFromInline final class _Box {
        @usableFromInline var value: T

        @inlinable
        init(value: T) {
            self.value = value
        }
    }

    @inlinable
    func _getBox() -> _Box {
        if let ptr = pthread_getspecific(_key.handle) {
            return Unmanaged<_Box>.fromOpaque(ptr).takeUnretainedValue()
        }
        let box = _Box(value: _constructor())
        let rc = pthread_setspecific(
            _key.handle,
            Unmanaged.passRetained(box).toOpaque()
        )
        precondition(rc == 0, "Could not set TLS value: \(rc)")
        return box
    }

    @inlinable
    func _destroyBox() {
        pthread_getspecific(_key.handle).map {
            Unmanaged<_Box>.fromOpaque($0).release()
        }
    }
}
