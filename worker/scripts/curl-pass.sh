#!/usr/bin/env bash
# Example: POST /pass against wrangler dev / deployed worker → /tmp/kept-test.pkpass
set -euo pipefail

BASE_URL="${BASE_URL:-http://127.0.0.1:8787}"
SECRET="${EXTRACT_SECRET:?set EXTRACT_SECRET}"
OUT="${OUT:-/tmp/kept-test.pkpass}"

curl -sS -X POST "${BASE_URL}/pass" \
  -H "content-type: application/json" \
  -H "authorization: Bearer ${SECRET}" \
  -d '{
    "merchant": "ASDA STORES LTD",
    "itemName": "Grocery shop",
    "total": 18.13,
    "currencyCode": "GBP",
    "purchaseDate": "2026-06-16",
    "coverageEndsAt": "2026-07-16T00:00:00.000Z",
    "serialNumber": "kept-test-serial-001"
  }' \
  --output "${OUT}"

file "${OUT}"
ls -la "${OUT}"
echo "Wrote ${OUT} — open it on a Mac/iPhone with Pass Type ID matching the signer cert."
