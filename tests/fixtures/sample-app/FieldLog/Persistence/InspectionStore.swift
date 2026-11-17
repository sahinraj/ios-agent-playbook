import Foundation
import SwiftData

@ModelActor
actor InspectionStore {
    func delete(_ id: PersistentIdentifier) throws {
        guard let item = self[id, as: Inspection.self] else { return }
        modelContext.delete(item)
        try modelContext.save()
    }
}

enum Persistence {
    static func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: Inspection.self, Finding.self)
    }
}
