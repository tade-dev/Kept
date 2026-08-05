#!/usr/bin/env bash
# Example: POST /extract against a deployed (or wrangler dev) worker.
set -euo pipefail

BASE_URL="${BASE_URL:-http://127.0.0.1:8787}"
SECRET="${EXTRACT_SECRET:?set EXTRACT_SECRET}"

curl -sS -X POST "${BASE_URL}/extract" \
  -H "content-type: application/json" \
  -H "authorization: Bearer ${SECRET}" \
  -d '{
    "lines": [
      { "text": "ASDA STORES LTD", "x": 0.1, "y": 0.9, "width": 0.5, "height": 0.04 },
      { "text": "Date: 16/06/2026", "x": 0.1, "y": 0.4, "width": 0.4, "height": 0.03 },
      { "text": "TOTAL", "x": 0.1, "y": 0.3, "width": 0.2, "height": 0.03 },
      { "text": "£18.13", "x": 0.5, "y": 0.3, "width": 0.2, "height": 0.03 }
    ]
  }' | python3 -m json.tool
