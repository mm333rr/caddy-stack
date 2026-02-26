# Caddy + Step-CA — HTTPS for The Capes

## Architecture

```
Internet → Cloudflare DNS → WAN IP → Caddy :443
                                         │
                          ┌──────────────┼──────────────────┐
                          │              │                   │
              *.am180.us (LE wildcard)   │      *.capes.local (Step-CA)
              grafana, overseerr,        │      prometheus, loki,
              sonarr, radarr...          │      adguard, internal tools
                                         │
                                   Split-horizon DNS
                                   *.am180.us → 192.168.1.35 (LAN)
                                   *.capes.local → 192.168.1.35 (LAN only)
```

## Components

| Container | IP:Port | Purpose |
|-----------|---------|---------|
| caddy | 0.0.0.0:80,443 | Reverse proxy + TLS termination |
| step-ca | 192.168.1.2:9000 | Internal CA for .capes.local certs |

## Cert Strategy

- ***.am180.us** — Let's Encrypt wildcard via Cloudflare DNS-01 challenge
  - Token: `/srv/docker/secrets/cf_dns_token.txt`
  - Permissions needed: Zone → DNS → Edit on am180.us
  - Auto-renews ~30 days before expiry, no downtime

- ***.capes.local** — Smallstep internal CA
  - Root cert: `/srv/docker/step-ca/data/certs/root_ca.crt`
  - Must be installed on all LAN devices (one-time)
  - ACME endpoint: `https://step-ca:9000/acme/acme/directory`

## ⚠️ Critical: Two-Part Setup Required for New Services

Every new service added to the Caddyfile **requires two steps** or it will return 403:

### Step 1 — Add AdGuard DNS rewrite
Without this, all LAN devices resolve the subdomain to the public WAN IP and get blocked.

```bash
# Add all three variants (am180.us, capes.local, bare hostname)
curl -s -X POST http://192.168.1.2:3000/control/rewrite/add \
  -H 'Content-Type: application/json' \
  -d '{"domain":"<service>.am180.us","answer":"192.168.1.35"}'

curl -s -X POST http://192.168.1.2:3000/control/rewrite/add \
  -H 'Content-Type: application/json' \
  -d '{"domain":"<service>.capes.local","answer":"192.168.1.35"}'

curl -s -X POST http://192.168.1.2:3000/control/rewrite/add \
  -H 'Content-Type: application/json' \
  -d '{"domain":"<service>","answer":"192.168.1.35"}'
```

### Step 2 — Add Caddyfile block and reload

```caddy
<service>.am180.us {
  import tls_wildcard
  import lan_only          # omit if publicly accessible
  reverse_proxy <container-name>:<port>
}
```

Then: `docker restart caddy`

### Step 3 — Flush DNS cache on client Macs
macOS caches DNS aggressively. After adding AdGuard rewrite:

```bash
dscacheutil -flushcache && killall -HUP mDNSResponder
```

iPhones: toggle Airplane Mode off/on.

---

## How `lan_only` Works (Docker Bridge NAT)

The `lan_only` snippet in the Caddyfile:

```caddy
(lan_only) {
  @external not remote_ip 192.168.0.0/16 172.16.0.0/12 10.0.0.0/8 127.0.0.1/8
  respond @external "Forbidden" 403
}
```

**Why `172.16.0.0/12` is required:** Caddy runs in a Docker bridge network. When a LAN device
(e.g. `192.168.1.30`) connects to port 443 on mbuntu, Docker's userspace NAT masquerades the
connection through a `172.x.x.x` Docker gateway IP. Caddy never sees the real `192.168.1.x`
source — it sees `172.x.x.x`. Without this subnet in the allowlist, all LAN devices get 403.

The three subnets in the allowlist cover:
- `192.168.0.0/16` — your LAN (Capes network)
- `172.16.0.0/12` — all Docker bridge networks (172.16–172.31.x.x)
- `10.0.0.0/8` — future Tailscale / VPN ranges
- `127.0.0.1/8` — loopback (health checks, local curls)

---

## First-Time Setup

```bash
bash /srv/docker/caddy/setup.sh
```

This will:
1. Prompt for Cloudflare DNS API token and save it
2. Verify token validity
3. Initialize Step-CA (first run only)
4. Start Step-CA, then Caddy
5. Print instructions for distributing root CA cert

## Day-2 Operations

### Start/Stop/Restart
```bash
# Caddy
cd /srv/docker/caddy && docker compose up -d
cd /srv/docker/caddy && docker compose down
docker restart caddy

# Step-CA
cd /srv/docker/step-ca && docker compose up -d
cd /srv/docker/step-ca && docker compose down
```

### Watch logs
```bash
docker logs -f caddy
docker logs -f step-ca
tail -f /srv/docker/caddy/logs/caddy-global.log | python3 -m json.tool
```

### Reload Caddy config
> ⚠️ Admin API is disabled (`admin off` in global config). Use `docker restart caddy` instead.

```bash
docker restart caddy
```

### Validate Caddyfile syntax before restart
```bash
docker exec caddy caddy validate --config /etc/caddy/Caddyfile
```

### Add a new service (full checklist)
1. Add Caddyfile block to `/srv/docker/caddy/Caddyfile`
2. If container is on a new Docker network, add that network to caddy's `docker-compose.yml`
3. Add AdGuard DNS rewrites (3 variants — see Critical section above)
4. `docker restart caddy`
5. Flush DNS cache on client Macs: `dscacheutil -flushcache && killall -HUP mDNSResponder`
6. iPhone/iPad: toggle Airplane Mode

## Service Map

### External (*.am180.us) — Let's Encrypt wildcard
| URL | Backend | Access |
|-----|---------|--------|
| https://grafana.am180.us | grafana:3000 | LAN + external |
| https://overseerr.am180.us | arr-overseerr:5055 | LAN + external |
| https://stack.am180.us | file_server /www/stack | LAN only (IP block) |
| https://prometheus.am180.us | prometheus:9090 | LAN only (IP block) |
| https://alertmanager.am180.us | alertmanager:9093 | LAN only (IP block) |
| https://sonarr.am180.us | arr-sonarr:8989 | LAN only (IP block) |
| https://radarr.am180.us | arr-radarr:7878 | LAN only (IP block) |
| https://lidarr.am180.us | music-lidarr:8686 | LAN only (IP block) |
| https://prowlarr.am180.us | indexers-prowlarr:9696 | LAN only (IP block) |
| https://jackett.am180.us | indexers-jackett:9117 | LAN only (IP block) |
| https://bitmagnet.am180.us | indexers-bitmagnet:3333 | LAN only (IP block) |
| https://qbit.am180.us | host:5555 (gluetun) | LAN only (IP block) |
| https://adguard.am180.us | host:3000 | LAN only (IP block) |

### Internal only (*.capes.local) — Step-CA
| URL | Backend |
|-----|---------|
| https://monitoring.capes.local | grafana:3000 |
| https://prometheus.capes.local | prometheus:9090 |
| https://loki.capes.local | loki:3100 |
| https://alertmanager.capes.local | alertmanager:9093 |
| https://adguard.capes.local | host:3000 |
| https://ca.capes.local | step-ca:9000 |
| https://sonarr.capes.local | arr-sonarr:8989 |
| https://radarr.capes.local | arr-radarr:7878 |
| https://overseerr.capes.local | arr-overseerr:5055 |
| https://prowlarr.capes.local | indexers-prowlarr:9696 |

## Installing the Step-CA Root Cert

### macOS
```bash
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain \
  /srv/docker/step-ca/data/certs/root_ca.crt
```
Or AirDrop the `.crt` file → double-click → Keychain Access → Trust → Always Trust.

### iOS / iPadOS
1. AirDrop `root_ca.crt`, or navigate to `http://192.168.1.2:9000/roots.pem`
2. Tap the file → Settings → "Profile Downloaded" banner → Install → Trust
3. Settings → General → About → Certificate Trust Settings → enable toggle

## Cloudflare Token Requirements

| Setting | Value |
|---------|-------|
| Token Name | mbuntu-caddy-acme |
| Permissions | Zone → DNS → Edit |
| Zone Resources | Include → Specific zone → am180.us |
| TTL | No expiry recommended |

Save token to: `/srv/docker/secrets/cf_dns_token.txt`

## Security Notes

- All *arr services are blocked from external IPs at the Caddy layer via `lan_only`
- Only `grafana.am180.us` and `overseerr.am180.us` are intentionally externally accessible
- `stack.am180.us` is LAN-only (dashboard, no sensitive data, but no reason to expose)
- Prometheus, Loki, Alertmanager are LAN-only
- qBit is LAN-only; VPN inside gluetun protects download traffic
- Next step: Cloudflare Zero Trust Access in front of grafana + overseerr for MFA

## Known Quirks

- **Admin API is disabled.** `caddy reload` won't work. Always use `docker restart caddy`.
- Caddy's DNS-01 plugin reads CF token via `{file.path}` syntax — token file must be accessible via Docker secret mount at `/run/secrets/cf_api_token`
- Step-CA auto-inits on first run if no `ca.json` exists — do NOT restart it during init
- macOS DNS cache persists after AdGuard rewrite changes — always flush after adding new entries
- HTTP/3 (QUIC) requires UDP 443 open on router (currently enabled on Orbi)

## Version History

| Version | Date | Notes |
|---------|------|-------|
| 1.0.0 | 2026-02-21 | Initial deploy — Caddy + Step-CA + Cloudflare DNS-01 |
| 1.1.0 | 2026-02-26 | Fixed lan_only to include Docker bridge subnets (172.16.0.0/12); added stack.am180.us with AdGuard rewrite; documented two-part new-service checklist |
