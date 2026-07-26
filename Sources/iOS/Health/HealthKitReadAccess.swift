import Foundation
import HealthKit

/// Shared HealthKit read types for Signals — one authorize call covers HR history + trends.
enum HealthKitReadAccess {
    /// UserDefaults key shared by historical HR + trends stores (prompt once).
    static let promptedKey = "synapse.healthKitHRReadPrompted"

    static var allReadTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = []

        let quantityIds: [HKQuantityTypeIdentifier] = [
            .heartRate,
            .restingHeartRate,
            .heartRateVariabilitySDNN,
            .activeEnergyBurned,
            .stepCount,
            .appleStandTime
        ]
        for id in quantityIds {
            if let type = HKQuantityType.quantityType(forIdentifier: id) {
                types.insert(type)
            }
        }

        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleep)
        }
        if let standHour = HKObjectType.categoryType(forIdentifier: .appleStandHour) {
            types.insert(standHour)
        }

        return types
    }

    /// Asleep stages only — excludes inBed / awake. Pure Int check for tests + queries.
    static func isAsleepSleepAnalysisValue(_ raw: Int) -> Bool {
        switch raw {
        case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
             HKCategoryValueSleepAnalysis.asleepCore.rawValue,
             HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
             HKCategoryValueSleepAnalysis.asleepREM.rawValue:
            return true
        default:
            return false
        }
    }

    /// Map HealthKit sleepAnalysis raw value → `SleepStageKind` (nil if unknown).
    static func sleepStage(forRawValue raw: Int) -> SleepStageKind? {
        switch raw {
        case HKCategoryValueSleepAnalysis.inBed.rawValue:
            return .inBed
        case HKCategoryValueSleepAnalysis.awake.rawValue:
            return .awake
        case HKCategoryValueSleepAnalysis.asleepCore.rawValue:
            return .core
        case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
            return .deep
        case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
            return .rem
        case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
            return .unspecified
        default:
            return nil
        }
    }

    static func isAppleWatchSource(_ source: HKSource) -> Bool {
        let name = source.name.lowercased()
        let bundle = source.bundleIdentifier.lowercased()
        if name.contains("watch") || bundle.contains("watch") {
            return true
        }
        // Many Watch samples show as "Amir's Apple Watch" under com.apple.health.*
        return name.contains("apple watch")
    }
}
