# Ragnar SSH VPN Panel v2.0

NPV Tunnel optimized SSH VPN panel for Linux servers.

## One-Click Install

```bash
bash <(curl -s https://raw.githubusercontent.com/faresbazed/Ragnar-ssh-panel-script/main/install.sh)
```

Or with wget:

```bash
wget -qO- https://raw.githubusercontent.com/faresbazed/Ragnar-ssh-panel-script/main/install.sh | bash
```

Then open the panel anytime with:

```bash
vpn
```

---

## Features

| Feature | Details |
|---------|---------|
| SSH-WebSocket | Port 80 (configurable), handles WS Upgrade + HTTP CONNECT + GET inject |
| SSH-TLS | Port 443 via Stunnel — bypasses DPI |
| Cloudflare Free Domain | `*.trycloudflare.com` — no account needed |
| Payload Configurator | 4 presets + custom payload for NPV Tunnel |
| User Management | Create, delete, lock, extend, kill sessions |
| Auto-Expiry | Cron runs every 5 min — locks expired accounts automatically |
| Login Limit | Enforces max concurrent sessions per user |
| Live Monitor | Real-time session viewer with limit warnings |
| Service Control | Restart any/all services in one click |
| Backup / Restore | Tar backup of all config + restore |
| Log Viewer | Panel, SSH auth, WS, Stunnel, Cloudflare logs |
| Update | In-panel update from GitHub |
| Uninstall | Full clean removal (SSH stays intact) |

---

## NPV Tunnel Settings

| Mode | Host | Port |
|------|------|------|
| SSH | your-server-ip | 22 |
| WebSocket (WS) | your-server-ip | 80 |
| WebSocket fallback | your-server-ip | 8880 |
| SSH over TLS | your-server-ip | 443 |
| Cloudflare WS | your-cf-domain.trycloudflare.com | 443 |

**Default Payload:**
```
GET / HTTP/1.1[crlf]Host: [host][crlf]Upgrade: websocket[crlf][crlf]
```

---

## Panel Menu

```
[1] Full Setup          — installs everything in one go
[2] SSH-WebSocket       — WS proxy setup and port config
[3] SSH-TLS (Stunnel)   — TLS on port 443
[4] Cloudflare Domain   — free *.trycloudflare.com domain
[5] Payload Config      — set HTTP payload for NPV Tunnel
[6] User Management     — create/delete/lock/extend/kill
[7] Live Monitor        — real-time connections
[8] Connection Details  — full NPV config info
[9] Service Control     — restart/status all services
[L] Log Viewer          — panel, SSH, WS, CF logs
[B] Backup/Restore      — save and restore config
[I] System Info         — CPU, RAM, disk
[U] Update              — update from GitHub
[X] Uninstall           — full removal
```

---

## Requirements

- Linux (Ubuntu 18.04+ / Debian 9+ recommended)
- Root access
- Open ports: 22, 80, 443, 8880

## Notes

- Users are created VPN-only (`/bin/false` shell) — no terminal access
- SSH config is modified safely — existing ports are never removed
- Auto-expiry cron runs every 5 minutes

## License

MIT
