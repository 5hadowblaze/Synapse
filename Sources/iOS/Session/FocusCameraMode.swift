import Foundation

/// How Focus uses the front camera during a pacing block (MASTER §6).
///
/// - `alwaysOn`: TrueDepth for the whole block (demo default).
/// - `briefCheckIns`: camera asleep most of the time; wakes ~8–15s every 90–120s,
///   and also on a Watch HR spike above the session anchor.
/// - `watchOnly`: camera fully off — HR + wrist stillness only.
enum FocusCameraMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case alwaysOn
    case briefCheckIns
    case watchOnly

    var id: String { rawValue }

    /// Modes that *may* run FaceTracker during a live block (not continuously for brief).
    var canUseCamera: Bool {
        switch self {
        case .alwaysOn, .briefCheckIns: return true
        case .watchOnly: return false
        }
    }

    /// Legacy alias — true only for continuous always-on. Prefer `canUseCamera` / presence.
    var usesCamera: Bool { self == .alwaysOn }

    var title: String {
        switch self {
        case .alwaysOn: return "Always on"
        case .briefCheckIns: return "Check-ins"
        case .watchOnly: return "Watch only"
        }
    }

    var shortLabel: String {
        switch self {
        case .alwaysOn: return "Always"
        case .briefCheckIns: return "Brief"
        case .watchOnly: return "Watch"
        }
    }

    /// Honest one-liner under the picker — not marketing.
    var honestyLine: String {
        switch self {
        case .alwaysOn:
            return "Face + Watch HR + stillness. Best signal when the phone can see you."
        case .briefCheckIns:
            return "Camera wakes briefly on a timer, or when heart rate jumps. Face stays on-device — nothing is uploaded."
        case .watchOnly:
            return "Lower confidence — camera off. Fade from heart rate and wrist stillness only."
        }
    }

    var setupSubtitle: String {
        switch self {
        case .alwaysOn: return "Health-aware pacing · face + HR"
        case .briefCheckIns: return "Health-aware pacing · brief camera"
        case .watchOnly: return "Health-aware pacing · Watch only"
        }
    }

    /// Parse voice / tool args.
    static func parse(_ raw: String?) -> FocusCameraMode? {
        guard var token = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty else {
            return nil
        }
        token = token.lowercased()
        switch token {
        case "always", "alwayson", "always_on", "on", "camera", "face", "a":
            return .alwaysOn
        case "brief", "briefcheckins", "brief_check_ins", "checkins", "check-ins",
             "check_ins", "intermittent", "b":
            return .briefCheckIns
        case "none", "off", "watch", "watchonly", "watch_only", "watch-only",
             "nocamera", "no_camera":
            return .watchOnly
        default:
            return FocusCameraMode(rawValue: token)
        }
    }
}

/// Live chip on the Focus HUD — what the camera is doing *right now*.
enum FocusCameraPresence: String, Equatable, Sendable {
    case cameraOn
    case checkingIn
    case cameraOff

    var chipLabel: String {
        switch self {
        case .cameraOn: return "Camera on"
        case .checkingIn: return "Checking in"
        case .cameraOff: return "Camera off"
        }
    }

    var isAwake: Bool {
        switch self {
        case .cameraOn, .checkingIn: return true
        case .cameraOff: return false
        }
    }
}

/// Pure scheduling for brief check-ins + HR spike wake. No ARKit — easy to unit test.
struct FocusCameraScheduler: Sendable {
    struct Config: Sendable, Equatable {
        /// Wake window length (MASTER: ~8–15s).
        var checkInDuration: TimeInterval = 12
        /// Quiet gap between scheduled wakes (MASTER: every 90–120s).
        var intervalMin: TimeInterval = 90
        var intervalMax: TimeInterval = 120
        /// HR rise above session anchor that opens one brief window.
        var spikeDeltaBpm: Double = 8
        /// Minimum quiet time after a wake before a spike can fire again.
        var spikeCooldown: TimeInterval = 60
        /// Open with an immediate check-in so the first ~12s can still see the face
        /// without holding the camera for the whole Quick baseline.
        var openWithImmediateCheckIn: Bool = true

        static let `default` = Config()
    }

    enum WakeReason: String, Sendable {
        case sessionStart
        case interval
        case spike
    }

    var config: Config
    private(set) var mode: FocusCameraMode = .alwaysOn
    private(set) var isActive = false
    private(set) var presence: FocusCameraPresence = .cameraOff
    private(set) var lastWakeReason: WakeReason?
    private(set) var wakeCount = 0
    private(set) var spikeWakeCount = 0

    private var checkInEndsAt: TimeInterval?
    private var nextIntervalWakeAt: TimeInterval?
    private var lastWakeEndedAt: TimeInterval?
    /// Deterministic interval when set (tests); otherwise random in [intervalMin, intervalMax].
    var fixedIntervalOverride: TimeInterval?

    init(config: Config = .default) {
        self.config = config
    }

    mutating func start(mode: FocusCameraMode, now: TimeInterval) {
        stop()
        self.mode = mode
        isActive = true
        lastWakeReason = nil
        wakeCount = 0
        spikeWakeCount = 0

        switch mode {
        case .alwaysOn:
            presence = .cameraOn
            checkInEndsAt = nil
            nextIntervalWakeAt = nil
        case .watchOnly:
            presence = .cameraOff
            checkInEndsAt = nil
            nextIntervalWakeAt = nil
        case .briefCheckIns:
            if config.openWithImmediateCheckIn {
                beginCheckIn(now: now, reason: .sessionStart)
            } else {
                presence = .cameraOff
                scheduleNextInterval(after: now)
            }
        }
    }

    mutating func stop() {
        isActive = false
        presence = .cameraOff
        checkInEndsAt = nil
        nextIntervalWakeAt = nil
        lastWakeReason = nil
    }

    /// Advance time. Returns `true` when presence changed.
    @discardableResult
    mutating func tick(now: TimeInterval) -> Bool {
        guard isActive, mode == .briefCheckIns else { return false }
        let before = presence

        if let end = checkInEndsAt, now >= end {
            endCheckIn(now: now)
        }
        if presence == .cameraOff, let next = nextIntervalWakeAt, now >= next {
            beginCheckIn(now: now, reason: .interval)
        }

        return presence != before
    }

    /// Brief mode only. Returns `true` when a spike opened a check-in.
    @discardableResult
    mutating func ingestHeartRate(bpm: Double, anchorBpm: Double?, now: TimeInterval) -> Bool {
        guard isActive, mode == .briefCheckIns else { return false }
        guard presence == .cameraOff else { return false }
        guard let anchor = anchorBpm else { return false }
        guard bpm - anchor >= config.spikeDeltaBpm else { return false }

        if let quietSince = lastWakeEndedAt, now - quietSince < config.spikeCooldown {
            return false
        }

        beginCheckIn(now: now, reason: .spike)
        spikeWakeCount += 1
        return true
    }

    // MARK: - Private

    private mutating func beginCheckIn(now: TimeInterval, reason: WakeReason) {
        presence = .checkingIn
        checkInEndsAt = now + config.checkInDuration
        nextIntervalWakeAt = nil
        lastWakeReason = reason
        wakeCount += 1
    }

    private mutating func endCheckIn(now: TimeInterval) {
        presence = .cameraOff
        checkInEndsAt = nil
        lastWakeEndedAt = now
        scheduleNextInterval(after: now)
    }

    private mutating func scheduleNextInterval(after now: TimeInterval) {
        let gap = fixedIntervalOverride
            ?? TimeInterval.random(in: config.intervalMin...max(config.intervalMin, config.intervalMax))
        nextIntervalWakeAt = now + gap
    }
}
