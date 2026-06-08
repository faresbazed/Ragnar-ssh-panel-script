# SSH VPN Panel

A full-featured SSH VPN panel script for Linux servers, compatible with **NPV Tunnel**, **HTTP Injector**, and similar tunnel apps.

## Features

- **SSH over WebSocket (WS/WSS)** — ports 8880 / 8443
- **SSH over TLS** — port 443 via Stunnel
- **Multi-port SSH** — 22, 80, 443
- **User management** — create, delete, lock, extend expiry
- **Live connection monitor**
- **Firewall/port management**
- **One-click installer**

## Requirements

- Linux server (Debian/Ubuntu recommended)
- Root access
- Open ports: 22, 80, 443, 8880, 8443

## Quick Install

```bash
sudo bash install.sh
```

After install, launch the panel anytime with:

```bash
vpn
```

## NPV Tunnel / HTTP Injector Settings

| Mode | Host | Port |
|------|------|------|
| SSH Direct | your-server-ip | 22 / 80 |
| SSH WebSocket (WS) | your-server-ip | 8880 |
| SSH WebSocket (WSS) | your-server-ip | 8443 |
| SSH over TLS | your-server-ip | 443 |

**Payload (HTTP Injector / NPV Tunnel):**
```
GET / HTTP/1.1[crlf]Host: your-server-ip[crlf][crlf]
```

## Panel Menu

```
[1] Install SSH Services        — sets up OpenSSH on ports 22, 80, 443
[2] SSH-WebSocket Setup         — installs Python WS proxy
[3] SSH-TLS Setup (Stunnel)     — wraps SSH in TLS on port 443
[4] User Management             — create/delete/lock/extend users
[5] Port Management             — add/remove ports, open firewall
[6] Monitor Connections         — live active session monitor
[7] Show Connection Details     — all config info in one view
[8] System Information          — CPU, RAM, disk, uptime
```

## Supported OS

- Ubuntu 18.04 / 20.04 / 22.04
- Debian 9 / 10 / 11
- CentOS 7 / 8 (basic support)

## License

MIT
