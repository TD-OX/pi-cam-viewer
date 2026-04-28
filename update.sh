#!/bin/bash
# Update-Skript für den Kamera-Viewer (DRM-Mode)
# Verwendung: sudo bash update.sh

if [ -z "$BASH_VERSION" ]; then
    exec bash "$0" "$@"
fi

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -n "$SUDO_USER" ]; then
    TARGET_USER="$SUDO_USER"
else
    TARGET_USER=$(getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 {print $1; exit}')
fi
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
INSTALL_DIR="$TARGET_HOME/cam-viewer"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo -e "${BLUE}======================================"
echo "   Kamera-Viewer Update (DRM-Mode)"
echo -e "======================================${NC}"
echo ""

if [ "$EUID" -ne 0 ]; then
    echo "Fehler: Bitte als root ausführen (sudo bash update.sh)"
    exit 1
fi

echo "1/5 Hole neueste Version von GitHub..."
cd "$SCRIPT_DIR"
chown -R "$TARGET_USER:$TARGET_USER" "$SCRIPT_DIR"
sudo -u "$TARGET_USER" git config --global --add safe.directory "$SCRIPT_DIR"
sudo -u "$TARGET_USER" git reset --hard
sudo -u "$TARGET_USER" git pull

echo ""
echo "2/5 Installiere benötigte Pakete..."
apt-get update
apt-get install -y \
    mpv \
    ffmpeg \
    python3 \
    python3-yaml \
    gstreamer1.0-tools \
    gstreamer1.0-plugins-base \
    gstreamer1.0-plugins-good \
    gstreamer1.0-plugins-bad \
    gstreamer1.0-libav

echo ""
echo "3/5 Räume alte X11-Konfiguration auf..."
rm -f /etc/X11/xorg.conf.d/10-modesetting.conf

# Plymouth (Boot-Splash) bleibt deaktiviert
for CMDLINE in /boot/cmdline.txt /boot/firmware/cmdline.txt; do
    if [ -f "$CMDLINE" ]; then
        sed -i 's/ splash//g; s/splash //g; s/^splash$//g' "$CMDLINE"
        sed -i 's/ quiet//g; s/quiet //g; s/^quiet$//g' "$CMDLINE"
    fi
done

echo ""
echo "4/5 Aktualisiere Programmdateien..."
cp "$SCRIPT_DIR/cam-viewer.py" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/start.sh" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/stop.sh" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/test-camera.sh" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/setup.sh" "$INSTALL_DIR/"

# xinitrc nicht mehr nötig
rm -f "$INSTALL_DIR/xinitrc"

chmod +x "$INSTALL_DIR/start.sh"
chmod +x "$INSTALL_DIR/stop.sh"
chmod +x "$INSTALL_DIR/cam-viewer.py"
chmod +x "$INSTALL_DIR/test-camera.sh"
chmod +x "$INSTALL_DIR/setup.sh"
chown -R "$TARGET_USER:$TARGET_USER" "$INSTALL_DIR"

echo ""
echo "5/5 Konfiguriere Auto-Start..."

# SSH aktivieren (für einfaches Debugging ohne abtippen)
systemctl enable ssh 2>/dev/null || true
systemctl start ssh 2>/dev/null || true

# Benutzer in video/render Gruppen für DRM-Zugriff
usermod -aG video,render,tty "$TARGET_USER"

PROFILE_FILE="$TARGET_HOME/.bash_profile"

if [ -f "$PROFILE_FILE" ]; then
    sed -i '/# cam-viewer auto-start/,/# cam-viewer auto-start end/d' "$PROFILE_FILE"
fi

cat >> "$PROFILE_FILE" << EOF

# cam-viewer auto-start
if [ "\$(tty)" = "/dev/tty1" ]; then
    cd $INSTALL_DIR
    exec ./start.sh
fi
# cam-viewer auto-start end
EOF
chown "$TARGET_USER:$TARGET_USER" "$PROFILE_FILE"

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
echo "Modus: DRM (kein X11 mehr)"
echo ""
echo "Reboot in 5 Sekunden... (Strg+C zum Abbrechen)"
echo ""

sleep 5
reboot
