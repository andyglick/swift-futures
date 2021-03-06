//
//  ThreadExecutor.swift
//  Futures
//
//  Copyright © 2019 Akis Kesoglou. Licensed under the MIT license.
//

import class Dispatch.DispatchSemaphore
import FuturesSync

public func assertOnThreadExecutor(_ executor: ThreadExecutor) {
    assert(ThreadExecutor.current === executor)
}

/// An executor that polls futures on the current thread.
///
/// `ThreadExecutor` is typically used to execute futures synchronously. Use
/// `wait()` to run the executor until all submitted futures complete or
/// `runUntil(_:)` to run until a given future completes. Both methods block
/// the current thread when no more progress can be made.
///
/// `ThreadExecutor` can also be used to integrate Futures with other
/// asynchronous systems. For example, each worker thread in a thread pool
/// could maintain a private `ThreadExecutor` instance and run it on every
/// tick using `run()`. This method does not block the current thread.
/// Instead, the executor runs until all possible progress is made and then
/// returns.
///
/// `ThreadExecutor` can optionally be initialized with limited capacity;
/// that is, it may be configured to have an upper bound on the number of
/// futures it tracks. Submitting a future that would result in the executor
/// exceeding capacity throws an error. You are encouraged to choose an
/// appropriate capacity for each use case, in order for the executor to
/// provide backpressure and limit memory usage or reduce latency. The executor
/// efficiently tracks its futures regardless of configured capacity; that is,
/// during each run it only polls futures that have signalled that they can
/// make progress.
///
/// Each thread automatically gets an unbounded `ThreadExecutor` instance that
/// is accessed via the `current` static property. Instances are lazily created
/// on first access and are stored in a thread local via `pthreads`. Note that
/// your code must still ensure it regularly calls `run()` or one of the `wait`
/// methods to run the executor.
///
/// `ThreadExecutor` is safe to use from one thread only, which is typically
/// the thread that created the instance. Submitting futures into the executor
/// or running the executor from multiple threads concurrently is undefined
/// behavior and will most likely result in a crash. The executor, however,
/// can handle concurrent wakeups from any number of threads.
public final class ThreadExecutor: BlockingExecutor {
    /// The type of errors this executor may return from `trySubmit(_:)`.
    ///
    /// It only defines one error case, for the executor being at capacity.
    public enum Failure: Error {
        /// Denotes that the executor is at capacity.
        ///
        /// This is a transient error; subsequent submissions may succeed.
        case atCapacity
    }

    public let label: String
    public let capacity: Int

    @usableFromInline let _runner: _TaskRunner
    @usableFromInline let _waker = _ThreadWaker()

    @inlinable
    public init(label: String? = nil, capacity: Int = .max) {
        let label = label ?? "futures.thread-executor"
        self.label = label
        self.capacity = capacity
        _runner = .init(label: label)
    }

    @inlinable
    public func trySubmit<F>(_ future: F) -> Result<Void, Failure>
        where F: FutureProtocol, F.Output == Void {
        if _runner.count == capacity {
            return .failure(.atCapacity)
        }
        _runner.schedule(future)
        return .success(())
    }

    @inlinable
    public func makeContext() -> Context {
        return Context(runner: _runner, waker: _waker)
    }

    @inlinable
    public func execute(in context: inout Context) -> Bool {
        return _runner.run(&context)
    }

    @inlinable
    public func block() {
        _waker.wait()
    }
}

// MARK: Default executors

@usableFromInline let _currentThreadExecutor = ThreadLocal {
    ThreadExecutor()
}

extension ThreadExecutor {
    @inlinable
    public static var current: ThreadExecutor {
        _currentThreadExecutor.value
    }

    @inlinable
    public var isCurrent: Bool {
        Self.current === self
    }
}

// MARK: - Private -

@usableFromInline
final class _ThreadWaker: WakerProtocol {
    @usableFromInline static let IDLE: UInt = 0
    @usableFromInline static let PARKED: UInt = 1
    @usableFromInline static let NOTIFIED: UInt = 2

    // used to prevent spurious wakeups due to the semaphore's value
    // accumulating via multiple signals by effectively coalescing them
    @usableFromInline var _state: AtomicUInt.RawValue = 0

    // used to park/unpark the thread
    @usableFromInline let _semaphore = DispatchSemaphore(value: 0)

    @inlinable
    init() {
        AtomicUInt.initialize(&_state, to: Self.IDLE)
    }

    @inlinable
    func signal() {
        switch AtomicUInt.exchange(&_state, Self.NOTIFIED) {
        case Self.NOTIFIED:
            // ignore this one; already signalled
            return

        case Self.IDLE:
            // ignore this one as well; `wait()` will observe
            // the notification and not block at all
            return

        case Self.PARKED:
            _semaphore.signal()

        default:
            fatalError("unreachable")
        }
    }

    @inlinable
    func wait() {
        switch AtomicUInt.compareExchange(&_state, Self.IDLE, Self.PARKED) {
        case Self.NOTIFIED:
            // already signalled; no need to block,
            // just consume the notification
            let prev = AtomicUInt.exchange(&_state, Self.IDLE)
            assert(prev == Self.NOTIFIED)
            return

        case Self.IDLE:
            // not signalled yet; block the thread.
            // There's potential for a race condition here that the counting
            // semaphore protects us against: after we changed the state above
            // and by the time we get to block the thread, someone may call
            // `signal()` on us and that notification would be lost. The
            // semaphore however "remembers" this signal and attempting to
            // wait on it results in `wait()` consuming that signal and
            // immediately returning (which is pretty much identical behavior
            // to what we do here as well).
            _semaphore.wait()

            while Self.NOTIFIED != AtomicUInt.compareExchange(&_state, Self.NOTIFIED, Self.IDLE) {
                Atomic.hardwarePause()
            }

        default:
            fatalError("unreachable")
        }
    }
}
