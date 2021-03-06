//
//  RemoveDuplicatesStream.swift
//  Futures
//
//  Copyright © 2019 Akis Kesoglou. Licensed under the MIT license.
//

extension Stream._Private {
    public enum RemoveDuplicates<Base: StreamProtocol>: StreamProtocol {
        public typealias Output = Base.Output
        public typealias Predicate = (Output, Output) -> Bool

        case pending(Base, Predicate)
        case comparing(Base, Predicate, Output)
        case done

        @inlinable
        public init(base: Base, predicate: @escaping Predicate) {
            self = .pending(base, predicate)
        }

        @inlinable
        public mutating func pollNext(_ context: inout Context) -> Poll<Output?> {
            switch self {
            case .pending(var base, let predicate):
                switch base.pollNext(&context) {
                case .ready(.some(let output)):
                    self = .comparing(base, predicate, output)
                    return .ready(output)
                case .ready(.none):
                    self = .done
                    return .ready(nil)
                case .pending:
                    self = .pending(base, predicate)
                    return .pending
                }

            case .comparing(var base, let predicate, let previousOutput):
                while true {
                    switch base.pollNext(&context) {
                    case .ready(.some(let output)):
                        if predicate(previousOutput, output) {
                            continue
                        }
                        self = .comparing(base, predicate, output)
                        return .ready(output)
                    case .ready(.none):
                        self = .done
                        return .ready(nil)
                    case .pending:
                        self = .comparing(base, predicate, previousOutput)
                        return .pending
                    }
                }

            case .done:
                fatalError("cannot poll after completion")
            }
        }
    }
}

extension Stream._Private.RemoveDuplicates where Output: Equatable {
    @inlinable
    public init(base: Base) {
        self = .pending(base) {
            $0 == $1
        }
    }
}
