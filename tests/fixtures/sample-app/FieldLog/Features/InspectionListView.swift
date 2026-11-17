import SwiftUI
import SwiftData

struct InspectionListView: View {
    @Query private var inspections: [Inspection]

    var body: some View {
        List(inspections) { inspection in
            Text(inspection.title)
        }
    }
}
