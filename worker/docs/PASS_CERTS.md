# Apple Wallet pass signing certs

Never commit PEM files or `.p12` keys. Load them via `.dev.vars` (local) or `wrangler secret put` (deploy).

## 1. Apple Developer

1. Certificates, Identifiers & Profiles → **Identifiers** → **Pass Type IDs** → create `pass.com.tade.Kept` (or your ID).
2. Create a **Pass Type ID Certificate** for that identifier; download the `.cer`.
3. Import into Keychain; export the private key + cert as `.p12`.
4. Enable **Passes** on App ID `com.tade.Kept`.

## 2. Convert to PEM (on your Mac)

```bash
# From the .p12 (you'll be prompted for the export password):
openssl pkcs12 -in Certificates.p12 -clcerts -nokeys -out signerCert.pem
openssl pkcs12 -in Certificates.p12 -nocerts -nodes -out signerKey.pem
openssl pkcs8 -topk8 -nocrypt -in signerKey.pem -out signerKey.pkcs8.pem

# Apple WWDR intermediate (G4):
curl -L -o AppleWWDRCAG4.cer https://www.apple.com/certificateauthority/AppleWWDRCAG4.cer
openssl x509 -inform DER -in AppleWWDRCAG4.cer -out wwdr.pem
```

## 3. Load into `.dev.vars`

PEMs can be multiline. Easiest: paste with literal newlines inside quotes, or collapse newlines to `\n`:

```
PASS_TYPE_IDENTIFIER=pass.com.tade.Kept
TEAM_IDENTIFIER=TU566926VK
SIGNER_CERT_PEM="-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----"
SIGNER_KEY_PKCS8_PEM="-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----"
WWDR_PEM="-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----"
```

Deployed:

```bash
npx wrangler secret put SIGNER_CERT_PEM
npx wrangler secret put SIGNER_KEY_PKCS8_PEM
npx wrangler secret put WWDR_PEM
```

`PASS_TYPE_IDENTIFIER` and `TEAM_IDENTIFIER` can stay in `wrangler.toml` `[vars]` (not secret).

## 4. Smoke test

With `npm run dev` running:

```bash
EXTRACT_SECRET=... ./scripts/curl-pass.sh
open /tmp/kept-test.pkpass
```
