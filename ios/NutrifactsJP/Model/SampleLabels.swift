import Foundation

/// The invented sample products from docs/ui-domain-context.md §9, plus the state-C variant it suggests.
nonisolated enum SampleLabels {
    struct Sample { var name: String; var panel: NutritionPanel }

    static let all: [Sample] = [
        Sample(name: "Potato chips", panel: panel("ポテトチップス", "1袋（60g）当たり", 60, .g, estimate: true,
                                                [.energy: 336, .protein: 3.1, .fat: 21.6, .carbohydrate: 32.4, .salt: 0.6])),
        Sample(name: "Bottled milk tea", panel: panel("ミルクティー", "100ml当たり", 100, .ml,
                                                    [.energy: 37, .protein: 0.7, .fat: 0.6, .carbohydrate: 7.2, .sugars: 7.0, .salt: 0.08])),
        Sample(name: "Fruit granola (no sugars line)", panel: panel("フルーツグラノーラ", "1食分（50g）当たり", 50, .g,
                                                    [.energy: 220, .protein: 4.3, .fat: 7.6, .saturatedFat: 2.9, .carbohydrate: 36.0,
                                                     .netCarbs: 32.1, .fibre: 3.9, .salt: 0.2])),
        Sample(name: "Fruit granola", panel: panel("フルーツグラノーラ", "1食分（50g）当たり", 50, .g,
                                                 [.energy: 220, .protein: 4.3, .fat: 7.6, .saturatedFat: 2.9, .carbohydrate: 36.0,
                                                  .netCarbs: 32.1, .sugars: 11.2, .fibre: 3.9, .salt: 0.2])),
        Sample(name: "Low-carb chocolate", panel: panel("糖質オフチョコ", "1枚（25g）当たり", 25, .g,
                                                      [.energy: 116, .protein: 2.3, .fat: 9.1, .saturatedFat: 5.6, .carbohydrate: 11.3,
                                                       .netCarbs: 6.4, .sugars: 0.9, .fibre: 4.9, .salt: 0.03])),
        Sample(name: "Zero-calorie cola", panel: panel("ゼロコーラ", "100ml当たり", 100, .ml,
                                                     [.energy: 0, .protein: 0, .fat: 0, .carbohydrate: 0.9, .salt: 0.02])),
    ]

    private static func panel(_ name: String, _ basis: String, _ amount: Double, _ unit: BasisUnit,
                              estimate: Bool = false, _ values: [Nutrient: Double]) -> NutritionPanel {
        NutritionPanel(productName: name,
                       basis: Basis(label: basis, amount: amount, unit: unit),
                       values: values.mapValues { v in
                           var a = Amount(v)
                           a.isPrintedZero = v == 0
                           return a
                       },
                       isEstimate: estimate)
    }
}
