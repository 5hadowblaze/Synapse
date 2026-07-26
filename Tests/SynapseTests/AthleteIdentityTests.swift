import XCTest
@testable import Synapse

final class AthleteIdentityTests: XCTestCase {
    func testSlugifyBasic() {
        XCTAssertEqual(AthleteIdentity.slugify("Amir Dzakwan"), "amir-dzakwan")
        XCTAssertEqual(AthleteIdentity.slugify("  Alex  "), "alex")
        XCTAssertEqual(AthleteIdentity.slugify("Sam_O'Neil"), "sam-o-neil")
    }

    func testSlugifyCollapsesPunctuation() {
        XCTAssertEqual(AthleteIdentity.slugify("Ann -- Marie!!!"), "ann-marie")
        XCTAssertEqual(AthleteIdentity.slugify("..."), "")
        XCTAssertEqual(AthleteIdentity.slugify(""), "")
    }

    func testEmptyNameMapsToDemoDefault() {
        XCTAssertEqual(AthleteIdentity.athleteId(forDisplayName: ""), AthleteIdentity.defaultAthleteId)
        XCTAssertEqual(AthleteIdentity.athleteId(forDisplayName: "   "), "athlete-1")
        XCTAssertEqual(AthleteIdentity.athleteId(forDisplayName: "!!!"), "athlete-1")
    }

    func testNamedMapsToSlug() {
        XCTAssertEqual(AthleteIdentity.athleteId(forDisplayName: "Jordan Lee"), "jordan-lee")
    }

    func testRecentNamesPromoteAndCap() {
        let existing = (1...8).map { "Person \($0)" }
        let next = AthleteIdentity.updatedRecentNames(existing: existing, promoting: "New Guest")
        XCTAssertEqual(next.count, 8)
        XCTAssertEqual(next.first, "New Guest")
        XCTAssertFalse(next.contains("Person 8"))
    }

    func testRecentNamesDedupCaseInsensitive() {
        let next = AthleteIdentity.updatedRecentNames(
            existing: ["amir", "Alex"],
            promoting: "Amir"
        )
        XCTAssertEqual(next, ["Amir", "Alex"])
    }

    func testRecentNamesIgnoresBlankPromote() {
        let existing = ["Alex"]
        let next = AthleteIdentity.updatedRecentNames(existing: existing, promoting: "  ")
        XCTAssertEqual(next, ["Alex"])
    }

    func testStorePersistsNameAndRecent() {
        let suite = "AthleteIdentityTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        var store = AthleteIdentityStore(defaults: defaults)
        XCTAssertEqual(store.athleteId, "athlete-1")

        store.commitDisplayName("Casey Park")
        XCTAssertEqual(store.displayName, "Casey Park")
        XCTAssertEqual(store.athleteId, "casey-park")
        XCTAssertEqual(store.recentNames, ["Casey Park"])

        store.commitDisplayName("Riley")
        store.selectRecent("Casey Park")
        XCTAssertEqual(store.displayName, "Casey Park")
        XCTAssertEqual(store.recentNames.first, "Casey Park")
        XCTAssertEqual(store.recentNames, ["Casey Park", "Riley"])

        var reloaded = AthleteIdentityStore(defaults: defaults)
        XCTAssertEqual(reloaded.displayName, "Casey Park")
        XCTAssertEqual(reloaded.recentNames, ["Casey Park", "Riley"])
        XCTAssertEqual(reloaded.athleteId, "casey-park")
    }
}
