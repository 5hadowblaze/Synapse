import Foundation
import Observation

/// A completed pre/post pair around one Focus block.
struct TapPVTBookend: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let completedAt: Date
    let pre: TapPVTResult
    let post: TapPVTResult

    init(id: UUID = UUID(), completedAt: Date = Date(), pre: TapPVTResult, post: TapPVTResult) {
        self.id = id
        self.completedAt = completedAt
        self.pre = pre
        self.post = post
    }

    var comparison: TapPVTComparison { TapPVTComparison(pre: pre, post: post) }
}

/// Local history of reaction checks so the recap survives a relaunch.
/// Mirrors `FocusPatternStore`: UserDefaults, newest first, capped.
@Observable
@MainActor
final class TapPVTStore {
    private static let bookendKey = "synapse.pvt.bookends.v1"
    private static let standaloneKey = "synapse.pvt.standalone.v1"
    private static let maxStored = 20

    private(set) var bookends: [TapPVTBookend] = []
    private(set) var standalone: [TapPVTResult] = []

    var latestBookend: TapPVTBookend? { bookends.first }
    var latestStandalone: TapPVTResult? { standalone.first }

    init() {
        bookends = Self.load([TapPVTBookend].self, key: Self.bookendKey) ?? []
        standalone = Self.load([TapPVTResult].self, key: Self.standaloneKey) ?? []
    }

    @discardableResult
    func recordBookend(pre: TapPVTResult, post: TapPVTResult) -> TapPVTBookend {
        let record = TapPVTBookend(pre: pre, post: post)
        bookends.insert(record, at: 0)
        bookends = Array(bookends.prefix(Self.maxStored))
        Self.save(bookends, key: Self.bookendKey)
        return record
    }

    func recordStandalone(_ result: TapPVTResult) {
        standalone.insert(result, at: 0)
        standalone = Array(standalone.prefix(Self.maxStored))
        Self.save(standalone, key: Self.standaloneKey)
    }

    /// Typical pre-block median across stored bookends — context for a single reading.
    var typicalPreMedianMs: Double? {
        TapPVTResult.median(bookends.compactMap(\.pre.medianRtMs))
    }

    // MARK: - Persistence

    private static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
