# Caddy Stack — CHANGELOG

## [1.1.0] — 2026-02-26 — lan_only fix + stack.am180.us

### Fixed — 403 Forbidden for all LAN devices on `lan_only` services

**Root cause:** The `@external` matcher in the `lan_only` snippet only allowed
`192.168.0.0/16` and `127.0.0.1/8`. Caddy runs in Docker bridge networks, so Docker's
userspace NAT masquerades all inbound connections through `172.x.x.x` gateway IPs.
Caddy never sees the real client `192.168.1.x` IP — it sees a Docker gateway address,
which did not match the allowlist, causing 403 on every LAN request.

**Fix:** Added `172.16.0.0/12` (all Docker bridge subnets) and `10.0.0.0/8` (future
Tailscale/VPN) to the `@external` allowlist. All `lan_only` services now correctly
pass LAN traffic from Mac Pro, iPhones, and any device on 192.168.1.x.

```caddy
# Before
@external not remote_ip 192.168.0.0/16 127.0.0.1/8

# After
@external not remote_ip 192.168.0.0/16 172.16.0.0/12 10.0.0.0/8 127.0.0.1/8
```

### Fixed — `stack.am180.us` missing from AdGuard DNS rewrites

`stack.am180.us` was added to the Caddyfile without a corresponding AdGuard split-horizon
DNS rewrite. All LAN devices were resolving it to the public WAN IP (172.89.21.35) via
Cloudflare, then getting correctly blocked as external traffic.

**Fix:** Added three AdGuard rewrite entries:
- `stack.am180.us` → `192.168.1.35`
- `stack.capes.local` → `192.168.1.35`
- `stack` → `192.168.1.35`

### Added — `stack.am180.us` service entry
Stack landing page (`/www/stack/index.html`) now accessible at `https://stack.am180.us`
from all LAN devices. `lan_only` protected.

### Documented — Two-part checklist for new services
README updated with explicit two-step checklist: (1) add AdGuard DNS rewrite, (2) add
Caddyfile block. Also documented macOS DNS cache flush requirement.

---

## [1.0.0] — 2026-02-21 — Initial Deploy

- Caddy + Step-CA deployed on mbuntu
- Let's Encrypt wildcard `*.am180.us` via Cloudflare DNS-01
- Step-CA internal CA for `*.capes.local`
- Cloudflare DDNS managing all A records
- Split-horizon DNS via AdGuard rewrites for all services
- Systemd service: `docker-stack-caddy.service`
