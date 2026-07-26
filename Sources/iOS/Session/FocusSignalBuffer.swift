import Foundation

/// One point on the live Signals timeline. Missing optionals = channel not available
/// (Watch off, camera asleep, no pace score yet) — never invent values.
struct FocusSignalSample: Equatable, Sendable {
    let date: Date
    /// Seconds since the Focus block that owns this buffer started.
    let elapsedSeconds: TimeInterval
    let heartRateBpm: Double?
    /// Fade composite 0…1 — UI labels this “Pace signal”, never “fatigue”.
    let paceScore: Double?
    /// Face arousal / eyeWide proxy when the camera is awake. Nil when camera is off.
    let presenceProxy: Double?
    /// Watch IMU motion energy (higher = more fidget). Nil when Watch stillness isn’t streaming.
    let motionEnergy: Double?
    let signalState: FocusSignalState
    let cameraAwake: Bool
}

enum FocusSignalEventKind: Equatable, Sendable {
    case baselineReady
    case breakSuggested
}

/// Discrete annotations on the Signals timeline (baseline ready, break suggested).
struct FocusSignalEvent: Equatable, Sendable, Identifiable {
    let id: UUID
    let date: Date
    let elapsedSeconds: TimeInterval
    let kind: FocusSignalEventKind

    init(
        id: UUID = UUID(),
        date: Date,
        elapsedSeconds: TimeInterval,
        kind: FocusSignalEventKind
    ) {
        self.id = id
        self.date = date
        self.elapsedSeconds = elapsedSeconds
        self.kind = kind
    }
}

/// Fixed-capacity ring buffer of Focus signal samples + event markers.
/// Pure value type — unit-testable without sensors or UI.
struct FocusSignalBuffer: Equatable, Sendable {
    /// Default holds ~10 minutes at a 2 s cadence.
    static let defaultCapacity = 300

    var capacity: Int
    private(set) var samples: [FocusSignalSample] = []
    private(set) var events: [FocusSignalEvent] = []

    init(capacity: Int = FocusSignalBuffer.defaultCapacity) {
        self.capacity = max(1, capacity)
    }

    var isEmpty: Bool { samples.isEmpty }
    var count: Int { samples.count }

    mutating func append(_ sample: FocusSignalSample) {
        samples.append(sample)
        trimToCapacity()
    }

    mutating func mark(_ event: FocusSignalEvent) {
        events.append(event)
        // Keep event list bounded to the same window as samples.
        if let oldest = samples.first?.elapsedSeconds {
            events.removeAll { $0.elapsedSeconds < oldest }
        }
        if events.count > capacity {
            events.removeFirst(events.count - capacity)
        }
    }

    mutating func reset() {
        samples.removeAll(keepingCapacity: true)
        events.removeAll(keepingCapacity: true)
    }

    // MARK: - Series (honest — skips missing channels)

    var heartRateSeries: [(elapsed: TimeInterval, value: Double)] {
        samples.compactMap { sample in
            guard let bpm = sample.heartRateBpm else { return nil }
            return (sample.elapsedSeconds, bpm)
        }
    }

    var paceSeries: [(elapsed: TimeInterval, value: Double)] {
        samples.compactMap { sample in
            guard let score = sample.paceScore else { return nil }
            return (sample.elapsedSeconds, score)
        }
    }

    var presenceSeries: [(elapsed: TimeInterval, value: Double)] {
        samples.compactMap { sample in
            guard sample.cameraAwake, let presence = sample.presenceProxy else { return nil }
            return (sample.elapsedSeconds, presence)
        }
    }

    var motionSeries: [(elapsed: TimeInterval, value: Double)] {
        samples.compactMap { sample in
            guard let energy = sample.motionEnergy else { return nil }
            return (sample.elapsedSeconds, energy)
        }
    }

    var hasHeartRate: Bool { samples.contains { $0.heartRateBpm != nil } }
    var hasPace: Bool { samples.contains { $0.paceScore != nil } }
    var hasPresence: Bool { samples.contains { $0.cameraAwake && $0.presenceProxy != nil } }
    var hasMotion: Bool { samples.contains { $0.motionEnergy != nil } }

    var latest: FocusSignalSample? { samples.last }

    private mutating func trimToCapacity() {
        guard samples.count > capacity else { return }
        let overflow = samples.count - capacity
        samples.removeFirst(overflow)
        if let oldest = samples.first?.elapsedSeconds {
            events.removeAll { $0.elapsedSeconds < oldest }
        }
    }
}

/// In-memory live + last-session store for the Signals screen.
@Observable
@MainActor
final class FocusSignalStore {
    private(set) var buffer = FocusSignalBuffer()
    private(set) var sessionStartedAt: Date?
    private(set) var isLive = false
    /// True after at least one Focus block has filled the buffer this app launch.
    private(set) var hasSessionData = false

    /// Minimum gap between ordinary samples (events may force a write).
    var minSampleInterval: TimeInterval = 2

    private var lastSampleAt: Date?
    private var lastRecordedState: FocusSignalState?

    func beginSession(at date: Date = Date()) {
        buffer.reset()
        sessionStartedAt = date
        isLive = true
        hasSessionData = false
        lastSampleAt = nil
        lastRecordedState = nil
    }

    func endSession() {
        isLive = false
        // Keep the buffer so Hub / Signals can show the last block.
    }

    /// Append a sample from the live Focus / Watch / face pipelines.
    /// Throttled unless `force` (used for fade / baseline markers).
    @discardableResult
    func record(
        heartRateBpm: Double?,
        paceScore: Double?,
        presenceProxy: Float?,
        motionEnergy: Double?,
        signalState: FocusSignalState,
        cameraAwake: Bool,
        force: Bool = false,
        at date: Date = Date()
    ) -> Bool {
        guard sessionStartedAt != nil || force else { return false }
        if sessionStartedAt == nil {
            sessionStartedAt = date
        }
        if !force, let last = lastSampleAt, date.timeIntervalSince(last) < minSampleInterval {
            return false
        }

        let started = sessionStartedAt ?? date
        let elapsed = max(0, date.timeIntervalSince(started))
        let sample = FocusSignalSample(
            date: date,
            elapsedSeconds: elapsed,
            heartRateBpm: heartRateBpm,
            paceScore: paceScore,
            presenceProxy: presenceProxy.map { Double($0) },
            motionEnergy: motionEnergy,
            signalState: signalState,
            cameraAwake: cameraAwake
        )
        buffer.append(sample)
        lastSampleAt = date
        hasSessionData = true
        lastRecordedState = signalState
        return true
    }

    func markBaselineReady(at date: Date = Date()) {
        ensureSessionClock(at: date)
        let started = sessionStartedAt ?? date
        let elapsed = max(0, date.timeIntervalSince(started))
        buffer.mark(FocusSignalEvent(date: date, elapsedSeconds: elapsed, kind: .baselineReady))
    }

    func markBreakSuggested(at date: Date = Date()) {
        ensureSessionClock(at: date)
        let started = sessionStartedAt ?? date
        let elapsed = max(0, date.timeIntervalSince(started))
        buffer.mark(FocusSignalEvent(date: date, elapsedSeconds: elapsed, kind: .breakSuggested))
    }

    private func ensureSessionClock(at date: Date) {
        if sessionStartedAt == nil {
            sessionStartedAt = date
        }
    }
}
