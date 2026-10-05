# Email receipt fixtures

Each fixture is a pair:
- `{name}.html` — the raw HTML body of a real order-confirmation email
- `{name}.expected.json` — the ground-truth values

## How to capture a real one

1. Open the order-confirmation email in Mail on Mac.
2. **View → Message → Raw Source** (⌥⌘U). Copy everything.
3. In Terminal: paste into a `.eml` file, then extract the HTML body via
   `formail` or a quick Python snippet, and save as `{merchant}.html` here.
   Alternatively: **File → Save As → HTML** works but includes Mail's
   wrapper chrome, which is fine — the stripper will drop it.
4. Fill in `{merchant}.expected.json` with what a human reader would say
   was the merchant, total, and purchase/delivery date.
5. **Redact anything personally identifying before committing:** name,
   full address, credit card last-4, order number if you want. The
   stripper doesn't care.

## Expected format

```json
{
  "merchant": "Amazon.co.uk",
  "totalCents": 4499,
  "currency": "GBP",
  "purchaseDate": "2026-08-20"
}
```

`totalCents` is the full order total including tax and shipping — same
as `Purchase.price * 100`. `purchaseDate` is ISO-8601 (yyyy-MM-dd),
usually the order date rather than the delivery date.

## What's here now

- `amazon_synthetic.html` — a hand-rolled Amazon-shaped fixture used to
  drive the stripper's unit tests. Not a real email. Real Amazon/Argos/
  John Lewis fixtures should replace it as they become available.
