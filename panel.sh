#!/bin/bash
# ================================================================
#   RAGNAR SSH VPN PANEL v2.0.0
#   NPV Tunnel Optimized
#   Features: SSH-WS | SSH-TLS | Cloudflare | User Mgmt
#             Auto-Expiry | Conn Limits | Payload Config
#             Backup/Restore | Live Monitor | Log Viewer
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

PANEL_VERSION="2.0.0"
REPO_RAW="https://raw.githubusercontent.com/faresbazed/Ragnar-ssh-panel-script/main"
CONFIG_DIR="/etc/ssh-vpn-panel"
USER_DB="$CONFIG_DIR/users.db"
LOG_FILE="/var/log/ssh-vpn-panel.log"
CF_DOMAIN_FILE="$CONFIG_DIR/cf_domain.txt"
PAYLOAD_FILE="$CONFIG_DIR/payload.txt"
INSTALL_DIR="/usr/local/ssh-vpn-panel"
WS_PORT_FILE="$CONFIG_DIR/ws_port.txt"

# ── Helpers ──────────────────────────────────────────────────────

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"; }

check_root() {
    [[ $EUID -ne 0 ]] && { echo -e "${RED}Run as root.${NC}"; exit 1; }
}

init_panel() {
    mkdir -p "$CONFIG_DIR" "$INSTALL_DIR"
    touch "$USER_DB" "$LOG_FILE"
    [[ ! -f "$WS_PORT_FILE" ]] && echo "80" > "$WS_PORT_FILE"
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

get_ws_port() { cat "$WS_PORT_FILE" 2>/dev/null || echo "80"; }

# ── Banner ───────────────────────────────────────────────────────

banner() {
    clear
    local IP; IP=$(get_public_ip)
    local WS_P; WS_P=$(get_ws_port)
    local CF_DOM; CF_DOM=$(cat "$CF_DOMAIN_FILE" 2>/dev/null | sed 's|https://||' || echo "Not set")
    local S_SSH; S_SSH=$(svc_status ssh)
    local S_WS;  S_WS=$(svc_status ssh-ws)
    local S_TLS; S_TLS=$(svc_status stunnel4)
    local S_CF;  S_CF=$(svc_status cloudflared-tunnel)
    echo -e "${CYAN}"
    echo "  ╔══════════════════════════════════════════════════════════╗"
    printf "  ║  %bRAGNAR SSH VPN PANEL%b %-6s %30s ║\n" "$BOLD$WHITE" "$CYAN" "v${PANEL_VERSION}" ""
    echo "  ╠══════════════════════════════════════════════════════════╣"
    printf "  ║  IP  : %-20s  Date: %-20s║\n" "${WHITE}${IP}${CYAN}" "${WHITE}$(date '+%d/%m/%y %H:%M:%S')${CYAN}"
    printf "  ║  WS  : %-6s  TLS: %-6s  CF: %-6s  SSH: %-12s║\n" \
        "$(get_ws_port)" "443" "${CF_DOM:0:18}" "22"
    printf "  ║  %b SSH %b%b WS %b%b TLS %b%b CF %b   Services Status              ║\n" \
        "$NC" "$S_SSH" "$NC" "$S_WS" "$NC" "$S_TLS" "$NC" "$S_CF" 
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

    echo -e "${YELLOW}  [1/6] Updating packages...${NC}"
    $PKG_MANAGER update -y >> "$LOG_FILE" 2>&1

    echo -e "${YELLOW}  [2/6] Installing dependencies...${NC}"
    $PKG_MANAGER install -y openssh-server curl wget python3 python3-pip \
        stunnel4 net-tools iptables openssl cron >> "$LOG_FILE" 2>&1

    echo -e "${YELLOW}  [3/6] Configuring SSH (safe, preserves your ports)...${NC}"
    configure_ssh_safe

    echo -e "${YELLOW}  [4/6] Setting up SSH-WebSocket on port 80...${NC}"
    deploy_ws_proxy 80

    echo -e "${YELLOW}  [5/6] Setting up SSH-TLS (Stunnel) on port 443...${NC}"
    deploy_stunnel_silent

    echo -e "${YELLOW}  [6/6] Setting up auto-expiry cron...${NC}"
    setup_expiry_cron

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

    # Only ADD ports 80/443 if not already there — never remove existing ports
    for P in 80 443; do
        grep -q "^Port ${P}$" "$CFG" || echo "Port ${P}" >> "$CFG"
    done

    # Safe sed — won't duplicate lines
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
Ragnar SSH-WebSocket Proxy for NPV Tunnel
Handles: HTTP CONNECT, WebSocket Upgrade, raw TCP
"""
import socket, threading, select, sys, re, time

SSH_HOST = '127.0.0.1'
SSH_PORT = 22
BUFFER   = 65536
TIMEOUT  = 120

WS_RESPONSE = (
    "HTTP/1.1 101 Switching Protocols\r\n"
    "Upgrade: websocket\r\n"
    "Connection: Upgrade\r\n"
    "Sec-WebSocket-Accept: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n"
)
HTTP_200 = "HTTP/1.1 200 Connection established\r\n\r\n"
HTTP_400 = "HTTP/1.1 400 Bad Request\r\n\r\n"

def pipe(src, dst, stop_evt):
    try:
        while not stop_evt.is_set():
            r, _, _ = select.select([src], [], [], 5)
            if not r: continue
            d = src.recv(BUFFER)
            if not d: break
            dst.sendall(d)
    except Exception: pass
    stop_evt.set()

def handle(client):
    try:
        client.settimeout(TIMEOUT)
        hdr = b""
        while b"\r\n\r\n" not in hdr:
            chunk = client.recv(4096)
            if not chunk: return
            hdr += chunk
            if len(hdr) > 8192: break

        hdr_str = hdr.decode('utf-8', errors='ignore')

        # WebSocket Upgrade request
        if 'Upgrade: websocket' in hdr_str or 'upgrade: websocket' in hdr_str:
            client.sendall(WS_RESPONSE.encode())

        # HTTP CONNECT method (some NPV Tunnel modes)
        elif hdr_str.startswith('CONNECT'):
            client.sendall(HTTP_200.encode())

        # HTTP GET with custom payload (NPV Tunnel inject mode)
        elif hdr_str.startswith('GET') or hdr_str.startswith('POST'):
            client.sendall(WS_RESPONSE.encode())

        # Raw TCP — just forward directly
        # else: pass through

        ssh = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        ssh.connect((SSH_HOST, SSH_PORT))
        ssh.settimeout(TIMEOUT)

        stop = threading.Event()
        t1 = threading.Thread(target=pipe, args=(client, ssh, stop), daemon=True)
        t2 = threading.Thread(target=pipe, args=(ssh, client, stop), daemon=True)
        t1.start(); t2.start()
        stop.wait()
        ssh.close()
    except Exception: pass
    finally:
        try: client.close()
        except Exception: pass

def serve(port):
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(('0.0.0.0', port))
    srv.listen(512)
    print(f"[Ragnar-WS] Listening on :{port} → SSH :{SSH_PORT}", flush=True)
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

    # Main WS service (port from arg)
    cat > /etc/systemd/system/ssh-ws.service << SVCEOF
[Unit]
Description=Ragnar SSH-WebSocket Proxy (port ${PORT})
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

    # Secondary WS service on 8880 (fallback)
    cat > /etc/systemd/system/ssh-wss.service << 'SVCEOF2'
[Unit]
Description=Ragnar SSH-WebSocket Proxy fallback (port 8880)
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
    echo -e "${CYAN}  [*] Installing SSH-WebSocket Proxy...${NC}\n"
    echo -ne "  ${YELLOW}WS Port [80]: ${NC}"; read -r WS_PORT
    WS_PORT=${WS_PORT:-80}
    deploy_ws_proxy "$WS_PORT"
    local IP; IP=$(get_public_ip)
    echo -e "\n  ${GREEN}[✓] WebSocket proxy deployed on port ${WS_PORT}!${NC}"
    echo -e "  WS URL  : ws://${IP}:${WS_PORT}"
    echo -e "  WSS URL : ws://${IP}:8880 (fallback)"
    log "WS proxy installed on port $WS_PORT"
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

[npv-tls]
accept  = 443
connect = 127.0.0.1:22
cert    = /etc/stunnel/stunnel.pem
TIMEOUTclose = 0
STLCONF

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
        4) systemctl stop cloudflared-tunnel; systemctl disable cloudflared-tunnel; echo -e "  ${YELLOW}Stopped.${NC}"; sleep 1; cloudflare_menu ;;
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
        command -v cloudflared &>/dev/null || { echo -e "${RED}Install failed.${NC}"; read -rp "Enter..."; cloudflare_menu; return; }
        echo -e "  ${GREEN}[✓] cloudflared installed.${NC}"
    else
        echo -e "  ${GREEN}[✓] cloudflared already present.${NC}"
    fi

    local WS_P; WS_P=$(get_ws_port)
    cat > /etc/systemd/system/cloudflared-tunnel.service << CFSVC
[Unit]
Description=Cloudflare Quick Tunnel → SSH-WS port ${WS_P}
After=network.target ssh-ws.service

[Service]
Type=simple
ExecStart=/usr/local/bin/cloudflared tunnel --url http://localhost:${WS_P} --no-autoupdate
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
    local IP; IP=$(get_public_ip)
    echo -e "\n  ${WHITE}┌──────────────────────────────────────────────────────┐"
    echo -e "  │  NPV Tunnel Settings via Cloudflare:                 │"
    echo -e "  ├──────────────────────────────────────────────────────┤"
    echo -e "  │  SSH Host   : ${IP}"
    echo -e "  │  SSH Port   : 22"
    echo -e "  │  Proxy Host : ${DOM}"
    echo -e "  │  Proxy Port : 443 (Cloudflare HTTPS)"
    echo -e "  │  Proxy Type : WebSocket over HTTPS"
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

    # Always /bin/false — VPN-only, no terminal access
    useradd -M -s /bin/false -e "$EXPIRY" "$USERNAME" >> "$LOG_FILE" 2>&1
    echo "$USERNAME:$PASSWORD" | chpasswd >> "$LOG_FILE" 2>&1

    # Enforce max login limit via ~/.ssh/authorized_keys isn't applicable here.
    # We enforce via cron-based connection checker instead.
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
    sed -i "/^${USERNAME}|/d" "$USER_DB"
    echo -e "  ${GREEN}[✓] Deleted.${NC}"; log "User deleted: $USERNAME"
    read -rp "  Press Enter..."; user_management_menu
}

extend_user() {
    banner
    echo -ne "  ${YELLOW}Username: ${NC}"; read -r USERNAME
    ! id "$USERNAME" &>/dev/null && { echo -e "${RED}Not found.${NC}"; sleep 2; user_management_menu; return; }
    echo -ne "  ${YELLOW}Extend by days [30]: ${NC}"; read -r DAYS; DAYS=${DAYS:-30}

    local CUR_EXP; CUR_EXP=$(chage -l "$USERNAME" 2>/dev/null | grep "Account expires" | awk -F': ' '{print $2}')
    local NEW_EXP
    if [[ "$CUR_EXP" == "never" || -z "$CUR_EXP" ]]; then
        NEW_EXP=$(date -d "+${DAYS} days" '+%Y-%m-%d')
    else
        NEW_EXP=$(date -d "$CUR_EXP +${DAYS} days" '+%Y-%m-%d' 2>/dev/null || date -d "+${DAYS} days" '+%Y-%m-%d')
    fi

    chage -E "$NEW_EXP" "$USERNAME"
    # Update USER_DB
    sed -i "s/^${USERNAME}|\([^|]*\)|\([^|]*\)|/\1|\2|${NEW_EXP}|/" "$USER_DB"
    echo -e "  ${GREEN}[✓] Extended to ${NEW_EXP}.${NC}"; log "Extended: $USERNAME → $NEW_EXP"
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
        pkill -u "$USERNAME" 2>/dev/null && echo -e "  ${GREEN}[✓] Sessions for '${USERNAME}' killed.${NC}" \
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
        elif [[ "$DAYS_LEFT" -lt 0 ]]; then ST_CLR="${RED}Expired${NC}"
        elif [[ "$DAYS_LEFT" -lt 3 ]]; then ST_CLR="${YELLOW}Expiring${NC}"
        else ST_CLR="${GREEN}Active${NC}"; fi
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
    [[ "$LOCK" == "L" || "$LOCK" == "LK" ]] && STATUS="Locked" || STATUS="Active"
    echo -e "  ${WHITE}┌──────────────────────────────────────┐"
    echo -e "  │  Username  : ${USERNAME}"
    echo -e "  │  Status    : ${STATUS}"
    echo -e "  │  Created   : ${CREATED:-N/A}"
    echo -e "  │  Expires   : ${EXP:-N/A}"
    echo -e "  │  Days Left : ${DAYS_LEFT}"
    echo -e "  │  Max Login : ${MAXL:-N/A}"
    echo -e "  │  Online    : ${ONLINE} session(s)"
    echo -e "  │  Shell     : $(getent passwd "$USERNAME" | cut -d: -f7)"
    echo -e "  └──────────────────────────────────────┘${NC}"
    read -rp "  Press Enter..."; user_management_menu
}

# ── Auto-expiry cron ──────────────────────────────────────────────

setup_expiry_cron() {
    cat > /usr/local/bin/ssh-vpn-expiry.sh << 'CRONSH'
#!/bin/bash
USER_DB="/etc/ssh-vpn-panel/users.db"
LOG="/var/log/ssh-vpn-panel.log"
TODAY=$(date +%s)

while IFS='|' read -r U PASS EXP MAXL CREATED STATUS; do
    [[ -z "$U" ]] && continue
    ! id "$U" &>/dev/null && continue
    EXP_TS=$(date -d "$EXP" +%s 2>/dev/null || echo 0)
    if [[ "$EXP_TS" -lt "$TODAY" ]]; then
        pkill -u "$U" 2>/dev/null
        passwd -l "$U" >> "$LOG" 2>&1
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] AUTO-EXPIRED: $U (expired $EXP)" >> "$LOG"
    fi
    # Enforce max login limit
    ONLINE=$(who 2>/dev/null | grep -c "^${U} " || echo 0)
    if [[ "$ONLINE" -gt "$MAXL" ]]; then
        EXCESS=$((ONLINE - MAXL))
        # Kill the oldest excess sessions
        who 2>/dev/null | grep "^${U} " | head -"$EXCESS" | awk '{print $2}' | \
            while read -r TTY; do fuser -k "/dev/${TTY}" 2>/dev/null; done
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] LOGIN LIMIT: $U exceeded $MAXL logins, killed $EXCESS" >> "$LOG"
    fi
done < "$USER_DB"
CRONSH
    chmod +x /usr/local/bin/ssh-vpn-expiry.sh

    # Run every 5 minutes
    if ! crontab -l 2>/dev/null | grep -q 'ssh-vpn-expiry'; then
        (crontab -l 2>/dev/null; echo "*/5 * * * * /usr/local/bin/ssh-vpn-expiry.sh") | crontab -
    fi
}

run_expiry_cleanup() {
    echo -e "${CYAN}  [*] Running expiry cleanup...${NC}"
    bash /usr/local/bin/ssh-vpn-expiry.sh
    echo -e "  ${GREEN}[✓] Done. Check logs for details.${NC}"
    log "Manual expiry cleanup run"
}

# ── [7] Live Monitor ──────────────────────────────────────────────

monitor_connections() {
    echo -e "${YELLOW}  Live monitor — Ctrl+C to stop${NC}"
    while true; do
        banner
        echo -e "${CYAN}  Active Sessions — $(date '+%H:%M:%S')${NC}\n"
        printf "  ${WHITE}%-15s %-20s %-10s${NC}\n" "User" "From" "Since"
        echo -e "  ${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        local COUNT=0
        while IFS= read -r LINE; do
            local U; U=$(echo "$LINE" | awk '{print $1}')
            local FROM; FROM=$(echo "$LINE" | awk '{print $3}' | tr -d '()')
            local SINCE; SINCE=$(echo "$LINE" | awk '{print $4, $5}')
            # Get max login for this user
            local MAXL; MAXL=$(grep "^${U}|" "$USER_DB" 2>/dev/null | cut -d'|' -f4)
            local ONLINE; ONLINE=$(who 2>/dev/null | grep -c "^${U} " || echo 0)
            local WARN=""
            [[ -n "$MAXL" && "$ONLINE" -ge "$MAXL" ]] && WARN=" ${RED}[LIMIT]${NC}"
            printf "  %-15s %-20s %-10s" "$U" "$FROM" "$SINCE"
            echo -e "$WARN"
            ((COUNT++))
        done < <(who 2>/dev/null)
        echo -e "  ${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "  Total: ${GREEN}${COUNT}${NC} session(s)   Refresh: 5s   Ctrl+C = exit"
        sleep 5
    done
}

# ── [8] Connection Details ────────────────────────────────────────

show_connection_details() {
    banner
    local IP; IP=$(get_public_ip)
    local WS_P; WS_P=$(get_ws_port)
    local CF_DOM; CF_DOM=$(cat "$CF_DOMAIN_FILE" 2>/dev/null | sed 's|https://||' || echo "Not configured")
    local PAYLOAD; PAYLOAD=$(cat "$PAYLOAD_FILE" 2>/dev/null)

    echo -e "  ${WHITE}┌──────────────────────────────────────────────────────────┐"
    echo -e "  │            NPV TUNNEL CONNECTION CONFIG                  │"
    echo -e "  ├──────────────────────────────────────────────────────────┤"
    echo -e "  │  [SSH over WebSocket]"
    echo -e "  │  SSH Host  : ${IP}"
    echo -e "  │  SSH Port  : 22"
    echo -e "  │  WS Host   : ${IP}"
    echo -e "  │  WS Port   : ${WS_P}"
    echo -e "  │  Payload   : ${PAYLOAD}"
    echo -e "  ├──────────────────────────────────────────────────────────┤"
    echo -e "  │  [SSH over TLS — Stunnel]"
    echo -e "  │  SSH Host  : 127.0.0.1   SSH Port: 22"
    echo -e "  │  TLS Host  : ${IP}   TLS Port: 443"
    echo -e "  │  TLS Cert  : Skip verify"
    echo -e "  ├──────────────────────────────────────────────────────────┤"
    echo -e "  │  [Cloudflare (no IP blocking)]"
    echo -e "  │  SSH Host  : ${IP}   SSH Port: 22"
    echo -e "  │  WS Host   : ${CF_DOM}"
    echo -e "  │  WS Port   : 443"
    echo -e "  └──────────────────────────────────────────────────────────┘${NC}"

    echo -e "\n  ${YELLOW}Services:${NC}"
    for S in ssh ssh-ws ssh-wss stunnel4 cloudflared-tunnel; do
        if systemctl is-active --quiet "$S" 2>/dev/null; then
            echo -e "  ${GREEN}[✓] ${S}${NC}"
        else
            echo -e "  ${RED}[✗] ${S} — not running${NC}"
        fi
    done
    read -rp "  Press Enter..."; main_menu
}

# ── [9] Service Control ───────────────────────────────────────────

service_control_menu() {
    banner
    echo -e "${WHITE}  ┌──────────────────────────────────────┐${NC}"
    echo -e "${WHITE}  │        SERVICE CONTROL               │${NC}"
    echo -e "${WHITE}  ├──────────────────────────────────────┤${NC}"
    for S in ssh ssh-ws ssh-wss stunnel4 cloudflared-tunnel; do
        local ST; ST=$(svc_status "$S")
        printf "  │  %b %-28s│\n" "$ST" "$S"
    done
    echo -e "${WHITE}  ├──────────────────────────────────────┤${NC}"
    echo -e "${WHITE}  │ ${GREEN}[1]${WHITE} Restart ALL Services             │${NC}"
    echo -e "${WHITE}  │ ${GREEN}[2]${WHITE} Restart SSH-WS                  │${NC}"
    echo -e "${WHITE}  │ ${GREEN}[3]${WHITE} Restart Stunnel (TLS)           │${NC}"
    echo -e "${WHITE}  │ ${GREEN}[4]${WHITE} Restart Cloudflare Tunnel       │${NC}"
    echo -e "${WHITE}  │ ${GREEN}[5]${WHITE} Restart SSH daemon               │${NC}"
    echo -e "${WHITE}  │ ${RED}[0]${WHITE} Back                             │${NC}"
    echo -e "${WHITE}  └──────────────────────────────────────┘${NC}"
    echo -ne "\n  ${YELLOW}Select: ${NC}"; read -r OPT
    case $OPT in
        1) systemctl restart ssh ssh-ws ssh-wss stunnel4 cloudflared-tunnel 2>/dev/null
           echo -e "  ${GREEN}[✓] All services restarted.${NC}" ;;
        2) systemctl restart ssh-ws ssh-wss; echo -e "  ${GREEN}[✓] SSH-WS restarted.${NC}" ;;
        3) systemctl restart stunnel4; echo -e "  ${GREEN}[✓] Stunnel restarted.${NC}" ;;
        4) systemctl restart cloudflared-tunnel; echo -e "  ${GREEN}[✓] Cloudflare restarted.${NC}" ;;
        5) systemctl restart ssh; echo -e "  ${GREEN}[✓] SSH restarted.${NC}" ;;
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
    echo -e "${WHITE}  │ ${RED}[0]${WHITE} Back                             │${NC}"
    echo -e "${WHITE}  └──────────────────────────────────────┘${NC}"
    echo -ne "\n  ${YELLOW}Select: ${NC}"; read -r OPT
    case $OPT in
        1) tail -n 30 "$LOG_FILE" 2>/dev/null || echo "No logs yet" ;;
        2) tail -n 30 /var/log/auth.log 2>/dev/null || journalctl -u ssh -n 30 --no-pager ;;
        3) journalctl -u ssh-ws -n 30 --no-pager ;;
        4) tail -n 30 /var/log/stunnel4/stunnel.log 2>/dev/null || echo "No stunnel logs" ;;
        5) journalctl -u cloudflared-tunnel -n 30 --no-pager ;;
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
    echo -e "  ${WHITE}┌──────────────────────────────────────┐"
    echo -e "  │  OS      : ${OS_INFO}"
    echo -e "  │  Kernel  : $(uname -r)"
    echo -e "  │  Uptime  : ${UPTIME}"
    echo -e "  │  CPU     : ${CPU}%"
    echo -e "  │  RAM     : ${MEM_U} MB / ${MEM_T} MB"
    echo -e "  │  Disk    : ${DISK}"
    echo -e "  │  Users   : $(wc -l < "$USER_DB") VPN users"
    echo -e "  │  Online  : $(who 2>/dev/null | wc -l) sessions"
    echo -e "  └──────────────────────────────────────┘${NC}"
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
    [[ ! -s "${CURRENT_SCRIPT}.tmp" ]] && { echo -e "${RED}Download failed.${NC}"; rm -f "${CURRENT_SCRIPT}.tmp"; read -rp "Enter..."; main_menu; return; }
    mv "${CURRENT_SCRIPT}.tmp" "$CURRENT_SCRIPT"
    chmod +x "$CURRENT_SCRIPT"
    echo -e "  ${GREEN}[✓] Updated to v${NEW_VER}! Relaunching...${NC}"
    log "Panel updated v${PANEL_VERSION} → v${NEW_VER}"
    read -rp "  Press Enter..."
    exec bash "$CURRENT_SCRIPT"
}

# ── [X] Uninstall ─────────────────────────────────────────────────

uninstall_panel() {
    banner
    echo -e "${RED}  [!] UNINSTALL PANEL${NC}\n"
    echo -e "  Removes: WS proxy, Stunnel, Cloudflare, panel files, cron, 'vpn' command"
    echo -e "  ${YELLOW}SSH server stays intact.${NC}\n"
    echo -ne "  ${RED}Type UNINSTALL to confirm: ${NC}"; read -r C
    [[ "$C" != "UNINSTALL" ]] && { main_menu; return; }

    for SVC in cloudflared-tunnel ssh-ws ssh-wss stunnel4; do
        systemctl stop "$SVC" 2>/dev/null
        systemctl disable "$SVC" 2>/dev/null
        rm -f "/etc/systemd/system/${SVC}.service"
    done
    systemctl daemon-reload
    rm -f /usr/local/bin/cloudflared /usr/local/bin/ssh-ws-proxy.py /usr/local/bin/ssh-vpn-expiry.sh
    rm -rf "$CONFIG_DIR" "$INSTALL_DIR" "$LOG_FILE"
    rm -f /usr/local/bin/vpn
    # Remove cron entry
    crontab -l 2>/dev/null | grep -v 'ssh-vpn-expiry' | crontab -

    echo -e "\n  ${GREEN}[✓] Panel fully uninstalled.${NC}\n"
    exit 0
}

# ── Entry ─────────────────────────────────────────────────────────

check_root
init_panel
main_menu
