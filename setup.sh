#!/usr/bin/env bash
# =============================================================================
# setup.sh — One-time setup for Caddy + Step-CA + Cloudflare DNS-01
# Run as: bash /srv/docker/caddy/setup.sh
# =============================================================================
set -euo pipefail

CF_TOKEN_FILE="/srv/docker/secrets/cf_dns_token.txt"
STEP_CA_DIR="/srv/docker/step-ca/data"
CADDY_DATA="/srv/docker/caddy/data"

echo "=================================================="
echo " Caddy + Step-CA Setup Script"
echo "=================================================="
echo ""

# ── Step 1: Cloudflare API token ─────────────────────────────────────────────
echo "STEP 1 — Cloudflare DNS API Token"
echo "----------------------------------"
echo "You need a Cloudflare API token with ONLY these permissions:"
echo "  Permissions:  Zone → DNS → Edit"
echo "  Zone Resources: Include → Specific zone → am180.us"
echo ""
echo "Create it at: https://dash.cloudflare.com/profile/api-tokens"
echo "  → Create Token → Custom Token"
echo ""

if [ ! -f "$CF_TOKEN_FILE" ]; then
  read -rsp "Paste your Cloudflare DNS API token (input hidden): " cf_token
  echo
  echo "$cf_token" > "$CF_TOKEN_FILE"
  chmod 600 "$CF_TOKEN_FILE"
  echo "✓ Token saved to $CF_TOKEN_FILE"
else
  echo "✓ Token file already exists at $CF_TOKEN_FILE"
fi

# ── Step 2: Verify token ─────────────────────────────────────────────────────
echo ""
echo "STEP 2 — Verifying Cloudflare token..."
result=$(curl -s -X GET "https://api.cloudflare.com/client/v4/user/tokens/verify" \
  -H "Authorization: Bearer $(cat $CF_TOKEN_FILE)" \
  -H "Content-Type: application/json")
if echo "$result" | grep -q '"success":true'; then
  echo "✓ Token is valid"
else
  echo "✗ Token invalid — check permissions and try again"
  echo "$result"
  exit 1
fi

# ── Step 3: Init Step-CA (first time only) ────────────────────────────────────
echo ""
echo "STEP 3 — Initializing Step-CA..."
if [ ! -f "$STEP_CA_DIR/config/ca.json" ]; then
  echo "Running Step-CA init container..."
  docker run --rm -it \
    -v "$STEP_CA_DIR:/home/step" \
    -e DOCKER_STEPCA_INIT_NAME="Capes Internal CA" \
    -e DOCKER_STEPCA_INIT_DNS_NAMES="ca.capes.local,192.168.1.2" \
    -e DOCKER_STEPCA_INIT_PROVISIONER_NAME="matt@am180.us" \
    -e DOCKER_STEPCA_INIT_ADDRESS=":9000" \
    -e DOCKER_STEPCA_INIT_ACME="true" \
    smallstep/step-ca
  echo "✓ Step-CA initialized"
else
  echo "✓ Step-CA already initialized (config/ca.json exists)"
fi

# ── Step 4: Extract Step-CA root cert for Caddy ───────────────────────────────
echo ""
echo "STEP 4 — Copying Step-CA root cert to Caddy data dir..."
if [ -f "$STEP_CA_DIR/certs/root_ca.crt" ]; then
  cp "$STEP_CA_DIR/certs/root_ca.crt" "$CADDY_DATA/step-ca-root.crt"
  echo "✓ Root cert copied to $CADDY_DATA/step-ca-root.crt"
else
  echo "⚠ Root cert not found yet — run this step after Step-CA first starts"
fi

# ── Step 5: Start Step-CA first ───────────────────────────────────────────────
echo ""
echo "STEP 5 — Starting Step-CA..."
cd /srv/docker/step-ca
docker compose up -d
echo "✓ Step-CA started. Waiting 5s for it to be ready..."
sleep 5

# ── Step 6: Start Caddy ───────────────────────────────────────────────────────
echo ""
echo "STEP 6 — Starting Caddy..."
cd /srv/docker/caddy
docker compose up -d
echo "✓ Caddy started"

# ── Step 7: Print root cert for device distribution ──────────────────────────
echo ""
echo "=================================================="
echo " DISTRIBUTE ROOT CA CERT TO YOUR DEVICES"
echo "=================================================="
echo ""
echo "Root CA cert location: $STEP_CA_DIR/certs/root_ca.crt"
echo ""
echo "Install on macOS (mMacPro, MacBooks):"
echo "  sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain \\"
echo "    $STEP_CA_DIR/certs/root_ca.crt"
echo ""
echo "Install on iOS (iPhone/iPad):"
echo "  1. Host the cert at https://ca.capes.local/roots.pem or AirDrop it"
echo "  2. Settings → Profile Downloaded → Install"
echo "  3. Settings → General → About → Certificate Trust Settings → Enable"
echo ""
echo "Caddy logs: docker logs -f caddy"
echo "Step-CA logs: docker logs -f step-ca"
echo ""
echo "✅ Setup complete!"
