# Retention messages

Copy for Apple's [Retention Messaging API](https://developer.apple.com/documentation/retentionmessaging).
Shown on the App Store subscription details page when a user taps
Cancel Subscription. Sits between the user and the cancel confirmation.

## Status

- **Access:** pre-release, gated. Request access via Apple's interest
  form before uploading anything.
- **Ship plan:** upload Version A as the default across all locales
  post-launch, once we have real subscribers. Version B stays in the
  drawer as a real-time targeted variant for users who've engaged with
  Pro features (see "Later" section).
- **Not shipping at launch.** Retention messaging is a "you have
  churning subscribers" problem, not a "we're launching" problem.

## Format

Apple's message shape (as of the pre-release API):
- Title — short, ~30 chars
- Body — one or two sentences
- Bullet points — optional, ~5 max
- Image — optional, we're not using one

---

## Version A — Calm default

**When:** every locale, every product, as the default message. Ship this
one first.

**Why:** neutral and factual. Someone who genuinely doesn't want Kept
still cancels; someone who forgot why they subscribed gets a plain
reminder of what stops working. Respects the decision either way.

### Title

```
You'll lose the countdown
```

### Body

```
Kept keeps working after you cancel — but only for the receipts you've already saved. The next fridge, laptop, or pair of headphones you buy won't be tracked.
```

### Bullets

- Wallet passes stop updating
- No more claim pack exports
- Free tier caps at 5 items — anything past that becomes read-only
- Your existing receipts and photos stay on your device

---

## Version B — Concrete moment

**When:** later, once we can target real-time. Only show this to users
who've exported at least one claim pack, so "£299 repair" lands as a
memory rather than a hypothetical.

**Why:** leans into the specific moment Kept was built for. More
emotional than Version A but still on-brand — no exclamation marks,
no urgency copy.

### Title

```
When the fridge dies
```

### Body

```
Kept exists for the day something you own breaks under warranty and you need the receipt in one tap. Cancel now and that safety net's gone the next time you need it.
```

### Bullets

- Claim pack PDF export — the one that saves the £299 repair
- Unlimited receipts, so nothing hits the 5-item cap
- Higher-quality receipt extraction on new scans
- Weekly summary of upcoming expiries

---

## What we're deliberately not doing

- **Discount offers** ("Stay for 50% off"). Corrodes the brand and
  trains users to threaten cancel yearly for a price drop.
- **"You'll lose everything you've built"**. Misleading — receipts stay
  on device.
- **Emoji, exclamation marks, urgency**. Every retention playbook uses
  these; not using them IS Kept's brand signal.
- **Countdown timers, "last chance" language**. Nope.

## Locales

Ship English (UK) first. When localisation lands (see main brief),
translate both versions into the target languages. Machine translation
alone is fine for a first pass here — retention messages are short and
factual — but a native-speaker review before publishing is worth doing.
Nuance in the emotional line ("safety net's gone the next time you
need it") is where machine translation typically fails.

## Later — real-time targeting ideas

Once real-time messaging is set up and we have usage signals, worth
trying:

- **Never scanned a receipt** → surface the value proposition, not a
  loss-aversion frame. "Kept is set up but you haven't scanned yet.
  A single receipt takes 8 seconds."
- **Scanned but never exported a claim pack** → nudge toward the
  payoff. "The claim pack is the moment Kept was built for. Try it
  once before you cancel."
- **Heavy user (10+ receipts, active passes)** → Version B, since the
  emotional lever is real for them.
- **Subscription < 30 days old** → probably a "wrong app" cancel. Don't
  waste retention effort; let them go cleanly.
