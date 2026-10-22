import HealthKit

/// Adds a scan to Apple Health as one food: the amount shown on the result, as eaten now. Write only;
/// NutriFacts never reads Health data. Lines the label doesn't print aren't written (rule 3), so Health
/// doesn't count a missing line as 0.
@MainActor
enum HealthLog {
    private static let store = HKHealthStore()

    /// False on iPad and wherever Health isn't on the device.
    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Each label line and the Health type it's written as. Salt is written as sodium, which is what Health tracks.
    private static let types: [(NutrientKey, HKQuantityTypeIdentifier, HKUnit)] = [
        (.energy, .dietaryEnergyConsumed, .kilocalorie()),
        (.protein, .dietaryProtein, .gram()),
        (.fat, .dietaryFatTotal, .gram()),
        (.saturatedFat, .dietaryFatSaturated, .gram()),
        (.carbohydrate, .dietaryCarbohydrates, .gram()),
        (.sugars, .dietarySugar, .gram()),
        (.fibre, .dietaryFiber, .gram()),
        (.salt, .dietarySodium, .gramUnit(with: .milli)),
    ]

    enum LogError: LocalizedError {
        case denied, nothingToLog
        var errorDescription: String? {
            switch self {
            case .denied: "NutriFacts can't add to Health. Turn it on in Settings › Health › Data Access & Devices › NutriFacts."
            case .nothingToLog: "This label has no values to add at this amount."
            }
        }
    }

    /// The samples for one food, without saving them, limited to the types in `allowed`.
    static func food(_ scan: Scan, analysis a: PanelAnalysis, at date: Date = .now,
                     allowed: Set<HKQuantityTypeIdentifier>? = nil) -> HKCorrelation? {
        let name = foodName(scan, analysis: a)
        let metadata: [String: Any] = [HKMetadataKeyFoodType: name]
        let samples: [HKQuantitySample] = types.compactMap { key, id, unit in
            guard allowed?.contains(id) ?? true else { return nil }
            // The sodium in the salt line: salt g × 1000 ÷ 2.54 (rule 5).
            let amount = key == .salt ? a.sodiumMg : a.value(key).map { $0.isUpperBound ? 0 : $0.amount }
            guard let amount, amount >= 0 else { return nil }
            return HKQuantitySample(type: HKQuantityType(id), quantity: HKQuantity(unit: unit, doubleValue: amount),
                                    start: date, end: date, metadata: metadata)
        }
        guard !samples.isEmpty else { return nil }
        return HKCorrelation(type: HKCorrelationType(.food), start: date, end: date, objects: Set(samples), metadata: metadata)
    }

    /// "Potato Chips Lightly Salted (whole pack, 60 g)": the name Health lists the food under.
    static func foodName(_ scan: Scan, analysis a: PanelAnalysis) -> String {
        let amount = a.basisDescription.hasPrefix("per ") ? String(a.basisDescription.dropFirst(4)) : a.basisDescription
        return "\(scan.title ?? "Japanese food") (\(amount))"
    }

    /// Asks for permission the first time, then saves the food with the types the user allowed.
    static func add(_ scan: Scan, analysis: PanelAnalysis) async throws {
        // Correlations aren't authorised themselves; their samples' types are.
        let shareTypes = Set(types.map { HKQuantityType($0.1) as HKSampleType })
        try await store.requestAuthorization(toShare: shareTypes, read: [])
        let allowed = Set(types.map(\.1).filter { store.authorizationStatus(for: HKQuantityType($0)) == .sharingAuthorized })
        guard !allowed.isEmpty else { throw LogError.denied }
        guard let food = food(scan, analysis: analysis, allowed: allowed) else { throw LogError.nothingToLog }
        try await store.save(food)
    }
}
