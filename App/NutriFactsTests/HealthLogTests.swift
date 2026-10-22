import HealthKit
import Testing
@testable import NutriFacts

@MainActor
@Suite struct HealthLogTests {
    private func values(_ food: HKCorrelation) -> [HKQuantityTypeIdentifier: Double] {
        var result: [HKQuantityTypeIdentifier: Double] = [:]
        for case let sample as HKQuantitySample in food.objects {
            let id = HKQuantityTypeIdentifier(rawValue: sample.quantityType.identifier)
            let unit: HKUnit = id == .dietaryEnergyConsumed ? .kilocalorie() : id == .dietarySodium ? .gramUnit(with: .milli) : .gram()
            result[id] = sample.quantity.doubleValue(for: unit)
        }
        return result
    }

    @Test func writesOnlyPrintedLinesWithSaltAsSodium() throws {
        var panel = SampleLabels.chips
        panel.productName = TranslatedText(japanese: "ポテトチップス", english: "Potato Chips")
        let analysis = PanelAnalysis(panel: panel, basis: .asLabelled, source: .japan)
        let food = try #require(HealthLog.food(Scan(date: .now, panel: panel), analysis: analysis))
        let v = values(food)
        #expect(Set(v.keys) == [.dietaryEnergyConsumed, .dietaryProtein, .dietaryFatTotal, .dietaryCarbohydrates, .dietarySodium])
        #expect(v[.dietaryEnergyConsumed] == 336)
        #expect(abs(v[.dietarySodium]! - 236.2) < 0.1)
        #expect(food.metadata?[HKMetadataKeyFoodType] as? String == "Potato Chips (60 g bag)")
    }

    @Test func leavesOutTypesTheUserDidntAllow() throws {
        let analysis = PanelAnalysis(panel: SampleLabels.chips, basis: .asLabelled, source: .japan)
        let food = try #require(HealthLog.food(Scan(date: .now, panel: SampleLabels.chips), analysis: analysis,
                                               allowed: [.dietaryEnergyConsumed]))
        #expect(Set(values(food).keys) == [.dietaryEnergyConsumed])
    }
}
