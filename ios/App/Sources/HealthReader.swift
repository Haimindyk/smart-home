import Foundation
import HealthKit
import CryptoKit
import WellnessCore

@MainActor
final class HealthReader {
    private let store = HKHealthStore()
    var available: Bool { HKHealthStore.isHealthDataAvailable() }
    private let steps = HKQuantityType(.stepCount)
    private let energy = HKQuantityType(.activeEnergyBurned)
    private let walking = HKQuantityType(.distanceWalkingRunning)
    private let cycling = HKQuantityType(.distanceCycling)
    private let swimming = HKQuantityType(.distanceSwimming)

    func requestAccess() async throws {
        guard available else { throw HealthError.unavailable }
        // Completion means the permission sheet finished, NOT that read access was granted.
        try await store.requestAuthorization(toShare: [], read: [HKObjectType.workoutType(), steps, energy, walking, cycling, swimming])
    }
    func workouts() async throws -> [AppleWorkout] {
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -30, to: end)!
        let type = HKObjectType.workoutType()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let samples: [HKWorkout] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 500, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, samples, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: samples as? [HKWorkout] ?? []) }
            }
            store.execute(query)
        }
        try Task.checkCancellation()
        return samples.map { workout in
            let distanceType: HKQuantityType
            switch workout.workoutActivityType {
            case .cycling: distanceType = cycling
            case .swimming: distanceType = swimming
            default: distanceType = walking
            }
            return AppleWorkout(id: workout.uuid, name: Self.name(workout.workoutActivityType), activityType: workout.workoutActivityType.rawValue,
                                sourceName: workout.sourceRevision.source.name, start: workout.startDate, end: workout.endDate, duration: workout.duration,
                                energyKcal: workout.statistics(for: energy)?.sumQuantity()?.doubleValue(for: .kilocalorie()),
                                distanceMeters: workout.statistics(for: distanceType)?.sumQuantity()?.doubleValue(for: .meter()))
        }
    }
    func todaySteps() async throws -> Double? {
        let end = Date(); let start = Calendar.current.startOfDay(for: end)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return try await withCheckedThrowingContinuation { continuation in
            // Statistics merges overlapping phone/watch sources instead of adding every sample.
            let query = HKStatisticsQuery(quantityType: steps, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: result?.sumQuantity()?.doubleValue(for: .count())) }
            }
            store.execute(query)
        }
    }
    static func rowID(_ workout: AppleWorkout, owner: String) throws -> String {
        let digest = SHA256.hash(data: Data(try workout.sourceKey(owner: owner).utf8))
        // RFC 9562 UUIDv8: deterministic application-specific SHA-256 bytes.
        var bytes = Array(digest.prefix(16)); bytes[6] = (bytes[6] & 0x0f) | 0x80; bytes[8] = (bytes[8] & 0x3f) | 0x80
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        let chars = Array(hex)
        return [String(chars[0..<8]), String(chars[8..<12]), String(chars[12..<16]), String(chars[16..<20]), String(chars[20..<32])].joined(separator: "-")
    }
    private static func name(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .walking: return "הליכה"
        case .running: return "ריצה"
        case .cycling: return "רכיבה"
        case .swimming: return "שחייה"
        case .traditionalStrengthTraining: return "אימון כוח"
        case .functionalStrengthTraining: return "אימון פונקציונלי"
        case .highIntensityIntervalTraining: return "אימון אינטרוולים"
        case .yoga: return "יוגה"
        case .pilates: return "פילאטיס"
        case .hiking: return "טיול"
        case .dance, .socialDance, .cardioDance: return "ריקוד"
        case .elliptical: return "אליפטיקל"
        case .rowing: return "חתירה"
        case .soccer: return "כדורגל"
        case .basketball: return "כדורסל"
        case .tennis: return "טניס"
        case .stairClimbing, .stairs: return "מדרגות"
        default: return "אימון"
        }
    }
    enum HealthError: Error { case unavailable }
}
