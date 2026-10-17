import CoreGraphics
import Foundation
import FoundationModels

/// What a second scan reads off the ingredients box (一括表示): a transcription with an English
/// translation of each text field, nothing inferred. See docs/ingredients-box.md.
@Generable
nonisolated struct ExtractedIngredientsBox: Codable, Sendable, Hashable {
    @Guide(description: "True only if a Japanese ingredients box (一括表示, with headings such as 名称 and 原材料名) is visible.")
    var boxFound: Bool

    @Guide(description: "名称, 品名 or 種類別: the food type, e.g. 清涼飲料水. Empty if not printed.")
    var category: TranslatedText

    @Guide(description: "Each top-level ingredient from 原材料名 in printed order, then the additives. Split only at top-level 、 and keep bracketed contents with their ingredient.")
    var ingredients: [ExtractedIngredient]

    @Guide(description: "Allergens the box names, in its own words, e.g. 小麦 or 乳成分. Empty if it names none.")
    var allergens: [String]

    @Guide(description: "内容量 exactly as printed, e.g. 120g（6個入）. Empty if not printed.")
    var netContentsText: String

    @Guide(description: "Weight or volume in 内容量 in g or ml. Convert L to ml and kg to g. For canned food use 内容総量. 0 if it's only a count, printed elsewhere or not printed.")
    var netContentsAmount: Double

    @Guide(description: "Unit of netContentsAmount: g, ml, or none when netContentsAmount is 0.")
    var netContentsUnit: ExtractedContentsUnit

    @Guide(description: "Pieces or packets if 内容量 says, e.g. 6 for 6個入, else 0.")
    var netContentsCount: Int

    @Guide(description: "True if 内容量 says it's printed elsewhere, e.g. キャップに記載 or 欄外に記載.")
    var netContentsPrintedElsewhere: Bool

    @Guide(description: "賞味期限 or 消費期限 as the box prints it, often 欄外上部に記載. Empty if not printed.")
    var date: TranslatedText

    @Guide(description: "True for 消費期限 (use by), false for 賞味期限 (best before).")
    var isUseBy: Bool

    @Guide(description: "保存方法 (storage). Empty if not printed.")
    var storage: TranslatedText

    @Guide(description: "製造者, 販売者, 輸入者 or 加工者 with the name, as printed. Empty if not printed.")
    var maker: String

    @Guide(description: "原産国名 (country of origin), only on imports. Empty if not printed.")
    var countryOfOrigin: TranslatedText
}

@Generable
nonisolated struct ExtractedIngredient: Codable, Sendable, Hashable {
    @Guide(description: "As printed, e.g. 砂糖 or 豚肉（国産）.")
    var japanese: String

    @Guide(description: "Plain English a shopper would know, e.g. sugar or pork (Japan).")
    var english: String

    @Guide(description: "True for additives: items after ／ or on the 添加物 line.")
    var isAdditive: Bool
}

@Generable
nonisolated struct TranslatedText: Codable, Sendable, Hashable {
    @Guide(description: "As printed. Empty if not printed.")
    var japanese: String

    @Guide(description: "Plain English translation. Empty if japanese is empty.")
    var english: String
}

extension ExtractedIngredientsBox {
    enum MappingError: LocalizedError {
        case noBox
        var errorDescription: String? {
            "No ingredients box found. Look for the box with 名称 and 原材料名, usually on the back or side."
        }
    }

    /// 内容量 as a weight or volume. Nil for a bare count or when it's printed elsewhere.
    var netContents: (amount: Double, unit: PackUnit)? {
        guard netContentsAmount > 0 else { return nil }
        switch netContentsUnit {
        case .g: return (netContentsAmount, .grams)
        case .ml: return (netContentsAmount, .millilitres)
        case .none: return nil
        }
    }

    static let instructions = """
    You transcribe the Japanese ingredients box (一括表示) on food packaging into structured data, and \
    give a plain English translation of each text field. You never judge the food, and you never fill in \
    anything that isn't printed.

    Rules:
    - Only read the box with headings such as 名称, 原材料名, 内容量, 賞味期限, 保存方法, 製造者. \
    Ignore the nutrition panel (栄養成分表示), marketing text and recycling marks.
    - category is 名称, 品名 or 種類別. It's a food type such as 清涼飲料水, not the brand.
    - ingredients: split 原材料名 at top-level 、 only. Keep anything in brackets with its ingredient, \
    e.g. チョコレート（砂糖、カカオマス） is one item. Items after ／, or on a 添加物 line, are additives.
    - Translate ingredients into the plain English name a shopper would know, e.g. 砂糖 sugar, \
    ぶどう糖果糖液糖 high-fructose corn syrup, 乳化剤 emulsifier, 香料 flavouring. Keep origins: \
    豚肉（国産） is "pork (Japan)". Don't add or drop ingredients.
    - allergens: only those the box names, e.g. （一部に小麦・乳成分・大豆を含む） gives 小麦, 乳成分, 大豆. \
    Never add an allergen because an ingredient might contain it.
    - 内容量: copy it exactly into netContentsText. Convert L to ml and kg to g. 120g（6個入） is 120 g \
    with count 6. A bare count such as 2個 or 10袋入 has amount 0 and unit none. For 固形量 and 内容総量, \
    use 内容総量. If it says it's printed elsewhere (キャップに記載, 欄外に記載, 表面に記載), set \
    netContentsPrintedElsewhere and leave the amount 0.
    - 賞味期限 and 消費期限 are usually printed elsewhere (欄外上部に記載). Copy what the box says.
    - Convert full-width digits (０-９, ．) to normal numbers.
    - If there is no ingredients box in the image, set boxFound to false and leave everything empty.
    """

    /// Reads the box with Apple Intelligence. The ai& Worker doesn't have a route for it yet.
    static func read(_ image: CGImage) async throws -> (box: ExtractedIngredientsBox, readBy: ReadBy) {
        let (box, readBy, _) = try await AppleIntelligenceReader().generate(
            ExtractedIngredientsBox.self, instructions: instructions,
            task: "Transcribe the Japanese ingredients box", image: image)
        guard box.boxFound, !box.ingredients.isEmpty || !box.netContentsText.isEmpty else { throw MappingError.noBox }
        return (box, readBy)
    }
}
