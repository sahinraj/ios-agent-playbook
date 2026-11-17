Context: Swift 6 language mode. Default actor isolation is MainActor for the app target. `NetworkClient` is a final class with a mutable token cache. It is used from view models and from a background sync task.

Task: make `NetworkClient` safe to use from the sync task. Show the plan first.
