# Kept

A receipts and warranty tracker for iPhone. Scan a receipt once — Kept keeps the coverage, the return window, and the proof for the day something breaks.

Live on the App Store: [Kept: Warranty Tracker](https://apps.apple.com/gb/app/kept-warranty-tracker/id6797898011)

## What it does

- **Scans** paper receipts and PDFs on-device with Vision OCR, enriches the result with a hosted LLM on Cloudflare Workers.
- **Tracks** warranty length and return windows automatically, per merchant and category.
- **Nudges** you 30, 14, and 7 days before coverage ends. Weekly summary too.
- **Puts a live countdown in Apple Wallet** so you see coverage on your lock screen.
- **Exports a one-page claim PDF** with the receipt and warranty details, ready to send to the seller.

## Stack

| Layer | What it uses |
|---|---|
| iOS app | SwiftUI (iOS 18+), SwiftData with CloudKit sync, StoreKit 2 via RevenueCat, Vision OCR, PassKit, on-device Foundation Models fallback (iOS 26+) |
| Extraction worker | TypeScript on Cloudflare Workers, OpenAI via Cloudflare AI Gateway, structured JSON schema |
| Wallet pass signing | PassKit certificates, PKCS7 signing inside the same worker |
| Design | Bricolage Grotesque, custom design tokens, adaptive light/dark |

## Repository layout

```
Kept/                — iOS app (Kept.xcodeproj)
worker/              — Cloudflare Worker (receipt extraction + Wallet pass signing)
docs/                — deep-link setup, cert setup, deployment notes
Config/              — xcconfig files (real values gitignored, .example files checked in)
```

## Development

**Requires**: Xcode 27.0+, Node 20+, `wrangler` CLI, RevenueCat + OpenAI accounts.

### iOS

1. Open `Kept.xcodeproj` in Xcode.
2. Copy the example configs:
   ```
   cp Config/Extract.xcconfig.example  Config/Extract.local.xcconfig
   cp Config/RevenueCat.xcconfig.example  Config/RevenueCat.xcconfig
   ```
3. Fill in your RevenueCat iOS public API key and (if talking to a hosted worker) an extract secret. Both files are gitignored.
4. Build for iPhone Simulator or a device signed with your Apple Developer team.

### Worker

```
cd worker
npm install
wrangler dev
```

Required secrets (set via `wrangler secret put`, never committed):
- `EXTRACT_SECRET` — shared secret the app sends on `/extract`
- `OPENAI_API_KEY` — the OpenAI model used behind AI Gateway
- `RC_SECRET_KEY` — RevenueCat REST API key (used to grant the trial-boost entitlement)
- `SIGNER_CERT_PEM`, `SIGNER_KEY_PKCS8_PEM`, `WWDR_PEM` — Wallet pass signing chain, see `worker/docs/PASS_CERTS.md`

Public vars (safe in `wrangler.toml`) cover the AI Gateway ID, model choices, pass type identifier, and RevenueCat entitlement name.

## Development notes

- `docs/DEEP_LINKS.md` — universal-link setup for `getkept.xyz`, custom scheme fallback, and the AASA content
- `worker/docs/PASS_CERTS.md` — Apple Pass Type Certificate setup
- `worker/src/prompt.ts` — the extraction prompt (structured JSON output)

## Built with AI tooling

Kept is developed by [Akintade Oluwaseun](https://github.com/tade-dev) with heavy [Claude Code](https://claude.com/claude-code) pair-programming — architecture, code, and copy all iterated with the model. The product decisions and shipping cadence are mine; the model is a fast, patient collaborator.

## License

MIT — see [LICENSE](LICENSE).
