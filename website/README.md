# Beta page

A one-page site that collects emails for the TestFlight beta. Plain HTML, CSS and JS, no build step.

| File | What's in it |
|---|---|
| `index.html` | Copy and sections |
| `styles.css` | All colours, type sizes, radii and spacing as tokens at the top (iOS system colours, light and dark) |
| `main.js` | Email provider config (`CONFIG` at the top) |
| `icon.svg` | App icon, used for the favicon, nav and CTA |

Preview locally: `python3 -m http.server -d website 8000`, then open http://localhost:8000.

## Email collection

Set `PROVIDER` and `ID` in `main.js`. With no `ID` the form runs in preview mode: it shows success and sends nothing.

| Provider | Free tier | `ID` | Why pick it |
|---|---|---|---|
| **[Kit](https://kit.com)** (default) | 10,000 subscribers | Form ID: Grow › Landing Pages & Forms › your form › Publish › HTML. It's the number in `app.kit.com/forms/1234567/subscriptions`. | Biggest free tier. Send the "beta is live" email from the same place. |
| [Loops](https://loops.so) | 1,000 contacts, 4,000 emails / 30 days | Form ID: Forms › Custom form. It's the last part of `app.loops.so/api/newsletter-form/abc123`. | Cleanest UI, made for app launches. |
| [Buttondown](https://buttondown.com) | 100 subscribers | Your Buttondown username | Simplest, Markdown emails. Fine for a small beta. |

Kit and Loops return a real success or error. Buttondown's embed endpoint doesn't allow reading the response, so the page always shows success.

When the beta opens, create a TestFlight public link in App Store Connect and send it to the list from the provider.

## Deploy

`.github/workflows/pages.yml` publishes this folder to GitHub Pages on every push to `main` that touches `website/`.

1. In the repo: Settings › Pages › Build and deployment › Source: **GitHub Actions**.
2. Push to `main`, or run the workflow by hand from the Actions tab.
3. Custom domain: add it in Settings › Pages and add a `CNAME` file containing the domain to this folder.

GitHub Pages is only free on public repos (or with GitHub Pro / Team for private ones).

GitHub Pages lets browsers cache files for 10 minutes. After changing `main.js` or `styles.css`, bump the `?v=` number where `index.html` loads them, so visitors get the new file straight away.
