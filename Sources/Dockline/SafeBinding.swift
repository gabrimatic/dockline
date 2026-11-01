import SwiftUI

extension Binding where Value: Sendable {
    /// A binding that is safe for SwiftUI to evaluate on any thread.
    ///
    /// `Binding(get:set:)` written inside a `@MainActor` view inherits main-actor isolation, and SwiftUI
    /// can call a binding's getter off the main thread while it updates a view graph. The runtime
    /// isolation check then traps (`_dispatch_assert_queue_fail`). This builds the binding in a
    /// nonisolated context instead: the getter returns `value`, which the caller read on the main
    /// actor while building its body, and the setter hops to the main actor to run `set`.
    /// SwiftUI reads the new value on its next update, because `set` changes observed state.
    nonisolated static func snapshot(
        _ value: Value,
        set: @escaping @MainActor @Sendable (Value) -> Void
    ) -> Binding<Value> {
        Binding(
            get: { @Sendable in value },
            set: { @Sendable newValue in Task { @MainActor in set(newValue) } }
        )
    }
}
