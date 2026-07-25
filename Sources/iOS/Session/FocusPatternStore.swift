import Foundation
import Observation

/// One completed Focus desk block — used for local pattern tips.
struct FocusSessionStat: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let startedAt: Date
    let startHour: Int
    let focusedMinutes: Double
    let fadeCount: Int
    let meanHrBpm: Double?

    init(
        id: UUID = UUID(),
        startedAt: Date,
        focusedMinutes: Double,
        fadeCount: Int,
        meanHrBpm: Double?
    ) {
        self.id = id
        self.startedAt = startedAt
        self.startHour = Calendar.current.component(.hour, from: startedAt)
        self.focusedMinutes = focusedMinutes
        self.fadeCount = fadeCount
        self.meanHrBpm = meanHrBpm
    }
}

/// Persists Focus stats and surfaces 1–3 plain-English heuristic tips (optional OpenAI polish).
@Observable
@MainActor
final class FocusPatternStore {
    private static let storageKey = "synapse.focus.sessionStats.v1"
    private static let maxStored = 40

    private(set) var sessions: [FocusSessionStat] = []
    /// Up to 3 tips for Hub / Recap.
    private(set) var tips: [String] = []
    private(set) var lastPolishedAt: Date?

    init() {
        load()
        tips = Self.heuristicTips(from: sessions)
    }

    func record(startedAt: Date, focusedSeconds: TimeInterval, fadeCount: Int, meanHrBpm: Double?) {
        let stat = FocusSessionStat(
            startedAt: startedAt,
            focusedMinutes: focusedSeconds / 60.0,
            fadeCount: fadeCount,
            meanHrBpm: meanHrBpm
        )
        sessions.insert(stat, at: 0)
        if sessions.count > Self.maxStored {
            sessions = Array(sessions.prefix(Self.maxStored))
        }
        save()
        tips = Self.heuristicTips(from: sessions)
        Task { await self.polishTipsIfPossible() }
    }

    func record(recap: FocusRecap, startedAt: Date) {
        record(
            startedAt: startedAt,
            focusedSeconds: recap.focusedSeconds,
            fadeCount: recap.fadeCount,
            meanHrBpm: recap.meanHrBpm
        )
    }

    /// Pure heuristics — unit-tested. Safe off main actor.
    nonisolated static func heuristicTips(from sessions: [FocusSessionStat]) -> [String] {
        guard !sessions.isEmpty else {
            return ["Complete a few Focus blocks so Synapse can spot when you fade."]
        }

        var tips: [String] = []

        // Afternoon vs morning fade rate.
        let morning = sessions.filter { (6..<12).contains($0.startHour) }
        let afternoon = sessions.filter { (14..<18).contains($0.startHour) }
        if morning.count >= 2, afternoon.count >= 2 {
            let mFade = averageFade(morning)
            let aFade = averageFade(afternoon)
            if aFade >= mFade + 0.75 {
                tips.append("You fade more after 14:00 — protect afternoons with shorter blocks or an earlier break.")
            } else if mFade >= aFade + 0.75 {
                tips.append("Mornings show more fade than afternoons — ease in before deep work.")
            }
        } else if afternoon.count >= 2, averageFade(afternoon) >= 1.5 {
            tips.append("Afternoon Focus blocks fade often — try a breathing reset before 14:00 deep work.")
        }

        // High-fade sessions.
        let highFade = sessions.filter { $0.fadeCount >= 2 }
        if highFade.count >= 2 {
            let avgMin = highFade.map(\.focusedMinutes).reduce(0, +) / Double(highFade.count)
            if avgMin < 18 {
                tips.append("When fades stack, you usually stop under 20 minutes — break earlier next time.")
            } else {
                tips.append("You often pick up \(Int(averageFade(highFade).rounded())) fades in a block — treat the first fade as a real stop sign.")
            }
        }

        // HR vs fade.
        let withHR = sessions.compactMap { s -> (FocusSessionStat, Double)? in
            guard let hr = s.meanHrBpm else { return nil }
            return (s, hr)
        }
        if withHR.count >= 3 {
            let faded = withHR.filter { $0.0.fadeCount >= 1 }
            let calm = withHR.filter { $0.0.fadeCount == 0 }
            if faded.count >= 2, calm.count >= 1 {
                let fadedHR = faded.map(\.1).reduce(0, +) / Double(faded.count)
                let calmHR = calm.map(\.1).reduce(0, +) / Double(calm.count)
                if fadedHR >= calmHR + 5 {
                    tips.append(String(format: "Fades show up more when mean HR is higher (≈%.0f vs %.0f bpm).", fadedHR, calmHR))
                }
            }
        }

        // Volume / encouragement.
        let totalMin = sessions.map(\.focusedMinutes).reduce(0, +)
        if sessions.count >= 3, tips.isEmpty {
            tips.append(String(format: "You've logged %.0f Focus minutes across %d blocks — keep the streak.", totalMin, sessions.count))
        } else if sessions.count == 1 {
            tips.append("First block logged. A couple more sessions and patterns will get sharper.")
        }

        if tips.isEmpty {
            tips.append("Solid Focus habit forming — watch for the first fade and break then.")
        }

        return Array(tips.prefix(3))
    }

    private nonisolated static func averageFade(_ list: [FocusSessionStat]) -> Double {
        guard !list.isEmpty else { return 0 }
        return list.map { Double($0.fadeCount) }.reduce(0, +) / Double(list.count)
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([FocusSessionStat].self, from: data)
        else {
            sessions = []
            return
        }
        sessions = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    // MARK: - Optional OpenAI polish

    private func polishTipsIfPossible() async {
        let key = VoiceConfig.openAIKey
        guard !key.isEmpty, !tips.isEmpty else { return }
        // Avoid polishing every few seconds while testing.
        if let last = lastPolishedAt, Date().timeIntervalSince(last) < 30 { return }

        let joined = tips.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        let prompt = """
        Rewrite these Focus pattern tips as 1–3 short plain-English coaching lines for a spoken/phone UI. \
        Keep the same facts. No medical claims. No emojis. Return only the lines, one per line.

        \(joined)
        """

        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "temperature": 0.4,
            "messages": [
                ["role": "system", "content": "You polish brief wellness coaching tips. Stay factual and calm."],
                ["role": "user", "content": prompt],
            ],
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let content = message["content"] as? String
            else { return }

            let lines = content
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .map { line -> String in
                    var s = line
                    while let c = s.first, c.isNumber || c == "." || c == "-" || c == "*" || c.isWhitespace {
                        s = String(s.dropFirst())
                    }
                    return s.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                .filter { !$0.isEmpty }
            if !lines.isEmpty {
                tips = Array(lines.prefix(3))
                lastPolishedAt = Date()
            }
        } catch {
            // Keep heuristic tips.
        }
    }
}
