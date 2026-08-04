# Kept — Project Context

Canonical reference for AI coding assistants. Everything decided so far lives here.

---

## Product

An iOS app that turns receipts into Apple Wallet passes warning you before a warranty expires.

**Flow:** photograph receipt → Vision OCR → parse into structured data → SwiftData stores it → signed Wallet pass added → notification fires 14 days before cover ends → user exports a claim pack PDF when something breaks.

**Positioning:** people don't want a receipt filing app. Filing is work with no reward. They want a deadline they didn't have to set. The receipt is not the product. The countdown is.

**Privacy is the pitch.** Everything runs on-device. Nothing leaves the phone except pass signing.

---

## Timeline

- **Hackathon:** RevenueCat Shipaton 2026, Aug 1 – Sep 30
- **Build started:** Aug 3, 2026
- **Submit to App Store review: Sep 14.** This is the real deadline. Review plus one rejection cycle eats 5–10 days.
- **Devpost submission closes:** Sep 30, 11:45pm PDT

Entry requirements: first public release must fall inside the window (Kept has never shipped, so it qualifies), and the RevenueCat SDK must power at least one IAP.

---

## Platform constraints

**Minimum iOS 26.0.**

**Foundation Models is not universally available.** It requires Apple Intelligence hardware, which starts at iPhone 15 Pro and the iPhone 16 line, plus Apple silicon iPads and Macs. On anything older `SystemLanguageModel.default.availability` returns `.unavailable(.deviceNotEligible)`.

The developer's own device is an iPhone 13, which cannot run it.

**Therefore extraction is two-tiered and the app must be fully functional without the model:**

| Tier | Availability | Produces |
|---|---|---|
| Rules parser | every supported device | merchant, date, price, total |
| Foundation Models | Apple Intelligence devices | item naming, category, inferred warranty length |

Both sit behind the same `ExtractionService` protocol. The rules tier is the floor, not a fallback. A user on an iPhone 12 gets a prefilled form they confirm, which is a complete product.

Never gate a core flow on model availability. Never show an Apple Intelligence upsell.

**Pass signing cannot happen on-device.** The Pass Type ID private key must never enter the app binary or the repo. A separate signing endpoint handles it. Architecture undecided (Vapor vs Cloudflare Worker) — resolve before week 2 starts.

---

## Stack

- Swift 6, strict concurrency complete
- SwiftUI, no UIKit unless a framework forces it
- SwiftData persistence, CloudKit sync (Pro only, week 4)
- Vision for OCR
- FoundationModels for enrichment where available
- PassKit for Wallet
- UserNotifications for expiry alerts
- RevenueCat via SPM
- Swift Testing, not XCTest

**RevenueCat is the only third-party dependency.** No networking libraries, no DI frameworks, no animation libraries, no analytics. Ask before adding anything.

---

## Architecture

Flat. This is a 58-day solo build.

```
Kept/
  App/                    entry point, root navigation
  Models/                 SwiftData @Model types
  Features/
    Capture/              camera, Vision OCR
    Extraction/           rules parser + FoundationModels
    Library/              list, detail, search
    Wallet/               pass generation, add-to-wallet
    Claim/                PDF claim pack export
    Paywall/              RevenueCat
  DesignSystem/
    Motion/               the five signature animations
  Services/               protocol-backed, injectable
  Tests/
```

- Views own no business logic. Push it into `@Observable` models or services.
- Every service gets a protocol so it can be faked in tests and previews.
- Every view needs a working `#Preview` with sample data.
- No singletons except where Apple forces one.

---

## Data model

Three `@Model` types: `Purchase`, `WarrantyTerm`, `PassRecord`.

**The schema is already CloudKit-shaped.** Every stored property has a default value, every relationship is optional, nothing uses `@Attribute(.unique)`. CloudKit's constraints are non-negotiable and retrofitting them in week 4 means a migration. Do not add a non-defaulted property or a required relationship.

**Warranties are one-to-many.** A laptop can carry a manufacturer term, a retailer guarantee, and card protection running different lengths. `primaryWarranty` is the longest-running one. Collapsing these into a single term costs the user real claims.

**`coverageEndsAt` is denormalised onto `Purchase`.** SwiftData `#Predicate` breaks when it traverses into an optional to-many relationship, and the library filters by expiry constantly. The stored date keeps queries translatable to SQL. It is `private(set)`; call `refreshCoverage()` after any mutation touching warranties.

**`WarrantySource` is stored as a raw String**, not a Codable enum. Raw strings survive CloudKit schema changes and allow new cases without migration.

**User edits always win.** `setDuration(months:from:byUser:)` refuses to overwrite a `.userProvided` value. Extraction fills gaps, it never corrects the person holding the receipt.

**Inferred values are never presented as fact.** Anything with `source == .inferred` and confidence below 0.8 surfaces as editable and visibly estimated. A wrong expiry date is worse than no expiry date.

---

## Design

Layout is standard Apple. Motion is not. Users should never learn where anything is, and should remember how it felt.

### Visual language
- HIG-native structure: `NavigationStack`, system list styles, standard detents and toolbar placement. Do not invent navigation patterns.
- One accent color. System backgrounds and materials elsewhere. No gradients on chrome.
- SF Pro only. Contrast comes from weight and size.
- Dynamic Type to XXL minimum on every screen. Cards reflow, they don't clip.
- Empty states carry voice and an SF Symbol, never "No items yet".
- Dark mode needs separate tuning for the card specular effect.

### Timing budget
- On the path to completing a task: **under 300ms**
- Moments of reward: up to **900ms**. There are exactly two, scan success and Wallet add.
- Nothing blocks input.

A flourish that makes the user wait is a bug, not craft.

### The five signature moments
Each gets its own file under `DesignSystem/Motion/`. First-class work, not week-5 polish.

1. **Scan sweep** (Capture) — frozen camera frame, light bar travelling down via Metal shader through `.layerEffect()`, Vision text boxes popping in behind it staggered by vertical position, soft haptic on completion. This is the first 5 seconds of the demo video.
2. **Receipt collapses into card** (Capture → Library) — `matchedGeometryEffect` folds the photo into the warranty card. The metaphor replaces onboarding copy.
3. **Add to Wallet** (Wallet) — `KeyframeAnimator` arc: lift, tilt, accelerate off the top edge. `.sensoryFeedback(.success)` on the exit frame. Match system Wallet timing.
4. **Live countdown** (Library) — `.contentTransition(.numericText(countsDown: true))` on days remaining, accent shifting warmer near expiry. Fires every app open, keep under 250ms.
5. **Card stack scroll** (Library) — `.scrollTransition` with scale and rotation falloff so passes read as physical.

### The warranty card
The signature object. Appears in library, detail, and the Wallet pass, and all three must feel like the same physical thing.

Depth via `rotation3DEffect` with perspective, a specular gradient mask driven by CoreMotion roll and pitch, and a shadow shifting opposite the tilt.

Throttle CoreMotion to 30Hz. Stop updates when the view leaves screen. Do not run the motion manager from the library list, only from detail and the add-to-Wallet flow.

### Reduce Motion
Every animation needs a path via `@Environment(\.accessibilityReduceMotion)`. Substitute cross-fades, never a jump cut. The scan sweep becomes a single fade with text boxes appearing together. Build it alongside each animation, not in a cleanup pass.

### Do not use
- **SceneKit** — soft-deprecated by Apple, maintenance mode only
- **RealityKit** — built for spatial and AR, fights SwiftUI layout, no 3D content here
- **Lottie or any animation library** — native SwiftUI plus Metal shaders only
- **Third-party design systems** — tokens live in `DesignSystem/`

If a task seems to need a 3D engine, stop and ask. The answer is almost always `rotation3DEffect` with a gradient mask.

---

## Milestones

### Week 1 (Aug 3–9) — Capture pipeline
Prove the hard part before building any UI.

- SwiftData models and schema ✅ (`Purchase`, `WarrantyTerm`, `PassRecord`; 1:N warranties; `coverageEndsAt`)
- Coverage logic unit tests ✅
- `OCRService`: protocol + Vision `VNRecognizeTextRequest`, accurate level, language correction on, returns lines with bounding boxes ordered top to bottom ✅
- `RulesExtractor`: regex over OCR lines for date, currency amounts, total; merchant from the top lines ✅
- `ModelExtractor`: `@Generable` struct with `@Guide` on every property, gated on availability ✅
- Both behind `ExtractionService`; rules tier is the floor ✅
- Receipt fixture bundle: 10 synthetic receipt images under `Kept/Resources/Fixtures/Receipts/` ✅ (replace with real photos when available)
- Ugly capture flow: camera sheet → OCR → extraction → save → library ✅

**Exit test:** three real receipts photographed, correct structured data from all three, on both tiers. Rules tier is verifiable on iPhone 13; Foundation Models tier needs Apple Intelligence hardware.

**Out of scope:** design system, Wallet, paywall, sync, onboarding, the scan sweep animation.

### Week 2 (Aug 10–16) — Wallet + notifications
- **Day one of the week: settle pass signing architecture.** This is the build's biggest schedule risk.
- Pass template design (the product's visual signature, give it real time)
- Pass generation and signing
- `UNUserNotificationCenter` scheduled at expiry minus 14 days
- Add to Wallet flow
- Scan sweep animation

### Week 3 (Aug 17–23) — Money
- RevenueCat SDK, products in App Store Connect, entitlements
- Free tier capped at 5 items
- Paywall screen
- Restore purchases, sandbox testing, edge cases

Ship the paywall early. Entries that bolt it on in the final week show it.

### Week 4 (Aug 24–30) — Claim pack
The feature people actually pay for.

- PDF export: receipt image, merchant, date, price, warranty terms
- Share sheet to Mail
- CloudKit sync (one-line container change, schema is ready)
- Pro gating on both

### Week 5 (Aug 31–Sep 6) — Craft
- Onboarding, three screens maximum
- Empty states
- App icon, typography lock-in
- Home screen widget: next expiring item
- Remaining signature animations, Reduce Motion paths

### Week 6 (Sep 7–13) — Ship
- TestFlight to 10 people, including at least one on Apple Intelligence hardware
- Replace the `fatalError` in `KeptApp.init` with a store recovery screen
- Screenshots, App Store copy, privacy nutrition labels
- **Submit for review Sep 14**

### Week 7 (Sep 14–20) — Launch
- Review buffer sits here
- Launch: Product Hunt, r/iOSProgramming, Indie Hackers, X, LinkedIn
- Grand Prize weighs traction, so this week matters as much as the code

### Week 8 (Sep 21–30) — Submit
- Demo video, 2 minutes, Wallet moment inside the first 15 seconds
- Devpost writeup
- Keep pushing installs

---

## Monetisation

- **Free:** 5 tracked items, no sync
- **Pro:** unlimited items, CloudKit sync, receipt image archive, claim pack export

The claim pack is the conversion moment. Nobody pays to store receipts. Everybody pays the day the kettle dies.

---

## Award targets

Three, not one:
- **Build in Public** — daily posting on X, three times weekly on LinkedIn
- **Design Award** — the Wallet pass and the five motion moments
- **Next Gen** — student-only, smaller field. Eligibility depends on BPP enrolment status in August.

---

## Conventions

- No force unwrapping outside tests. No `try!`.
- Errors are typed enums surfaced in plain language. No error codes in UI.
- Async/await everywhere, no completion handlers.
- Feature flags for anything half-built so `main` always runs.
- Commit per working increment, present-tense messages.
- Ask before adding a dependency, changing the data model, or introducing a new architectural pattern.
- When a build fails, show the actual error before proposing a fix.
- Prefer the smallest change that works.
- Do not build ahead of the current milestone. Say so and stop.

---

## Open questions

1. **Is the dev Mac Apple silicon with Apple Intelligence enabled?** If not, there is no way to run Foundation Models locally at all and the rules tier becomes the only testable path.
2. **Pass signing: Vapor or Cloudflare Worker?** Blocks week 2.
3. **Does `Decimal` round correctly through SwiftData in this release?** If drift appears, switch to storing minor units as `Int`.
4. **Next Gen award eligibility** given an August graduation.
