#!/bin/bash
# ================================================================
#   RAGNAR SSH VPN PANEL v3.0.0
#   NPV Tunnel Optimized
#   Features: SSH-WS | SSH-TLS | Cloudflare | User Mgmt
#             Auto-Expiry | Conn Limits | Payload Config
#             Backup/Restore | Live Monitor | Log Viewer
#             Bandwidth Monitor | Web Panel | Speed Limits
# ================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
PURPLE='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

PANEL_VERSION="3.0.0"
REPO_RAW="https://raw.githubusercontent.com/faresbazed/Ragnar-ssh-panel-script/main"
CONFIG_DIR="/etc/ssh-vpn-panel"
USER_DB="$CONFIG_DIR/users.db"
LOG_FILE="/var/log/ssh-vpn-panel.log"
CF_DOMAIN_FILE="$CONFIG_DIR/cf_domain.txt"
PAYLOAD_FILE="$CONFIG_DIR/payload.txt"
INSTALL_DIR="/usr/local/ssh-vpn-panel"
WS_PORT_FILE="$CONFIG_DIR/ws_port.txt"
WEB_PORT_FILE="$CONFIG_DIR/web_port.txt"
WEB_PASS_FILE="$CONFIG_DIR/web_pass.txt"

# ── Helpers ──────────────────────────────────────────────────────

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"; }

check_root() {
    [[ $EUID -ne 0 ]] && { echo -e "${RED}Run as root.${NC}"; exit 1; }
}

init_panel() {
    mkdir -p "$CONFIG_DIR" "$INSTALL_DIR"
    touch "$USER_DB" "$LOG_FILE"
    [[ ! -f "$WS_PORT_FILE" ]] && echo "80" > "$WS_PORT_FILE"
    [[ ! -f "$WEB_PORT_FILE" ]] && echo "8080" > "$WEB_PORT_FILE"
    [[ ! -f "$PAYLOAD_FILE" ]] && echo "GET / HTTP/1.1[crlf]Host: [host][crlf]Upgrade: websocket[crlf][crlf]" > "$PAYLOAD_FILE"
    setup_expiry_cron
}

detect_os() {
    if   [[ -f /etc/debian_version ]]; then PKG_MANAGER="apt-get"; OS="debian"
    elif [[ -f /etc/redhat-release ]]; then PKG_MANAGER="yum";     OS="redhat"
    else                                    PKG_MANAGER="apt-get"; OS="unknown"; fi
}

get_public_ip() {
    curl -s --max-time 5 https://api.ipify.org 2>/dev/null || \
    curl -s --max-time 5 https://ifconfig.me   2>/dev/null || \
    echo "Unknown"
}

svc_status() {
    systemctl is-active --quiet "$1" 2>/dev/null && echo -e "${GREEN}●${NC}" || echo -e "${RED}●${NC}"
}

get_ws_port()  { cat "$WS_PORT_FILE"  2>/dev/null || echo "80"; }
get_web_port() { cat "$WEB_PORT_FILE" 2>/dev/null || echo "8080"; }

# ── Banner ───────────────────────────────────────────────────────

banner() {
    clear
    local IP; IP=$(get_public_ip)
    local S_SSH; S_SSH=$(svc_status ssh)
    local S_WS;  S_WS=$(svc_status ssh-ws)
    local S_TLS; S_TLS=$(svc_status stunnel4)
    local S_CF;  S_CF=$(svc_status cloudflared-tunnel)
    local S_WEB; S_WEB=$(svc_status ragnar-web)
    local CF_DOM; CF_DOM=$(cat "$CF_DOMAIN_FILE" 2>/dev/null | sed 's|https://||' || echo "Not set")
    echo -e "${CYAN}"
    echo "  ╔══════════════════════════════════════════════════════════╗"
    printf "  ║  %bRAGNAR SSH VPN PANEL%b %-6s %30s ║\n" "$BOLD$WHITE" "$CYAN" "v${PANEL_VERSION}" ""
    echo "  ╠══════════════════════════════════════════════════════════╣"
    printf "  ║  IP  : %-20s  Date: %-20s║\n" "${WHITE}${IP}${CYAN}" "${WHITE}$(date '+%d/%m/%y %H:%M:%S')${CYAN}"
    printf "  ║  WS  : %-6s  TLS: %-6s  CF: %-18s║\n" \
        "$(get_ws_port)" "443" "${CF_DOM:0:18}"
    printf "  ║  %b SSH %b%b WS %b%b TLS %b%b CF %b%b WEB %b  Services Status         ║\n" \
        "$NC" "$S_SSH" "$NC" "$S_WS" "$NC" "$S_TLS" "$NC" "$S_CF" "$NC" "$S_WEB"
    echo -e "  ╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# ── Main Menu ────────────────────────────────────────────────────

main_menu() {
    banner
    echo -e "${WHITE}  ┌──────────────────────────────────────────┐${NC}"
    echo -e "${WHITE}  │           NPV TUNNEL PANEL               │${NC}"
    echo -e "${WHITE}  ├──────────────────────────────────────────┤${NC}"
    echo -e "${WHITE}  │ ${GREEN}[1]${WHITE} Full Setup (Install Everything)    │${NC}"
    echo -e "${WHITE}  │ ${GREEN}[2]${WHITE} SSH-WebSocket (WS/WSS)            │${NC}"
    echo -e "${WHITE}  │ ${GREEN}[3]${WHITE} SSH-TLS (Stunnel port 443)        │${NC}"
    echo -e "${WHITE}  │ ${CYAN}[4]${WHITE} Cloudflare Free Domain            │${NC}"
    echo -e "${WHITE}  │ ${GREEN}[5]${WHITE} Payload Configurator              │${NC}"
    echo -e "${WHITE}  ├──────────────────────────────────────────┤${NC}"
    echo -e "${WHITE}  │ ${GREEN}[6]${WHITE} User Management                  │${NC}"
    echo -e "${WHITE}  │ ${GREEN}[7]${WHITE} Live Connection Monitor           │${NC}"
    echo -e "${WHITE}  │ ${GREEN}[8]${WHITE} Connection Details (NPV Config)   │${NC}"
    echo -e "${WHITE}  ├──────────────────────────────────────────┤${NC}"
    echo -e "${WHITE}  │ ${PURPLE}[W]${WHITE} Web Panel (Browser UI)           │${NC}"
    echo -e "${WHITE}  │ ${PURPLE}[N]${WHITE} Bandwidth Monitor                │${NC}"
    echo -e "${WHITE}  ├──────────────────────────────────────────┤${NC}"
    echo -e "${WHITE}  │ ${GREEN}[9]${WHITE} Service Control                  │${NC}"
    echo -e "${WHITE}  │ ${GREEN}[L]${WHITE} Log Viewer                       │${NC}"
    echo -e "${WHITE}  │ ${GREEN}[B]${WHITE} Backup / Restore                 │${NC}"
    echo -e "${WHITE}  │ ${GREEN}[I]${WHITE} System Info                      │${NC}"
    echo -e "${WHITE}  ├──────────────────────────────────────────┤${NC}"
    echo -e "${WHITE}  │ ${YELLOW}[U]${WHITE} Update Panel                     │${NC}"
    echo -e "${WHITE}  │ ${RED}[X]${WHITE} Uninstall Panel                  │${NC}"
    echo -e "${WHITE}  │ ${RED}[0]${WHITE} Exit                             │${NC}"
    echo -e "${WHITE}  └──────────────────────────────────────────┘${NC}"
    echo -ne "\n  ${YELLOW}Select: ${NC}"
    read -r OPT
    case ${OPT,,} in
        1) full_setup ;;
        2) ws_menu ;;
        3) setup_stunnel ;;
        4) cloudflare_menu ;;
        5) payload_configurator ;;
        6) user_management_menu ;;
        7) monitor_connections ;;
        8) show_connection_details ;;
        w) web_panel_menu ;;
        n) bandwidth_monitor ;;
        9) service_control_menu ;;
        l) log_viewer ;;
        b) backup_restore_menu ;;
        i) system_info ;;
        u) update_panel ;;
        x) uninstall_panel ;;
        0) echo -e "\n${GREEN}Goodbye!${NC}\n"; exit 0 ;;
        *) echo -e "${RED}Invalid.${NC}"; sleep 1; main_menu ;;
    esac
}

# ── [1] Full Setup ───────────────────────────────────────────────

full_setup() {
    banner
    echo -e "${CYAN}  [*] Full NPV Tunnel Setup${NC}\n"
    detect_os

    echo -e "${YELLOW}  [1/7] Updating packages...${NC}"
    $PKG_MANAGER update -y >> "$LOG_FILE" 2>&1

    echo -e "${YELLOW}  [2/7] Installing dependencies...${NC}"
    $PKG_MANAGER install -y openssh-server curl wget python3 python3-pip \
        stunnel4 net-tools iptables openssl cron vnstat >> "$LOG_FILE" 2>&1

    echo -e "${YELLOW}  [3/7] Configuring SSH (safe, preserves your ports)...${NC}"
    configure_ssh_safe

    echo -e "${YELLOW}  [4/7] Setting up SSH-WebSocket on port 80...${NC}"
    deploy_ws_proxy 80

    echo -e "${YELLOW}  [5/7] Setting up SSH-TLS (Stunnel) on port 443...${NC}"
    deploy_stunnel_silent

    echo -e "${YELLOW}  [6/7] Setting up auto-expiry cron...${NC}"
    setup_expiry_cron

    echo -e "${YELLOW}  [7/7] Initializing bandwidth tracking (vnstat)...${NC}"
    local IFACE; IFACE=$(ip route get 1 2>/dev/null | awk '{print $5; exit}')
    [[ -n "$IFACE" ]] && vnstat -i "$IFACE" --add >> "$LOG_FILE" 2>&1 || true

    systemctl daemon-reload
    systemctl enable ssh ssh-ws ssh-wss stunnel4 >> "$LOG_FILE" 2>&1
    systemctl restart ssh ssh-ws ssh-wss stunnel4 >> "$LOG_FILE" 2>&1

    local IP; IP=$(get_public_ip)
    echo -e "\n  ${GREEN}[✓] Full setup complete!${NC}"
    echo -e "\n  ${WHITE}┌──────────────────────────────────────────────────┐"
    echo -e "  │  NPV Tunnel Settings:                            │"
    echo -e "  │  SSH Host   : ${IP}"
    echo -e "  │  SSH Port   : 22"
    echo -e "  │  WS Host    : ${IP}"
    echo -e "  │  WS Port    : 80"
    echo -e "  │  TLS Port   : 443"
    echo -e "  │  Payload    : $(cat "$PAYLOAD_FILE" 2>/dev/null)"
    echo -e "  └──────────────────────────────────────────────────┘${NC}"
    log "Full setup completed"
    read -rp "  Press Enter to continue..."
    main_menu
}

configure_ssh_safe() {
    local CFG="/etc/ssh/sshd_config"
    cp "$CFG" "${CFG}.backup.$(date +%Y%m%d%H%M%S)" 2>/dev/null

    # Port 80 reserved for ssh-ws proxy — NOT added to sshd

    sed -i '/^#*PasswordAuthentication/c\PasswordAuthentication yes' "$CFG"
    sed -i '/^#*ChallengeResponseAuthentication/c\ChallengeResponseAuthentication no' "$CFG"
    sed -i '/^#*ClientAliveInterval/c\ClientAliveInterval 60' "$CFG"
    sed -i '/^#*ClientAliveCountMax/c\ClientAliveCountMax 3' "$CFG"
    sed -i '/^#*MaxSessions/c\MaxSessions 50' "$CFG"

    grep -q "^PasswordAuthentication"  "$CFG" || echo "PasswordAuthentication yes"  >> "$CFG"
    grep -q "^ClientAliveInterval"     "$CFG" || echo "ClientAliveInterval 60"     >> "$CFG"
    grep -q "^MaxSessions"             "$CFG" || echo "MaxSessions 50"             >> "$CFG"

    cat > /etc/ssh/banner << 'BNRTXT'
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  RAGNAR VPN SERVER — NPV Tunnel
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
BNRTXT
    grep -q "^Banner" "$CFG" || echo "Banner /etc/ssh/banner" >> "$CFG"
    systemctl restart ssh >> "$LOG_FILE" 2>&1
}

# ── [2] WebSocket Menu ───────────────────────────────────────────

ws_menu() {
    banner
    local WS_P; WS_P=$(get_ws_port)
    echo -e "${WHITE}  ┌──────────────────────────────────────┐${NC}"
    echo -e "${WHITE}  │        SSH WEBSOCKET (NPV WS)        │${NC}"
    echo -e "${WHITE}  ├──────────────────────────────────────┤${NC}"
    echo -e "${WHITE}  │  Current WS Port : ${CYAN}${WS_P}${WHITE}"
    echo -e "${WHITE}  ├──────────────────────────────────────┤${NC}"
    echo -e "${WHITE}  │ ${GREEN}[1]${WHITE} Install / Reinstall WS Proxy     │${NC}"
    echo -e "${WHITE}  │ ${GREEN}[2]${WHITE} Change WS Port                   │${NC}"
    echo -e "${WHITE}  │ ${GREEN}[3]${WHITE} Restart WS Service               │${NC}"
    echo -e "${WHITE}  │ ${GREEN}[4]${WHITE} View WS Logs                     │${NC}"
    echo -e "${WHITE}  │ ${RED}[0]${WHITE} Back                             │${NC}"
    echo -e "${WHITE}  └──────────────────────────────────────┘${NC}"
    echo -ne "\n  ${YELLOW}Select: ${NC}"; read -r OPT
    case $OPT in
        1) setup_websocket_full ;;
        2) change_ws_port ;;
        3) systemctl restart ssh-ws ssh-wss; echo -e "  ${GREEN}[✓] Restarted.${NC}"; sleep 1; ws_menu ;;
        4) journalctl -u ssh-ws -n 30 --no-pager; read -rp "  Enter to continue..."; ws_menu ;;
        0) main_menu ;;
        *) ws_menu ;;
    esac
}

deploy_ws_proxy() {
    local PORT="${1:-80}"
    echo "$PORT" > "$WS_PORT_FILE"

    cat > /usr/local/bin/ssh-ws-proxy.py << 'PYEOF'
#!/usr/bin/env python3
"""
Ragnar SSH-WebSocket Proxy v4 — Universal NPV Tunnel Handler

Non-destructive MSG_PEEK protocol detection. Handles:
  GET, POST, CONNECT, CF-RAY, any custom method, raw SSH, binary.
Double-header NPV sequences handled with 3s grace period.
IPv6 dual-stack (covers both :: and 0.0.0.0 in one socket).
"""
import socket, threading, select, sys

SSH_HOST = '127.0.0.1'
SSH_PORT = 22
BUFFER   = 65536
TIMEOUT  = 120

WS_101      = (b"HTTP/1.1 101 Switching Protocols\r\n"
               b"Upgrade: websocket\r\n"
               b"Connection: Upgrade\r\n\r\n")
CONNECT_200 = b"HTTP/1.1 200 Connection established\r\n\r\n"


def pipe(src, dst, stop):
    try:
        while not stop.is_set():
            r, _, _ = select.select([src], [], [], 10)
            if not r:
                continue
            data = src.recv(BUFFER)
            if not data:
                break
            dst.sendall(data)
    except Exception:
        pass
    finally:
        stop.set()


def relay(client, ssh, initial=b""):
    """Bidirectional pipe; forward any initial bytes to SSH first."""
    try:
        if initial:
            ssh.sendall(initial)
    except Exception:
        return
    stop = threading.Event()
    t1 = threading.Thread(target=pipe, args=(client, ssh, stop), daemon=True)
    t2 = threading.Thread(target=pipe, args=(ssh, client, stop), daemon=True)
    t1.start()
    t2.start()
    stop.wait()


def read_http_request(sock):
    """
    Read a complete HTTP request from the client.

    NPV Tunnel quirks handled:
      - Double-segment: first segment GET/HEAD/etc + second CF-RAY/Upgrade segment
      - We wait up to 3 s for the second segment, 1 s for a third
      - Everything after the last \\r\\n\\r\\n is leftover SSH data

    Returns: (headers_text: str, leftover: bytes)
    """
    buf = b""
    sock.settimeout(5)
    try:
        # Phase 1: read until we have a complete first segment
        while b'\r\n\r\n' not in buf and len(buf) < 65536:
            chunk = sock.recv(4096)
            if not chunk:
                break
            buf += chunk

        if b'\r\n\r\n' not in buf:
            sock.settimeout(TIMEOUT)
            return buf.decode('utf-8', errors='ignore'), b""

        # Phase 2: NPV Tunnel second segment (CF-RAY / custom payload)
        # Wait up to 3 s for it to arrive
        sock.settimeout(3.0)
        try:
            extra = sock.recv(4096)
            if extra:
                buf += extra
        except socket.timeout:
            pass

        # Phase 3: optional third segment (rare)
        if buf.count(b'\r\n\r\n') >= 2:
            sock.settimeout(1.0)
            try:
                extra = sock.recv(4096)
                if extra:
                    buf += extra
            except socket.timeout:
                pass

    except socket.timeout:
        pass
    finally:
        sock.settimeout(TIMEOUT)

    last_end = buf.rfind(b'\r\n\r\n')
    if last_end >= 0:
        headers  = buf[:last_end].decode('utf-8', errors='ignore')
        leftover = buf[last_end + 4:]
    else:
        headers  = buf.decode('utf-8', errors='ignore')
        leftover = b""
    return headers, leftover


def choose_response(headers):
    """CONNECT -> 200; everything else (GET/POST/CF-RAY/custom) -> 101."""
    for line in headers.splitlines():
        if line.strip().upper().startswith('CONNECT'):
            return CONNECT_200
    return WS_101


def drain_late_http(sock):
    """
    After sending 101/200, absorb any late-arriving stale HTTP bytes.
    Real SSH handshake data (doesn't contain bare \\r\\n or starts with SSH-)
    is returned as leftover.
    """
    sock.settimeout(0.8)
    try:
        chunk = sock.recv(4096)
        if chunk:
            if b'\r\n' in chunk[:256] and not chunk.lstrip().startswith(b'SSH-'):
                end = chunk.find(b'\r\n\r\n')
                return chunk[end + 4:] if end >= 0 else b""
            return chunk
    except socket.timeout:
        pass
    finally:
        sock.settimeout(TIMEOUT)
    return b""


def handle(client):
    ssh = None
    try:
        client.settimeout(TIMEOUT)

        # Non-destructive peek — detect protocol without consuming bytes
        client.settimeout(5)
        try:
            first = client.recv(4096, socket.MSG_PEEK)
        except socket.timeout:
            return
        finally:
            client.settimeout(TIMEOUT)

        if not first:
            return

        # ── Case 1: Plain SSH client (sends banner like "SSH-2.0-OpenSSH...") ──
        if first.lstrip()[:4] == b'SSH-':
            ssh = socket.create_connection((SSH_HOST, SSH_PORT), timeout=10)
            ssh.settimeout(TIMEOUT)
            relay(client, ssh)
            return

        # ── Case 2: Any HTTP method (GET, POST, CONNECT, CF-RAY, etc.) ──
        if b'\r\n' in first[:512] or b'HTTP' in first[:32] or b' / ' in first[:32]:
            headers, leftover = read_http_request(client)
            resp = choose_response(headers)
            client.sendall(resp)

            late = drain_late_http(client)
            if late:
                leftover = leftover + late

            ssh = socket.create_connection((SSH_HOST, SSH_PORT), timeout=10)
            ssh.settimeout(TIMEOUT)
            relay(client, ssh, leftover)
            return

        # ── Case 3: Binary / unknown — pipe directly ──
        raw = client.recv(BUFFER)
        ssh = socket.create_connection((SSH_HOST, SSH_PORT), timeout=10)
        ssh.settimeout(TIMEOUT)
        relay(client, ssh, raw)

    except Exception:
        pass
    finally:
        for s in (client, ssh):
            if s:
                try:
                    s.close()
                except Exception:
                    pass


def make_server(port):
    """Create a listening socket, preferring IPv6 dual-stack."""
    if socket.has_ipv6:
        try:
            srv = socket.socket(socket.AF_INET6, socket.SOCK_STREAM)
            srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            srv.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
            srv.bind(('::', port))
            return srv
        except Exception:
            try:
                srv.close()
            except Exception:
                pass
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(('0.0.0.0', port))
    return srv


def serve(port):
    srv = make_server(port)
    srv.listen(2048)
    print(f"[Ragnar-WS v4] :{port} -> SSH:{SSH_PORT}", flush=True)
    while True:
        try:
            c, _ = srv.accept()
            threading.Thread(target=handle, args=(c,), daemon=True).start()
        except Exception as e:
            print(f"[ERR] {e}", flush=True)


if __name__ == '__main__':
    serve(int(sys.argv[1]) if len(sys.argv) > 1 else 80)

PYEOF
    chmod +x /usr/local/bin/ssh-ws-proxy.py

    # Remove WS port from sshd_config if present (fixes existing servers)
    local SSHD_CFG="/etc/ssh/sshd_config"
    if grep -q "^Port ${PORT}$" "$SSHD_CFG" 2>/dev/null; then
        echo -e "  ${YELLOW}[!] Removing Port ${PORT} from sshd (conflicts with WS proxy)...${NC}"
        sed -i "/^Port ${PORT}$/d" "$SSHD_CFG"
        systemctl restart ssh >> "$LOG_FILE" 2>&1
        sleep 1
    fi
    # Kill anything already using the WS port
    local PIDS; PIDS=$(ss -tlnp "sport = :${PORT}" 2>/dev/null | awk 'NR>1{print $NF}' | grep -oP 'pid=\K[0-9]+')
    if [[ -n "$PIDS" ]]; then
        echo -e "  ${YELLOW}[!] Port ${PORT} in use — clearing...${NC}"
        echo "$PIDS" | xargs -r kill -9 2>/dev/null
        for SVC in nginx apache2 apache httpd lighttpd; do
            systemctl stop "$SVC" 2>/dev/null && systemctl disable "$SVC" 2>/dev/null \
                && echo -e "  ${YELLOW}[!] Stopped ${SVC}${NC}"
        done
        sleep 1
    fi

    cat > /etc/systemd/system/ssh-ws.service << SVCEOF
[Unit]
Description=Ragnar SSH-WebSocket Proxy v4 (port ${PORT})
After=network.target ssh.service

[Service]
Type=simple
ExecStart=/usr/bin/python3 /usr/local/bin/ssh-ws-proxy.py ${PORT}
Restart=always
RestartSec=5
User=root
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SVCEOF

    cat > /etc/systemd/system/ssh-wss.service << 'SVCEOF2'
[Unit]
Description=Ragnar SSH-WebSocket Proxy v4 fallback (port 8880)
After=network.target ssh.service

[Service]
Type=simple
ExecStart=/usr/bin/python3 /usr/local/bin/ssh-ws-proxy.py 8880
Restart=always
RestartSec=5
User=root
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SVCEOF2

    systemctl daemon-reload
    systemctl enable ssh-ws ssh-wss >> "$LOG_FILE" 2>&1
    systemctl restart ssh-ws ssh-wss >> "$LOG_FILE" 2>&1
}

setup_websocket_full() {
    banner
    echo -e "${CYAN}  [*] Installing SSH-WebSocket Proxy v3...${NC}\n"
    echo -ne "  ${YELLOW}WS Port [80]: ${NC}"; read -r WS_PORT
    WS_PORT=${WS_PORT:-80}
    deploy_ws_proxy "$WS_PORT"
    local IP; IP=$(get_public_ip)
    echo -e "\n  ${GREEN}[✓] WebSocket proxy v3 deployed on port ${WS_PORT}!${NC}"
    echo -e "  WS URL  : ws://${IP}:${WS_PORT}"
    echo -e "  WSS URL : ws://${IP}:8880 (fallback)"
    log "WS proxy v3 installed on port $WS_PORT"
    read -rp "  Press Enter..."; ws_menu
}

change_ws_port() {
    banner
    echo -ne "  ${YELLOW}New WS port: ${NC}"; read -r NEW_PORT
    [[ ! "$NEW_PORT" =~ ^[0-9]+$ ]] && { echo -e "${RED}Invalid.${NC}"; sleep 1; ws_menu; return; }
    deploy_ws_proxy "$NEW_PORT"
    echo -e "  ${GREEN}[✓] WS port changed to ${NEW_PORT}.${NC}"
    log "WS port changed to $NEW_PORT"
    read -rp "  Press Enter..."; ws_menu
}

# ── [3] Stunnel TLS ──────────────────────────────────────────────

deploy_stunnel_silent() {
    detect_os
    $PKG_MANAGER install -y stunnel4 openssl >> "$LOG_FILE" 2>&1
    mkdir -p /etc/stunnel /var/run/stunnel4 /var/log/stunnel4

    local CFG="/etc/ssh/sshd_config"
    if grep -q "^Port 443$" "$CFG"; then
        sed -i '/^Port 443$/d' "$CFG"
        systemctl restart ssh >> "$LOG_FILE" 2>&1
        echo -e "  ${YELLOW}[!] Removed Port 443 from SSH (Stunnel takes 443)${NC}"
    fi

    local PIDS443; PIDS443=$(ss -tlnp "sport = :443" 2>/dev/null | awk 'NR>1{print $NF}' | grep -oP 'pid=\K[0-9]+')
    if [[ -n "$PIDS443" ]]; then
        echo -e "  ${YELLOW}[!] Clearing port 443...${NC}"
        echo "$PIDS443" | xargs -r kill -9 2>/dev/null
        sleep 1
    fi

    local IP; IP=$(get_public_ip)
    openssl req -new -x509 -days 3650 -nodes \
        -out /etc/stunnel/stunnel.pem -keyout /etc/stunnel/stunnel.pem \
        -subj "/C=US/O=RagnarVPN/CN=${IP}" >> "$LOG_FILE" 2>&1
    chmod 600 /etc/stunnel/stunnel.pem

    cat > /etc/stunnel/stunnel.conf << 'STLCONF'
pid     = /var/run/stunnel4/stunnel4.pid
output  = /var/log/stunnel4/stunnel.log
socket  = l:TCP_NODELAY=1
socket  = r:TCP_NODELAY=1
foreground = no

[npv-tls]
accept  = 0.0.0.0:443
connect = 127.0.0.1:22
cert    = /etc/stunnel/stunnel.pem
TIMEOUTclose = 0
sslVersion = all
options = NO_SSLv2
options = NO_SSLv3
STLCONF

    sed -i 's/^ENABLED=0/ENABLED=1/' /etc/default/stunnel4 2>/dev/null
    systemctl daemon-reload
    systemctl enable stunnel4 >> "$LOG_FILE" 2>&1
    systemctl restart stunnel4 >> "$LOG_FILE" 2>&1
}

setup_stunnel() {
    banner
    echo -e "${CYAN}  [*] SSH-TLS Setup (Stunnel port 443)...${NC}\n"
    deploy_stunnel_silent
    local IP; IP=$(get_public_ip)
    echo -e "  ${GREEN}[✓] Stunnel running on port 443!${NC}"
    echo -e "\n  ${WHITE}NPV Tunnel TLS Settings:"
    echo -e "  ┌─────────────────────────────────────────┐"
    echo -e "  │  TLS Host : ${IP}"
    echo -e "  │  TLS Port : 443"
    echo -e "  │  SSH Port : 22 (via TLS)"
    echo -e "  │  TLS Cert : Self-signed (skip verify)"
    echo -e "  └─────────────────────────────────────────┘${NC}"
    log "Stunnel TLS setup"
    read -rp "  Press Enter..."; main_menu
}

# ── [4] Cloudflare ───────────────────────────────────────────────

cloudflare_menu() {
    banner
    local CF_S; CF_S="$(svc_status cloudflared-tunnel) $(systemctl is-active cloudflared-tunnel 2>/dev/null)"
    local CF_DOM; CF_DOM=$(cat "$CF_DOMAIN_FILE" 2>/dev/null || echo "None")
    echo -e "${WHITE}  ┌──────────────────────────────────────┐${NC}"
    echo -e "${WHITE}  │      CLOUDFLARE FREE DOMAIN          │${NC}"
    echo -e "${WHITE}  ├──────────────────────────────────────┤${NC}"
    echo -e "  │  Status : ${CF_S}"
    echo -e "  │  Domain : ${CYAN}${CF_DOM}${NC}"
    echo -e "${WHITE}  ├──────────────────────────────────────┤${NC}"
    echo -e "${WHITE}  │ ${GREEN}[1]${WHITE} Install & Start Tunnel            │${NC}"
    echo -e "${WHITE}  │ ${GREEN}[2]${WHITE} Show Domain / NPV Config          │${NC}"
    echo -e "${WHITE}  │ ${GREEN}[3]${WHITE} Restart (get new domain)          │${NC}"
    echo -e "${WHITE}  │ ${RED}[4]${WHITE} Stop Tunnel                      │${NC}"
    echo -e "${WHITE}  │ ${RED}[5]${WHITE} Uninstall cloudflared            │${NC}"
    echo -e "${WHITE}  │ ${RED}[0]${WHITE} Back                             │${NC}"
    echo -e "${WHITE}  └──────────────────────────────────────┘${NC}"
    echo -ne "\n  ${YELLOW}Select: ${NC}"; read -r OPT
    case $OPT in
        1) install_cloudflare ;;
        2) show_cf_domain ;;
        3) restart_cf_tunnel ;;
        4) systemctl stop cloudflared-tunnel; systemctl disable cloudflared-tunnel
           echo -e "  ${YELLOW}Stopped.${NC}"; sleep 1; cloudflare_menu ;;
        5) uninstall_cloudflare ;;
        0) main_menu ;;
        *) cloudflare_menu ;;
    esac
}

install_cloudflare() {
    banner
    echo -e "${CYAN}  [*] Setting up Cloudflare Free Tunnel...${NC}\n"

    if ! command -v cloudflared &>/dev/null; then
        echo -e "${YELLOW}  Downloading cloudflared...${NC}"
        local ARCH; ARCH=$(uname -m)
        case "$ARCH" in
            x86_64)  CF_ARCH="amd64" ;;
            aarch64) CF_ARCH="arm64" ;;
            armv7l)  CF_ARCH="arm"   ;;
            *)       CF_ARCH="amd64" ;;
        esac
        curl -sSL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CF_ARCH}" \
            -o /usr/local/bin/cloudflared >> "$LOG_FILE" 2>&1
        chmod +x /usr/local/bin/cloudflared
        command -v cloudflared &>/dev/null || {
            echo -e "${RED}Install failed.${NC}"; read -rp "Enter..."; cloudflare_menu; return
        }
        echo -e "  ${GREEN}[✓] cloudflared installed.${NC}"
    else
        echo -e "  ${GREEN}[✓] cloudflared already present.${NC}"
    fi

    local WS_P; WS_P=$(get_ws_port)
    cat > /etc/systemd/system/cloudflared-tunnel.service << CFSVC
[Unit]
Description=Cloudflare Quick Tunnel -> SSH-WS port ${WS_P}
After=network.target ssh-ws.service

[Service]
Type=simple
ExecStart=/usr/local/bin/cloudflared tunnel --url http://localhost:${WS_P} --no-autoupdate --loglevel info
Restart=always
RestartSec=10
User=root
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
CFSVC

    systemctl daemon-reload
    systemctl enable cloudflared-tunnel >> "$LOG_FILE" 2>&1
    systemctl restart cloudflared-tunnel >> "$LOG_FILE" 2>&1

    echo -e "  ${YELLOW}Waiting for Cloudflare domain (up to 30s)...${NC}"
    local CF_DOM=""
    for i in $(seq 1 10); do
        sleep 3
        CF_DOM=$(journalctl -u cloudflared-tunnel --no-pager -n 80 2>/dev/null | \
            grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' | tail -1)
        [[ -n "$CF_DOM" ]] && break
        echo -ne "  Attempt ${i}/10...\r"
    done

    if [[ -n "$CF_DOM" ]]; then
        echo "$CF_DOM" > "$CF_DOMAIN_FILE"
        echo -e "\n  ${GREEN}[✓] Cloudflare tunnel LIVE!${NC}"
        echo -e "  Domain: ${CYAN}${CF_DOM}${NC}"
        _print_npv_cf_config "$CF_DOM"
    else
        echo -e "\n  ${YELLOW}Domain not detected yet. Use [2] in a moment.${NC}"
    fi
    log "Cloudflare tunnel started"
    read -rp "  Press Enter..."; cloudflare_menu
}

_print_npv_cf_config() {
    local DOM="$1"
    local BARE; BARE=$(echo "$DOM" | sed 's|https://||')
    local IP; IP=$(get_public_ip)
    local PAYLOAD; PAYLOAD=$(cat "$PAYLOAD_FILE" 2>/dev/null)
    echo -e "\n  ${WHITE}┌──────────────────────────────────────────────────────┐"
    echo -e "  │  NPV Tunnel Settings (Cloudflare WS mode):           │"
    echo -e "  ├──────────────────────────────────────────────────────┤"
    echo -e "  │  SSH Host    : ${IP}"
    echo -e "  │  SSH Port    : 22"
    echo -e "  ├──────────────────────────────────────────────────────┤"
    echo -e "  │  Network     : WebSocket"
    echo -e "  │  WS Host     : ${BARE}"
    echo -e "  │  WS Port     : 443"
    echo -e "  │  SSL/TLS     : ON  (Cloudflare handles it)"
    echo -e "  ├──────────────────────────────────────────────────────┤"
    echo -e "  │  Payload     : ${PAYLOAD}"
    echo -e "  ├──────────────────────────────────────────────────────┤"
    echo -e "  │  NOTE: WS Host is the Cloudflare domain, NOT your IP │"
    echo -e "  │  SSH Host is still your real server IP               │"
    echo -e "  └──────────────────────────────────────────────────────┘${NC}"
}

show_cf_domain() {
    banner
    local CF_DOM
    CF_DOM=$(journalctl -u cloudflared-tunnel --no-pager -n 100 2>/dev/null | \
        grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' | tail -1)
    [[ -z "$CF_DOM" ]] && CF_DOM=$(cat "$CF_DOMAIN_FILE" 2>/dev/null)
    if [[ -z "$CF_DOM" ]]; then
        echo -e "  ${RED}No domain found. Is the tunnel running?${NC}"
        read -rp "  Press Enter..."; cloudflare_menu; return
    fi
    echo "$CF_DOM" > "$CF_DOMAIN_FILE"
    _print_npv_cf_config "$CF_DOM"
    read -rp "  Press Enter..."; cloudflare_menu
}

restart_cf_tunnel() {
    banner
    echo -e "${YELLOW}  Restarting Cloudflare tunnel...${NC}"
    systemctl restart cloudflared-tunnel
    sleep 5
    show_cf_domain
}

uninstall_cloudflare() {
    systemctl stop cloudflared-tunnel 2>/dev/null
    systemctl disable cloudflared-tunnel 2>/dev/null
    rm -f /etc/systemd/system/cloudflared-tunnel.service /usr/local/bin/cloudflared "$CF_DOMAIN_FILE"
    systemctl daemon-reload
    echo -e "  ${GREEN}[✓] cloudflared removed.${NC}"
    log "cloudflared uninstalled"
    read -rp "  Press Enter..."; cloudflare_menu
}

# ── [5] Payload Configurator ──────────────────────────────────────

payload_configurator() {
    banner
    local CURRENT; CURRENT=$(cat "$PAYLOAD_FILE" 2>/dev/null)
    echo -e "${CYAN}  [*] NPV Tunnel Payload Configurator${NC}\n"
    echo -e "  Current payload:"
    echo -e "  ${CYAN}${CURRENT}${NC}\n"
    echo -e "  ${WHITE}Common payloads for NPV Tunnel:${NC}"
    echo -e "  ${GREEN}[1]${NC} GET / HTTP/1.1[crlf]Host: [host][crlf]Upgrade: websocket[crlf][crlf]"
    echo -e "  ${GREEN}[2]${NC} CONNECT [host]:22 HTTP/1.1[crlf]Host: [host][crlf][crlf]"
    echo -e "  ${GREEN}[3]${NC} GET wss://[host]/ HTTP/1.1[crlf]Host: [host][crlf]Upgrade: websocket[crlf][crlf]"
    echo -e "  ${GREEN}[4]${NC} GET / HTTP/1.1[crlf]Host: [host][crlf]X-Forward-Host: [host][crlf]Upgrade: websocket[crlf][crlf]"
    echo -e "  ${GREEN}[5]${NC} Enter custom payload"
    echo -e "  ${RED}[0]${NC} Back\n"
    echo -ne "  ${YELLOW}Select: ${NC}"; read -r OPT
    local PAYLOAD
    case $OPT in
        1) PAYLOAD="GET / HTTP/1.1[crlf]Host: [host][crlf]Upgrade: websocket[crlf][crlf]" ;;
        2) PAYLOAD="CONNECT [host]:22 HTTP/1.1[crlf]Host: [host][crlf][crlf]" ;;
        3) PAYLOAD="GET wss://[host]/ HTTP/1.1[crlf]Host: [host][crlf]Upgrade: websocket[crlf][crlf]" ;;
        4) PAYLOAD="GET / HTTP/1.1[crlf]Host: [host][crlf]X-Forward-Host: [host][crlf]Upgrade: websocket[crlf][crlf]" ;;
        5) echo -ne "  Enter payload (use [crlf] for line breaks): "; read -r PAYLOAD ;;
        0) main_menu; return ;;
        *) payload_configurator; return ;;
    esac
    echo "$PAYLOAD" > "$PAYLOAD_FILE"
    echo -e "  ${GREEN}[✓] Payload saved!${NC}"
    log "Payload updated: $PAYLOAD"
    read -rp "  Press Enter..."; main_menu
}

# ── [6] User Management ───────────────────────────────────────────

user_management_menu() {
    banner
    echo -e "${WHITE}  ┌──────────────────────────────────────┐${NC}"
    echo -e "${WHITE}  │        USER MANAGEMENT               │${NC}"
    echo -e "${WHITE}  ├──────────────────────────────────────┤${NC}"
    echo -e "${WHITE}  │ ${GREEN}[1]${WHITE} Create User                      │${NC}"
    echo -e "${WHITE}  │ ${GREEN}[2]${WHITE} Delete User                      │${NC}"
    echo -e "${WHITE}  │ ${GREEN}[3]${WHITE} Extend Expiry                    │${NC}"
    echo -e "${WHITE}  │ ${GREEN}[4]${WHITE} Lock / Unlock User               │${NC}"
    echo -e "${WHITE}  │ ${GREEN}[5]${WHITE} Kill User Sessions                │${NC}"
    echo -e "${WHITE}  │ ${GREEN}[6]${WHITE} List All Users                   │${NC}"
    echo -e "${WHITE}  │ ${GREEN}[7]${WHITE} Check User Details               │${NC}"
    echo -e "${WHITE}  │ ${GREEN}[8]${WHITE} Run Expiry Cleanup Now           │${NC}"
    echo -e "${WHITE}  │ ${PURPLE}[9]${WHITE} Set Speed Limit for User        │${NC}"
    echo -e "${WHITE}  │ ${RED}[0]${WHITE} Back                             │${NC}"
    echo -e "${WHITE}  └──────────────────────────────────────┘${NC}"
    echo -ne "\n  ${YELLOW}Select: ${NC}"; read -r OPT
    case $OPT in
        1) create_user ;;
        2) delete_user ;;
        3) extend_user ;;
        4) lock_unlock_user ;;
        5) kill_user_sessions ;;
        6) list_users ;;
        7) check_user ;;
        8) run_expiry_cleanup; read -rp "  Press Enter..."; user_management_menu ;;
        9) set_speed_limit ;;
        0) main_menu ;;
        *) user_management_menu ;;
    esac
}

create_user() {
    banner
    echo -e "${CYAN}  [*] Create NPV Tunnel User${NC}\n"
    echo -ne "  ${YELLOW}Username  : ${NC}"; read -r USERNAME
    [[ -z "$USERNAME" ]] && { echo -e "${RED}Empty.${NC}"; sleep 1; user_management_menu; return; }
    id "$USERNAME" &>/dev/null && { echo -e "${RED}User exists.${NC}"; sleep 2; user_management_menu; return; }

    echo -ne "  ${YELLOW}Password  : ${NC}"; read -rs PASSWORD; echo
    [[ -z "$PASSWORD" ]] && { echo -e "${RED}Empty.${NC}"; sleep 1; user_management_menu; return; }

    echo -ne "  ${YELLOW}Days      [30]: ${NC}"; read -r DAYS; DAYS=${DAYS:-30}
    echo -ne "  ${YELLOW}Max logins [2]: ${NC}"; read -r MAX_LOGIN; MAX_LOGIN=${MAX_LOGIN:-2}

    local EXPIRY; EXPIRY=$(date -d "+${DAYS} days" '+%Y-%m-%d')

    useradd -M -s /bin/false -e "$EXPIRY" "$USERNAME" >> "$LOG_FILE" 2>&1
    echo "$USERNAME:$PASSWORD" | chpasswd >> "$LOG_FILE" 2>&1
    echo "${USERNAME}|${PASSWORD}|${EXPIRY}|${MAX_LOGIN}|$(date '+%Y-%m-%d')|active" >> "$USER_DB"

    local IP; IP=$(get_public_ip)
    local WS_P; WS_P=$(get_ws_port)
    local PAYLOAD; PAYLOAD=$(cat "$PAYLOAD_FILE" 2>/dev/null)
    local CF_DOM; CF_DOM=$(cat "$CF_DOMAIN_FILE" 2>/dev/null | sed 's|https://||')

    echo -e "\n  ${GREEN}[✓] User created!${NC}"
    echo -e "  ${WHITE}┌──────────────────────────────────────────────────────┐"
    echo -e "  │  NPV Tunnel Account Details                          │"
    echo -e "  ├──────────────────────────────────────────────────────┤"
    echo -e "  │  Username  : ${USERNAME}"
    echo -e "  │  Password  : ${PASSWORD}"
    echo -e "  │  Expires   : ${EXPIRY} (${DAYS} days)"
    echo -e "  │  Max Login : ${MAX_LOGIN}"
    echo -e "  ├──────────────────────────────────────────────────────┤"
    echo -e "  │  SSH Host  : ${IP}   SSH Port: 22"
    echo -e "  │  WS Host   : ${IP}   WS Port : ${WS_P}"
    echo -e "  │  TLS Port  : 443"
    [[ -n "$CF_DOM" ]] && echo -e "  │  CF Domain : ${CF_DOM}"
    echo -e "  │  Payload   : ${PAYLOAD}"
    echo -e "  └──────────────────────────────────────────────────────┘${NC}"
    log "User created: $USERNAME expires $EXPIRY"
    read -rp "  Press Enter..."; user_management_menu
}

delete_user() {
    banner
    echo -ne "  ${YELLOW}Username to delete: ${NC}"; read -r USERNAME
    ! id "$USERNAME" &>/dev/null && { echo -e "${RED}Not found.${NC}"; sleep 2; user_management_menu; return; }
    echo -ne "  ${YELLOW}Confirm delete '${USERNAME}'? (y/N): ${NC}"; read -r C
    [[ "${C,,}" != "y" ]] && { user_management_menu; return; }
    pkill -u "$USERNAME" 2>/dev/null
    userdel -f "$USERNAME" >> "$LOG_FILE" 2>&1
    _remove_speed_limit "$USERNAME" 2>/dev/null || true
    sed -i "/^${USERNAME}|/d" "$USER_DB"
    echo -e "  ${GREEN}[✓] Deleted.${NC}"; log "User deleted: $USERNAME"
    read -rp "  Press Enter..."; user_management_menu
}

extend_user() {
    banner
    echo -ne "  ${YELLOW}Username: ${NC}"; read -r USERNAME
    ! id "$USERNAME" &>/dev/null && { echo -e "${RED}Not found.${NC}"; sleep 2; user_management_menu; return; }
    echo -ne "  ${YELLOW}Extend by days [30]: ${NC}"; read -r DAYS; DAYS=${DAYS:-30}

    local CUR_EXP; CUR_EXP=$(chage -l "$USERNAME" 2>/dev/null | grep "Account expires" | awk -F': ' '{print $2}' | xargs)
    local NEW_EXP
    if [[ "$CUR_EXP" == "never" || -z "$CUR_EXP" ]]; then
        NEW_EXP=$(date -d "+${DAYS} days" '+%Y-%m-%d')
    else
        NEW_EXP=$(date -d "$CUR_EXP +${DAYS} days" '+%Y-%m-%d' 2>/dev/null || date -d "+${DAYS} days" '+%Y-%m-%d')
    fi

    chage -E "$NEW_EXP" "$USERNAME"

    # Update USER_DB: rebuild the line with corrected expiry (field 3)
    if grep -q "^${USERNAME}|" "$USER_DB"; then
        local LINE; LINE=$(grep "^${USERNAME}|" "$USER_DB")
        local F1 F2 F3 F4 F5 F6
        IFS='|' read -r F1 F2 F3 F4 F5 F6 <<< "$LINE"
        local NEW_LINE="${F1}|${F2}|${NEW_EXP}|${F4}|${F5}|${F6}"
        sed -i "/^${USERNAME}|/c\\${NEW_LINE}" "$USER_DB"
    fi

    echo -e "  ${GREEN}[✓] Extended to ${NEW_EXP}.${NC}"; log "Extended: $USERNAME to $NEW_EXP"
    read -rp "  Press Enter..."; user_management_menu
}

lock_unlock_user() {
    banner
    echo -ne "  ${YELLOW}Username: ${NC}"; read -r USERNAME
    ! id "$USERNAME" &>/dev/null && { echo -e "${RED}Not found.${NC}"; sleep 2; user_management_menu; return; }
    local ST; ST=$(passwd -S "$USERNAME" 2>/dev/null | awk '{print $2}')
    if [[ "$ST" == "L" || "$ST" == "LK" ]]; then
        passwd -u "$USERNAME" >> "$LOG_FILE" 2>&1
        echo -e "  ${GREEN}[✓] Unlocked.${NC}"; log "Unlocked: $USERNAME"
    else
        passwd -l "$USERNAME" >> "$LOG_FILE" 2>&1
        pkill -u "$USERNAME" 2>/dev/null
        echo -e "  ${YELLOW}[✓] Locked + sessions killed.${NC}"; log "Locked: $USERNAME"
    fi
    read -rp "  Press Enter..."; user_management_menu
}

kill_user_sessions() {
    banner
    echo -ne "  ${YELLOW}Username (blank = all): ${NC}"; read -r USERNAME
    if [[ -z "$USERNAME" ]]; then
        who | awk '{print $1}' | sort -u | while read -r U; do pkill -u "$U" 2>/dev/null; done
        echo -e "  ${GREEN}[✓] All sessions killed.${NC}"
    else
        pkill -u "$USERNAME" 2>/dev/null \
            && echo -e "  ${GREEN}[✓] Sessions for '${USERNAME}' killed.${NC}" \
            || echo -e "  ${YELLOW}No sessions found.${NC}"
    fi
    log "Sessions killed: ${USERNAME:-all}"
    read -rp "  Press Enter..."; user_management_menu
}

list_users() {
    banner
    echo -e "${CYAN}  [*] All VPN Users${NC}\n"
    printf "  ${WHITE}%-15s %-12s %-12s %-8s %-8s %-8s${NC}\n" "User" "Expires" "Created" "MaxConn" "Online" "Status"
    echo -e "  ${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    while IFS='|' read -r U PASS EXP MAXL CREATED STATUS; do
        [[ -z "$U" ]] && continue
        local ONLINE; ONLINE=$(who 2>/dev/null | grep -c "^${U} " || echo 0)
        local LOCK; LOCK=$(passwd -S "$U" 2>/dev/null | awk '{print $2}')
        local DAYS_LEFT; DAYS_LEFT=$(( ( $(date -d "$EXP" +%s 2>/dev/null || echo 0) - $(date +%s) ) / 86400 ))
        local ST_CLR
        if [[ "$LOCK" == "L" || "$LOCK" == "LK" ]]; then ST_CLR="${RED}Locked${NC}"
        elif [[ "$DAYS_LEFT" -lt 0 ]]; then             ST_CLR="${RED}Expired${NC}"
        elif [[ "$DAYS_LEFT" -lt 3 ]]; then             ST_CLR="${YELLOW}Expiring${NC}"
        else                                             ST_CLR="${GREEN}Active${NC}"; fi
        printf "  %-15s %-12s %-12s %-8s " "$U" "$EXP" "$CREATED" "$MAXL"
        printf "%-8s " "$ONLINE"
        echo -e "$ST_CLR"
    done < "$USER_DB"

    echo -e "  ${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  Total: $(wc -l < "$USER_DB") users  |  Online: $(who 2>/dev/null | wc -l) sessions"
    read -rp "  Press Enter..."; user_management_menu
}

check_user() {
    banner
    echo -ne "  ${YELLOW}Username: ${NC}"; read -r USERNAME
    ! id "$USERNAME" &>/dev/null && { echo -e "${RED}Not found.${NC}"; sleep 2; user_management_menu; return; }
    local LINE; LINE=$(grep "^${USERNAME}|" "$USER_DB" 2>/dev/null)
    local EXP;     EXP=$(echo "$LINE"     | cut -d'|' -f3)
    local MAXL;    MAXL=$(echo "$LINE"    | cut -d'|' -f4)
    local CREATED; CREATED=$(echo "$LINE" | cut -d'|' -f5)
    local ONLINE;  ONLINE=$(who 2>/dev/null | grep -c "^${USERNAME} " || echo 0)
    local LOCK;    LOCK=$(passwd -S "$USERNAME" 2>/dev/null | awk '{print $2}')
    local DAYS_LEFT; DAYS_LEFT=$(( ( $(date -d "$EXP" +%s 2>/dev/null || echo 0) - $(date +%s) ) / 86400 ))

    echo -e "\n  ${WHITE}┌──────────────────────────────────────┐"
    echo -e "  │  User Details: ${USERNAME}"
    echo -e "  ├──────────────────────────────────────┤"
    echo -e "  │  Created   : ${CREATED}"
    echo -e "  │  Expires   : ${EXP} (${DAYS_LEFT}d left)"
    echo -e "  │  Max Login : ${MAXL}"
    echo -e "  │  Online    : ${ONLINE} session(s)"
    echo -e "  │  Lock      : ${LOCK}"
    echo -e "  └──────────────────────────────────────┘${NC}"
    read -rp "  Press Enter..."; user_management_menu
}

# ── Speed Limits ──────────────────────────────────────────────────

_remove_speed_limit() {
    local USER="$1"
    local UID_NUM; UID_NUM=$(id -u "$USER" 2>/dev/null) || return 0
    local IFACE; IFACE=$(ip route get 1 2>/dev/null | awk '{print $5; exit}')
    [[ -z "$IFACE" ]] && return 0
    local CLASSID; CLASSID=$(( UID_NUM % 65535 + 1 ))
    tc class del dev "$IFACE" classid "1:${CLASSID}" 2>/dev/null || true
    tc filter del dev "$IFACE" protocol ip handle "$UID_NUM" fw 2>/dev/null || true
    iptables -t mangle -D OUTPUT -m owner --uid-owner "$UID_NUM" -j MARK --set-mark "$UID_NUM" 2>/dev/null || true
}

set_speed_limit() {
    banner
    echo -e "${CYAN}  [*] Per-User Speed Limit (Traffic Control)${NC}\n"
    echo -ne "  ${YELLOW}Username: ${NC}"; read -r USERNAME
    ! id "$USERNAME" &>/dev/null && { echo -e "${RED}Not found.${NC}"; sleep 2; user_management_menu; return; }

    echo -e "  ${WHITE}Examples: 1mbit  512kbit  2mbit${NC}"
    echo -ne "  ${YELLOW}Upload limit   (blank = unlimited): ${NC}"; read -r UL_LIMIT
    echo -ne "  ${YELLOW}Download limit (blank = unlimited): ${NC}"; read -r DL_LIMIT

    if [[ -z "$DL_LIMIT" && -z "$UL_LIMIT" ]]; then
        _remove_speed_limit "$USERNAME"
        echo -e "  ${GREEN}[✓] Speed limits removed for ${USERNAME}.${NC}"
        log "Speed limit removed: $USERNAME"
        read -rp "  Press Enter..."; user_management_menu; return
    fi

    local UID_NUM; UID_NUM=$(id -u "$USERNAME")
    local IFACE; IFACE=$(ip route get 1 2>/dev/null | awk '{print $5; exit}')
    if [[ -z "$IFACE" ]]; then
        echo -e "  ${RED}Cannot detect network interface.${NC}"
        read -rp "  Press Enter..."; user_management_menu; return
    fi

    local CLASSID; CLASSID=$(( UID_NUM % 65535 + 1 ))
    local RATE="${UL_LIMIT:-100mbit}"

    tc qdisc add dev "$IFACE" root handle 1: htb default 9999 2>/dev/null || true
    _remove_speed_limit "$USERNAME"
    tc class add dev "$IFACE" parent 1: classid "1:${CLASSID}" htb rate "$RATE" ceil "$RATE" 2>/dev/null
    iptables -t mangle -A OUTPUT -m owner --uid-owner "$UID_NUM" -j MARK --set-mark "$UID_NUM" 2>/dev/null
    tc filter add dev "$IFACE" protocol ip handle "$UID_NUM" fw classid "1:${CLASSID}" 2>/dev/null

    echo -e "  ${GREEN}[✓] Speed limit applied for ${USERNAME}:${NC}"
    [[ -n "$UL_LIMIT" ]] && echo -e "     Upload  : ${UL_LIMIT}"
    [[ -n "$DL_LIMIT" ]] && echo -e "     Download: ${DL_LIMIT} (ingress limiting requires IFB — apply manually if needed)"
    log "Speed limit set: $USERNAME UL=${UL_LIMIT:-unlimited}"
    read -rp "  Press Enter..."; user_management_menu
}

# ── [7] Live Monitor ──────────────────────────────────────────────

monitor_connections() {
    echo -e "${CYAN}  Monitoring connections... (Ctrl+C to stop)${NC}\n"
    while true; do
        clear
        banner
        echo -e "${WHITE}  ┌── LIVE CONNECTIONS ─────────────────────────────────┐${NC}"
        who 2>/dev/null | awk '{printf "  │  %-12s  %-10s  %s\n", $1, $2, $3" "$4" "$5}' \
            || echo "  │  No active sessions"
        echo -e "${WHITE}  ├── ACTIVE SSH PROCESSES ────────────────────────────┤${NC}"
        ps aux 2>/dev/null | grep "sshd:" | grep -v grep | \
            awk '{printf "  │  %-8s  %-6s  %s\n", $1, $2, substr($0,index($0,$11))}' | head -15
        echo -e "${WHITE}  └─────────────────────────────────────────────────────┘${NC}"
        echo -e "  ${YELLOW}Sessions: $(who 2>/dev/null | wc -l)  |  Updated: $(date '+%H:%M:%S')${NC}"
        sleep 3
    done
}

# ── [8] Connection Details ────────────────────────────────────────

show_connection_details() {
    banner
    local IP; IP=$(get_public_ip)
    local WS_P; WS_P=$(get_ws_port)
    local PAYLOAD; PAYLOAD=$(cat "$PAYLOAD_FILE" 2>/dev/null)
    local CF_DOM; CF_DOM=$(cat "$CF_DOMAIN_FILE" 2>/dev/null | sed 's|https://||')
    echo -e "  ${WHITE}┌──────────────────────────────────────────────────────┐"
    echo -e "  │  NPV Tunnel — Full Connection Details                │"
    echo -e "  ├──────────────────────────────────────────────────────┤"
    echo -e "  │  SSH Direct:    Host: ${IP}  Port: 22"
    echo -e "  ├──────────────────────────────────────────────────────┤"
    echo -e "  │  WebSocket:     WS Host: ${IP}  WS Port: ${WS_P}"
    echo -e "  │  Payload  :     ${PAYLOAD:0:50}"
    echo -e "  ├──────────────────────────────────────────────────────┤"
    echo -e "  │  TLS (Stunnel): Host: ${IP}  Port: 443"
    echo -e "  │  TLS Cert : Self-signed (disable cert check)"
    if [[ -n "$CF_DOM" ]]; then
        echo -e "  ├──────────────────────────────────────────────────────┤"
        echo -e "  │  Cloudflare:    WS Host: ${CF_DOM}"
        echo -e "  │                 WS Port: 443   SSL: ON"
    fi
    echo -e "  └──────────────────────────────────────────────────────┘${NC}"
    read -rp "  Press Enter..."; main_menu
}

# ── [W] Web Panel ─────────────────────────────────────────────────

web_panel_menu() {
    banner
    local WEB_P; WEB_P=$(get_web_port)
    local IP; IP=$(get_public_ip)
    echo -e "${WHITE}  ┌──────────────────────────────────────────┐${NC}"
    echo -e "${WHITE}  │        WEB PANEL (Browser UI)            │${NC}"
    echo -e "${WHITE}  ├──────────────────────────────────────────┤${NC}"
    echo -e "  │  Status : $(svc_status ragnar-web) $(systemctl is-active ragnar-web 2>/dev/null)"
    echo -e "  │  URL    : ${CYAN}http://${IP}:${WEB_P}${WHITE}"
    echo -e "${WHITE}  ├──────────────────────────────────────────┤${NC}"
    echo -e "${WHITE}  │ ${GREEN}[1]${WHITE} Install / Reinstall Web Panel      │${NC}"
    echo -e "${WHITE}  │ ${GREEN}[2]${WHITE} Change Web Panel Port              │${NC}"
    echo -e "${WHITE}  │ ${GREEN}[3]${WHITE} Change Web Panel Password          │${NC}"
    echo -e "${WHITE}  │ ${GREEN}[4]${WHITE} Restart Web Panel                  │${NC}"
    echo -e "${WHITE}  │ ${GREEN}[5]${WHITE} View Web Panel Logs                │${NC}"
    echo -e "${WHITE}  │ ${RED}[6]${WHITE} Uninstall Web Panel               │${NC}"
    echo -e "${WHITE}  │ ${RED}[0]${WHITE} Back                               │${NC}"
    echo -e "${WHITE}  └──────────────────────────────────────────┘${NC}"
    echo -ne "\n  ${YELLOW}Select: ${NC}"; read -r OPT
    case $OPT in
        1) install_web_panel ;;
        2) change_web_port ;;
        3) change_web_password ;;
        4) systemctl restart ragnar-web; echo -e "  ${GREEN}[✓] Restarted.${NC}"; sleep 1; web_panel_menu ;;
        5) journalctl -u ragnar-web -n 40 --no-pager; read -rp "  Enter..."; web_panel_menu ;;
        6) uninstall_web_panel ;;
        0) main_menu ;;
        *) web_panel_menu ;;
    esac
}

install_web_panel() {
    banner
    echo -e "${CYAN}  [*] Installing Ragnar Web Panel...${NC}\n"

    local WEB_P; WEB_P=$(get_web_port)
    echo -ne "  ${YELLOW}Web panel port [${WEB_P}]: ${NC}"; read -r INPUT_PORT
    WEB_P=${INPUT_PORT:-$WEB_P}
    echo "$WEB_P" > "$WEB_PORT_FILE"

    local WEB_PASS; WEB_PASS=$(cat "$WEB_PASS_FILE" 2>/dev/null)
    if [[ -z "$WEB_PASS" ]]; then
        echo -ne "  ${YELLOW}Set web panel password: ${NC}"; read -rs WEB_PASS; echo
        [[ -z "$WEB_PASS" ]] && WEB_PASS="ragnar$(shuf -i 1000-9999 -n1)"
        echo "$WEB_PASS" > "$WEB_PASS_FILE"
        chmod 600 "$WEB_PASS_FILE"
    fi

    cat > /usr/local/bin/ragnar-web-panel.py << 'WEBEOF'
#!/usr/bin/env python3
"""Ragnar Web Panel v3.1 — browser-based SSH VPN management + Web Terminal.
No external Python deps required (uses only stdlib).
"""
import os, json, subprocess, time, html, hashlib, base64
import struct, select, threading, pty, fcntl, termios
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import parse_qs, urlparse
import secrets as _sec

PORT      = int(os.environ.get("WEB_PORT", "8080"))
PASSWORD  = os.environ.get("WEB_PASS", "ragnar")
CONFIG    = "/etc/ssh-vpn-panel"
USER_DB   = f"{CONFIG}/users.db"
LOG_FILE  = "/var/log/ssh-vpn-panel.log"

TOKENS    = {}
TOKEN_TTL = 3600
WS_MAGIC  = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

# ── Shell helpers ─────────────────────────────────────────────────

def sh(cmd, t=10):
    try:
        r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=t)
        return (r.stdout + r.stderr).strip()
    except Exception as e:
        return str(e)

def svc(name):
    return sh(f"systemctl is-active {name}")

def ip_addr():
    return sh("curl -s --max-time 4 https://api.ipify.org")

def read_users():
    rows = []
    try:
        with open(USER_DB) as f:
            for ln in f:
                p = ln.strip().split("|")
                if len(p) >= 6:
                    u      = p[0]
                    online = sh(f"who | grep -c '^{u} ' 2>/dev/null || echo 0").split()[0]
                    lock   = sh(f"passwd -S {u} 2>/dev/null | awk '{{print $2}}'")
                    rows.append(dict(user=u, pw=p[1], exp=p[2], ml=p[3],
                                     created=p[4], lock=lock, online=online))
    except:
        pass
    return rows

def info():
    return dict(
        ip      = ip_addr(),
        uptime  = sh("uptime -p"),
        cpu     = sh("top -bn1 | grep 'Cpu(s)' | awk '{print $2}'"),
        mem_u   = sh("free -m | awk 'NR==2{print $3}'"),
        mem_t   = sh("free -m | awk 'NR==2{print $2}'"),
        disk    = sh("df -h / | awk 'NR==2{print $3\"/\"$2\" (\"$5\")'\"'\"'}"),
        users   = sh(f"wc -l < {USER_DB}").strip(),
        online  = sh("who | wc -l").strip(),
        ssh     = svc("ssh"),
        ws      = svc("ssh-ws"),
        tls     = svc("stunnel4"),
        cf      = svc("cloudflared-tunnel"),
        web     = svc("ragnar-web"),
        ws_port = sh(f"cat {CONFIG}/ws_port.txt 2>/dev/null || echo 80"),
        cf_dom  = sh(f"cat {CONFIG}/cf_domain.txt 2>/dev/null | sed 's|https://||'"),
    )

# ── Auth helpers ──────────────────────────────────────────────────

def tok_new():
    t = _sec.token_hex(24)
    TOKENS[t] = time.time() + TOKEN_TTL
    return t

def tok_ok(t):
    exp = TOKENS.get(t)
    if exp and time.time() < exp:
        TOKENS[t] = time.time() + TOKEN_TTL
        return True
    TOKENS.pop(t, None)
    return False

def get_tok(hdrs):
    for part in hdrs.get("Cookie", "").split(";"):
        k, _, v = part.strip().partition("=")
        if k.strip() == "rp":
            return v.strip()
    return ""

# ── WebSocket helpers ─────────────────────────────────────────────

def ws_accept_key(key):
    return base64.b64encode(
        hashlib.sha1((key + WS_MAGIC).encode()).digest()
    ).decode()

def ws_recv_frame(sock):
    try:
        hdr = b""
        while len(hdr) < 2:
            c = sock.recv(2 - len(hdr))
            if not c: return None
            hdr += c
        opcode = hdr[0] & 0x0f
        if opcode == 8: return None   # close frame
        masked = (hdr[1] & 0x80) != 0
        plen   = hdr[1] & 0x7f
        if plen == 126:
            ext = b""
            while len(ext) < 2: ext += sock.recv(2 - len(ext))
            plen = struct.unpack(">H", ext)[0]
        elif plen == 127:
            ext = b""
            while len(ext) < 8: ext += sock.recv(8 - len(ext))
            plen = struct.unpack(">Q", ext)[0]
        mask = sock.recv(4) if masked else b"\x00\x00\x00\x00"
        data = b""
        while len(data) < plen:
            c = sock.recv(min(plen - len(data), 65536))
            if not c: return None
            data += c
        if masked:
            data = bytes(b ^ mask[i % 4] for i, b in enumerate(data))
        return data
    except:
        return None

def ws_send_frame(sock, data):
    try:
        if isinstance(data, str): data = data.encode()
        l = len(data)
        if l < 126:      hdr = bytes([0x82, l])
        elif l < 65536:  hdr = bytes([0x82, 126]) + struct.pack(">H", l)
        else:            hdr = bytes([0x82, 127]) + struct.pack(">Q", l)
        sock.sendall(hdr + data)
        return True
    except:
        return False

def handle_terminal_ws(handler):
    """Upgrade HTTP to WebSocket and proxy to an interactive bash pty."""
    key    = handler.headers.get("Sec-WebSocket-Key", "")
    accept = ws_accept_key(key)
    resp   = (
        "HTTP/1.1 101 Switching Protocols\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        f"Sec-WebSocket-Accept: {accept}\r\n\r\n"
    )
    sock = handler.connection
    sock.sendall(resp.encode())
    sock.settimeout(None)

    master_fd, slave_fd = pty.openpty()
    proc = subprocess.Popen(
        ["/bin/bash", "-i"],
        stdin=slave_fd, stdout=slave_fd, stderr=slave_fd,
        close_fds=True,
        env=dict(os.environ, TERM="xterm-256color", HOME="/root", USER="root")
    )
    os.close(slave_fd)

    stop = threading.Event()

    def pty_reader():
        while not stop.is_set():
            try:
                r, _, _ = select.select([master_fd], [], [], 0.5)
                if r:
                    data = os.read(master_fd, 4096)
                    if not data or not ws_send_frame(sock, data):
                        break
            except:
                break
        stop.set()

    t = threading.Thread(target=pty_reader, daemon=True)
    t.start()

    while not stop.is_set():
        data = ws_recv_frame(sock)
        if data is None:
            break
        # Check for resize JSON message
        try:
            msg = json.loads(data.decode())
            if msg.get("type") == "resize":
                cols    = int(msg.get("cols", 80))
                rows    = int(msg.get("rows", 24))
                winsize = struct.pack("HHHH", rows, cols, 0, 0)
                fcntl.ioctl(master_fd, termios.TIOCSWINSZ, winsize)
            continue
        except:
            pass
        try:
            os.write(master_fd, data)
        except:
            break

    stop.set()
    try: proc.terminate()
    except: pass
    try: os.close(master_fd)
    except: pass

# ── CSS ───────────────────────────────────────────────────────────

CSS = """
*{box-sizing:border-box;margin:0;padding:0}
body{background:#0d1117;color:#e6edf3;font-family:'Segoe UI',Arial,sans-serif;font-size:14px}
.nav{background:#161b22;border-bottom:1px solid #30363d;padding:14px 24px;display:flex;align-items:center;gap:16px}
.nav h1{font-size:18px;color:#58a6ff;font-weight:700}
.nav .sub{color:#8b949e;font-size:13px}
.nav-links{margin-left:auto;display:flex;gap:12px;align-items:center}
.nav-links a{color:#8b949e;text-decoration:none;font-size:13px}
.nav-links a:hover{color:#58a6ff}
.nav-links a.term{background:#238636;color:#fff;padding:5px 12px;border-radius:6px;font-size:12px;font-weight:600}
.nav-links a.term:hover{background:#2ea043;color:#fff}
.wrap{max-width:1100px;margin:0 auto;padding:24px 16px}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(190px,1fr));gap:14px;margin-bottom:20px}
.card{background:#161b22;border:1px solid #30363d;border-radius:8px;padding:18px}
.card h3{font-size:11px;color:#8b949e;text-transform:uppercase;letter-spacing:.5px;margin-bottom:8px}
.card .v{font-size:21px;font-weight:700}
.card .s{font-size:12px;color:#8b949e;margin-top:4px}
.panel{background:#161b22;border:1px solid #30363d;border-radius:8px;margin-bottom:18px}
.ph{padding:14px 18px;border-bottom:1px solid #30363d;display:flex;justify-content:space-between;align-items:center}
.ph h2{font-size:15px;font-weight:600}
table{width:100%;border-collapse:collapse}
th{padding:9px 16px;text-align:left;font-size:11px;color:#8b949e;text-transform:uppercase;letter-spacing:.4px;border-bottom:1px solid #21262d}
td{padding:9px 16px;border-bottom:1px solid #21262d;font-size:13px}
tr:last-child td{border-bottom:none}
tr:hover{background:#1c2128}
.btn{display:inline-block;padding:5px 12px;border-radius:6px;font-size:12px;font-weight:500;cursor:pointer;border:none;text-decoration:none;line-height:1.4}
.b-blue{background:#1f6feb;color:#fff}.b-blue:hover{background:#388bfd}
.b-red{background:#da3633;color:#fff}.b-red:hover{background:#f85149}
.b-green{background:#238636;color:#fff}.b-green:hover{background:#2ea043}
.b-gray{background:#21262d;color:#e6edf3;border:1px solid #30363d}.b-gray:hover{background:#30363d}
.fr{display:flex;gap:8px;align-items:center;flex-wrap:wrap;padding:14px 18px}
.fr input{background:#0d1117;border:1px solid #30363d;border-radius:6px;padding:6px 11px;color:#e6edf3;font-size:13px;flex:1;min-width:120px}
.fr input:focus{outline:none;border-color:#58a6ff}
.svc-row{display:flex;gap:20px;padding:14px 18px;flex-wrap:wrap;align-items:center}
.dot{display:inline-block;width:8px;height:8px;border-radius:50%;margin-right:5px}
.dot.ok{background:#3fb950}.dot.off{background:#f85149}
.log{background:#0d1117;font-family:monospace;font-size:12px;padding:14px;overflow-y:auto;max-height:300px;white-space:pre-wrap;color:#8b949e}
.login{display:flex;height:100vh;align-items:center;justify-content:center}
.lbox{background:#161b22;border:1px solid #30363d;border-radius:12px;padding:36px;width:330px}
.lbox h2{color:#58a6ff;margin-bottom:22px;font-size:20px;text-align:center}
.lbox input{width:100%;background:#0d1117;border:1px solid #30363d;border-radius:6px;padding:9px 13px;color:#e6edf3;font-size:14px;margin-bottom:13px}
.lbox button{width:100%;padding:10px;background:#1f6feb;color:#fff;border:none;border-radius:6px;font-size:15px;cursor:pointer;font-weight:600}
.lbox button:hover{background:#388bfd}
.err{color:#f85149;font-size:13px;margin-bottom:11px;text-align:center}
"""

TERM_HTML = """<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>Ragnar Terminal</title>
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/xterm@5.3.0/css/xterm.min.css">
  <script src="https://cdn.jsdelivr.net/npm/xterm@5.3.0/lib/xterm.min.js"></script>
  <script src="https://cdn.jsdelivr.net/npm/xterm-addon-fit@0.8.0/lib/xterm-addon-fit.min.js"></script>
  <style>
    *{box-sizing:border-box;margin:0;padding:0}
    body{background:#0d1117;overflow:hidden}
    .topbar{background:#161b22;border-bottom:1px solid #30363d;padding:10px 20px;
            display:flex;align-items:center;gap:12px;height:44px}
    .topbar h1{color:#58a6ff;font-size:15px;font-family:sans-serif;font-weight:700}
    .topbar a{color:#8b949e;text-decoration:none;font-size:13px;font-family:sans-serif;margin-left:auto}
    .topbar a:hover{color:#58a6ff}
    .badge{font-size:12px;font-family:sans-serif;padding:3px 9px;border-radius:4px;
           background:#238636;color:#fff;font-weight:600}
    .badge.off{background:#da3633}
    #terminal{height:calc(100vh - 44px)}
  </style>
</head>
<body>
<div class="topbar">
  <h1>&#9889; Ragnar Web Terminal</h1>
  <span id="badge" class="badge">Connecting...</span>
  <a href="/">&#8592; Dashboard</a>
</div>
<div id="terminal"></div>
<script>
const term = new Terminal({
  theme:{background:'#0d1117',foreground:'#e6edf3',cursor:'#58a6ff',
         selectionBackground:'#264f78'},
  fontFamily:'Consolas,"Courier New",monospace',
  fontSize:14,
  cursorBlink:true,
  scrollback:5000,
});
const fitAddon = new FitAddon.FitAddon();
term.loadAddon(fitAddon);
term.open(document.getElementById('terminal'));
fitAddon.fit();

const badge = document.getElementById('badge');
const proto = location.protocol === 'https:' ? 'wss:' : 'ws:';
const ws    = new WebSocket(proto + '//' + location.host + '/terminal');
ws.binaryType = 'arraybuffer';

ws.onopen = function() {
  badge.textContent = 'Connected';
  badge.className   = 'badge';
  ws.send(JSON.stringify({type:'resize', cols:term.cols, rows:term.rows}));
};
ws.onmessage = function(e) {
  if (e.data instanceof ArrayBuffer) term.write(new Uint8Array(e.data));
  else term.write(e.data);
};
ws.onclose = function() {
  badge.textContent = 'Disconnected';
  badge.className   = 'badge off';
  term.writeln('\\r\\n\\x1b[31m[Session closed — refresh to reconnect]\\x1b[0m');
};
ws.onerror = function() {
  badge.textContent = 'Error';
  badge.className   = 'badge off';
};
term.onData(function(data) {
  if (ws.readyState === WebSocket.OPEN) ws.send(data);
});
term.onResize(function(sz) {
  if (ws.readyState === WebSocket.OPEN)
    ws.send(JSON.stringify({type:'resize', cols:sz.cols, rows:sz.rows}));
});
window.addEventListener('resize', function() { fitAddon.fit(); });
</script>
</body>
</html>"""

# ── Render helpers ────────────────────────────────────────────────

def render_login(err=""):
    e = f'<div class="err">{html.escape(err)}</div>' if err else ""
    return (
        f'<!DOCTYPE html><html><head><meta charset=utf-8>'
        f'<title>Ragnar Panel</title><style>{CSS}</style></head>'
        f'<body><div class="login"><div class="lbox">'
        f'<h2>&#9889; Ragnar Panel</h2>{e}'
        f'<form method=POST action=/login>'
        f'<input type=password name=password placeholder="Password" autofocus required>'
        f'<button>Sign In</button></form></div></div></body></html>'
    )

def badge(s):
    cls   = "ok" if s == "active" else "off"
    label = "active" if s == "active" else (s or "inactive")
    return f'<span class="dot {cls}"></span>{label}'

def render_dash(d, users):
    user_rows = ""
    for u in users:
        lk       = "Locked" if u["lock"] in ("L", "LK") else "Active"
        lk_color = "color:#f85149" if u["lock"] in ("L", "LK") else "color:#3fb950"
        un = html.escape(u['user'])
        user_rows += (
            f'<tr>'
            f'<td><strong>{un}</strong></td>'
            f'<td>{html.escape(u["exp"])}</td>'
            f'<td>{html.escape(u["created"])}</td>'
            f'<td>{html.escape(u["ml"])}</td>'
            f'<td>{html.escape(str(u["online"]))}</td>'
            f'<td style="{lk_color}">{lk}</td>'
            f'<td style="display:flex;gap:5px;flex-wrap:wrap">'
            f'<form method=POST action=/user/kill style=display:inline>'
            f'<input type=hidden name=u value="{un}">'
            f'<button class="btn b-gray" onclick="return confirm(\'Kill sessions?\')">Kill</button></form>'
            f'<form method=POST action=/user/lock style=display:inline>'
            f'<input type=hidden name=u value="{un}">'
            f'<button class="btn b-gray">Lock/Unlock</button></form>'
            f'<form method=POST action=/user/delete style=display:inline>'
            f'<input type=hidden name=u value="{un}">'
            f'<button class="btn b-red" onclick="return confirm(\'Delete user?\')">Delete</button></form>'
            f'</td></tr>'
        )

    svc_html = "".join(
        f'<span>{name} {badge(d[key])}</span>'
        for name, key in [("SSH","ssh"),("WebSocket","ws"),("TLS/Stunnel","tls"),("Cloudflare","cf"),("Web Panel","web")]
    )
    cf_row  = (f'<div style="padding:0 18px 10px;color:#8b949e;font-size:12px">'
               f'Cloudflare: {html.escape(d["cf_dom"])}</div>') if d["cf_dom"] else ""
    log_txt = html.escape(sh(f"tail -n 50 {LOG_FILE}"))
    no_users = '<tr><td colspan=7 style="text-align:center;color:#8b949e;padding:22px">No users yet</td></tr>'

    return (
        f'<!DOCTYPE html><html><head><meta charset=utf-8><title>Ragnar Panel</title>'
        f'<style>{CSS}</style><meta http-equiv=refresh content=30></head><body>'
        f'<div class="nav">'
        f'<h1>&#9889; Ragnar Web Panel</h1><span class="sub">v3.1.0</span>'
        f'<div class="nav-links">'
        f'<a href=/terminal class="term" target=_blank>&#9889; Web Terminal</a>'
        f'<a href=/logout>Sign Out</a>'
        f'</div></div>'
        f'<div class="wrap">'
        f'<div class="grid">'
        f'<div class="card"><h3>Server IP</h3>'
        f'<div class="v" style="font-size:15px">{html.escape(d["ip"])}</div>'
        f'<div class="s">Uptime: {html.escape(d["uptime"])}</div></div>'
        f'<div class="card"><h3>VPN Users</h3>'
        f'<div class="v">{html.escape(d["users"])}</div>'
        f'<div class="s">{html.escape(d["online"])} online</div></div>'
        f'<div class="card"><h3>CPU</h3><div class="v">{html.escape(d["cpu"])}%</div></div>'
        f'<div class="card"><h3>Memory</h3>'
        f'<div class="v">{html.escape(d["mem_u"])} MB</div>'
        f'<div class="s">of {html.escape(d["mem_t"])} MB</div></div>'
        f'<div class="card"><h3>Disk</h3>'
        f'<div class="v" style="font-size:14px">{html.escape(d["disk"])}</div></div>'
        f'</div>'
        f'<div class="panel"><div class="ph"><h2>Services</h2>'
        f'<div style="display:flex;gap:6px;flex-wrap:wrap">'
        f'<form method=POST action=/svc/restart><input type=hidden name=svc value=ssh-ws>'
        f'<button class="btn b-blue">Restart WS</button></form>'
        f'<form method=POST action=/svc/restart><input type=hidden name=svc value=stunnel4>'
        f'<button class="btn b-blue">Restart TLS</button></form>'
        f'<form method=POST action=/svc/restart><input type=hidden name=svc value=cloudflared-tunnel>'
        f'<button class="btn b-blue">Restart CF</button></form>'
        f'<form method=POST action=/svc/restart><input type=hidden name=svc value=ssh>'
        f'<button class="btn b-blue">Restart SSH</button></form>'
        f'</div></div>'
        f'<div class="svc-row">{svc_html}</div>'
        f'{cf_row}</div>'
        f'<div class="panel"><div class="ph"><h2>Users</h2></div>'
        f'<form method=POST action=/user/create class="fr">'
        f'<input name=username placeholder="Username" required>'
        f'<input name=password type=password placeholder="Password" required>'
        f'<input name=days placeholder="Days (30)" value="30" style="max-width:90px">'
        f'<input name=ml placeholder="MaxLogin (2)" value="2" style="max-width:90px">'
        f'<button class="btn b-green" type=submit>+ Add User</button></form>'
        f'<table>'
        f'<tr><th>User</th><th>Expires</th><th>Created</th>'
        f'<th>MaxLogin</th><th>Online</th><th>Status</th><th>Actions</th></tr>'
        f'{user_rows or no_users}'
        f'</table></div>'
        f'<div class="panel"><div class="ph"><h2>Panel Log</h2></div>'
        f'<div class="log">{log_txt}</div></div>'
        f'</div></body></html>'
    )

# ── HTTP handler ──────────────────────────────────────────────────

class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass

    def send_html(self, body, status=200, hdrs=None):
        b = body.encode()
        self.send_response(status)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(b)))
        for k, v in (hdrs or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(b)

    def redir(self, to, hdrs=None):
        self.send_response(302)
        self.send_header("Location", to)
        for k, v in (hdrs or {}).items():
            self.send_header(k, v)
        self.end_headers()

    def body(self):
        n = int(self.headers.get("Content-Length", 0))
        return parse_qs(self.rfile.read(n).decode()) if n else {}

    def authed(self):
        return tok_ok(get_tok(self.headers))

    def do_GET(self):
        path = urlparse(self.path).path

        if path == "/logout":
            TOKENS.pop(get_tok(self.headers), None)
            self.redir("/")
            return

        if not self.authed():
            self.send_html(render_login())
            return

        if path == "/terminal":
            if self.headers.get("Upgrade", "").lower() == "websocket":
                handle_terminal_ws(self)
            else:
                self.send_html(TERM_HTML)
            return

        self.send_html(render_dash(info(), read_users()))

    def do_POST(self):
        path = urlparse(self.path).path

        if path == "/login":
            pw = self.body().get("password", [""])[0]
            if pw == PASSWORD:
                t = tok_new()
                self.redir("/", {"Set-Cookie": f"rp={t}; Path=/; HttpOnly; Max-Age={TOKEN_TTL}"})
            else:
                self.send_html(render_login("Wrong password"))
            return

        if not self.authed():
            self.redir("/")
            return

        p = self.body()

        if path == "/svc/restart":
            s = p.get("svc", [""])[0]
            if s and all(c.isalnum() or c == '-' for c in s):
                sh(f"systemctl restart {s}")

        elif path == "/user/create":
            u  = p.get("username", [""])[0].strip()
            pw = p.get("password", [""])[0].strip()
            d  = p.get("days",    ["30"])[0].strip() or "30"
            ml = p.get("ml",      ["2"])[0].strip()  or "2"
            if u and pw and u.replace("_", "").isalnum():
                exp   = sh(f"date -d '+{d} days' '+%Y-%m-%d'")
                today = sh("date '+%Y-%m-%d'")
                sh(f"useradd -M -s /bin/false -e {exp} {u}")
                sh(f"echo '{u}:{pw}' | chpasswd")
                with open(USER_DB, "a") as f:
                    f.write(f"{u}|{pw}|{exp}|{ml}|{today}|active\n")

        elif path == "/user/delete":
            u = p.get("u", [""])[0].strip()
            if u and u.replace("_", "").isalnum():
                sh(f"pkill -u {u} 2>/dev/null")
                sh(f"userdel -f {u}")
                try:
                    with open(USER_DB) as f:
                        lines = [l for l in f if not l.startswith(f"{u}|")]
                    with open(USER_DB, "w") as f:
                        f.writelines(lines)
                except:
                    pass

        elif path == "/user/kill":
            u = p.get("u", [""])[0].strip()
            if u and u.replace("_", "").isalnum():
                sh(f"pkill -u {u} 2>/dev/null")

        elif path == "/user/lock":
            u = p.get("u", [""])[0].strip()
            if u and u.replace("_", "").isalnum():
                st = sh(f"passwd -S {u} | awk '{{print $2}}'")
                if st in ("L", "LK"):
                    sh(f"passwd -u {u}")
                else:
                    sh(f"passwd -l {u}")
                    sh(f"pkill -u {u} 2>/dev/null")

        self.redir("/")


class ThreadedHTTPServer(HTTPServer):
    """Handle each request in a daemon thread (needed for long-lived WS connections)."""
    def process_request(self, request, client_address):
        t = threading.Thread(
            target=self._handle, args=(request, client_address), daemon=True
        )
        t.start()

    def _handle(self, request, client_address):
        try:
            self.finish_request(request, client_address)
        except Exception:
            pass
        finally:
            self.shutdown_request(request)


if __name__ == "__main__":
    print(f"[Ragnar Web Panel v3.1] http://0.0.0.0:{PORT}", flush=True)
    ThreadedHTTPServer(("0.0.0.0", PORT), H).serve_forever()

WEBEOF
    chmod +x /usr/local/bin/ragnar-web-panel.py

    cat > /etc/systemd/system/ragnar-web.service << WEBSVC
[Unit]
Description=Ragnar SSH VPN Web Panel (port ${WEB_P})
After=network.target

[Service]
Type=simple
Environment="WEB_PORT=${WEB_P}"
Environment="WEB_PASS=$(cat "$WEB_PASS_FILE")"
ExecStart=/usr/bin/python3 /usr/local/bin/ragnar-web-panel.py
Restart=always
RestartSec=5
User=root
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
WEBSVC

    systemctl daemon-reload
    systemctl enable ragnar-web >> "$LOG_FILE" 2>&1
    systemctl restart ragnar-web >> "$LOG_FILE" 2>&1

    local IP; IP=$(get_public_ip)
    echo -e "\n  ${GREEN}[✓] Web panel installed!${NC}"
    echo -e "  ${WHITE}┌──────────────────────────────────────────┐"
    echo -e "  │  URL      : http://${IP}:${WEB_P}"
    echo -e "  │  Password : $(cat "$WEB_PASS_FILE")"
    echo -e "  └──────────────────────────────────────────┘${NC}"
    echo -e "  ${YELLOW}Open this URL in your browser to manage the VPN.${NC}"
    log "Web panel installed on port $WEB_P"
    read -rp "  Press Enter..."; web_panel_menu
}

change_web_port() {
    banner
    echo -ne "  ${YELLOW}New web panel port: ${NC}"; read -r NEW_PORT
    [[ ! "$NEW_PORT" =~ ^[0-9]+$ ]] && { echo -e "${RED}Invalid.${NC}"; sleep 1; web_panel_menu; return; }
    echo "$NEW_PORT" > "$WEB_PORT_FILE"
    if [[ -f /etc/systemd/system/ragnar-web.service ]]; then
        sed -i "s|WEB_PORT=.*\\"|WEB_PORT=${NEW_PORT}\\"|" /etc/systemd/system/ragnar-web.service
        systemctl daemon-reload; systemctl restart ragnar-web
    fi
    echo -e "  ${GREEN}[✓] Web panel port changed to ${NEW_PORT}.${NC}"
    log "Web panel port changed to $NEW_PORT"
    read -rp "  Press Enter..."; web_panel_menu
}

change_web_password() {
    banner
    echo -ne "  ${YELLOW}New web panel password: ${NC}"; read -rs NEW_PASS; echo
    [[ -z "$NEW_PASS" ]] && { echo -e "${RED}Empty.${NC}"; sleep 1; web_panel_menu; return; }
    echo "$NEW_PASS" > "$WEB_PASS_FILE"; chmod 600 "$WEB_PASS_FILE"
    if [[ -f /etc/systemd/system/ragnar-web.service ]]; then
        sed -i "s|WEB_PASS=.*\\"|WEB_PASS=${NEW_PASS}\\"|" /etc/systemd/system/ragnar-web.service
        systemctl daemon-reload; systemctl restart ragnar-web
    fi
    echo -e "  ${GREEN}[✓] Password updated.${NC}"
    log "Web panel password changed"
    read -rp "  Press Enter..."; web_panel_menu
}

uninstall_web_panel() {
    systemctl stop ragnar-web 2>/dev/null
    systemctl disable ragnar-web 2>/dev/null
    rm -f /etc/systemd/system/ragnar-web.service /usr/local/bin/ragnar-web-panel.py
    systemctl daemon-reload
    echo -e "  ${GREEN}[✓] Web panel uninstalled.${NC}"
    log "Web panel uninstalled"
    read -rp "  Press Enter..."; web_panel_menu
}

# ── [N] Bandwidth Monitor ─────────────────────────────────────────

bandwidth_monitor() {
    banner
    local IFACE; IFACE=$(ip route get 1 2>/dev/null | awk '{print $5; exit}')
    echo -e "${WHITE}  ┌──────────────────────────────────────┐${NC}"
    echo -e "${WHITE}  │        BANDWIDTH MONITOR             │${NC}"
    echo -e "${WHITE}  ├──────────────────────────────────────┤${NC}"
    echo -e "  │  Interface : ${CYAN}${IFACE:-unknown}${WHITE}"
    echo -e "${WHITE}  ├──────────────────────────────────────┤${NC}"
    echo -e "${WHITE}  │ ${GREEN}[1]${WHITE} Live traffic meter               │${NC}"
    echo -e "${WHITE}  │ ${GREEN}[2]${WHITE} Monthly summary (vnstat)         │${NC}"
    echo -e "${WHITE}  │ ${GREEN}[3]${WHITE} Daily summary (vnstat)           │${NC}"
    echo -e "${WHITE}  │ ${GREEN}[4]${WHITE} Per-user traffic (iptables)      │${NC}"
    echo -e "${WHITE}  │ ${GREEN}[5]${WHITE} Reset user traffic counters      │${NC}"
    echo -e "${WHITE}  │ ${RED}[0]${WHITE} Back                             │${NC}"
    echo -e "${WHITE}  └──────────────────────────────────────┘${NC}"
    echo -ne "\n  ${YELLOW}Select: ${NC}"; read -r OPT
    case $OPT in
        1) [[ -n "$IFACE" ]] && bw_live "$IFACE" || { echo -e "  ${RED}No interface detected.${NC}"; sleep 2; bandwidth_monitor; } ;;
        2) bw_vnstat_monthly ;;
        3) bw_vnstat_daily ;;
        4) bw_per_user ;;
        5) bw_reset ;;
        0) main_menu ;;
        *) bandwidth_monitor ;;
    esac
}

bw_live() {
    local IFACE="$1"
    echo -e "\n  ${CYAN}Live traffic on ${IFACE} — Ctrl+C to stop${NC}\n"
    local RX_P TX_P
    RX_P=$(awk -v i="${IFACE}:" '$1==i{print $2}' /proc/net/dev 2>/dev/null)
    TX_P=$(awk -v i="${IFACE}:" '$1==i{print $10}' /proc/net/dev 2>/dev/null)
    while true; do
        sleep 1
        local RX_N TX_N
        RX_N=$(awk -v i="${IFACE}:" '$1==i{print $2}' /proc/net/dev 2>/dev/null)
        TX_N=$(awk -v i="${IFACE}:" '$1==i{print $10}' /proc/net/dev 2>/dev/null)
        local RR TR
        RR=$(( (RX_N - RX_P) * 8 / 1000 ))
        TR=$(( (TX_N - TX_P) * 8 / 1000 ))
        RX_P=$RX_N; TX_P=$TX_N
        printf "\r  ${GREEN}↓ RX: %7d kbps${NC}   ${CYAN}↑ TX: %7d kbps${NC}   [%s]   " "$RR" "$TR" "$(date '+%H:%M:%S')"
    done
}

bw_vnstat_monthly() {
    if command -v vnstat &>/dev/null; then
        local IFACE; IFACE=$(ip route get 1 2>/dev/null | awk '{print $5; exit}')
        echo -e "${CYAN}  Monthly traffic for ${IFACE}:${NC}\n"
        vnstat -i "$IFACE" -m 2>/dev/null || echo "  No data yet. vnstat collects data over time."
    else
        echo -e "  ${YELLOW}vnstat not installed. Run Full Setup or install manually: apt install vnstat${NC}"
    fi
    read -rp "  Press Enter..."; bandwidth_monitor
}

bw_vnstat_daily() {
    if command -v vnstat &>/dev/null; then
        local IFACE; IFACE=$(ip route get 1 2>/dev/null | awk '{print $5; exit}')
        echo -e "${CYAN}  Daily traffic for ${IFACE}:${NC}\n"
        vnstat -i "$IFACE" -d 2>/dev/null || echo "  No data yet."
    else
        echo -e "  ${RED}vnstat not installed.${NC}"
    fi
    read -rp "  Press Enter..."; bandwidth_monitor
}

bw_per_user() {
    banner
    echo -e "${CYAN}  [*] Per-User Traffic Counters (iptables)${NC}\n"
    iptables -N RAGNAR_ACCT 2>/dev/null || true
    iptables -C OUTPUT -j RAGNAR_ACCT 2>/dev/null || iptables -A OUTPUT -j RAGNAR_ACCT
    iptables -C INPUT  -j RAGNAR_ACCT 2>/dev/null || iptables -A INPUT  -j RAGNAR_ACCT

    while IFS='|' read -r U _; do
        [[ -z "$U" ]] && continue
        local UID_N; UID_N=$(id -u "$U" 2>/dev/null) || continue
        iptables -C RAGNAR_ACCT -m owner --uid-owner "$UID_N" -j ACCEPT 2>/dev/null || \
            iptables -A RAGNAR_ACCT -m owner --uid-owner "$UID_N" -j ACCEPT
    done < "$USER_DB"

    printf "  ${WHITE}%-15s  %-10s  %s${NC}\n" "User" "UID" "Bytes (TX)"
    echo -e "  ${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    while IFS='|' read -r U _; do
        [[ -z "$U" ]] && continue
        local UID_N; UID_N=$(id -u "$U" 2>/dev/null) || continue
        local BYTES; BYTES=$(iptables -L RAGNAR_ACCT -vnx 2>/dev/null | \
            awk -v uid="uid-owner ${UID_N}" '$0~uid{sum+=$2}END{print sum+0}')
        printf "  %-15s  %-10s  %s bytes\n" "$U" "$UID_N" "${BYTES:-0}"
    done < "$USER_DB"
    echo -e "  ${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${YELLOW}Note: counters accumulate since last reset.${NC}"
    read -rp "  Press Enter..."; bandwidth_monitor
}

bw_reset() {
    echo -ne "  ${YELLOW}Reset all traffic counters? (y/N): ${NC}"; read -r C
    [[ "${C,,}" != "y" ]] && { bandwidth_monitor; return; }
    iptables -Z RAGNAR_ACCT 2>/dev/null || true
    echo -e "  ${GREEN}[✓] Counters reset.${NC}"; log "Bandwidth counters reset"
    read -rp "  Press Enter..."; bandwidth_monitor
}

# ── [9] Service Control ───────────────────────────────────────────

service_control_menu() {
    banner
    echo -e "${WHITE}  ┌──────────────────────────────────────┐${NC}"
    echo -e "${WHITE}  │        SERVICE CONTROL               │${NC}"
    echo -e "${WHITE}  ├──────────────────────────────────────┤${NC}"
    echo -e "${WHITE}  │ ${GREEN}[1]${WHITE} Restart All Services             │${NC}"
    echo -e "${WHITE}  │ ${GREEN}[2]${WHITE} Restart SSH-WS                   │${NC}"
    echo -e "${WHITE}  │ ${GREEN}[3]${WHITE} Restart Stunnel (TLS)           │${NC}"
    echo -e "${WHITE}  │ ${GREEN}[4]${WHITE} Restart Cloudflare Tunnel       │${NC}"
    echo -e "${WHITE}  │ ${GREEN}[5]${WHITE} Restart SSH daemon               │${NC}"
    echo -e "${WHITE}  │ ${GREEN}[6]${WHITE} Restart Web Panel                │${NC}"
    echo -e "${WHITE}  │ ${RED}[0]${WHITE} Back                             │${NC}"
    echo -e "${WHITE}  └──────────────────────────────────────┘${NC}"
    echo -ne "\n  ${YELLOW}Select: ${NC}"; read -r OPT
    case $OPT in
        1) systemctl restart ssh ssh-ws ssh-wss stunnel4 cloudflared-tunnel ragnar-web 2>/dev/null
           echo -e "  ${GREEN}[✓] All services restarted.${NC}" ;;
        2) systemctl restart ssh-ws ssh-wss; echo -e "  ${GREEN}[✓] SSH-WS restarted.${NC}" ;;
        3) systemctl restart stunnel4; echo -e "  ${GREEN}[✓] Stunnel restarted.${NC}" ;;
        4) systemctl restart cloudflared-tunnel; echo -e "  ${GREEN}[✓] Cloudflare restarted.${NC}" ;;
        5) systemctl restart ssh; echo -e "  ${GREEN}[✓] SSH restarted.${NC}" ;;
        6) systemctl restart ragnar-web; echo -e "  ${GREEN}[✓] Web panel restarted.${NC}" ;;
        0) main_menu; return ;;
    esac
    sleep 1; service_control_menu
}

# ── [L] Log Viewer ────────────────────────────────────────────────

log_viewer() {
    banner
    echo -e "${WHITE}  ┌──────────────────────────────────────┐${NC}"
    echo -e "${WHITE}  │            LOG VIEWER                │${NC}"
    echo -e "${WHITE}  ├──────────────────────────────────────┤${NC}"
    echo -e "${WHITE}  │ ${GREEN}[1]${WHITE} Panel Logs (last 30)             │${NC}"
    echo -e "${WHITE}  │ ${GREEN}[2]${WHITE} SSH Auth Logs (last 30)          │${NC}"
    echo -e "${WHITE}  │ ${GREEN}[3]${WHITE} WS Service Logs (last 30)        │${NC}"
    echo -e "${WHITE}  │ ${GREEN}[4]${WHITE} Stunnel Logs (last 30)           │${NC}"
    echo -e "${WHITE}  │ ${GREEN}[5]${WHITE} Cloudflare Logs (last 30)        │${NC}"
    echo -e "${WHITE}  │ ${GREEN}[6]${WHITE} Web Panel Logs (last 30)         │${NC}"
    echo -e "${WHITE}  │ ${RED}[0]${WHITE} Back                             │${NC}"
    echo -e "${WHITE}  └──────────────────────────────────────┘${NC}"
    echo -ne "\n  ${YELLOW}Select: ${NC}"; read -r OPT
    case $OPT in
        1) tail -n 30 "$LOG_FILE" 2>/dev/null || echo "No logs yet" ;;
        2) tail -n 30 /var/log/auth.log 2>/dev/null || journalctl -u ssh -n 30 --no-pager ;;
        3) journalctl -u ssh-ws -n 30 --no-pager ;;
        4) tail -n 30 /var/log/stunnel4/stunnel.log 2>/dev/null || echo "No stunnel logs" ;;
        5) journalctl -u cloudflared-tunnel -n 30 --no-pager ;;
        6) journalctl -u ragnar-web -n 30 --no-pager ;;
        0) main_menu; return ;;
    esac
    read -rp "  Press Enter..."; log_viewer
}

# ── [B] Backup / Restore ──────────────────────────────────────────

backup_restore_menu() {
    banner
    echo -e "${WHITE}  ┌──────────────────────────────────────┐${NC}"
    echo -e "${WHITE}  │        BACKUP / RESTORE              │${NC}"
    echo -e "${WHITE}  ├──────────────────────────────────────┤${NC}"
    echo -e "${WHITE}  │ ${GREEN}[1]${WHITE} Create Backup                    │${NC}"
    echo -e "${WHITE}  │ ${GREEN}[2]${WHITE} Restore from Backup              │${NC}"
    echo -e "${WHITE}  │ ${GREEN}[3]${WHITE} List Backups                     │${NC}"
    echo -e "${WHITE}  │ ${RED}[0]${WHITE} Back                             │${NC}"
    echo -e "${WHITE}  └──────────────────────────────────────┘${NC}"
    echo -ne "\n  ${YELLOW}Select: ${NC}"; read -r OPT
    case $OPT in
        1) create_backup ;;
        2) restore_backup ;;
        3) ls -lh /root/ragnar-backup-*.tar.gz 2>/dev/null || echo "  No backups found."
           read -rp "  Press Enter..."; backup_restore_menu ;;
        0) main_menu ;;
        *) backup_restore_menu ;;
    esac
}

create_backup() {
    local BK="/root/ragnar-backup-$(date '+%Y%m%d-%H%M%S').tar.gz"
    tar -czf "$BK" "$CONFIG_DIR" /etc/ssh/sshd_config /etc/stunnel 2>/dev/null
    echo -e "  ${GREEN}[✓] Backup saved: ${BK}${NC}"
    log "Backup created: $BK"
    read -rp "  Press Enter..."; backup_restore_menu
}

restore_backup() {
    echo -ne "  ${YELLOW}Backup file path: ${NC}"; read -r BK_PATH
    [[ ! -f "$BK_PATH" ]] && { echo -e "${RED}File not found.${NC}"; sleep 2; backup_restore_menu; return; }
    tar -xzf "$BK_PATH" -C / >> "$LOG_FILE" 2>&1
    systemctl restart ssh ssh-ws ssh-wss stunnel4 2>/dev/null
    echo -e "  ${GREEN}[✓] Restored from ${BK_PATH}.${NC}"
    log "Restored from: $BK_PATH"
    read -rp "  Press Enter..."; backup_restore_menu
}

# ── [I] System Info ───────────────────────────────────────────────

system_info() {
    banner
    local OS_INFO; OS_INFO=$(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')
    local UPTIME; UPTIME=$(uptime -p 2>/dev/null || uptime)
    local CPU; CPU=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 2>/dev/null || echo "N/A")
    local MEM_T; MEM_T=$(free -m | awk 'NR==2{print $2}')
    local MEM_U; MEM_U=$(free -m | awk 'NR==2{print $3}')
    local DISK; DISK=$(df -h / | awk 'NR==2{print $3"/"$2" ("$5")"}')
    local IFACE; IFACE=$(ip route get 1 2>/dev/null | awk '{print $5; exit}')
    local RX_B TX_B
    RX_B=$(awk -v i="${IFACE}:" '$1==i{print $2}' /proc/net/dev 2>/dev/null || echo 0)
    TX_B=$(awk -v i="${IFACE}:" '$1==i{print $10}' /proc/net/dev 2>/dev/null || echo 0)
    local RX_GB; RX_GB=$(awk "BEGIN{printf \"%.2f\", ${RX_B:-0}/1073741824}")
    local TX_GB; TX_GB=$(awk "BEGIN{printf \"%.2f\", ${TX_B:-0}/1073741824}")
    echo -e "  ${WHITE}┌──────────────────────────────────────────┐"
    echo -e "  │  OS      : ${OS_INFO}"
    echo -e "  │  Kernel  : $(uname -r)"
    echo -e "  │  Uptime  : ${UPTIME}"
    echo -e "  │  CPU     : ${CPU}%"
    echo -e "  │  RAM     : ${MEM_U} MB / ${MEM_T} MB"
    echo -e "  │  Disk    : ${DISK}"
    echo -e "  │  Iface   : ${IFACE}"
    echo -e "  │  RX      : ${RX_GB} GB (since boot)"
    echo -e "  │  TX      : ${TX_GB} GB (since boot)"
    echo -e "  │  Users   : $(wc -l < "$USER_DB") VPN users"
    echo -e "  │  Online  : $(who 2>/dev/null | wc -l) sessions"
    echo -e "  └──────────────────────────────────────────┘${NC}"
    read -rp "  Press Enter..."; main_menu
}

# ── [U] Update ────────────────────────────────────────────────────

update_panel() {
    banner
    echo -e "${CYAN}  [*] Checking for updates...${NC}\n"
    local REMOTE_URL="${REPO_RAW}/panel.sh"
    local CURRENT_SCRIPT="$INSTALL_DIR/panel.sh"

    local NEW_VER; NEW_VER=$(curl -sSL "$REMOTE_URL" 2>/dev/null | grep 'PANEL_VERSION=' | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
    [[ -z "$NEW_VER" ]] && { echo -e "${RED}Cannot reach update server.${NC}"; read -rp "Enter..."; main_menu; return; }

    echo -e "  Current : ${WHITE}v${PANEL_VERSION}${NC}"
    echo -e "  Latest  : ${WHITE}v${NEW_VER}${NC}\n"

    if [[ "$NEW_VER" == "$PANEL_VERSION" ]]; then
        echo -e "  ${GREEN}[✓] Already up to date!${NC}"; read -rp "Enter..."; main_menu; return
    fi

    cp "$CURRENT_SCRIPT" "${CURRENT_SCRIPT}.bak" 2>/dev/null
    curl -sSL "$REMOTE_URL" -o "${CURRENT_SCRIPT}.tmp"
    [[ ! -s "${CURRENT_SCRIPT}.tmp" ]] && {
        echo -e "${RED}Download failed.${NC}"; rm -f "${CURRENT_SCRIPT}.tmp"
        read -rp "Enter..."; main_menu; return
    }
    mv "${CURRENT_SCRIPT}.tmp" "$CURRENT_SCRIPT"
    chmod +x "$CURRENT_SCRIPT"
    echo -e "  ${GREEN}[✓] Updated to v${NEW_VER}! Relaunching...${NC}"
    log "Panel updated v${PANEL_VERSION} -> v${NEW_VER}"
    read -rp "  Press Enter..."
    exec bash "$CURRENT_SCRIPT"
}

# ── Expiry / Cron ─────────────────────────────────────────────────

setup_expiry_cron() {
    cat > /usr/local/bin/ssh-vpn-expiry.sh << 'EXEOF'
#!/bin/bash
USER_DB="/etc/ssh-vpn-panel/users.db"
LOG_FILE="/var/log/ssh-vpn-panel.log"
[[ ! -f "$USER_DB" ]] && exit 0
while IFS='|' read -r U P EXP ML CD ST; do
    [[ -z "$U" ]] && continue
    [[ "$ST" == "locked" ]] && continue
    EXP_TS=$(date -d "$EXP" +%s 2>/dev/null) || continue
    NOW_TS=$(date +%s)
    if [[ "$EXP_TS" -lt "$NOW_TS" ]]; then
        id "$U" &>/dev/null && {
            passwd -l "$U" 2>/dev/null
            pkill -u "$U" 2>/dev/null
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Auto-expired: $U" >> "$LOG_FILE"
        }
    fi
done < "$USER_DB"
EXEOF
    chmod +x /usr/local/bin/ssh-vpn-expiry.sh
    (crontab -l 2>/dev/null | grep -v 'ssh-vpn-expiry'; echo "*/10 * * * * /usr/local/bin/ssh-vpn-expiry.sh") | crontab -
}

run_expiry_cleanup() {
    bash /usr/local/bin/ssh-vpn-expiry.sh
    echo -e "  ${GREEN}[✓] Expiry cleanup done.${NC}"
}

# ── [X] Uninstall ─────────────────────────────────────────────────

uninstall_panel() {
    banner
    echo -e "${RED}  [!] FULL UNINSTALL — removes everything added by this panel${NC}\n"
    echo -e "  Will remove:"
    echo -e "  ${RED}●${NC} ssh-ws / ssh-wss / stunnel4 / cloudflared / ragnar-web services"
    echo -e "  ${RED}●${NC} WS proxy, web panel, expiry script, cloudflared binary"
    echo -e "  ${RED}●${NC} Stunnel config + TLS certificates"
    echo -e "  ${RED}●${NC} Panel config dir, user database, log file"
    echo -e "  ${RED}●${NC} SSH ports 80/443 added by panel"
    echo -e "  ${RED}●${NC} SSH banner, cron job, 'vpn' alias"
    echo -e "  ${YELLOW}  SSH server itself stays intact.${NC}\n"
    echo -ne "  ${RED}Type UNINSTALL to confirm: ${NC}"; read -r C
    [[ "$C" != "UNINSTALL" ]] && { main_menu; return; }

    echo -e "\n  ${CYAN}Removing services...${NC}"
    for SVC in cloudflared-tunnel ssh-ws ssh-wss stunnel4 ragnar-web; do
        systemctl stop    "$SVC" 2>/dev/null
        systemctl disable "$SVC" 2>/dev/null
        rm -f "/etc/systemd/system/${SVC}.service"
        echo -e "  ${GREEN}[✓]${NC} $SVC removed"
    done
    systemctl daemon-reload

    echo -e "\n  ${CYAN}Removing binaries + configs...${NC}"
    rm -f /usr/local/bin/cloudflared /usr/local/bin/ssh-ws-proxy.py
    rm -f /usr/local/bin/ssh-vpn-expiry.sh /usr/local/bin/ragnar-web-panel.py
    rm -f /usr/local/bin/vpn
    rm -rf "$CONFIG_DIR" "$INSTALL_DIR" "$LOG_FILE"
    rm -rf /etc/stunnel /var/log/stunnel4 /etc/ssh/banner
    echo -e "  ${GREEN}[✓]${NC} Files removed"

    echo -e "\n  ${CYAN}Cleaning SSH config...${NC}"
    local CFG="/etc/ssh/sshd_config"
    sed -i '/^Port 80$/d;/^Port 443$/d;/^Banner \/etc\/ssh\/banner$/d' "$CFG" 2>/dev/null
    rm -f /etc/ssh/sshd_config.backup.* 2>/dev/null
    systemctl restart ssh 2>/dev/null
    echo -e "  ${GREEN}[✓]${NC} SSH config cleaned"

    crontab -l 2>/dev/null | grep -v 'ssh-vpn-expiry' | crontab -
    echo -e "  ${GREEN}[✓]${NC} Cron removed"
    echo -e "\n  ${GREEN}[✓] Panel fully uninstalled. Server is clean.${NC}\n"
    exit 0
}

# ── Entry ─────────────────────────────────────────────────────────

check_root
init_panel
main_menu
