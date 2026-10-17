// NutriFacts API: reads a nutrition label photo with AI& and returns the transcription.
// The app never sees the AI& key, and this Worker only does label reading, so its URL
// can't be used as a general AI& proxy. See README.md.

import { completionRequest, parseCompletion } from "./label.ts";

export interface Env {
  AIAND_API_KEY: string;
  AIAND_MODEL: string;
  /** Reasoning level when the app doesn't ask for one. Ignored if the model doesn't offer it. */
  AIAND_REASONING_EFFORT?: string;
  /** Optional. When set, requests need a matching X-App-Token header. */
  APP_TOKEN?: string;
  READ_LIMITER: RateLimit;
  /** Overridable in tests. */
  AIAND_BASE_URL?: string;
}

const MAX_IMAGE_BYTES = 8 * 1024 * 1024;
const MIME_TYPES = new Set(["image/jpeg", "image/png", "image/webp"]);

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname === "/health") return json({ ok: true });
    if (url.pathname !== "/v1/nutrition-label/read" && url.pathname !== "/v1/config") return error(404, "Not found.");

    if (env.APP_TOKEN && request.headers.get("X-App-Token") !== env.APP_TOKEN) {
      return error(401, "Missing or wrong app token.");
    }
    if (!env.AIAND_API_KEY || !env.AIAND_MODEL) return error(500, "The server isn't configured yet.");

    // What the app's Settings can offer: the reasoning levels this model supports.
    if (url.pathname === "/v1/config") {
      if (request.method !== "GET") return error(405, "Use GET.");
      const efforts = await reasoningEfforts(env);
      return json({ model: env.AIAND_MODEL, reasoningEfforts: efforts, defaultReasoningEffort: pickEffort(env, efforts) ?? null });
    }
    if (request.method !== "POST") return error(405, "Use POST.");
    const client = request.headers.get("CF-Connecting-IP") ?? "unknown";
    const { success } = await env.READ_LIMITER.limit({ key: client });
    if (!success) return error(429, "Too many label reads. Wait a minute and try again.");

    let body: { image?: unknown; mimeType?: unknown; reasoningEffort?: unknown };
    try {
      body = await request.json();
    } catch {
      return error(400, "Send JSON: { image, mimeType }.");
    }
    const image = typeof body.image === "string" ? body.image : "";
    const mimeType = typeof body.mimeType === "string" ? body.mimeType : "image/jpeg";
    if (!image) return error(400, "Missing image.");
    if (!MIME_TYPES.has(mimeType)) return error(400, "Send a JPEG, PNG or WebP image.");
    if ((image.length * 3) / 4 > MAX_IMAGE_BYTES) return error(413, "The image is too large.");

    const effort = pickEffort(env, await reasoningEfforts(env), body.reasoningEffort);
    const upstream = await fetch(`${base(env)}/chat/completions`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${env.AIAND_API_KEY}` },
      body: JSON.stringify(completionRequest(env.AIAND_MODEL, image, mimeType, effort)),
    });
    if (!upstream.ok) return upstreamError(upstream);

    try {
      const res = json(parseCompletion(await upstream.json()));
      // The level AI& actually applied, for checking it took effect.
      const applied = upstream.headers.get("X-Reasoning-Effort") ?? effort;
      if (applied) res.headers.set("X-Reasoning-Effort", applied);
      return res;
    } catch {
      return error(502, "The model's answer couldn't be read. Try again.");
    }
  },
} satisfies ExportedHandler<Env>;

/** Maps AI& errors to messages the app can show. Never forwards AI&'s own details about the key or account. */
async function upstreamError(upstream: Response): Promise<Response> {
  const detail = (await upstream.json().catch(() => null)) as { error?: { message?: string; code?: string } } | null;
  console.error("AI& error", upstream.status, detail?.error?.code, detail?.error?.message);
  switch (upstream.status) {
    case 401:
    case 402:
    case 403:
      return error(503, "Label reading with AI& is unavailable right now.");
    case 400:
      return detail?.error?.code === "invalid_value"
        ? error(503, "The server's AI& model can't read images.")
        : error(502, "AI& couldn't read this photo.");
    case 429:
      return error(429, "AI& is busy. Try again in a moment.");
    default:
      return error(502, `AI& returned HTTP ${upstream.status}. Try again.`);
  }
}

function base(env: Env): string {
  return env.AIAND_BASE_URL ?? "https://api.aiand.com/v1";
}

// The model's reasoning levels, from AI&'s model list. Cached per Worker instance for an hour.
let effortsCache: { model: string; efforts: string[]; at: number } | undefined;

export async function reasoningEfforts(env: Env): Promise<string[]> {
  if (effortsCache && effortsCache.model === env.AIAND_MODEL && Date.now() - effortsCache.at < 3_600_000) {
    return effortsCache.efforts;
  }
  const res = await fetch(`${base(env)}/models`, { headers: { Authorization: `Bearer ${env.AIAND_API_KEY}` } });
  if (!res.ok) return [];
  const list = (await res.json()) as { data?: { id: string; reasoning_efforts?: string[] }[] };
  const efforts = list.data?.find((m) => m.id === env.AIAND_MODEL)?.reasoning_efforts ?? [];
  effortsCache = { model: env.AIAND_MODEL, efforts, at: Date.now() };
  return efforts;
}

export function resetEffortsCache() {
  effortsCache = undefined;
}

/** The app's choice if the model offers it, else the configured default if the model offers that, else none sent. */
export function pickEffort(env: Env, efforts: string[], requested?: unknown): string | undefined {
  if (typeof requested === "string" && efforts.includes(requested)) return requested;
  if (env.AIAND_REASONING_EFFORT && efforts.includes(env.AIAND_REASONING_EFFORT)) return env.AIAND_REASONING_EFFORT;
  return undefined;
}

function json(value: unknown, status = 200): Response {
  return new Response(JSON.stringify(value), { status, headers: { "Content-Type": "application/json" } });
}

function error(status: number, message: string): Response {
  return json({ error: { message } }, status);
}
