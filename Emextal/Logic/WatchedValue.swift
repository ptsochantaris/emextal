import Foundation
import Synchronization

/// A thread-safe value cell that lets callers `await` until the value satisfies a condition,
/// replacing the `while !flag { try? await Task.sleep(...) }` polling-as-a-barrier pattern.
///
/// Reads and writes are synchronous and lock-protected, so it drops in wherever a plain flag
/// lived. Writers wake any waiters whose predicate the new value satisfies; waiters suspend
/// (no polling, no wake-ups in between) until then.
///
/// ```swift
/// private let bootDone = WatchedValue(false)
/// ...
/// bootDone.set(true)          // from the producer
/// await bootDone.reaches(true) // from the consumer
/// ```
final nonisolated class WatchedValue<Value: Sendable>: Sendable {
    private struct Waiter {
        let predicate: @Sendable (Value) -> Bool
        let continuation: CheckedContinuation<Value, Never>
    }

    private struct State {
        var value: Value
        var waiters: [Int: Waiter] = [:]
        var nextID = 0
    }

    private let state: Mutex<State>

    init(_ initialValue: Value) {
        state = Mutex(State(value: initialValue))
    }

    /// A synchronous snapshot of the current value.
    var value: Value {
        state.withLock { $0.value }
    }

    /// Sets a new value, waking every waiter whose predicate it now satisfies.
    func set(_ newValue: Value) {
        let resumable = state.withLock { state -> [CheckedContinuation<Value, Never>] in
            state.value = newValue
            var toResume: [CheckedContinuation<Value, Never>] = []
            state.waiters = state.waiters.filter { _, waiter in
                if waiter.predicate(newValue) {
                    toResume.append(waiter.continuation)
                    return false
                }
                return true
            }
            return toResume
        }
        // Resume outside the lock so a continuation that immediately re-enters can't deadlock.
        for continuation in resumable {
            continuation.resume(returning: newValue)
        }
    }

    /// Mutates the value in place, then wakes any waiters the result satisfies.
    func mutate(_ transform: (inout Value) -> Void) {
        var snapshot = value
        transform(&snapshot)
        set(snapshot)
    }

    /// Suspends until the value satisfies `predicate`, returning the value that did. Returns
    /// immediately if the current value already satisfies it. Honours task cancellation.
    @discardableResult
    func first(where predicate: @escaping @Sendable (Value) -> Bool) async -> Value {
        let id = state.withLock { state -> Int in
            let id = state.nextID
            state.nextID += 1
            return id
        }

        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Value, Never>) in
                let immediate: Value? = state.withLock { state in
                    if predicate(state.value) {
                        return state.value
                    }
                    state.waiters[id] = Waiter(predicate: predicate, continuation: continuation)
                    return nil
                }
                if let immediate {
                    continuation.resume(returning: immediate)
                }
            }
        } onCancel: {
            let pending = state.withLock { state -> (CheckedContinuation<Value, Never>, Value)? in
                guard let waiter = state.waiters.removeValue(forKey: id) else { return nil }
                return (waiter.continuation, state.value)
            }
            pending?.0.resume(returning: pending!.1)
        }
    }
}

extension WatchedValue where Value: Equatable {
    /// Suspends until the value equals `target`.
    func reaches(_ target: Value) async {
        await first { $0 == target }
    }
}
