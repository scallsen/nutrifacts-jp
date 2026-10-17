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
export const INSTRUCTIONS = `You transcribe Japanese nutrition facts panels (栄養成分表示) into structured data. You never judge or score the food, and you never fill in values that aren't printed.

Rules:
- Only output lines that are actually printed. A missing line is "not disclosed", never 0.
- 炭水化物 is carbohydrate (includes fibre). 糖質 is netCarbs. 糖類 is sugars and sits under 糖質 or 炭水化物. 食物繊維 is fibre. Never map 糖質 to sugars.
- 食塩相当量 is salt in grams. ナトリウム is sodium; keep its printed unit (mg, or g when ≥ 1000 mg).
- エネルギー means energy (熱量). たんぱく, 蛋白質 and タンパク質 mean protein. 飽和脂肪酸 is saturatedFat.
- Grouped zeros such as たんぱく質・脂質 0g give 0 to each named nutrient.
- Ranges such as 120〜150kcal: minValue 120, maxValue 150.
- Convert full-width digits (０-９, ．) to normal numbers. Keep the printed precision.
- Caffeine, collagen and other items printed outside the panel are nutrient "other".
- basisText is only the per-what phrase, e.g. 1食分（50g）当たり or 1個当たり, without 栄養成分表示 or outer brackets. basisAmount is the grams or ml in it, or 0 if none is printed. Never take basisAmount from 内容量.
- 内容量 (net contents) is often printed away from the panel. Give its weight or volume and unit if visible, and how many pieces it holds if it says (6個入り). A bare count like 2個 is not a weight.
- If there is no nutrition panel in the image, set panelFound to false and leave lines empty.`;

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
          minValue: { type: "number" },
          maxValue: { type: "number" },
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

/** Pulls the label out of a chat completion and checks it has the right shape. */
export function parseCompletion(completion: unknown): ExtractedLabel {
  const content = (completion as { choices?: { message?: { content?: string } }[] })?.choices?.[0]?.message?.content;
  if (typeof content !== "string" || content.length === 0) throw new Error("empty answer");
  const label = JSON.parse(content) as ExtractedLabel;
  if (typeof label.panelFound !== "boolean" || !Array.isArray(label.lines)) throw new Error("answer doesn't match the schema");
  // Strict schema mode should already guarantee this; drop anything outside the known nutrients regardless.
  label.lines = label.lines.filter((l) => (NUTRIENTS as readonly string[]).includes(l.nutrient));
  return label;
}
