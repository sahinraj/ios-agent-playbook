import Foundation
@preconcurrency import Combine

final class SyncEngine: @unchecked Sendable {
    private let queue = DispatchQueue(label: "sync")
    private var pending: [String] = []

    func flush() {
        Task {
            try await upload()
        }
        queue.async { self.pending.removeAll() }
    }

    func upload() async throws {}
}
