import Foundation
import Combine

public extension Publisher {
    func cancellable(id: AnyHashable) -> AnyPublisher<Self.Output, Self.Failure> {
        cancellablesLock.lock()
        defer { cancellablesLock.unlock() }
        
        let subject = PassthroughSubject<Output, Failure>()
        let cancellable = self.subscribe(subject)
        
        var cancellationCancellable: AnyCancellable!
        cancellationCancellable = AnyCancellable {
            cancellablesLock.sync {
                subject.send(completion: .finished)
                cancellable.cancel()
                cancellationCancellables[id]?.remove(cancellationCancellable)
                if cancellationCancellables[id]?.isEmpty == .some(true) {
                    cancellationCancellables[id] = nil
                }
            }
        }
        
        cancellationCancellables[id, default: []].insert(
            cancellationCancellable
        )
        
        return subject.handleEvents(
            receiveCompletion: { _ in cancellationCancellable.cancel() },
            receiveCancel: cancellationCancellable.cancel
        )
        .eraseToAnyPublisher()
    }
    
    static func cancel(id: AnyHashable) -> AnyPublisher<Self.Output, Self.Failure> {
        cancellablesLock.sync {
            cancellationCancellables[id]?.forEach { $0.cancel() }
        }
        
        return Just<Output?>(
            nil
        )
        .setFailureType(to: Failure.self)
        .compactMap { $0 }
        .eraseToAnyPublisher()
    }
}

var cancellationCancellables: [AnyHashable: Set<AnyCancellable>] = [:]
let cancellablesLock = NSRecursiveLock()

extension UnsafeMutablePointer where Pointee == os_unfair_lock_s {
    @inlinable @discardableResult
    func sync<R>(_ work: () -> R) -> R {
        os_unfair_lock_lock(self)
        defer { os_unfair_lock_unlock(self) }
        return work()
    }
}

extension NSRecursiveLock {
    @inlinable @discardableResult
    func sync<R>(work: () -> R) -> R {
        self.lock()
        defer { self.unlock() }
        return work()
    }
}
