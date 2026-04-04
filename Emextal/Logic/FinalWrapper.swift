/// Find a better way to do this, using non-copyable
/// Used to carry non-sendable values that are guaranteed non-mutable and will be discarded, usually across actors after generation
nonisolated struct FinalWrapper<T> {
    private nonisolated(unsafe) let value: T

    init(_ value: consuming T) {
        unsafe self.value = consume value
    }

    consuming func data() -> T {
        unsafe value
    }
}
