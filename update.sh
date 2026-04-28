#!/bin/bash
# Update-Skript für den Kamera-Viewer
# Aktualisiert die Installation ohne erneutes Setup
# Verwendung: sudo bash update.sh

# Sicherstellen dass das Skript mit bash läuft
if [ -z "$BASH_VERSION" ]; then
    exec bash "$0" "$@"
fi

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Benutzer ermitteln
if [ -n "$SUDO_USER" ]; then
    TARGET_USER="$SUDO_USER"
else
    TARGET_USER=$(getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 {print $1; exit}')
fi
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
INSTALL_DIR="$TARGET_HOME/cam-viewer"

# Farben
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo -e "${BLUE}======================================"
echo "   Kamera-Viewer Update"
echo -e "======================================${NC}"
echo ""

# Prüfen ob root
if [ "$EUID" -ne 0 ]; then
    echo "Fehler: Bitte als root ausführen (sudo bash update.sh)"
    exit 1
fi

echo "1/5 Hole neueste Version von GitHub..."
cd "$SCRIPT_DIR"
# Repository dem User gehört normalerweise dem Benutzer, aber falls als root
# Dateien angelegt wurden, korrigieren:
chown -R "$TARGET_USER:$TARGET_USER" "$SCRIPT_DIR"
sudo -u "$TARGET_USER" git config --global --add safe.directory "$SCRIPT_DIR"
sudo -u "$TARGET_USER" git reset --hard
sudo -u "$TARGET_USER" git pull

echo ""
echo "2/5 Installiere fehlende Pakete..."
apt-get update
apt-get install -y \
    xserver-xorg-video-modesetting \
    libgl1-mesa-dri \
    mpv \
    python3-yaml

echo ""
echo "3/5 Erstelle Xorg-Konfiguration für Pi-GPU..."
mkdir -p /etc/X11/xorg.conf.d
cat > /etc/X11/xorg.conf.d/10-modesetting.conf << 'EOF'
Section "OutputClass"
    Identifier "vc4"
    MatchDriver "vc4"
    Driver "modesetting"
    Option "PrimaryGPU" "true"
EndSection
EOF

echo ""
echo "4/5 Aktualisiere Programmdateien..."
cp "$SCRIPT_DIR/cam-viewer.py" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/start.sh" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/xinitrc" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/test-camera.sh" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/setup.sh" "$INSTALL_DIR/"

chmod +x "$INSTALL_DIR/start.sh"
chmod +x "$INSTALL_DIR/xinitrc"
chmod +x "$INSTALL_DIR/cam-viewer.py"
chmod +x "$INSTALL_DIR/test-camera.sh"
chmod +x "$INSTALL_DIR/setup.sh"
chown -R "$TARGET_USER:$TARGET_USER" "$INSTALL_DIR"

echo ""
echo "5/5 Stelle sicher dass Auto-Start konfiguriert ist..."
PROFILE_FILE="$TARGET_HOME/.bash_profile"

# Alten Auto-Start entfernen
if [ -f "$PROFILE_FILE" ]; then
    sed -i '/# cam-viewer auto-start/,/# cam-viewer auto-start end/d' "$PROFILE_FILE"
fi

# Neu anlegen
cat >> "$PROFILE_FILE" << EOF

# cam-viewer auto-start
if [ -z "\$DISPLAY" ] && [ "\$(tty)" = "/dev/tty1" ]; then
    cd $INSTALL_DIR
    exec ./start.sh
fi
# cam-viewer auto-start end
EOF
chown "$TARGET_USER:$TARGET_USER" "$PROFILE_FILE"

# Xwrapper.config sicherstellen
cat > /etc/X11/Xwrapper.config << 'EOF'
allowed_users=anybody
needs_root_rights=yes
EOF

# Alten Service entfernen falls vorhanden
if [ -f /etc/systemd/system/cam-viewer.service ]; then
    systemctl disable cam-viewer 2>/dev/null || true
    systemctl stop cam-viewer 2>/dev/null || true
    rm /etc/systemd/system/cam-viewer.service
    systemctl daemon-reload
fi

echo ""
echo -e "${GREEN}======================================"
echo "   Update abgeschlossen!"
echo -e "======================================${NC}"
echo ""
echo "Das System wird in 5 Sekunden neu gestartet..."
echo "(Strg+C zum Abbrechen)"
echo ""

sleep 5
reboot
