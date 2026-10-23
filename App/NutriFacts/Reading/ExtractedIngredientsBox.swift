import CoreGraphics
import Foundation
import FoundationModels

/// What a second scan reads off the ingredients box (一括表示): a transcription with an English
/// translation of each text field, nothing inferred. Mirrors backend/src/ingredients.ts, which the
/// ai& Worker fills and returns in this shape. See docs/ingredients-box.md.
@Generable
nonisolated struct ExtractedIngredientsBox: Codable, Sendable, Hashable {
    @Guide(description: "True only if a Japanese ingredients box (一括表示, with headings such as 名称 and 原材料名) is visible.")
    var boxFound: Bool

    @Guide(description: "名称, 品名 or 種類別: the food type, e.g. 清涼飲料水. Empty if not printed.")
    var category: TranslatedText

    @Guide(description: "Each top-level ingredient from 原材料名 in printed order, then the additives. Split only at top-level 、 and keep bracketed contents with their ingredient. Not the allergen statement.")
    var ingredients: [ExtractedIngredient]

    @Guide(description: "Allergens an allergen statement names, as printed, e.g. 小麦 or 乳成分. Empty if it names none.")
    var allergens: [String]

    @Guide(description: "内容量 exactly as printed, e.g. 120g（6個入）. Empty if not printed.")
    var netContentsText: String

    @Guide(description: "Weight or volume in 内容量 in g or ml. Convert L to ml and kg to g. For canned food use 内容総量. 0 if it's only a count, printed elsewhere or not printed.")
    var netContentsAmount: Double

    @Guide(description: "Unit of netContentsAmount: g, ml, or none when netContentsAmount is 0.")
    var netContentsUnit: ExtractedContentsUnit

    @Guide(description: "Pieces or packets if 内容量 says, e.g. 6 for 6個入 or 1 for 1個, else 0.")
    var netContentsCount: Int

    @Guide(description: "True if 内容量 says it's printed elsewhere, e.g. キャップに記載 or 欄外に記載.")
    var netContentsPrintedElsewhere: Bool

    @Guide(description: "賞味期限 or 消費期限 as the box prints it, often 欄外上部に記載. Empty if not printed.")
    var date: TranslatedText

    @Guide(description: "True for 消費期限 (use by), false for 賞味期限 (best before).")
    var isUseBy: Bool

    @Guide(description: "保存方法 (storage). Empty if not printed.")
    var storage: TranslatedText

    @Guide(description: "The 製造者, 販売者, 輸入者 or 加工者 name as printed, without the address. Empty if not printed.")
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

    /// English names for the 28 allergens Japan lists (8 required, 20 recommended). Unknown words stay as printed.
    static func allergenName(_ japanese: String) -> String {
        let names = ["えび": "Shrimp", "かに": "Crab", "くるみ": "Walnut", "小麦": "Wheat", "そば": "Buckwheat",
                     "卵": "Egg", "乳": "Milk", "乳成分": "Milk", "落花生": "Peanut", "ピーナッツ": "Peanut",
                     "アーモンド": "Almond", "あわび": "Abalone", "いか": "Squid", "いくら": "Salmon roe",
                     "オレンジ": "Orange", "カシューナッツ": "Cashew", "キウイフルーツ": "Kiwi", "牛肉": "Beef",
                     "ごま": "Sesame", "さけ": "Salmon", "さば": "Mackerel", "大豆": "Soy", "鶏肉": "Chicken",
                     "バナナ": "Banana", "豚肉": "Pork", "まつたけ": "Matsutake", "もも": "Peach",
                     "やまいも": "Yam", "りんご": "Apple", "ゼラチン": "Gelatin"]
        let key = japanese.trimmingCharacters(in: .whitespaces)
        return names[key] ?? key
    }

    /// 内容量 as a weight or volume. Nil for a bare count or when it's printed elsewhere. Models sometimes
    /// take a count (1個) as 1 g, so a weight counts only when the printed text has one.
    var netContents: (amount: Double, unit: PackUnit)? {
        let weightPrinted = netContentsText.isEmpty
            ? !(netContentsCount > 0 && netContentsAmount == Double(netContentsCount))
            : LabelPanel.printsWeight(netContentsText)
        guard netContentsAmount > 0, weightPrinted else { return nil }
        switch netContentsUnit {
        case .g: return (netContentsAmount, .grams)
        case .ml: return (netContentsAmount, .millilitres)
        case .none: return nil
        }
    }

    // Same rules the Worker gives AI& (backend/src/ingredients.ts, BOX_INSTRUCTIONS). Keep the two in step.
    static let instructions = """
    You transcribe the Japanese ingredients box (一括表示) on food packaging into structured data, and \
    give a plain English translation of each text field. You never judge the food, and you never fill in \
    anything that isn't printed.

    Rules:
    - Only read the box with headings such as 名称, 原材料名, 内容量, 賞味期限, 保存方法, 製造者. \
    Ignore the nutrition panel (栄養成分表示), marketing text, notes outside the box and recycling marks.
    - category is 名称, 品名 or 種類別. It's a food type such as 清涼飲料水, not the brand.
    - ingredients: split 原材料名 at top-level 、 only (some small labels separate them with spaces instead). \
    Keep anything in brackets with its ingredient, e.g. チョコレート（砂糖、カカオマス） is one item. Items after ／, \
    or on a 添加物 line, are additives. Without a ／ or 添加物 line, every item is isAdditive false.
    - The allergen statement in brackets, e.g. （一部に小麦・乳成分・大豆を含む） or （原材料の一部にりんごを含む）, \
    is not an ingredient. Leave it out of ingredients.
    - Translate ingredients into the plain English name a shopper would know, e.g. 砂糖 sugar, \
    ぶどう糖果糖液糖 high-fructose corn syrup, 乳化剤 emulsifier, 香料 flavouring. Keep origins: \
    豚肉（国産） is "pork (Japan)". Don't add or drop ingredients.
    - allergens: only those an allergen statement names: the summary （一部に小麦・乳成分・大豆を含む） gives \
    小麦, 乳成分, 大豆, and a per-item note such as （小麦を含む） or （乳由来） gives 小麦 or 乳. Write each as printed. \
    Never add an allergen because an ingredient might contain it.
    - 内容量: copy it exactly into netContentsText. Convert L to ml and kg to g. 120g（6個入） is 120 g \
    with count 6. A bare count such as 2個 or 10袋入 has amount 0, unit none and that count. For 固形量 and \
    内容総量, use 内容総量. If it says it's printed elsewhere (キャップに記載, 欄外に記載, 表面に記載), set \
    netContentsPrintedElsewhere and leave the amount 0.
    - 賞味期限 and 消費期限 are often printed elsewhere (欄外上部に記載). Copy what the box says, a date or the note.
    - maker is the 製造者, 販売者, 輸入者 or 加工者 name as printed, without the address or phone number.
    - Convert full-width digits (０-９, ．) to normal numbers.
    - If there is no ingredients box in the image, set boxFound to false and leave everything empty.
    """

    /// Reads the box with the backend chosen in Settings, like the panel: the ai& Worker's box route,
    /// or Apple Intelligence. Falls back to Apple Intelligence while the deployed Worker has no box route.
    static func read(_ image: CGImage, backend: Backend = Backend.selected) async throws -> (box: ExtractedIngredientsBox, readBy: ReadBy) {
        var box: ExtractedIngredientsBox, readBy: ReadBy
        switch backend {
        case .aiAnd:
            do {
                (box, readBy) = (try await AIAndReader(config: .current).readBox(image), .aiAnd)
            } catch LabelReaderError.aiAndRouteMissing {
                ScanTiming.logger.notice("the ai& Worker has no ingredients box route; reading with Apple Intelligence")
                (box, readBy) = try await readWithAppleIntelligence(image)
            }
        case .appleIntelligence:
            (box, readBy) = try await readWithAppleIntelligence(image)
        }
        guard box.boxFound, !box.ingredients.isEmpty || !box.netContentsText.isEmpty else { throw MappingError.noBox }
        return (box, readBy)
    }

    private static func readWithAppleIntelligence(_ image: CGImage) async throws -> (ExtractedIngredientsBox, ReadBy) {
        let (box, readBy, _) = try await AppleIntelligenceReader().generate(
            ExtractedIngredientsBox.self, instructions: instructions,
            task: "Transcribe the Japanese ingredients box", image: image)
        return (box, readBy)
    }
}
