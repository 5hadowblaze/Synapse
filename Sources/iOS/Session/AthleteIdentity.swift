import Foundation

/// Hallway-demo identity: display name ↔ stable Firestore `athleteId`.
///
/// SCHEMA (`sessions/{id}`) only has `athleteId` — no displayName field.
/// We persist the typed name in UserDefaults and write the derived slug as `athleteId`.
///
/// Mapping:
/// - Trim → lowercase → non-alphanumeric runs become a single `-` → trim hyphens.
/// - Empty / whitespace-only → `"athlete-1"` (demo default, matches the old hardcode).
enum AthleteIdentity {
    static let defaultAthleteId = "athlete-1"
    static let maxRecentNames = 8

    static let displayNameKey = "synapse.athleteDisplayName"
    static let recentNamesKey = "synapse.athleteRecentNames"

    /// Stable session `athleteId` for a display name.
    static func athleteId(forDisplayName name: String) -> String {
        let slug = slugify(name)
        return slug.isEmpty ? defaultAthleteId : slug
    }

    /// Lowercase hyphenated slug; empty string if nothing alphanumeric remains.
    static func slugify(_ raw: String) -> String {
        let lowered = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lowered.isEmpty else { return "" }

        var out = ""
        var pendingHyphen = false
        for ch in lowered {
            if ch.isLetter || ch.isNumber {
                if pendingHyphen, !out.isEmpty {
                    out.append("-")
                }
                out.append(ch)
                pendingHyphen = false
            } else {
                pendingHyphen = true
            }
        }
        return out
    }

    /// Most-recent-first list, capped, excluding blanks and duplicates (case-insensitive).
    static func updatedRecentNames(
        existing: [String],
        promoting name: String,
        maxCount: Int = maxRecentNames
    ) -> [String] {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Array(existing.prefix(maxCount)) }

        var next = [trimmed]
        for item in existing {
            let t = item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { continue }
            if t.caseInsensitiveCompare(trimmed) == .orderedSame { continue }
            next.append(t)
            if next.count >= maxCount { break }
        }
        return next
    }
}

/// UserDefaults-backed display name + recent list for venue switching.
struct AthleteIdentityStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var displayName: String {
        get { defaults.string(forKey: AthleteIdentity.displayNameKey) ?? "" }
        set { defaults.set(newValue, forKey: AthleteIdentity.displayNameKey) }
    }

    var recentNames: [String] {
        get { defaults.stringArray(forKey: AthleteIdentity.recentNamesKey) ?? [] }
        set { defaults.set(newValue, forKey: AthleteIdentity.recentNamesKey) }
    }

    var athleteId: String {
        AthleteIdentity.athleteId(forDisplayName: displayName)
    }

    /// Persist name and promote into the recent list (skip blanks).
    mutating func commitDisplayName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        displayName = trimmed
        recentNames = AthleteIdentity.updatedRecentNames(existing: recentNames, promoting: trimmed)
    }

    mutating func selectRecent(_ name: String) {
        commitDisplayName(name)
    }
}
