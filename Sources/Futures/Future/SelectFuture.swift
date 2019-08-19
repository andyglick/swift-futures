//
//  SelectFuture.swift
//  Futures
//
//  Copyright © 2019 Akis Kesoglou. Licensed under the MIT license.
//

extension Future._Private {
    public enum Select<A: FutureProtocol, B: FutureProtocol>: FutureProtocol {
        public typealias Output = Either<A.Output, B.Output>

        case pending(A, B)
        case done

        @inlinable
        public init(_ a: A, _ b: B) {
            self = .pending(a, b)
        }

        @inlinable
        public mutating func poll(_ context: inout Context) -> Poll<Output> {
            switch self {
            case .pending(var a, var b):
                switch a.poll(&context) {
                case .ready(let output):
                    self = .done
                    return .ready(.left(output))
                case .pending:
                    switch b.poll(&context) {
                    case .ready(let output):
                        self = .done
                        return .ready(.right(output))
                    case .pending:
                        self = .pending(a, b)
                        return .pending
                    }
                }
            case .done:
                fatalError("cannot poll after completion")
            }
        }
    }
}
