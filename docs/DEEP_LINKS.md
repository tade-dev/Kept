# Deep links

Kept supports one deep-link destination today — the receipt scan / Capture flow — reached via either:

- **Universal link** (production, used by the App Store In-App Event): `https://getkept.xyz/app/scan`
- **Custom scheme** (fallback / testing): `kept://scan`

Both land the user in the same place: onboarding + trial-entry paywall first (if not yet completed), then `CaptureView` presented as a sheet on top of the Library.

## App Store Connect

For the "Launch Week: First Scans" event and any future In-App Event, paste this into **Event deep link**:

```
https://getkept.xyz/app/scan
```

Do not use a URL shortener — App Review rejects those. Do not use the `kept://` scheme in App Store metadata — the store only accepts `https` for event links.

## Hosting the AASA file (one-time setup)

For the universal link to work, `getkept.xyz` must serve an `apple-app-site-association` file at:

```
https://getkept.xyz/.well-known/apple-app-site-association
```

Content (exact bytes, no BOM, Content-Type `application/json`):

```json
{
  "applinks": {
    "apps": [],
    "details": [
      {
        "appIDs": ["TU566926VK.com.tade.Kept"],
        "components": [
          { "/": "/app/*", "comment": "Kept in-app destinations" }
        ]
      }
    ]
  }
}
```

The same file lives in `docs/apple-app-site-association.json` in this repo for reference.

### Vercel

If `getkept.xyz` is on Vercel (the marketing site), drop the file at `public/.well-known/apple-app-site-association` (no extension). Vercel serves it verbatim. Deploy and confirm:

```
curl -I https://getkept.xyz/.well-known/apple-app-site-association
# Expect: HTTP/2 200 with content-type: application/json
```

### Any other host

Serve the file over HTTPS at the exact `.well-known` path. It must be reachable without redirects and with `Content-Type: application/json`. Apple's CDN caches it for ~24h — expect ~5 minutes to a day for a fresh install to see it.

## Testing without waiting for AASA propagation

1. **Notes app** — type `https://getkept.xyz/app/scan` and long-press → **Open** → Kept should open into the scanner.
2. If Notes opens Safari instead of Kept, the AASA hasn't propagated. Use the custom scheme in the meantime: `kept://scan` in Notes.
3. In the Simulator with a debug build, either link works from Safari after you've built once (Xcode registers the app's associated domain via `-com.apple.developer.applinks.mode developer` flag; not required for App Store).

## Entitlements & Info.plist

- **`Kept.entitlements`** — `com.apple.developer.associated-domains` includes `applinks:getkept.xyz`.
- **`Kept/Info.plist`** — `CFBundleURLTypes` declares the `kept` scheme for the custom-scheme fallback.

## Routing

- `Kept/App/DeepLinkRouter.swift` — the single source of truth for pending deep-link destinations.
- `Kept/App/RootView.swift` — hooks `.onOpenURL` and `.onContinueUserActivity(NSUserActivityTypeBrowseWeb)`, then presents `CaptureView` when the pending destination is `.scan` AND onboarding + paywall gates are clear.
