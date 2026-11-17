import Foundation
import SwiftData

@Model
final class Inspection {
    var number: String
    var title: String
    @Relationship(deleteRule: .cascade) var findings: [Finding] = []

    init(number: String, title: String) {
        self.number = number
        self.title = title
    }
}

@Model final class Finding {
    var note: String
    init(note: String) { self.note = note }
}
