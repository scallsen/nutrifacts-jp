// What the app needs back: a transcription of the panel, nothing inferred.
// Mirrors ExtractedLabel in App/NutriFacts/Reading/ExtractedLabel.swift. Keep the two in step.

export const NUTRIENTS = ["energy", "protein", "fat", "saturatedFat", "carbohydrate", "netCarbs",
  "sugars", "fibre", "salt", "sodium", "other"] as const;

export interface ExtractedLine {
  nutrient: (typeof NUTRIENTS)[number];
  printedName: string;
  minValue: number;
  maxValue: number;
  unit: string;
}

export interface ExtractedLabel {
  panelFound: boolean;
  productName: string;
  basisText: string;
  basisAmount: number;
  basisUnit: "g" | "ml";
  netContentsAmount: number;
  netContentsUnit: "g" | "ml" | "none";
  netContentsCount: number;
  lines: ExtractedLine[];
  isEstimate: boolean;
}

// Same rules the app gives Apple's models (AppleIntelligenceReader.instructions).
export const INSTRUCTIONS = `You transcribe Japanese nutrition facts panels (栄養成分表示) into structured data, copying exactly what is printed. You never judge or score the food, and you never fill in values that aren't printed.

Japanese panels use a fixed set of line names. The printed name decides the nutrient:
- エネルギー or 熱量 → energy
- たんぱく質, タンパク質, 蛋白質 → protein
- 脂質 → fat; 飽和脂肪酸 → saturatedFat
- 炭水化物 → carbohydrate (includes fibre)
- 糖質 → netCarbs. 糖類 → sugars. They are different lines: 糖質 is not sugars.
- 食物繊維 → fibre
- 食塩相当量 → salt; ナトリウム → sodium
- Anything else (コレステロール, カリウム, カルシウム, 鉄, vitamins, リコピン, イソフラボン …) → other
Read each line's name character by character before choosing; カリウム (potassium) is not ナトリウム (sodium), and 糖質 is not 炭水化物.

Rules:
- Output one line per row you can actually see, in printed order, with its name and value both visible. Never add a row because labels usually have it: a missing line is "not disclosed", never 0.
- Breakdowns of one value in brackets, such as 食塩相当量 4.7g (めん・かやく 2.2g)(スープ 2.5g), are not lines. Give only the total.
- If the panel has several value columns (100g当たり and 大さじ1杯当たり), use the first column.
- ナトリウム keeps its printed unit (mg, or g when ≥ 1000 mg).
- Grouped zeros such as たんぱく質・脂質 0g give 0 to each named nutrient.
- Ranges such as 120〜150kcal: minValue 120, maxValue 150.
- Convert full-width digits (０-９, ．) to normal numbers. Keep the printed precision.
- basisText is only the per-what phrase, e.g. 1食分（50g）当たり or 12個（標準59g）当たり, without 栄養成分表示 or outer brackets. basisAmount is the grams or ml in it, or 0 if none is printed. Never take basisAmount from 内容量.
- 内容量 (net contents) is often printed away from the panel. Give its weight or volume and unit only if the word 内容量 is visible. netContentsCount comes only from 内容量 saying how many pieces the pack holds (6個入り → 6); the count in the basis (12個当たり, 4本当たり) is not 内容量. Otherwise 0.
- isEstimate is true only if 推定値 or 目安 is printed near the panel.
- panelFound is true only for a Japanese 栄養成分表示. An English, Chinese or other foreign nutrition table, a product front or an ingredients list is panelFound false with no lines.`;

export const LABEL_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["panelFound", "productName", "basisText", "basisAmount", "basisUnit",
    "netContentsAmount", "netContentsUnit", "netContentsCount", "lines", "isEstimate"],
  properties: {
    panelFound: { type: "boolean", description: "True only if a Japanese nutrition facts panel (栄養成分表示) is visible." },
    productName: { type: "string", description: "Product name if visible, else empty." },
    basisText: { type: "string", description: "Only the per-what phrase, e.g. 1袋（60g）当たり or 1個当たり. Empty if not printed." },
    basisAmount: { type: "number", description: "Grams or ml in the basis text, or 0 if none is printed. Never from 内容量." },
    basisUnit: { type: "string", enum: ["g", "ml"] },
    netContentsAmount: { type: "number", description: "内容量 weight or volume if visible, else 0. 0 if 内容量 is only a count like 2個." },
    netContentsUnit: { type: "string", enum: ["g", "ml", "none"] },
    netContentsCount: { type: "integer", description: "Pieces in the pack if 内容量 states it (6個入り → 6), else 0." },
    lines: {
      type: "array",
      description: "One entry per printed nutrient line. Never add lines that aren't printed.",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["nutrient", "printedName", "minValue", "maxValue", "unit"],
        properties: {
          nutrient: { type: "string", enum: NUTRIENTS },
          printedName: { type: "string" },
          minValue: { type: "number", description: "The printed value, or the low end of a range like 120〜150." },
          maxValue: { type: "number", description: "Same as minValue for a single value. Only differs for a printed range." },
          unit: { type: "string", description: "As printed: kcal, kJ, g, mg or µg." },
        },
      },
    },
    isEstimate: { type: "boolean", description: "True if the label says 推定値 or この表示値は、目安です." },
  },
} as const;

/** The chat completion request for AI&'s OpenAI-compatible API. */
export function completionRequest(model: string, imageBase64: string, mimeType: string, reasoningEffort?: string) {
  return {
    model,
    temperature: 0,
    ...(reasoningEffort ? { reasoning_effort: reasoningEffort } : {}),
    messages: [
      { role: "system", content: INSTRUCTIONS },
      {
        role: "user",
        content: [
          { type: "text", text: "Transcribe the Japanese nutrition facts panel in this photo." },
          { type: "image_url", image_url: { url: `data:${mimeType};base64,${imageBase64}` } },
        ],
      },
    ],
    response_format: {
      type: "json_schema",
      json_schema: { name: "nutrition_label", strict: true, schema: LABEL_SCHEMA },
    },
  };
}

// The names 食品表示基準 allows for each nutrient. Japanese panels use only these, so the Worker
// sets `nutrient` from the printed name itself rather than trusting the model's choice, which
// mixes up 糖質 and 糖類 because both contain 糖.
const PRINTED_NAMES: Record<string, ExtractedLine["nutrient"]> = {
  エネルギー: "energy", 熱量: "energy",
  たんぱく質: "protein", タンパク質: "protein", 蛋白質: "protein", たん白質: "protein",
  脂質: "fat", 飽和脂肪酸: "saturatedFat",
  炭水化物: "carbohydrate", 糖質: "netCarbs", 糖類: "sugars", 食物繊維: "fibre",
  食塩相当量: "salt", ナトリウム: "sodium",
};

/** `ー飽和脂肪酸`, `脂　質` or `食塩相当量(g)` → the bare name. */
function bareName(printed: string): string {
  return printed.normalize("NFKC").replace(/\s/g, "").replace(/^\((.*)\)$/, "$1").replace(/^[-‐−–—ー一・]+/, "").replace(/\(.*\)$/, "");
}

/** The nutrient a printed name stands for: one of the standard names, else `other`. */
export function nutrientFor(printedName: string): ExtractedLine["nutrient"] {
  return PRINTED_NAMES[bareName(printedName)] ?? "other";
}

/**
 * Sets each line's nutrient from its printed name, and treats a panel with none of the standard
 * Japanese names (a Canadian or EU table) as no Japanese panel.
 */
export function normaliseLabel(label: ExtractedLabel): ExtractedLabel {
  if (!label.panelFound) return { ...label, lines: [] };
  const lines = label.lines.map((l) => ({
    ...l,
    nutrient: nutrientFor(l.printedName),
    // Some models put 0 (or anything below minValue) in maxValue for a single value. A real range
    // always has max ≥ min, so treat that as "no range", as the app does.
    maxValue: l.maxValue >= l.minValue ? l.maxValue : l.minValue,
  }));
  if (!lines.some((l) => l.nutrient !== "other")) return { ...label, panelFound: false, lines: [] };
  return { ...label, lines };
}

/** Pulls the label out of a chat completion and checks it has the right shape. */
export function parseCompletion(completion: unknown): ExtractedLabel {
  const content = (completion as { choices?: { message?: { content?: string } }[] })?.choices?.[0]?.message?.content;
  if (typeof content !== "string" || content.length === 0) throw new Error("empty answer");
  const label = JSON.parse(content) as ExtractedLabel;
  if (typeof label.panelFound !== "boolean" || !Array.isArray(label.lines)) throw new Error("answer doesn't match the schema");
  return normaliseLabel(label);
}
