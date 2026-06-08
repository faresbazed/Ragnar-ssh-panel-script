#!/bin/bash
# ============================================================
#   RAGNAR SSH VPN Panel v3.0.0 — One-Click Installer
#   Features: SSH-WS | SSH-TLS | Cloudflare | Web Panel
#             Bandwidth Monitor | Speed Limits | User Mgmt
#   Usage: bash install.sh
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[ERROR] Run as root: sudo bash install.sh${NC}"
    exit 1
fi

INSTALL_DIR="/usr/local/ssh-vpn-panel"
SCRIPT_URL="https://raw.githubusercontent.com/faresbazed/Ragnar-ssh-panel-script/main/panel.sh"

echo -e "${CYAN}"
echo "  ╔══════════════════════════════════════════════╗"
echo "  ║   RAGNAR SSH VPN Panel v3.0.0 — Installer   ║"
echo "  ╚══════════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "${YELLOW}[1/4] Updating system...${NC}"
apt-get update -y > /dev/null 2>&1 || yum update -y > /dev/null 2>&1

echo -e "${YELLOW}[2/4] Installing dependencies...${NC}"
apt-get install -y curl wget python3 python3-pip stunnel4 openssh-server \
    net-tools iptables openssl vnstat > /dev/null 2>&1 || \
yum install -y curl wget python3 stunnel openssh-server \
    net-tools iptables openssl > /dev/null 2>&1

echo -e "${YELLOW}[3/4] Setting up panel...${NC}"
mkdir -p "$INSTALL_DIR"
mkdir -p /etc/ssh-vpn-panel
touch /etc/ssh-vpn-panel/users.db
touch /var/log/ssh-vpn-panel.log

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/panel.sh" ]; then
    cp "$SCRIPT_DIR/panel.sh" "$INSTALL_DIR/panel.sh"
else
    echo -e "${YELLOW}Downloading panel.sh...${NC}"
    curl -sSL "$SCRIPT_URL" -o "$INSTALL_DIR/panel.sh"
fi

chmod +x "$INSTALL_DIR/panel.sh"

echo -e "${YELLOW}[4/4] Creating 'vpn' command...${NC}"
cat > /usr/local/bin/vpn << VPNCMD
#!/bin/bash
bash $INSTALL_DIR/panel.sh
VPNCMD
chmod +x /usr/local/bin/vpn

echo -e "\n${GREEN}[✓] RAGNAR SSH VPN Panel v3.0.0 installed!${NC}"
echo -e "${WHITE}Run the panel anytime with: ${CYAN}vpn${NC}"
echo -e "${WHITE}New features: Web panel [W], Bandwidth monitor [N], Speed limits [User→9]${NC}"
echo ""
