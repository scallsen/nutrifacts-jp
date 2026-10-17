import Foundation

/// The five mock labels from docs/ui-domain-context.md. Each one covers a different case.
enum SampleLabels {
    static let chips = LabelPanel(
        nickname: "Potato chips",
        basisJapanese: "1袋（60g）当たり", basisAmount: 60, basisDescription: "per 60 g bag", basisShort: "Bag · 60 g",
        packAmount: 60, packShort: "Bag · 60 g", unit: .grams,
        printed: [.energy: "336", .protein: "3.1", .fat: "21.6", .carbohydrate: "32.4", .salt: "0.6"],
        isEstimate: true, layout: .inline,
        ingredients: "名称：ポテトチップス　原材料名：じゃがいも（国産）、植物油、食塩、デキストリン／調味料（アミノ酸等）　内容量：60g",
        packColors: [0xF2B441, 0xC9781C])

    static let milkTea = LabelPanel(
        nickname: "Bottled milk tea",
        basisJapanese: "100ml当たり", basisAmount: 100, basisDescription: "per 100 ml", basisShort: "100 ml",
        packAmount: 500, packShort: "Bottle · 500 ml", unit: .millilitres,
        printed: [.energy: "37", .protein: "0.7", .fat: "0.6", .carbohydrate: "7.2", .sugars: "7.0", .salt: "0.08"],
        ingredients: "名称：紅茶飲料　原材料名：牛乳（国内製造）、砂糖、紅茶、全粉乳／香料、乳化剤　内容量：500ml",
        packColors: [0xEFE3CB, 0xCBB487])

    static let granola = LabelPanel(
        nickname: "Fruit granola",
        basisJapanese: "1食分（50g）当たり", basisAmount: 50, basisDescription: "per 50 g serving", basisShort: "Serving · 50 g",
        packAmount: 400, packShort: "Bag · 400 g", unit: .grams,
        printed: [.energy: "220", .protein: "4.3", .fat: "7.6", .saturatedFat: "2.9", .carbohydrate: "36.0",
                  .netCarbs: "32.1", .sugars: "11.2", .fibre: "3.9", .salt: "0.2"],
        ingredients: "名称：シリアル食品　原材料名：オーツ麦、砂糖、ドライフルーツ（レーズン、パパイヤ）、植物油脂、小麦粉　内容量：400g",
        packColors: [0xB88752, 0x7E5530])

    static let chocolate = LabelPanel(
        nickname: "Low-carb chocolate",
        basisJapanese: "1枚（25g）当たり", basisAmount: 25, basisDescription: "per 25 g bar", basisShort: "Bar · 25 g",
        packAmount: 75, packShort: "Pack · 75 g", unit: .grams,
        printed: [.energy: "116", .protein: "2.3", .fat: "9.1", .saturatedFat: "5.6", .carbohydrate: "11.3",
                  .netCarbs: "6.4", .sugars: "0.9", .fibre: "4.9", .salt: "0.03"],
        frontClaim: "糖質オフ",
        ingredients: "名称：チョコレート　原材料名：カカオマス、エリスリトール、ココアバター、マルチトール、全粉乳　内容量：75g（3枚）",
        packColors: [0x5B3B2B, 0x2E1C13])

    static let cola = LabelPanel(
        nickname: "Zero-calorie cola",
        basisJapanese: "100ml当たり", basisAmount: 100, basisDescription: "per 100 ml", basisShort: "100 ml",
        packAmount: 500, packShort: "Bottle · 500 ml", unit: .millilitres,
        printed: [.energy: "0", .protein: "0", .fat: "0", .carbohydrate: "0.9", .salt: "0.02"],
        groupedZeros: [.protein, .fat],
        frontClaim: "カロリーゼロ",
        ingredients: "名称：炭酸飲料　原材料名：カラメル色素、酸味料、香料、甘味料（アスパルテーム・L-フェニルアラニン化合物）　内容量：500ml",
        packColors: [0xD1262D, 0x7E1015])

    static let all = [chips, milkTea, granola, chocolate, cola]
}
