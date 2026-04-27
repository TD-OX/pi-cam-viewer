#!/bin/bash
# Interaktives Setup für den Kamera-Viewer
# Fragt nach Kameras und erstellt die Konfiguration

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
echo "  - Kameras: $NUM_CAMERAS"
echo "  - RTSP-Pfad: $DEFAULT_RTSP_PATH"
echo ""
echo "Konfigurierte Kameras:"
for cam in "${CAMERAS[@]}"; do
    IFS='|' read -r name ip user pass rtsp <<< "$cam"
    echo "  - $name ($ip)"
done
echo ""
echo -e "${YELLOW}Nächste Schritte:${NC}"
echo "  1. Service aktivieren:  sudo systemctl enable cam-viewer"
echo "  2. System neu starten:  sudo reboot"
echo ""
echo "Später Kameras ändern:   sudo $TARGET_HOME/cam-viewer/setup.sh"
echo ""
