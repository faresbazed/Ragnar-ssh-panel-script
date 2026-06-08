#!/bin/bash
# ============================================================
#   SSH VPN PANEL — NPV Tunnel Ready
#   Supports: SSH-WS (80/443), SSH-TLS (443), Multi-port SSH
#             Cloudflare Free Domain (trycloudflare.com)
#   Compatible with: NPV Tunnel, HTTP Injector, and similar
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

PANEL_VERSION="1.1.0"
CONFIG_DIR="/etc/ssh-vpn-panel"
USER_DB="$CONFIG_DIR/users.db"
LOG_FILE="/var/log/ssh-vpn-panel.log"
CF_DOMAIN_FILE="$CONFIG_DIR/cf_domain.txt"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}[ERROR] This script must be run as root.${NC}"
        exit 1
    fi
}

init_panel() {
    mkdir -p "$CONFIG_DIR"
    touch "$USER_DB"
    touch "$LOG_FILE"
}

detect_os() {
    if [ -f /etc/debian_version ]; then
        OS="debian"
        PKG_MANAGER="apt-get"
    elif [ -f /etc/redhat-release ]; then
        OS="redhat"
        PKG_MANAGER="yum"
    else
        OS="unknown"
        PKG_MANAGER="apt-get"
    fi
}

get_public_ip() {
    PUBLIC_IP=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || \
                curl -s --max-time 5 https://ifconfig.me 2>/dev/null || \
                echo "Unknown")
    echo "$PUBLIC_IP"
}

banner() {
    clear
    IP=$(get_public_ip)
    echo -e "${CYAN}"
    echo "  ╔══════════════════════════════════════════════════════╗"
    echo "  ║          SSH VPN PANEL  v${PANEL_VERSION}                      ║"
    echo "  ║      NPV Tunnel / HTTP Injector Compatible           ║"
    echo "  ╠══════════════════════════════════════════════════════╣"
    echo -e "  ║  Server IP : ${WHITE}${IP}${CYAN}                                 "
    echo -e "  ║  Date/Time : ${WHITE}$(date '+%Y-%m-%d %H:%M:%S')${CYAN}                    "
    echo "  ╚══════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

main_menu() {
    banner
    echo -e "${WHITE}  ┌──────────────────────────────────────┐${NC}"
    echo -e "${WHITE}  │           MAIN MENU                  │${NC}"
    echo -e "${WHITE}  ├──────────────────────────────────────┤${NC}"
    echo -e "${WHITE}  │ ${GREEN}[1]${WHITE} Install SSH Services              │${NC}"
    echo -e "${WHITE}  │ ${GREEN}[2]${WHITE} SSH-WebSocket Setup (WS/WSS)      │${NC}"
    echo -e "${WHITE}  │ ${GREEN}[3]${WHITE} SSH-TLS Setup (Stunnel)           │${NC}"
    echo -e "${WHITE}  │ ${GREEN}[4]${WHITE} User Management                  │${NC}"
    echo -e "${WHITE}  │ ${GREEN}[5]${WHITE} Port Management                  │${NC}"
    echo -e "${WHITE}  │ ${GREEN}[6]${WHITE} Monitor Connections               │${NC}"
    echo -e "${WHITE}  │ ${GREEN}[7]${WHITE} Show Connection Details           │${NC}"
    echo -e "${WHITE}  │ ${GREEN}[8]${WHITE} System Information                │${NC}"
    echo -e "${WHITE}  │ ${CYAN}[9]${WHITE} Cloudflare Free Domain            │${NC}"
    echo -e "${WHITE}  ├──────────────────────────────────────┤${NC}"
    echo -e "${WHITE}  │ ${YELLOW}[U]${WHITE} Update Panel                     │${NC}"
    echo -e "${WHITE}  │ ${RED}[X]${WHITE} Uninstall Panel                  │${NC}"
    echo -e "${WHITE}  │ ${RED}[0]${WHITE} Exit                             │${NC}"
    echo -e "${WHITE}  └──────────────────────────────────────┘${NC}"
    echo -ne "\n  ${YELLOW}Select option: ${NC}"
    read -r OPTION

    case $OPTION in
        1) install_ssh_services ;;
        2) setup_websocket ;;
        3) setup_stunnel ;;
        4) user_management_menu ;;
        5) port_management_menu ;;
        6) monitor_connections ;;
        7) show_connection_details ;;
        8) system_info ;;
        9) cloudflare_menu ;;
        u|U) update_panel ;;
        x|X) uninstall_panel ;;
        0) echo -e "\n${GREEN}Goodbye!${NC}\n"; exit 0 ;;
        *) echo -e "${RED}Invalid option.${NC}"; sleep 1; main_menu ;;
    esac
}

install_ssh_services() {
    banner
    echo -e "${CYAN}  [*] Installing SSH Services...${NC}\n"
    detect_os

    echo -e "${YELLOW}  [1/5] Updating package lists...${NC}"
    $PKG_MANAGER update -y >> "$LOG_FILE" 2>&1

    echo -e "${YELLOW}  [2/5] Installing OpenSSH Server...${NC}"
    $PKG_MANAGER install -y openssh-server >> "$LOG_FILE" 2>&1

    echo -e "${YELLOW}  [3/5] Installing required tools...${NC}"
    $PKG_MANAGER install -y curl wget python3 python3-pip stunnel4 netcat-openbsd \
        net-tools iptables fail2ban >> "$LOG_FILE" 2>&1

    echo -e "${YELLOW}  [4/5] Configuring SSH server...${NC}"
    configure_ssh

    echo -e "${YELLOW}  [5/5] Starting SSH service...${NC}"
    systemctl enable ssh >> "$LOG_FILE" 2>&1
    systemctl restart ssh >> "$LOG_FILE" 2>&1

    echo -e "\n  ${GREEN}[✓] SSH Services installed successfully!${NC}"
    log "SSH services installed"
    read -rp "  Press Enter to continue..."
    main_menu
}

configure_ssh() {
    SSHD_CONFIG="/etc/ssh/sshd_config"

    cp "$SSHD_CONFIG" "${SSHD_CONFIG}.backup.$(date +%Y%m%d)"

    cat > "$SSHD_CONFIG" << 'SSHCONF'
Port 22
Port 80
Port 443
AddressFamily inet
ListenAddress 0.0.0.0

PermitRootLogin yes
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
PasswordAuthentication yes
PermitEmptyPasswords no
ChallengeResponseAuthentication no

UsePAM yes
X11Forwarding yes
PrintMotd no
ClientAliveInterval 60
ClientAliveCountMax 3

MaxAuthTries 6
MaxSessions 10

AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/openssh/sftp-server

Banner /etc/ssh/banner
SSHCONF

    cat > /etc/ssh/banner << 'BANNER'
##############################################
#         Welcome to SSH VPN Server         #
#          Powered by NPV Tunnel            #
##############################################
BANNER

    systemctl restart ssh >> "$LOG_FILE" 2>&1
    echo -e "  ${GREEN}[✓] SSH configured on ports 22, 80, 443${NC}"
}

setup_websocket() {
    banner
    echo -e "${CYAN}  [*] SSH WebSocket Setup${NC}\n"
    echo -e "${WHITE}  SSH-WS allows SSH tunneling over WebSocket protocol"
    echo -e "  Compatible with NPV Tunnel, HTTP Injector, etc.${NC}\n"

    echo -e "${YELLOW}  [1/4] Installing Python WebSocket proxy...${NC}"
    pip3 install websockify >> "$LOG_FILE" 2>&1

    echo -e "${YELLOW}  [2/4] Creating WebSocket proxy service...${NC}"

    cat > /usr/local/bin/ssh-ws-proxy.py << 'PYWS'
#!/usr/bin/env python3
"""
SSH WebSocket Proxy
Forwards WebSocket connections to local SSH server
"""
import socket
import threading
import select
import sys
import struct

LISTEN_PORT_WS = 80     # WS (plain WebSocket)
LISTEN_PORT_WSS = 8443  # WSS (WebSocket over TLS - stunnel handles TLS)
SSH_HOST = '127.0.0.1'
SSH_PORT = 22
BUFFER = 4096

RESPONSE = (
    "HTTP/1.1 101 Switching Protocols\r\n"
    "Upgrade: websocket\r\n"
    "Connection: Upgrade\r\n\r\n"
)

def handle_client(client_sock):
    try:
        data = client_sock.recv(BUFFER).decode('utf-8', errors='ignore')
        if 'Upgrade: websocket' in data or 'CONNECT' in data:
            client_sock.send(RESPONSE.encode())

        ssh_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        ssh_sock.connect((SSH_HOST, SSH_PORT))

        def forward(src, dst):
            try:
                while True:
                    r, _, _ = select.select([src], [], [], 60)
                    if not r:
                        break
                    d = src.recv(BUFFER)
                    if not d:
                        break
                    dst.sendall(d)
            except Exception:
                pass
            finally:
                src.close()
                dst.close()

        t1 = threading.Thread(target=forward, args=(client_sock, ssh_sock), daemon=True)
        t2 = threading.Thread(target=forward, args=(ssh_sock, client_sock), daemon=True)
        t1.start()
        t2.start()
        t1.join()
        t2.join()
    except Exception as e:
        pass
    finally:
        try:
            client_sock.close()
        except Exception:
            pass

def start_server(port):
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(('0.0.0.0', port))
    srv.listen(100)
    print(f"[SSH-WS] Listening on port {port}")
    while True:
        try:
            client, addr = srv.accept()
            threading.Thread(target=handle_client, args=(client,), daemon=True).start()
        except Exception as e:
            print(f"[ERROR] {e}")

if __name__ == '__main__':
    port = int(sys.argv[1]) if len(sys.argv) > 1 else LISTEN_PORT_WS
    start_server(port)
PYWS

    chmod +x /usr/local/bin/ssh-ws-proxy.py

    echo -e "${YELLOW}  [3/4] Creating systemd services...${NC}"

    cat > /etc/systemd/system/ssh-ws.service << 'SVCWS'
[Unit]
Description=SSH WebSocket Proxy (Port 80)
After=network.target ssh.service
Wants=ssh.service

[Service]
Type=simple
ExecStart=/usr/bin/python3 /usr/local/bin/ssh-ws-proxy.py 80
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
SVCWS

    cat > /etc/systemd/system/ssh-wss.service << 'SVCWSS'
[Unit]
Description=SSH WebSocket Proxy (Port 8443 for WSS)
After=network.target ssh.service
Wants=ssh.service

[Service]
Type=simple
ExecStart=/usr/bin/python3 /usr/local/bin/ssh-ws-proxy.py 8443
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
SVCWSS

    echo -e "${YELLOW}  [4/4] Starting WebSocket services...${NC}"
    systemctl daemon-reload
    systemctl enable ssh-ws ssh-wss >> "$LOG_FILE" 2>&1
    systemctl restart ssh-ws ssh-wss >> "$LOG_FILE" 2>&1

    IP=$(get_public_ip)
    echo -e "\n  ${GREEN}[✓] SSH WebSocket setup complete!${NC}"
    echo -e "\n  ${WHITE}NPV Tunnel / HTTP Injector Settings:"
    echo -e "  ┌─────────────────────────────────────────┐"
    echo -e "  │  SSH Host   : ${IP}"
    echo -e "  │  SSH Port   : 22"
    echo -e "  │  WS Port    : 80    (ws://${IP}:80)"
    echo -e "  │  WSS Port   : 8443  (wss://${IP}:8443)"
    echo -e "  │  Proxy Type : WebSocket"
    echo -e "  └─────────────────────────────────────────┘${NC}"

    log "SSH WebSocket setup completed"
    read -rp "  Press Enter to continue..."
    main_menu
}

setup_stunnel() {
    banner
    echo -e "${CYAN}  [*] SSH-TLS Setup (Stunnel)${NC}\n"
    echo -e "${WHITE}  Stunnel wraps SSH inside TLS on port 443"
    echo -e "  This bypasses deep packet inspection (DPI)${NC}\n"

    echo -e "${YELLOW}  [1/4] Installing stunnel4...${NC}"
    $PKG_MANAGER install -y stunnel4 >> "$LOG_FILE" 2>&1

    echo -e "${YELLOW}  [2/4] Generating TLS certificate...${NC}"
    mkdir -p /etc/stunnel

    openssl req -new -x509 -days 3650 -nodes \
        -out /etc/stunnel/stunnel.pem \
        -keyout /etc/stunnel/stunnel.pem \
        -subj "/C=US/ST=State/L=City/O=SSH-VPN/CN=$(get_public_ip)" \
        >> "$LOG_FILE" 2>&1

    chmod 600 /etc/stunnel/stunnel.pem

    echo -e "${YELLOW}  [3/4] Configuring stunnel...${NC}"

    cat > /etc/stunnel/stunnel.conf << 'STUNNELCONF'
; Stunnel SSH-TLS Configuration
; Listens on 443 (TLS), forwards to local SSH port 22

pid = /var/run/stunnel4/stunnel4.pid
output = /var/log/stunnel4/stunnel.log
socket = l:TCP_NODELAY=1
socket = r:TCP_NODELAY=1

[ssh-tls]
accept  = 443
connect = 127.0.0.1:22
cert    = /etc/stunnel/stunnel.pem
TIMEOUTclose = 0
STUNNELCONF

    echo -e "${YELLOW}  [4/4] Starting stunnel service...${NC}"
    systemctl enable stunnel4 >> "$LOG_FILE" 2>&1
    systemctl restart stunnel4 >> "$LOG_FILE" 2>&1

    IP=$(get_public_ip)
    echo -e "\n  ${GREEN}[✓] SSH-TLS (Stunnel) setup complete!${NC}"
    echo -e "\n  ${WHITE}NPV Tunnel / SSH-TLS Settings:"
    echo -e "  ┌─────────────────────────────────────────┐"
    echo -e "  │  SSH Host    : ${IP}"
    echo -e "  │  SSH Port    : 22"
    echo -e "  │  TLS Host    : ${IP}"
    echo -e "  │  TLS Port    : 443"
    echo -e "  │  TLS Mode    : Enabled (Self-signed cert)"
    echo -e "  │  Protocol    : SSH over TLS"
    echo -e "  └─────────────────────────────────────────┘${NC}"

    log "SSH-TLS stunnel setup completed"
    read -rp "  Press Enter to continue..."
    main_menu
}

user_management_menu() {
    banner
    echo -e "${WHITE}  ┌──────────────────────────────────────┐${NC}"
    echo -e "${WHITE}  │        USER MANAGEMENT               │${NC}"
    echo -e "${WHITE}  ├──────────────────────────────────────┤${NC}"
    echo -e "${WHITE}  │ ${GREEN}[1]${WHITE} Create User                      │${NC}"
    echo -e "${WHITE}  │ ${GREEN}[2]${WHITE} Delete User                      │${NC}"
    echo -e "${WHITE}  │ ${GREEN}[3]${WHITE} Extend User Expiry               │${NC}"
    echo -e "${WHITE}  │ ${GREEN}[4]${WHITE} Lock / Unlock User               │${NC}"
    echo -e "${WHITE}  │ ${GREEN}[5]${WHITE} List All Users                   │${NC}"
    echo -e "${WHITE}  │ ${GREEN}[6]${WHITE} Check User Details               │${NC}"
    echo -e "${WHITE}  │ ${RED}[0]${WHITE} Back to Main Menu                │${NC}"
    echo -e "${WHITE}  └──────────────────────────────────────┘${NC}"
    echo -ne "\n  ${YELLOW}Select option: ${NC}"
    read -r OPTION

    case $OPTION in
        1) create_user ;;
        2) delete_user ;;
        3) extend_user ;;
        4) lock_unlock_user ;;
        5) list_users ;;
        6) check_user ;;
        0) main_menu ;;
        *) echo -e "${RED}Invalid option.${NC}"; sleep 1; user_management_menu ;;
    esac
}

create_user() {
    banner
    echo -e "${CYAN}  [*] Create SSH VPN User${NC}\n"

    echo -ne "  ${YELLOW}Username: ${NC}"
    read -r USERNAME

    if [[ -z "$USERNAME" ]]; then
        echo -e "  ${RED}Username cannot be empty.${NC}"
        sleep 1; user_management_menu; return
    fi

    if id "$USERNAME" &>/dev/null; then
        echo -e "  ${RED}User '${USERNAME}' already exists.${NC}"
        sleep 2; user_management_menu; return
    fi

    echo -ne "  ${YELLOW}Password: ${NC}"
    read -rs PASSWORD
    echo

    echo -ne "  ${YELLOW}Expiry days (e.g. 30): ${NC}"
    read -r DAYS
    DAYS=${DAYS:-30}

    echo -ne "  ${YELLOW}Max logins (e.g. 2): ${NC}"
    read -r MAX_LOGINS
    MAX_LOGINS=${MAX_LOGINS:-2}

    EXPIRY_DATE=$(date -d "+${DAYS} days" '+%Y-%m-%d')

    useradd -M -s /bin/false -e "$EXPIRY_DATE" "$USERNAME" >> "$LOG_FILE" 2>&1
    echo "$USERNAME:$PASSWORD" | chpasswd >> "$LOG_FILE" 2>&1

    echo "${USERNAME}:${PASSWORD}:${EXPIRY_DATE}:${MAX_LOGINS}:$(date '+%Y-%m-%d')" >> "$USER_DB"

    IP=$(get_public_ip)
    echo -e "\n  ${GREEN}[✓] User created successfully!${NC}"
    echo -e "\n  ${WHITE}Account Details:"
    echo -e "  ┌─────────────────────────────────────────┐"
    echo -e "  │  Username   : ${USERNAME}"
    echo -e "  │  Password   : ${PASSWORD}"
    echo -e "  │  Expires    : ${EXPIRY_DATE} (${DAYS} days)"
    echo -e "  │  Max Logins : ${MAX_LOGINS}"
    echo -e "  │  SSH Host   : ${IP}"
    echo -e "  │  SSH Port   : 22 / 80"
    echo -e "  │  WS Port    : 80"
    echo -e "  │  TLS Port   : 443"
    echo -e "  └─────────────────────────────────────────┘${NC}"

    log "User created: $USERNAME (expires: $EXPIRY_DATE)"
    read -rp "  Press Enter to continue..."
    user_management_menu
}

delete_user() {
    banner
    echo -e "${CYAN}  [*] Delete SSH VPN User${NC}\n"
    echo -ne "  ${YELLOW}Username to delete: ${NC}"
    read -r USERNAME

    if ! id "$USERNAME" &>/dev/null; then
        echo -e "  ${RED}User '${USERNAME}' does not exist.${NC}"
        sleep 2; user_management_menu; return
    fi

    echo -ne "  ${YELLOW}Are you sure? (y/N): ${NC}"
    read -r CONFIRM
    if [[ "${CONFIRM,,}" != "y" ]]; then
        echo -e "  ${YELLOW}Cancelled.${NC}"
        sleep 1; user_management_menu; return
    fi

    pkill -u "$USERNAME" >> "$LOG_FILE" 2>&1
    userdel -f "$USERNAME" >> "$LOG_FILE" 2>&1

    sed -i "/^${USERNAME}:/d" "$USER_DB"

    echo -e "  ${GREEN}[✓] User '${USERNAME}' deleted.${NC}"
    log "User deleted: $USERNAME"
    read -rp "  Press Enter to continue..."
    user_management_menu
}

extend_user() {
    banner
    echo -e "${CYAN}  [*] Extend User Expiry${NC}\n"
    echo -ne "  ${YELLOW}Username: ${NC}"
    read -r USERNAME

    if ! id "$USERNAME" &>/dev/null; then
        echo -e "  ${RED}User not found.${NC}"
        sleep 2; user_management_menu; return
    fi

    echo -ne "  ${YELLOW}Extend by days: ${NC}"
    read -r DAYS
    DAYS=${DAYS:-30}

    CURRENT_EXPIRY=$(chage -l "$USERNAME" | grep "Account expires" | awk -F': ' '{print $2}')
    if [[ "$CURRENT_EXPIRY" == "never" || -z "$CURRENT_EXPIRY" ]]; then
        NEW_EXPIRY=$(date -d "+${DAYS} days" '+%Y-%m-%d')
    else
        NEW_EXPIRY=$(date -d "$CURRENT_EXPIRY +${DAYS} days" '+%Y-%m-%d' 2>/dev/null || date -d "+${DAYS} days" '+%Y-%m-%d')
    fi

    chage -E "$NEW_EXPIRY" "$USERNAME"
    sed -i "s/^${USERNAME}:\([^:]*\):[^:]*:/\1:${NEW_EXPIRY}:/" "$USER_DB"

    echo -e "  ${GREEN}[✓] User '${USERNAME}' extended until ${NEW_EXPIRY}.${NC}"
    log "User extended: $USERNAME until $NEW_EXPIRY"
    read -rp "  Press Enter to continue..."
    user_management_menu
}

lock_unlock_user() {
    banner
    echo -e "${CYAN}  [*] Lock / Unlock User${NC}\n"
    echo -ne "  ${YELLOW}Username: ${NC}"
    read -r USERNAME

    if ! id "$USERNAME" &>/dev/null; then
        echo -e "  ${RED}User not found.${NC}"
        sleep 2; user_management_menu; return
    fi

    STATUS=$(passwd -S "$USERNAME" | awk '{print $2}')
    if [[ "$STATUS" == "L" || "$STATUS" == "LK" ]]; then
        passwd -u "$USERNAME" >> "$LOG_FILE" 2>&1
        echo -e "  ${GREEN}[✓] User '${USERNAME}' unlocked.${NC}"
        log "User unlocked: $USERNAME"
    else
        passwd -l "$USERNAME" >> "$LOG_FILE" 2>&1
        pkill -u "$USERNAME" >> "$LOG_FILE" 2>&1
        echo -e "  ${YELLOW}[✓] User '${USERNAME}' locked and disconnected.${NC}"
        log "User locked: $USERNAME"
    fi

    read -rp "  Press Enter to continue..."
    user_management_menu
}

list_users() {
    banner
    echo -e "${CYAN}  [*] All SSH VPN Users${NC}\n"
    echo -e "  ${WHITE}%-15s %-20s %-12s %-10s${NC}" "Username" "Expires" "Status" "Online"
    echo -e "  ${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    while IFS=: read -r USER PASS EXPIRY MAXLOGINS CREATED; do
        [[ -z "$USER" ]] && continue

        STATUS=$(passwd -S "$USER" 2>/dev/null | awk '{print $2}')
        [[ "$STATUS" == "L" || "$STATUS" == "LK" ]] && STATUS_TEXT="${RED}Locked${NC}" || STATUS_TEXT="${GREEN}Active${NC}"

        ONLINE=$(who | grep -c "^${USER} " 2>/dev/null || echo "0")
        [[ "$ONLINE" -gt 0 ]] && ONLINE_TEXT="${GREEN}${ONLINE}${NC}" || ONLINE_TEXT="${YELLOW}0${NC}"

        printf "  %-15s %-20s " "$USER" "$EXPIRY"
        echo -e "$STATUS_TEXT  $ONLINE_TEXT"
    done < "$USER_DB"

    echo -e "\n  ${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  Total users: $(wc -l < "$USER_DB")"
    read -rp "  Press Enter to continue..."
    user_management_menu
}

check_user() {
    banner
    echo -e "${CYAN}  [*] Check User Details${NC}\n"
    echo -ne "  ${YELLOW}Username: ${NC}"
    read -r USERNAME

    if ! id "$USERNAME" &>/dev/null; then
        echo -e "  ${RED}User not found.${NC}"
        sleep 2; user_management_menu; return
    fi

    USER_LINE=$(grep "^${USERNAME}:" "$USER_DB" 2>/dev/null)
    EXPIRY=$(echo "$USER_LINE" | cut -d: -f3)
    MAX_LOGIN=$(echo "$USER_LINE" | cut -d: -f4)
    CREATED=$(echo "$USER_LINE" | cut -d: -f5)

    ONLINE=$(who | grep -c "^${USERNAME} " 2>/dev/null || echo "0")
    STATUS=$(passwd -S "$USERNAME" 2>/dev/null | awk '{print $2}')
    [[ "$STATUS" == "L" || "$STATUS" == "LK" ]] && STATUS_TEXT="Locked" || STATUS_TEXT="Active"

    DAYS_LEFT=$(( ( $(date -d "$EXPIRY" +%s) - $(date +%s) ) / 86400 )) 2>/dev/null || DAYS_LEFT="N/A"

    echo -e "  ${WHITE}┌─────────────────────────────────────────┐"
    echo -e "  │  Username     : ${USERNAME}"
    echo -e "  │  Status       : ${STATUS_TEXT}"
    echo -e "  │  Created      : ${CREATED:-N/A}"
    echo -e "  │  Expires      : ${EXPIRY:-N/A}"
    echo -e "  │  Days Left    : ${DAYS_LEFT}"
    echo -e "  │  Max Logins   : ${MAX_LOGIN:-N/A}"
    echo -e "  │  Online Now   : ${ONLINE} session(s)"
    echo -e "  └─────────────────────────────────────────┘${NC}"

    read -rp "  Press Enter to continue..."
    user_management_menu
}

port_management_menu() {
    banner
    echo -e "${WHITE}  ┌──────────────────────────────────────┐${NC}"
    echo -e "${WHITE}  │        PORT MANAGEMENT               │${NC}"
    echo -e "${WHITE}  ├──────────────────────────────────────┤${NC}"
    echo -e "${WHITE}  │ ${GREEN}[1]${WHITE} Add SSH Port                     │${NC}"
    echo -e "${WHITE}  │ ${GREEN}[2]${WHITE} Remove SSH Port                  │${NC}"
    echo -e "${WHITE}  │ ${GREEN}[3]${WHITE} Change WS Port                   │${NC}"
    echo -e "${WHITE}  │ ${GREEN}[4]${WHITE} Open Firewall Port               │${NC}"
    echo -e "${WHITE}  │ ${GREEN}[5]${WHITE} List Open Ports                  │${NC}"
    echo -e "${WHITE}  │ ${RED}[0]${WHITE} Back to Main Menu                │${NC}"
    echo -e "${WHITE}  └──────────────────────────────────────┘${NC}"
    echo -ne "\n  ${YELLOW}Select option: ${NC}"
    read -r OPTION

    case $OPTION in
        1) add_ssh_port ;;
        2) remove_ssh_port ;;
        3) change_ws_port ;;
        4) open_firewall_port ;;
        5) list_open_ports ;;
        0) main_menu ;;
        *) echo -e "${RED}Invalid option.${NC}"; sleep 1; port_management_menu ;;
    esac
}

add_ssh_port() {
    banner
    echo -ne "  ${YELLOW}Enter port to add for SSH: ${NC}"
    read -r PORT

    if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
        echo -e "  ${RED}Invalid port number.${NC}"; sleep 2; port_management_menu; return
    fi

    if grep -q "^Port $PORT" /etc/ssh/sshd_config; then
        echo -e "  ${YELLOW}Port $PORT already exists in SSH config.${NC}"
        sleep 2; port_management_menu; return
    fi

    echo "Port $PORT" >> /etc/ssh/sshd_config
    systemctl restart ssh >> "$LOG_FILE" 2>&1

    iptables -I INPUT -p tcp --dport "$PORT" -j ACCEPT 2>/dev/null

    echo -e "  ${GREEN}[✓] SSH port ${PORT} added.${NC}"
    log "Added SSH port: $PORT"
    read -rp "  Press Enter to continue..."
    port_management_menu
}

remove_ssh_port() {
    banner
    echo -ne "  ${YELLOW}Enter port to remove from SSH: ${NC}"
    read -r PORT

    sed -i "/^Port $PORT$/d" /etc/ssh/sshd_config
    systemctl restart ssh >> "$LOG_FILE" 2>&1

    echo -e "  ${GREEN}[✓] SSH port ${PORT} removed.${NC}"
    log "Removed SSH port: $PORT"
    read -rp "  Press Enter to continue..."
    port_management_menu
}

change_ws_port() {
    banner
    echo -ne "  ${YELLOW}New WebSocket port: ${NC}"
    read -r PORT

    if ! [[ "$PORT" =~ ^[0-9]+$ ]]; then
        echo -e "  ${RED}Invalid port.${NC}"; sleep 2; port_management_menu; return
    fi

    sed -i "s|ExecStart=.*ssh-ws-proxy.py .*|ExecStart=/usr/bin/python3 /usr/local/bin/ssh-ws-proxy.py $PORT|" \
        /etc/systemd/system/ssh-ws.service

    systemctl daemon-reload
    systemctl restart ssh-ws >> "$LOG_FILE" 2>&1

    echo -e "  ${GREEN}[✓] WebSocket port changed to ${PORT}.${NC}"
    log "Changed WS port to: $PORT"
    read -rp "  Press Enter to continue..."
    port_management_menu
}

open_firewall_port() {
    banner
    echo -ne "  ${YELLOW}Port to open in firewall: ${NC}"
    read -r PORT
    echo -ne "  ${YELLOW}Protocol (tcp/udp) [tcp]: ${NC}"
    read -r PROTO
    PROTO=${PROTO:-tcp}

    if command -v ufw &>/dev/null; then
        ufw allow "$PORT/$PROTO" >> "$LOG_FILE" 2>&1
        echo -e "  ${GREEN}[✓] UFW: Port ${PORT}/${PROTO} opened.${NC}"
    fi

    iptables -I INPUT -p "$PROTO" --dport "$PORT" -j ACCEPT 2>/dev/null
    echo -e "  ${GREEN}[✓] iptables: Port ${PORT}/${PROTO} opened.${NC}"
    log "Opened firewall port: $PORT/$PROTO"
    read -rp "  Press Enter to continue..."
    port_management_menu
}

list_open_ports() {
    banner
    echo -e "${CYAN}  [*] Currently Open/Listening Ports${NC}\n"
    ss -tlnp 2>/dev/null | grep LISTEN | awk '{print $4, $6}' | \
        sed 's/.*://' | column -t | \
        while read -r PORT PROC; do
            echo -e "  ${GREEN}[OPEN]${NC} Port ${WHITE}${PORT}${NC} — ${PROC}"
        done
    echo ""
    read -rp "  Press Enter to continue..."
    port_management_menu
}

monitor_connections() {
    banner
    echo -e "${CYAN}  [*] Live Connection Monitor (Ctrl+C to stop)${NC}\n"

    while true; do
        clear
        banner
        echo -e "${CYAN}  [*] Active SSH Connections — $(date '+%H:%M:%S')${NC}\n"

        TOTAL=0
        echo -e "  ${WHITE}%-15s %-20s %-15s${NC}" "User" "From IP" "Duration"
        echo -e "  ${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

        while IFS= read -r line; do
            USER=$(echo "$line" | awk '{print $1}')
            IP=$(echo "$line" | awk '{print $3}' | sed 's/[()]//g')
            TIME=$(echo "$line" | awk '{print $4, $5}')
            printf "  %-15s %-20s %-15s\n" "$USER" "$IP" "$TIME"
            ((TOTAL++))
        done < <(who 2>/dev/null)

        echo -e "  ${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "  Total connections: ${GREEN}${TOTAL}${NC}"
        echo -e "\n  ${YELLOW}Refreshing every 5s — Ctrl+C to exit...${NC}"
        sleep 5
    done
}

show_connection_details() {
    banner
    IP=$(get_public_ip)
    echo -e "${CYAN}  [*] Server Connection Details${NC}\n"
    echo -e "  ${WHITE}┌──────────────────────────────────────────────────┐"
    echo -e "  │            SSH / VPN CONNECTION INFO                │"
    echo -e "  ├──────────────────────────────────────────────────┤"
    echo -e "  │  Public IP      : ${IP}"
    echo -e "  │"
    echo -e "  │  [SSH DIRECT]"
    echo -e "  │  Host           : ${IP}"
    echo -e "  │  Ports          : 22, 80, 443"
    echo -e "  │"
    echo -e "  │  [SSH WEBSOCKET (NPV Tunnel / HTTP Injector)]"
    echo -e "  │  SSH Host       : ${IP}"
    echo -e "  │  SSH Port       : 22"
    echo -e "  │  WS URL         : ws://${IP}:80"
    echo -e "  │  WSS URL        : wss://${IP}:8443"
    echo -e "  │  Payload        : GET / HTTP/1.1[crlf]Host: ${IP}[crlf][crlf]"
    echo -e "  │"
    echo -e "  │  [SSH TLS (Stunnel)]"
    echo -e "  │  SSH Host       : 127.0.0.1 (via stunnel)"
    echo -e "  │  SSH Port       : 22"
    echo -e "  │  TLS Host       : ${IP}"
    echo -e "  │  TLS Port       : 443"
    echo -e "  │  TLS Verify     : No (self-signed)"
    echo -e "  └──────────────────────────────────────────────────┘${NC}"

    echo -e "\n  ${YELLOW}Services Status:${NC}"
    for SVC in ssh ssh-ws ssh-wss stunnel4; do
        if systemctl is-active --quiet "$SVC" 2>/dev/null; then
            echo -e "  ${GREEN}[✓] ${SVC} — Running${NC}"
        else
            echo -e "  ${RED}[✗] ${SVC} — Not running${NC}"
        fi
    done

    read -rp "  Press Enter to continue..."
    main_menu
}

system_info() {
    banner
    echo -e "${CYAN}  [*] System Information${NC}\n"

    OS_INFO=$(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')
    UPTIME=$(uptime -p 2>/dev/null || uptime)
    CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d% -f1 2>/dev/null || echo "N/A")
    MEM_TOTAL=$(free -m | awk 'NR==2{print $2}')
    MEM_USED=$(free -m | awk 'NR==2{print $3}')
    DISK_USAGE=$(df -h / | awk 'NR==2{print $3"/"$2" ("$5")"}')

    echo -e "  ${WHITE}┌──────────────────────────────────────────┐"
    echo -e "  │  OS          : ${OS_INFO}"
    echo -e "  │  Uptime      : ${UPTIME}"
    echo -e "  │  CPU Usage   : ${CPU_USAGE}%"
    echo -e "  │  Memory      : ${MEM_USED} MB / ${MEM_TOTAL} MB"
    echo -e "  │  Disk        : ${DISK_USAGE}"
    echo -e "  │  Kernel      : $(uname -r)"
    echo -e "  │  Total Users : $(wc -l < "$USER_DB")"
    echo -e "  └──────────────────────────────────────────┘${NC}"

    read -rp "  Press Enter to continue..."
    main_menu
}

cloudflare_menu() {
    banner
    CF_STATUS="Not running"
    CF_DOMAIN_DISPLAY="None"
    if systemctl is-active --quiet cloudflared-tunnel 2>/dev/null; then
        CF_STATUS="${GREEN}Running${NC}"
        CF_DOMAIN_DISPLAY="${CYAN}$(cat "$CF_DOMAIN_FILE" 2>/dev/null || echo 'Unknown')${NC}"
    else
        CF_STATUS="${RED}Stopped${NC}"
    fi

    echo -e "${WHITE}  ┌──────────────────────────────────────┐${NC}"
    echo -e "${WHITE}  │      CLOUDFLARE FREE DOMAIN          │${NC}"
    echo -e "${WHITE}  ├──────────────────────────────────────┤${NC}"
    echo -e "  │  Status : $(echo -e $CF_STATUS)"
    echo -e "  │  Domain : $(echo -e $CF_DOMAIN_DISPLAY)"
    echo -e "${WHITE}  ├──────────────────────────────────────┤${NC}"
    echo -e "${WHITE}  │ ${GREEN}[1]${WHITE} Install & Start Cloudflare Tunnel │${NC}"
    echo -e "${WHITE}  │ ${GREEN}[2]${WHITE} Show Current Domain               │${NC}"
    echo -e "${WHITE}  │ ${GREEN}[3]${WHITE} Restart Tunnel (get new domain)   │${NC}"
    echo -e "${WHITE}  │ ${RED}[4]${WHITE} Stop Tunnel                      │${NC}"
    echo -e "${WHITE}  │ ${RED}[5]${WHITE} Uninstall cloudflared            │${NC}"
    echo -e "${WHITE}  │ ${YELLOW}[0]${WHITE} Back to Main Menu                │${NC}"
    echo -e "${WHITE}  └──────────────────────────────────────┘${NC}"
    echo -ne "\n  ${YELLOW}Select option: ${NC}"
    read -r OPTION

    case $OPTION in
        1) install_cloudflare ;;
        2) show_cf_domain ;;
        3) restart_cf_tunnel ;;
        4) stop_cf_tunnel ;;
        5) uninstall_cloudflare ;;
        0) main_menu ;;
        *) echo -e "${RED}Invalid option.${NC}"; sleep 1; cloudflare_menu ;;
    esac
}

install_cloudflare() {
    banner
    echo -e "${CYAN}  [*] Setting up Cloudflare Free Domain...${NC}\n"
    echo -e "${WHITE}  This installs cloudflared and creates a FREE tunnel."
    echo -e "  You get a public domain like: abc123.trycloudflare.com"
    echo -e "  No Cloudflare account required!${NC}\n"

    detect_os

    if command -v cloudflared &>/dev/null; then
        echo -e "  ${YELLOW}cloudflared already installed. Starting tunnel...${NC}"
    else
        echo -e "${YELLOW}  [1/3] Downloading cloudflared...${NC}"
        ARCH=$(uname -m)
        case "$ARCH" in
            x86_64)  CF_ARCH="amd64" ;;
            aarch64) CF_ARCH="arm64" ;;
            armv7l)  CF_ARCH="arm" ;;
            *)       CF_ARCH="amd64" ;;
        esac

        CF_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CF_ARCH}"
        curl -sSL "$CF_URL" -o /usr/local/bin/cloudflared >> "$LOG_FILE" 2>&1
        chmod +x /usr/local/bin/cloudflared

        if ! command -v cloudflared &>/dev/null; then
            echo -e "  ${RED}[✗] Failed to install cloudflared. Check your internet connection.${NC}"
            read -rp "  Press Enter to continue..."
            cloudflare_menu; return
        fi
        echo -e "  ${GREEN}[✓] cloudflared installed.${NC}"
    fi

    echo -e "${YELLOW}  [2/3] Creating systemd tunnel service...${NC}"

    cat > /etc/systemd/system/cloudflared-tunnel.service << 'CFSVC'
[Unit]
Description=Cloudflare Quick Tunnel (SSH-WS)
After=network.target ssh-ws.service
Wants=ssh-ws.service

[Service]
Type=simple
ExecStart=/usr/local/bin/cloudflared tunnel --url http://localhost:80 --no-autoupdate
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

    echo -e "${YELLOW}  [3/3] Waiting for Cloudflare to assign domain...${NC}"
    CF_DOMAIN=""
    for i in $(seq 1 20); do
        sleep 3
        CF_DOMAIN=$(journalctl -u cloudflared-tunnel --no-pager -n 50 2>/dev/null | \
            grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' | tail -1)
        if [[ -n "$CF_DOMAIN" ]]; then
            break
        fi
        echo -ne "  Waiting... (${i}/20)\r"
    done

    if [[ -z "$CF_DOMAIN" ]]; then
        echo -e "\n  ${YELLOW}[!] Domain not detected yet. Try option [2] in a moment.${NC}"
        log "Cloudflare tunnel started but domain not yet detected"
        read -rp "  Press Enter to continue..."
        cloudflare_menu; return
    fi

    echo "$CF_DOMAIN" > "$CF_DOMAIN_FILE"

    echo -e "\n  ${GREEN}[✓] Cloudflare tunnel is LIVE!${NC}"
    echo -e "\n  ${WHITE}┌──────────────────────────────────────────────────────┐"
    echo -e "  │         YOUR FREE CLOUDFLARE DOMAIN                  │"
    echo -e "  ├──────────────────────────────────────────────────────┤"
    echo -e "  │  Domain  : ${CYAN}${CF_DOMAIN}${WHITE}"
    echo -e "  │  WS URL  : ${CYAN}${CF_DOMAIN}${WHITE}  (port 80 tunneled)"
    echo -e "  │"
    echo -e "  │  NPV Tunnel / HTTP Injector Settings:"
    echo -e "  │  ► SSH Host  : $(get_public_ip)"
    echo -e "  │  ► SSH Port  : 22"
    echo -e "  │  ► Proxy     : ${CF_DOMAIN}"
    echo -e "  │  ► Proxy Port: 443 (Cloudflare HTTPS)"
    echo -e "  └──────────────────────────────────────────────────────┘${NC}"

    log "Cloudflare tunnel started: $CF_DOMAIN"
    read -rp "  Press Enter to continue..."
    cloudflare_menu
}

show_cf_domain() {
    banner
    echo -e "${CYAN}  [*] Current Cloudflare Domain${NC}\n"

    if ! systemctl is-active --quiet cloudflared-tunnel 2>/dev/null; then
        echo -e "  ${RED}[✗] Cloudflare tunnel is not running.${NC}"
        echo -e "  ${YELLOW}Use option [1] to install and start it.${NC}"
        read -rp "  Press Enter to continue..."
        cloudflare_menu; return
    fi

    CF_DOMAIN=$(journalctl -u cloudflared-tunnel --no-pager -n 100 2>/dev/null | \
        grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' | tail -1)

    if [[ -z "$CF_DOMAIN" ]]; then
        CF_DOMAIN=$(cat "$CF_DOMAIN_FILE" 2>/dev/null)
    fi

    if [[ -z "$CF_DOMAIN" ]]; then
        echo -e "  ${YELLOW}[!] Domain not detected yet. Wait a few seconds and try again.${NC}"
        read -rp "  Press Enter to continue..."
        cloudflare_menu; return
    fi

    echo "$CF_DOMAIN" > "$CF_DOMAIN_FILE"
    IP=$(get_public_ip)

    echo -e "  ${WHITE}┌──────────────────────────────────────────────────────┐"
    echo -e "  │  Free Domain  : ${CYAN}${CF_DOMAIN}${WHITE}"
    echo -e "  │  Tunnel Port  : 443 (Cloudflare HTTPS → port 80)"
    echo -e "  │  SSH Host     : ${IP}"
    echo -e "  │  SSH Port     : 22"
    echo -e "  │"
    echo -e "  │  For NPV Tunnel / HTTP Injector:"
    echo -e "  │  Host   → ${CF_DOMAIN}"
    echo -e "  │  Port   → 443"
    echo -e "  └──────────────────────────────────────────────────────┘${NC}"

    read -rp "  Press Enter to continue..."
    cloudflare_menu
}

restart_cf_tunnel() {
    banner
    echo -e "${CYAN}  [*] Restarting Cloudflare Tunnel...${NC}\n"
    echo -e "${YELLOW}  A new random domain will be assigned.${NC}\n"

    systemctl restart cloudflared-tunnel >> "$LOG_FILE" 2>&1

    echo -e "  ${YELLOW}Waiting for new domain...${NC}"
    CF_DOMAIN=""
    for i in $(seq 1 20); do
        sleep 3
        CF_DOMAIN=$(journalctl -u cloudflared-tunnel --no-pager -n 50 2>/dev/null | \
            grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' | tail -1)
        [[ -n "$CF_DOMAIN" ]] && break
        echo -ne "  Waiting... (${i}/20)\r"
    done

    if [[ -n "$CF_DOMAIN" ]]; then
        echo "$CF_DOMAIN" > "$CF_DOMAIN_FILE"
        echo -e "\n  ${GREEN}[✓] New Cloudflare domain: ${CYAN}${CF_DOMAIN}${NC}"
        log "Cloudflare tunnel restarted: $CF_DOMAIN"
    else
        echo -e "\n  ${YELLOW}[!] Domain not detected yet. Try option [2] in a moment.${NC}"
    fi

    read -rp "  Press Enter to continue..."
    cloudflare_menu
}

stop_cf_tunnel() {
    banner
    echo -e "${CYAN}  [*] Stopping Cloudflare Tunnel...${NC}\n"
    systemctl stop cloudflared-tunnel >> "$LOG_FILE" 2>&1
    systemctl disable cloudflared-tunnel >> "$LOG_FILE" 2>&1
    echo -e "  ${YELLOW}[✓] Cloudflare tunnel stopped.${NC}"
    log "Cloudflare tunnel stopped"
    read -rp "  Press Enter to continue..."
    cloudflare_menu
}

uninstall_cloudflare() {
    banner
    echo -ne "  ${YELLOW}Remove cloudflared completely? (y/N): ${NC}"
    read -r CONFIRM
    if [[ "${CONFIRM,,}" != "y" ]]; then
        cloudflare_menu; return
    fi

    systemctl stop cloudflared-tunnel >> "$LOG_FILE" 2>&1
    systemctl disable cloudflared-tunnel >> "$LOG_FILE" 2>&1
    rm -f /etc/systemd/system/cloudflared-tunnel.service
    systemctl daemon-reload
    rm -f /usr/local/bin/cloudflared
    rm -f "$CF_DOMAIN_FILE"

    echo -e "  ${GREEN}[✓] cloudflared uninstalled.${NC}"
    log "cloudflared uninstalled"
    read -rp "  Press Enter to continue..."
    main_menu
}

update_panel() {
    banner
    echo -e "${CYAN}  [*] Update Panel${NC}\n"

    REMOTE_URL="https://raw.githubusercontent.com/faresbazed/Ragnar-ssh-panel-script/main/panel.sh"
    INSTALL_DIR="/usr/local/ssh-vpn-panel"
    CURRENT_SCRIPT="$INSTALL_DIR/panel.sh"
    BACKUP="$INSTALL_DIR/panel.sh.bak"

    echo -e "${YELLOW}  [1/4] Checking for updates...${NC}"
    NEW_VERSION=$(curl -sSL "$REMOTE_URL" 2>/dev/null | grep 'PANEL_VERSION=' | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')

    if [[ -z "$NEW_VERSION" ]]; then
        echo -e "  ${RED}[✗] Could not reach update server. Check your internet connection.${NC}"
        read -rp "  Press Enter to continue..."
        main_menu; return
    fi

    echo -e "  Current version : ${WHITE}${PANEL_VERSION}${NC}"
    echo -e "  Latest version  : ${WHITE}${NEW_VERSION}${NC}\n"

    if [[ "$NEW_VERSION" == "$PANEL_VERSION" ]]; then
        echo -e "  ${GREEN}[✓] You are already on the latest version!${NC}"
        read -rp "  Press Enter to continue..."
        main_menu; return
    fi

    echo -e "${YELLOW}  [2/4] Backing up current panel...${NC}"
    cp "$CURRENT_SCRIPT" "$BACKUP" 2>/dev/null && \
        echo -e "  ${GREEN}[✓] Backup saved to ${BACKUP}${NC}" || \
        echo -e "  ${YELLOW}[!] No existing install found, fresh update.${NC}"

    echo -e "${YELLOW}  [3/4] Downloading latest version...${NC}"
    curl -sSL "$REMOTE_URL" -o "$CURRENT_SCRIPT.tmp"

    if [[ ! -s "$CURRENT_SCRIPT.tmp" ]]; then
        echo -e "  ${RED}[✗] Download failed. Keeping current version.${NC}"
        rm -f "$CURRENT_SCRIPT.tmp"
        read -rp "  Press Enter to continue..."
        main_menu; return
    fi

    mv "$CURRENT_SCRIPT.tmp" "$CURRENT_SCRIPT"
    chmod +x "$CURRENT_SCRIPT"

    echo -e "${YELLOW}  [4/4] Reloading panel...${NC}"
    echo -e "\n  ${GREEN}[✓] Panel updated to v${NEW_VERSION}!${NC}"
    log "Panel updated from v${PANEL_VERSION} to v${NEW_VERSION}"

    read -rp "  Press Enter to relaunch..."
    exec bash "$CURRENT_SCRIPT"
}

uninstall_panel() {
    banner
    echo -e "${RED}  [!] UNINSTALL PANEL${NC}\n"
    echo -e "${WHITE}  This will remove:"
    echo -e "  - All panel files and services (SSH-WS, SSH-TLS, Cloudflare)"
    echo -e "  - The 'vpn' shortcut command"
    echo -e "  - Panel config and logs"
    echo -e "${YELLOW}  SSH server itself will NOT be removed.${NC}\n"

    echo -ne "  ${RED}Type 'UNINSTALL' to confirm: ${NC}"
    read -r CONFIRM
    if [[ "$CONFIRM" != "UNINSTALL" ]]; then
        echo -e "  ${YELLOW}Cancelled.${NC}"
        sleep 1; main_menu; return
    fi

    echo -e "\n${YELLOW}  [1/6] Stopping Cloudflare tunnel...${NC}"
    systemctl stop cloudflared-tunnel 2>/dev/null
    systemctl disable cloudflared-tunnel 2>/dev/null
    rm -f /etc/systemd/system/cloudflared-tunnel.service
    rm -f /usr/local/bin/cloudflared

    echo -e "${YELLOW}  [2/6] Stopping SSH-WebSocket services...${NC}"
    systemctl stop ssh-ws ssh-wss 2>/dev/null
    systemctl disable ssh-ws ssh-wss 2>/dev/null
    rm -f /etc/systemd/system/ssh-ws.service
    rm -f /etc/systemd/system/ssh-wss.service
    rm -f /usr/local/bin/ssh-ws-proxy.py

    echo -e "${YELLOW}  [3/6] Stopping Stunnel...${NC}"
    systemctl stop stunnel4 2>/dev/null
    systemctl disable stunnel4 2>/dev/null

    echo -e "${YELLOW}  [4/6] Reloading systemd...${NC}"
    systemctl daemon-reload

    echo -e "${YELLOW}  [5/6] Removing panel files and config...${NC}"
    rm -rf "$CONFIG_DIR"
    rm -rf /usr/local/ssh-vpn-panel
    rm -f "$LOG_FILE"

    echo -e "${YELLOW}  [6/6] Removing 'vpn' command...${NC}"
    rm -f /usr/local/bin/vpn

    echo -e "\n  ${GREEN}[✓] SSH VPN Panel has been fully uninstalled.${NC}"
    echo -e "  ${WHITE}SSH server is still running. Goodbye!${NC}\n"
    log "Panel uninstalled"
    exit 0
}

check_root
init_panel
main_menu
