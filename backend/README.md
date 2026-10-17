# NutriFacts API

A Cloudflare Worker that reads nutrition label photos with [AI&](https://www.aiand.com/jp/) for the app's **ai&** option. It keeps the AI& key off the app. How it works and the API: [`docs/aiand.md`](../docs/aiand.md).

## Set up

You need an AI& account with credit and a Cloudflare account.

1. **Get an AI& key.** At [console.aiand.com](https://console.aiand.com), add credit and create an API key (`sk-…`).

2. **Pick a vision model.** Models vary by account, so list the ones yours can use, keeping the image-capable ones:

   ```bash
   curl -s https://api.aiand.com/v1/models -H "Authorization: Bearer $AIAND_API_KEY" | jq -r '.data[] | select((.capabilities // []) | index("vision")) | "\(.id)  in \(.input_per_1m) / out \(.output_per_1m) \(.currency) per 1M"'
   ```

   `wrangler.jsonc` → `vars.AIAND_MODEL` is set to `qwen/qwen3.8-27b`. To compare models on real labels first, run this with a few photos. iPhone HEIC files are fine, and the key stays in your shell:

   ```bash
   cd backend && AIAND_API_KEY=sk-… npm run compare -- ~/Desktop/label1.heic ~/Desktop/label2.heic
   ```

   It prints what each vision model read, how long it took and what it cost.

3. **Install and log in to Cloudflare:**

   ```bash
   cd backend && npm install && npx wrangler login
   ```

4. **Store the key as a secret.** It's never written to a file:

   ```bash
   npx wrangler secret put AIAND_API_KEY
   ```

   Optional: `npx wrangler secret put APP_TOKEN` to require an app token (see below).

5. **Deploy:**

   ```bash
   npm run deploy
   ```

   It prints the Worker's URL, e.g. `https://nutrifacts-api.<your-subdomain>.workers.dev`.

6. **Point the app at it.** Set `NUTRIFACTS_API_URL` in [`App/Config/NutriFacts.xcconfig`](../App/Config/NutriFacts.xcconfig). If you set `APP_TOKEN`, copy `App/Config/Secrets.example.xcconfig` to `Secrets.xcconfig` (git-ignored) and put the same value in it.

Check it's up with `curl https://nutrifacts-api.<your-subdomain>.workers.dev/health`.

## Develop

```bash
npm test            # Node's test runner, AI& mocked
npm run typecheck
npm run dev         # local Worker; put secrets in .dev.vars (git-ignored)
```

`src/label.ts` holds the prompt and JSON schema. Keep them in step with `ExtractedLabel` and `AppleIntelligenceReader.instructions` in the app.

## Logs

`npx wrangler tail` shows live requests. AI& errors (bad key, no credit, model without vision) are logged there, but the app only gets a generic message.
