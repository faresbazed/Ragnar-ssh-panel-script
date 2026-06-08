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

    grep -q "^Port 80$" "$CFG" || echo "Port 80" >> "$CFG"

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
Ragnar SSH-WebSocket Proxy v3 — Robust NPV Tunnel Handler

Key fixes over v2:
  1. choose_response() checks for 'Upgrade: websocket' ANYWHERE in ALL
     collected headers — works regardless of non-standard first-line
     methods (GET, CF-RAY, custom methods, etc.).
  2. drain_extra_payload() discards any stale HTTP segment that arrives
     AFTER we have sent our 101/200 response, preventing CF-RAY or
     other late payload bytes from reaching the SSH daemon as garbage.
  3. Extended second-segment wait (2 s instead of 0.4 s) to absorb
     slow double-header payloads used by some NPV Tunnel configs.
  4. Gracefully handles 301/501/any redirect: non-HTTP bytes from a
     redirect are discarded; SSH gets only clean tunnel data.
"""
import socket, threading, select, sys

SSH_HOST = '127.0.0.1'
SSH_PORT = 22
BUFFER   = 65536
TIMEOUT  = 120

WS_101 = (
    b"HTTP/1.1 101 Switching Protocols\r\n"
    b"Upgrade: websocket\r\n"
    b"Connection: Upgrade\r\n\r\n"
)
CONNECT_200 = b"HTTP/1.1 200 Connection established\r\n\r\n"

# ── Pipe ─────────────────────────────────────────────────────────

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

# ── Payload reader ───────────────────────────────────────────────

def read_full_payload(sock):
    """
    Collect the entire HTTP payload from the client.

    NPV Tunnel sends a double-header sequence:
      Segment 1:  GET / HTTP/1.1\\r\\nHost: fake\\r\\n\\r\\n
      Segment 2:  CF-RAY / HTTP/1.1\\r\\nHost: real\\r\\nUpgrade: websocket\\r\\n\\r\\n

    We read until we see 2 complete segments (two \\r\\n\\r\\n markers) or
    until we time out waiting for the second segment.
    The wait for the second segment is 2 s (extended from 0.4 s) to handle
    slow NPV Tunnel clients without dropping the CF-RAY segment.
    """
    buf = b""
    sock.settimeout(5)
    try:
        while len(buf) < 65536:
            chunk = sock.recv(4096)
            if not chunk:
                break
            buf += chunk

            seg_count = buf.count(b'\r\n\r\n')
            if seg_count >= 2:
                break                       # both segments received — done
            if seg_count == 1:
                # First segment complete — wait up to 2 s for a second
                sock.settimeout(2.0)
                try:
                    extra = sock.recv(4096)
                    if extra:
                        buf += extra
                except socket.timeout:
                    pass
                break
    except socket.timeout:
        pass

    sock.settimeout(TIMEOUT)

    last_end = buf.rfind(b'\r\n\r\n')
    if last_end >= 0:
        leftover = buf[last_end + 4:]   # SSH bytes that arrived with payload
        headers  = buf[:last_end]
    else:
        leftover = b""
        headers  = buf

    return headers.decode('utf-8', errors='ignore'), leftover

# ── Post-response drain ──────────────────────────────────────────

def drain_extra_payload(sock):
    """
    After we have sent our HTTP upgrade response, drain any stale HTTP
    segment that may arrive late from the client (e.g. the CF-RAY second
    segment that was too slow to be caught by read_full_payload).

    Heuristic: data containing \\r\\n but NOT starting with 'SSH-' is
    almost certainly a stale HTTP payload segment and must be discarded.
    Binary SSH handshake bytes (or 'SSH-2.0-...' banner) are returned as
    leftover to be forwarded to the SSH daemon.
    """
    sock.settimeout(0.5)
    leftover = b""
    try:
        chunk = sock.recv(4096)
        if chunk:
            if b'\r\n' in chunk and not chunk.startswith(b'SSH-'):
                # Stale HTTP segment — find its end and keep any remainder
                end = chunk.find(b'\r\n\r\n')
                if end >= 0:
                    leftover = chunk[end + 4:]
                # else: entirely HTTP — discard all of it
            else:
                leftover = chunk
    except socket.timeout:
        pass
    sock.settimeout(TIMEOUT)
    return leftover

# ── Response chooser ─────────────────────────────────────────────

def choose_response(headers_text):
    """
    Decide which HTTP response to send.

    Priority:
    1. Any line starting with CONNECT → 200 Connection established
    2. 'Upgrade: websocket' found ANYWHERE in headers → 101
    3. Default (any other method, including CF-RAY) → 101
    """
    lower = headers_text.lower()
    for line in headers_text.splitlines():
        if line.upper().startswith('CONNECT'):
            return CONNECT_200
    if 'upgrade: websocket' in lower:
        return WS_101
    # Non-standard method (CF-RAY, custom, etc.) — assume WebSocket upgrade
    return WS_101

# ── Connection handler ───────────────────────────────────────────

def handle(client):
    ssh = None
    try:
        headers, leftover = read_full_payload(client)

        response = choose_response(headers)
        client.sendall(response)

        # Drain any HTTP segment that arrived after we sent our response
        extra = drain_extra_payload(client)
        if extra:
            leftover = (leftover + extra) if leftover else extra

        ssh = socket.create_connection((SSH_HOST, SSH_PORT), timeout=10)
        ssh.settimeout(TIMEOUT)

        if leftover:
            ssh.sendall(leftover)

        stop = threading.Event()
        t1 = threading.Thread(target=pipe, args=(client, ssh, stop), daemon=True)
        t2 = threading.Thread(target=pipe, args=(ssh, client, stop), daemon=True)
        t1.start()
        t2.start()
        stop.wait()

    except Exception:
        pass
    finally:
        for s in (client, ssh):
            try:
                if s:
                    s.close()
            except Exception:
                pass

# ── Server ───────────────────────────────────────────────────────

def serve(port):
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(('0.0.0.0', port))
    srv.listen(1024)
    print(f"[Ragnar-WS v3] :{port} -> SSH:{SSH_PORT}", flush=True)
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
Description=Ragnar SSH-WebSocket Proxy v3 (port ${PORT})
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
Description=Ragnar SSH-WebSocket Proxy v3 fallback (port 8880)
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
        sed -i "s|^${USERNAME}|.*|${NEW_LINE}|" "$USER_DB"
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
"""Ragnar Web Panel v3 — browser-based SSH VPN management. No external deps."""
import os, json, subprocess, time, html
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import parse_qs, urlparse
import secrets as _sec

PORT     = int(os.environ.get("WEB_PORT", "8080"))
PASSWORD = os.environ.get("WEB_PASS", "ragnar")
CONFIG   = "/etc/ssh-vpn-panel"
USER_DB  = f"{CONFIG}/users.db"
LOG_FILE = "/var/log/ssh-vpn-panel.log"

TOKENS   = {}   # token -> expiry timestamp
TOKEN_TTL = 3600

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
                    u = p[0]
                    online = sh(f"who | grep -c '^{u} ' 2>/dev/null || echo 0").split()[0]
                    lock = sh(f"passwd -S {u} 2>/dev/null | awk '{{print $2}}'")
                    rows.append(dict(user=u, pw=p[1], exp=p[2], ml=p[3], created=p[4], lock=lock, online=online))
    except:
        pass
    return rows

def info():
    return dict(
        ip       = ip_addr(),
        uptime   = sh("uptime -p"),
        cpu      = sh("top -bn1 | grep 'Cpu(s)' | awk '{print $2}'"),
        mem_u    = sh("free -m | awk 'NR==2{print $3}'"),
        mem_t    = sh("free -m | awk 'NR==2{print $2}'"),
        disk     = sh("df -h / | awk 'NR==2{print $3\"/\"$2\" (\"$5\")'\"'\"'}"),
        users    = sh(f"wc -l < {USER_DB}").strip(),
        online   = sh("who | wc -l").strip(),
        ssh      = svc("ssh"),
        ws       = svc("ssh-ws"),
        tls      = svc("stunnel4"),
        cf       = svc("cloudflared-tunnel"),
        web      = svc("ragnar-web"),
        ws_port  = sh(f"cat {CONFIG}/ws_port.txt 2>/dev/null || echo 80"),
        cf_dom   = sh(f"cat {CONFIG}/cf_domain.txt 2>/dev/null | sed 's|https://||'"),
    )

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
    for part in hdrs.get("Cookie","").split(";"):
        k, _, v = part.strip().partition("=")
        if k.strip() == "rp": return v.strip()
    return ""

CSS = """
*{box-sizing:border-box;margin:0;padding:0}
body{background:#0d1117;color:#e6edf3;font-family:'Segoe UI',Arial,sans-serif;font-size:14px}
.nav{background:#161b22;border-bottom:1px solid #30363d;padding:14px 24px;display:flex;align-items:center;gap:16px}
.nav h1{font-size:18px;color:#58a6ff;font-weight:700}
.nav .sub{color:#8b949e;font-size:13px}
.nav a{color:#8b949e;text-decoration:none;margin-left:auto;font-size:13px}
.nav a:hover{color:#58a6ff}
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

def render_login(err=""):
    e = f'<div class="err">{html.escape(err)}</div>' if err else ""
    return f"""<!DOCTYPE html><html><head><meta charset=utf-8><title>Ragnar Panel</title><style>{CSS}</style></head>
<body><div class="login"><div class="lbox">
<h2>Ragnar Panel</h2>{e}
<form method=POST action=/login>
<input type=password name=password placeholder="Password" autofocus required>
<button>Sign In</button></form></div></div></body></html>"""

def badge(s):
    cls = "ok" if s == "active" else "off"
    label = "active" if s == "active" else s or "inactive"
    return f'<span class="dot {cls}"></span>{label}'

def render_dash(d, users):
    user_rows = ""
    for u in users:
        lk = "Locked" if u["lock"] in ("L","LK") else "Active"
        lk_color = "color:#f85149" if u["lock"] in ("L","LK") else "color:#3fb950"
        user_rows += f"""<tr>
<td><strong>{html.escape(u['user'])}</strong></td>
<td>{html.escape(u['exp'])}</td>
<td>{html.escape(u['created'])}</td>
<td>{html.escape(u['ml'])}</td>
<td>{html.escape(str(u['online']))}</td>
<td style="{lk_color}">{lk}</td>
<td style="display:flex;gap:5px;flex-wrap:wrap">
  <form method=POST action=/user/kill style=display:inline>
    <input type=hidden name=u value="{html.escape(u['user'])}">
    <button class="btn b-gray" onclick="return confirm('Kill sessions for {html.escape(u[\"user\"])}?')">Kill</button></form>
  <form method=POST action=/user/lock style=display:inline>
    <input type=hidden name=u value="{html.escape(u['user'])}">
    <button class="btn b-gray">Lock/Unlock</button></form>
  <form method=POST action=/user/delete style=display:inline>
    <input type=hidden name=u value="{html.escape(u['user'])}">
    <button class="btn b-red" onclick="return confirm('Delete {html.escape(u[\"user\"])}?')">Delete</button></form>
</td></tr>"""

    svc_html = ""
    for name, key in [("SSH","ssh"),("WebSocket","ws"),("TLS/Stunnel","tls"),("Cloudflare","cf"),("Web Panel","web")]:
        svc_html += f'<span>{name} {badge(d[key])}</span>'
    cf_row = f'<div style="padding:0 18px 10px;color:#8b949e;font-size:12px">Cloudflare: {html.escape(d["cf_dom"])}</div>' if d["cf_dom"] else ""
    log_txt = html.escape(sh(f"tail -n 50 {LOG_FILE}"))

    return f"""<!DOCTYPE html><html><head><meta charset=utf-8><title>Ragnar Panel</title>
<style>{CSS}</style><meta http-equiv=refresh content=30></head><body>
<div class="nav"><h1>Ragnar Web Panel</h1><span class="sub">v3.0.0</span>
<a href=/logout>Sign Out</a></div>
<div class="wrap">

<div class="grid">
  <div class="card"><h3>Server IP</h3><div class="v" style="font-size:15px">{html.escape(d['ip'])}</div><div class="s">Uptime: {html.escape(d['uptime'])}</div></div>
  <div class="card"><h3>VPN Users</h3><div class="v">{html.escape(d['users'])}</div><div class="s">{html.escape(d['online'])} online</div></div>
  <div class="card"><h3>CPU</h3><div class="v">{html.escape(d['cpu'])}%</div></div>
  <div class="card"><h3>Memory</h3><div class="v">{html.escape(d['mem_u'])} MB</div><div class="s">of {html.escape(d['mem_t'])} MB</div></div>
  <div class="card"><h3>Disk</h3><div class="v" style="font-size:14px">{html.escape(d['disk'])}</div></div>
</div>

<div class="panel">
  <div class="ph"><h2>Services</h2>
  <div style="display:flex;gap:6px;flex-wrap:wrap">
    <form method=POST action=/svc/restart><input type=hidden name=svc value=ssh-ws><button class="btn b-blue">Restart WS</button></form>
    <form method=POST action=/svc/restart><input type=hidden name=svc value=stunnel4><button class="btn b-blue">Restart TLS</button></form>
    <form method=POST action=/svc/restart><input type=hidden name=svc value=cloudflared-tunnel><button class="btn b-blue">Restart CF</button></form>
    <form method=POST action=/svc/restart><input type=hidden name=svc value=ssh><button class="btn b-blue">Restart SSH</button></form>
  </div></div>
  <div class="svc-row">{svc_html}</div>
  {cf_row}
</div>

<div class="panel">
  <div class="ph"><h2>Users</h2></div>
  <form method=POST action=/user/create class="fr">
    <input name=username placeholder="Username" required>
    <input name=password type=password placeholder="Password" required>
    <input name=days placeholder="Days (30)" value="30" style="max-width:90px">
    <input name=ml placeholder="MaxLogin (2)" value="2" style="max-width:90px">
    <button class="btn b-green" type=submit>+ Add User</button>
  </form>
  <table>
    <tr><th>User</th><th>Expires</th><th>Created</th><th>MaxLogin</th><th>Online</th><th>Status</th><th>Actions</th></tr>
    {user_rows or '<tr><td colspan=7 style="text-align:center;color:#8b949e;padding:22px">No users yet</td></tr>'}
  </table>
</div>

<div class="panel">
  <div class="ph"><h2>Panel Log</h2></div>
  <div class="log">{log_txt}</div>
</div>

</div></body></html>"""

class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def send_html(self, body, status=200, hdrs=None):
        b = body.encode()
        self.send_response(status)
        self.send_header("Content-Type","text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(b)))
        for k,v in (hdrs or {}).items(): self.send_header(k,v)
        self.end_headers(); self.wfile.write(b)
    def redir(self, to, hdrs=None):
        self.send_response(302)
        self.send_header("Location", to)
        for k,v in (hdrs or {}).items(): self.send_header(k,v)
        self.end_headers()
    def body(self):
        n = int(self.headers.get("Content-Length",0))
        return parse_qs(self.rfile.read(n).decode()) if n else {}
    def authed(self): return tok_ok(get_tok(self.headers))

    def do_GET(self):
        path = urlparse(self.path).path
        if path == "/logout":
            TOKENS.pop(get_tok(self.headers), None); self.redir("/"); return
        if not self.authed():
            self.send_html(render_login()); return
        self.send_html(render_dash(info(), read_users()))

    def do_POST(self):
        path = urlparse(self.path).path
        if path == "/login":
            pw = self.body().get("password",[""])[0]
            if pw == PASSWORD:
                t = tok_new()
                self.redir("/", {"Set-Cookie": f"rp={t}; Path=/; HttpOnly; Max-Age={TOKEN_TTL}"})
            else:
                self.send_html(render_login("Wrong password"))
            return
        if not self.authed(): self.redir("/"); return
        p = self.body()

        if path == "/svc/restart":
            svc = p.get("svc",[""])[0]
            if svc and all(c.isalnum() or c=='-' for c in svc):
                sh(f"systemctl restart {svc}")

        elif path == "/user/create":
            u = p.get("username",[""])[0].strip()
            pw= p.get("password",[""])[0].strip()
            d = p.get("days",["30"])[0].strip() or "30"
            ml= p.get("ml",["2"])[0].strip() or "2"
            if u and pw and u.replace("_","").isalnum():
                exp = sh(f"date -d '+{d} days' '+%Y-%m-%d'")
                sh(f"useradd -M -s /bin/false -e {exp} {u}")
                sh(f"echo '{u}:{pw}' | chpasswd")
                today = sh("date '+%Y-%m-%d'")
                with open(USER_DB,"a") as f: f.write(f"{u}|{pw}|{exp}|{ml}|{today}|active\n")

        elif path == "/user/delete":
            u = p.get("u",[""])[0].strip()
            if u and u.replace("_","").isalnum():
                sh(f"pkill -u {u}"); sh(f"userdel -f {u}")
                lines = []
                try:
                    with open(USER_DB) as f: lines = [l for l in f if not l.startswith(f"{u}|")]
                    with open(USER_DB,"w") as f: f.writelines(lines)
                except: pass

        elif path == "/user/kill":
            u = p.get("u",[""])[0].strip()
            if u and u.replace("_","").isalnum(): sh(f"pkill -u {u}")

        elif path == "/user/lock":
            u = p.get("u",[""])[0].strip()
            if u and u.replace("_","").isalnum():
                st = sh(f"passwd -S {u} | awk '{{print $2}}'")
                if st in ("L","LK"): sh(f"passwd -u {u}")
                else: sh(f"passwd -l {u}"); sh(f"pkill -u {u}")

        self.redir("/")

if __name__ == "__main__":
    print(f"[Ragnar Web Panel v3] http://0.0.0.0:{PORT}", flush=True)
    HTTPServer(("0.0.0.0", PORT), H).serve_forever()
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
        sed -i "s/WEB_PORT=.*/WEB_PORT=${NEW_PORT}\"/" /etc/systemd/system/ragnar-web.service
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
        sed -i "s/WEB_PASS=.*/WEB_PASS=${NEW_PASS}\"/" /etc/systemd/system/ragnar-web.service
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
