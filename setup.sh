#!/bin/bash
# Interaktives Setup für den Kamera-Viewer
# Fragt nach Kameras und erstellt die Konfiguration

# Sicherstellen dass das Skript mit bash läuft
if [ -z "$BASH_VERSION" ]; then
    exec bash "$0" "$@"
fi

set -e

# Benutzer ermitteln
if [ -n "$SUDO_USER" ]; then
    TARGET_USER="$SUDO_USER"
else
    TARGET_USER=$(getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 {print $1; exit}')
fi
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
CONFIG_FILE="$TARGET_HOME/cam-viewer/config.yaml"

# Farben für bessere Lesbarkeit
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo ""
echo -e "${BLUE}======================================"
echo "   Kamera-Viewer Setup"
echo -e "======================================${NC}"
echo ""

# ============================================
# Netzwerkkonfiguration
# ============================================
echo -e "${BLUE}--- Netzwerkkonfiguration ---${NC}"
echo ""

NETWORK_IFACE="eth0"

echo "Die Kameras haben vermutlich IPs wie 192.168.1.100, 192.168.1.101, ..."
echo "Der Pi braucht eine freie IP im selben Netz, z.B. 192.168.1.50"
echo ""

# IP-Adresse
while true; do
    read -p "IP-Adresse für den Pi: " PI_IP
    if [[ "$PI_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        break
    fi
    echo -e "${RED}Ungültige IP-Adresse. Format: 192.168.1.50${NC}"
done

# Subnetzmaske
read -p "Subnetzmaske [255.255.255.0]: " NETMASK
NETMASK="${NETMASK:-255.255.255.0}"

# CIDR berechnen
case "$NETMASK" in
    "255.255.255.0") CIDR="24" ;;
    "255.255.0.0") CIDR="16" ;;
    "255.0.0.0") CIDR="8" ;;
    "255.255.255.128") CIDR="25" ;;
    "255.255.255.192") CIDR="26" ;;
    *) CIDR="24" ;;
esac

# Kein Gateway nötig (isoliertes Kameranetz)
GATEWAY=""

echo ""
echo -e "${BLUE}Konfiguriere Netzwerk...${NC}"

# Netzwerk konfigurieren - prüfen welches System verwendet wird
if systemctl is-active --quiet NetworkManager; then
    # NetworkManager (neuere Systeme)
    echo "Verwende NetworkManager..."
    
    # Bestehende Verbindung löschen falls vorhanden
    nmcli con delete "cam-viewer-static" 2>/dev/null || true
    
    # Neue statische Verbindung erstellen
    if [ -n "$GATEWAY" ]; then
        nmcli con add type ethernet con-name "cam-viewer-static" ifname "$NETWORK_IFACE" \
            ipv4.addresses "$PI_IP/$CIDR" \
            ipv4.gateway "$GATEWAY" \
            ipv4.method manual \
            autoconnect yes
    else
        nmcli con add type ethernet con-name "cam-viewer-static" ifname "$NETWORK_IFACE" \
            ipv4.addresses "$PI_IP/$CIDR" \
            ipv4.method manual \
            autoconnect yes
    fi
    
    # Verbindung aktivieren
    nmcli con up "cam-viewer-static"
    
elif [ -f /etc/dhcpcd.conf ]; then
    # dhcpcd (ältere Pi OS Versionen)
    echo "Verwende dhcpcd..."
    
    # Alte Einträge entfernen
    sed -i '/# cam-viewer static IP/,/^$/d' /etc/dhcpcd.conf
    
    # Neue Konfiguration anhängen
    cat >> /etc/dhcpcd.conf << EOF

# cam-viewer static IP
interface $NETWORK_IFACE
static ip_address=$PI_IP/$CIDR
EOF
    
    if [ -n "$GATEWAY" ]; then
        echo "static routers=$GATEWAY" >> /etc/dhcpcd.conf
    fi
    
    echo "" >> /etc/dhcpcd.conf
    
else
    # Fallback: /etc/network/interfaces
    echo "Verwende /etc/network/interfaces..."
    
    # Backup
    cp /etc/network/interfaces /etc/network/interfaces.backup 2>/dev/null || true
    
    cat > /etc/network/interfaces << EOF
# Loopback
auto lo
iface lo inet loopback

# Kamera-Netzwerk (statisch)
auto $NETWORK_IFACE
iface $NETWORK_IFACE inet static
    address $PI_IP
    netmask $NETMASK
EOF
    
    if [ -n "$GATEWAY" ]; then
        echo "    gateway $GATEWAY" >> /etc/network/interfaces
    fi
fi

echo -e "${GREEN}Netzwerk konfiguriert: $PI_IP/$CIDR auf $NETWORK_IFACE${NC}"
echo ""

# Anzahl Kameras
while true; do
    read -p "Wie viele Kameras sollen angezeigt werden? [1-16]: " NUM_CAMERAS
    if [[ "$NUM_CAMERAS" =~ ^[0-9]+$ ]] && [ "$NUM_CAMERAS" -ge 1 ] && [ "$NUM_CAMERAS" -le 16 ]; then
        break
    fi
    echo -e "${RED}Bitte eine Zahl zwischen 1 und 16 eingeben.${NC}"
done

echo ""
echo -e "${YELLOW}Häufige RTSP-Pfade:${NC}"
echo "  [1] /cam/realmonitor?channel=1&subtype=0  (Burgwächter/Dahua)"
echo "  [2] /Streaming/Channels/101               (Hikvision)"
echo "  [3] /stream1                              (ONVIF generisch)"
echo "  [4] Eigenen Pfad eingeben"
echo ""

while true; do
    read -p "Welchen RTSP-Pfad verwenden die Kameras? [1-4]: " RTSP_CHOICE
    case $RTSP_CHOICE in
        1) DEFAULT_RTSP_PATH="/cam/realmonitor?channel=1&subtype=0"; break;;
        2) DEFAULT_RTSP_PATH="/Streaming/Channels/101"; break;;
        3) DEFAULT_RTSP_PATH="/stream1"; break;;
        4) 
            read -p "RTSP-Pfad eingeben (z.B. /live/main): " DEFAULT_RTSP_PATH
            break;;
        *) echo -e "${RED}Bitte 1, 2, 3 oder 4 eingeben.${NC}";;
    esac
done

echo ""
echo -e "${YELLOW}Verwenden alle Kameras die gleichen Zugangsdaten?${NC}"
read -p "[j/n]: " SAME_CREDENTIALS

GLOBAL_USER=""
GLOBAL_PASS=""
if [[ "$SAME_CREDENTIALS" =~ ^[Jj]$ ]]; then
    echo ""
    read -p "Benutzername (leer lassen wenn keine Authentifizierung): " GLOBAL_USER
    if [ -n "$GLOBAL_USER" ]; then
        read -s -p "Passwort: " GLOBAL_PASS
        echo ""
    fi
fi

# Kameras abfragen
echo ""
echo -e "${BLUE}--- Kamera-Konfiguration ---${NC}"
echo ""

declare -a CAMERAS

for ((i=1; i<=NUM_CAMERAS; i++)); do
    echo -e "${GREEN}Kamera $i von $NUM_CAMERAS:${NC}"
    
    # Name
    read -p "  Name (z.B. Einfahrt, Garten): " CAM_NAME
    [ -z "$CAM_NAME" ] && CAM_NAME="Kamera $i"
    
    # IP
    while true; do
        read -p "  IP-Adresse: " CAM_IP
        if [[ "$CAM_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            break
        fi
        echo -e "${RED}  Ungültige IP-Adresse. Format: 192.168.1.100${NC}"
    done
    
    # Zugangsdaten (wenn nicht global)
    if [[ ! "$SAME_CREDENTIALS" =~ ^[Jj]$ ]]; then
        read -p "  Benutzername (leer = keine Auth): " CAM_USER
        if [ -n "$CAM_USER" ]; then
            read -s -p "  Passwort: " CAM_PASS
            echo ""
        else
            CAM_PASS=""
        fi
    else
        CAM_USER="$GLOBAL_USER"
        CAM_PASS="$GLOBAL_PASS"
    fi
    
    # Optional: eigener RTSP-Pfad
    read -p "  Eigener RTSP-Pfad? (Enter = Standard): " CAM_RTSP
    [ -z "$CAM_RTSP" ] && CAM_RTSP=""
    
    # Speichern
    CAMERAS+=("$CAM_NAME|$CAM_IP|$CAM_USER|$CAM_PASS|$CAM_RTSP")
    
    echo ""
done

# Config generieren
echo -e "${BLUE}Erstelle Konfiguration...${NC}"

cat > "$CONFIG_FILE" << EOF
# Kamera-Viewer Konfiguration
# Erstellt am: $(date)
# ============================

display:
  resolution: ""
  layout: "grid"
  background: "#000000"

defaults:
  port: 554
  rtsp_path: "$DEFAULT_RTSP_PATH"
  transport: "tcp"
  buffer_ms: 500

cameras:
EOF

for cam in "${CAMERAS[@]}"; do
    IFS='|' read -r name ip user pass rtsp <<< "$cam"
    
    echo "  - name: \"$name\"" >> "$CONFIG_FILE"
    echo "    ip: \"$ip\"" >> "$CONFIG_FILE"
    
    if [ -n "$user" ]; then
        echo "    username: \"$user\"" >> "$CONFIG_FILE"
        echo "    password: \"$pass\"" >> "$CONFIG_FILE"
    else
        echo "    username: \"\"" >> "$CONFIG_FILE"
        echo "    password: \"\"" >> "$CONFIG_FILE"
    fi
    
    if [ -n "$rtsp" ]; then
        echo "    rtsp_path: \"$rtsp\"" >> "$CONFIG_FILE"
    fi
    
    echo "" >> "$CONFIG_FILE"
done

# Berechtigungen
chown "$TARGET_USER:$TARGET_USER" "$CONFIG_FILE"
chmod 600 "$CONFIG_FILE"  # Nur Owner kann lesen (wegen Passwörter)

echo ""
echo -e "${GREEN}======================================"
echo "   Setup abgeschlossen!"
echo -e "======================================${NC}"
echo ""
echo "Konfiguration gespeichert: $CONFIG_FILE"
echo ""
echo "Zusammenfassung:"
echo "  - Pi IP-Adresse: $PI_IP/$CIDR"
echo "  - Kameras: $NUM_CAMERAS"
echo "  - RTSP-Pfad: $DEFAULT_RTSP_PATH"
echo ""
echo "Konfigurierte Kameras:"
for cam in "${CAMERAS[@]}"; do
    IFS='|' read -r name ip user pass rtsp <<< "$cam"
    echo "  - $name ($ip)"
done
echo ""
