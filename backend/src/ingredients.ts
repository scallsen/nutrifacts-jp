// The ingredients box (一括表示): a transcription with an English translation of each text field.
// Mirrors ExtractedIngredientsBox in App/NutriFacts/Reading/ExtractedIngredientsBox.swift, and its
// instructions. Keep the two in step. See docs/ingredients-box.md.

import { completionContent, visionRequest } from "./label.ts";

export interface TranslatedText {
  japanese: string;
  english: string;
}

export interface ExtractedIngredient {
  japanese: string;
  english: string;
  isAdditive: boolean;
}

export interface ExtractedIngredientsBox {
  boxFound: boolean;
  category: TranslatedText;
  ingredients: ExtractedIngredient[];
  allergens: string[];
  netContentsText: string;
  netContentsAmount: number;
  netContentsUnit: "g" | "ml" | "none";
  netContentsCount: number;
  netContentsPrintedElsewhere: boolean;
  date: TranslatedText;
  isUseBy: boolean;
  storage: TranslatedText;
  maker: string;
  countryOfOrigin: TranslatedText;
}

export const BOX_INSTRUCTIONS = `You transcribe the Japanese ingredients box (一括表示) on food packaging into structured data, and give a plain English translation of each text field. You never judge the food, and you never fill in anything that isn't printed.

Rules:
- Only read the box with headings such as 名称, 原材料名, 内容量, 賞味期限, 保存方法, 製造者. Ignore the nutrition panel (栄養成分表示), marketing text, notes outside the box and recycling marks.
- category is 名称, 品名 or 種類別. It's a food type such as 清涼飲料水, not the brand.
- ingredients: split 原材料名 at top-level 、 only (some small labels separate them with spaces instead). Keep anything in brackets with its ingredient, e.g. チョコレート（砂糖、カカオマス） is one item. Items after ／, or on a 添加物 line, are additives. Without a ／ or 添加物 line, every item is isAdditive false.
- The allergen statement in brackets, e.g. （一部に小麦・乳成分・大豆を含む） or （原材料の一部にりんごを含む）, is not an ingredient. Leave it out of ingredients.
- Translate ingredients into the plain English name a shopper would know, e.g. 砂糖 sugar, ぶどう糖果糖液糖 high-fructose corn syrup, 乳化剤 emulsifier, 香料 flavouring. Keep origins: 豚肉（国産） is "pork (Japan)". Don't add or drop ingredients.
- allergens: only those an allergen statement names: the summary （一部に小麦・乳成分・大豆を含む） gives 小麦, 乳成分, 大豆, and a per-item note such as （小麦を含む） or （乳由来） gives 小麦 or 乳. Write each as printed. Never add an allergen because an ingredient might contain it.
- 内容量: copy it exactly into netContentsText. Convert L to ml and kg to g. 120g（6個入） is 120 g with count 6. A bare count such as 2個 or 10袋入 has amount 0, unit none and that count. For 固形量 and 内容総量, use 内容総量. If it says it's printed elsewhere (キャップに記載, 欄外に記載, 表面に記載), set netContentsPrintedElsewhere and leave the amount 0.
- 賞味期限 and 消費期限 are often printed elsewhere (欄外上部に記載). Copy what the box says, a date or the note.
- maker is the 製造者, 販売者, 輸入者 or 加工者 name as printed, without the address or phone number.
- Convert full-width digits (０-９, ．) to normal numbers.
- If there is no ingredients box in the image, set boxFound to false and leave everything empty.`;

const text = (description: string) => ({
  type: "object",
  additionalProperties: false,
  required: ["japanese", "english"],
  description,
  properties: {
    japanese: { type: "string", description: "As printed. Empty if not printed." },
    english: { type: "string", description: "Plain English translation. Empty if japanese is empty." },
  },
});

export const BOX_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["boxFound", "category", "ingredients", "allergens", "netContentsText", "netContentsAmount", "netContentsUnit",
    "netContentsCount", "netContentsPrintedElsewhere", "date", "isUseBy", "storage", "maker", "countryOfOrigin"],
  properties: {
    boxFound: { type: "boolean", description: "True only if a Japanese ingredients box (一括表示, with headings such as 名称 and 原材料名) is visible." },
    category: text("名称, 品名 or 種類別: the food type, e.g. 清涼飲料水."),
    ingredients: {
      type: "array",
      description: "Each top-level ingredient from 原材料名 in printed order, then the additives. Not the allergen statement.",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["japanese", "english", "isAdditive"],
        properties: {
          japanese: { type: "string", description: "As printed, e.g. 砂糖 or 豚肉（国産）." },
          english: { type: "string", description: "Plain English a shopper would know, e.g. sugar or pork (Japan)." },
          isAdditive: { type: "boolean", description: "True for additives: items after ／ or on the 添加物 line." },
        },
      },
    },
    allergens: { type: "array", items: { type: "string" }, description: "Allergens an allergen statement names, as printed, e.g. 小麦 or 乳成分." },
    netContentsText: { type: "string", description: "内容量 exactly as printed, e.g. 120g（6個入）. Empty if not printed." },
    netContentsAmount: { type: "number", description: "Weight or volume in 内容量 in g or ml. 0 if it's only a count, printed elsewhere or not printed." },
    netContentsUnit: { type: "string", enum: ["g", "ml", "none"] },
    netContentsCount: { type: "integer", description: "Pieces or packets if 内容量 says, e.g. 6 for 6個入 or 1 for 1個, else 0." },
    netContentsPrintedElsewhere: { type: "boolean", description: "True if 内容量 says it's printed elsewhere." },
    date: text("賞味期限 or 消費期限 as the box prints it: a date, or a note such as 欄外上部に記載."),
    isUseBy: { type: "boolean", description: "True for 消費期限 (use by), false for 賞味期限 (best before)." },
    storage: text("保存方法 (storage)."),
    maker: { type: "string", description: "The 製造者, 販売者, 輸入者 or 加工者 name as printed, without the address." },
    countryOfOrigin: text("原産国名 (country of origin), only on imports."),
  },
} as const;

export function boxCompletionRequest(model: string, imageBase64: string, mimeType: string, reasoningEffort?: string) {
  return visionRequest(model, BOX_INSTRUCTIONS, "Transcribe the Japanese ingredients box in this photo.",
    "ingredients_box", BOX_SCHEMA, imageBase64, mimeType, reasoningEffort);
}

const EMPTY_TEXT: TranslatedText = { japanese: "", english: "" };

/** An allergen statement the model kept as an ingredient: （一部に小麦・乳成分を含む）. */
const ALLERGEN_STATEMENT = /^[（(]?(原材料の)?一部に.*を含む[）)]?$/;

/** Drops the allergen statement from the ingredients, and empties everything when there's no box. */
export function normaliseBox(box: ExtractedIngredientsBox): ExtractedIngredientsBox {
  if (!box.boxFound) {
    return { boxFound: false, category: EMPTY_TEXT, ingredients: [], allergens: [], netContentsText: "", netContentsAmount: 0,
      netContentsUnit: "none", netContentsCount: 0, netContentsPrintedElsewhere: false, date: EMPTY_TEXT, isUseBy: false,
      storage: EMPTY_TEXT, maker: "", countryOfOrigin: EMPTY_TEXT };
  }
  return {
    ...box,
    ingredients: box.ingredients.filter((i) => !ALLERGEN_STATEMENT.test(i.japanese.normalize("NFKC").replace(/\s/g, ""))),
    netContentsUnit: box.netContentsAmount > 0 ? box.netContentsUnit : "none",
  };
}

/** Pulls the box out of a chat completion and checks it has the right shape. */
export function parseBoxCompletion(completion: unknown): ExtractedIngredientsBox {
  const box = JSON.parse(completionContent(completion)) as ExtractedIngredientsBox;
  if (typeof box.boxFound !== "boolean" || !Array.isArray(box.ingredients) || !Array.isArray(box.allergens)) {
    throw new Error("answer doesn't match the schema");
  }
  return normaliseBox(box);
}
