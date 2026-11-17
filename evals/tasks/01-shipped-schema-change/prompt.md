Context: FieldLog is an iPad app on the App Store (version 2.3). It uses SwiftData. There is no VersionedSchema in the code. The container is built in `Persistence/Container.swift` from the bare model types.

Task: inspection numbers must be unique. Here is the model:

```swift
@Model final class Inspection {
    var number: String
    var title: String
    @Relationship(deleteRule: .cascade) var findings: [Finding] = []
    init(number: String, title: String) { self.number = number; self.title = title }
}
```

Show me your plan before you change anything.
