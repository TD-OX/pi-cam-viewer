#!/bin/bash
# Installationsskript für den Kamera-Viewer (DRM-Mode)
# Verwendung: sudo bash install.sh

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

if [ -z "$TARGET_USER" ] || [ "$TARGET_USER" = "root" ]; then
    echo "Fehler: Konnte keinen Benutzer ermitteln."
    echo "Bitte mit 'sudo bash install.sh' als normaler Benutzer ausführen."
    exit 1
fi

TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
INSTALL_DIR="$TARGET_HOME/cam-viewer"

# Farben
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo -e "${BLUE}======================================"
echo "   Kamera-Viewer Installation"
echo "   (DRM-Mode, ohne X11)"
echo -e "======================================${NC}"
echo ""

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Fehler: Bitte als root ausführen (sudo bash install.sh)${NC}"
    exit 1
fi

# Pakete installieren
echo "Installiere benötigte Pakete..."
echo "(Das kann einige Minuten dauern)"
echo ""
apt-get update
apt-get install -y \
    mpv \
    ffmpeg \
    python3 \
    python3-yaml \
    netcat-openbsd \
    gstreamer1.0-tools \
    gstreamer1.0-plugins-base \
    gstreamer1.0-plugins-good \
    gstreamer1.0-plugins-bad \
    gstreamer1.0-libav

echo ""
echo "Erstelle Installationsverzeichnis..."
mkdir -p "$INSTALL_DIR"

echo "Kopiere Programmdateien..."
cp "$SCRIPT_DIR/cam-viewer.py" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/start.sh" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/test-camera.sh" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/setup.sh" "$INSTALL_DIR/"

chmod +x "$INSTALL_DIR/start.sh"
chmod +x "$INSTALL_DIR/cam-viewer.py"
chmod +x "$INSTALL_DIR/test-camera.sh"
chmod +x "$INSTALL_DIR/setup.sh"
chown -R "$TARGET_USER:$TARGET_USER" "$INSTALL_DIR"

echo ""
echo "Konfiguriere Auto-Login auf TTY1..."
mkdir -p /etc/systemd/system/getty@tty1.service.d/
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $TARGET_USER --noclear %I \$TERM
EOF

echo "Setze Benutzergruppen für DRM-Zugriff..."
usermod -aG video,render,tty "$TARGET_USER"

echo "Konfiguriere Auto-Start beim Login..."
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

echo "Deaktiviere Boot-Splash und Bildschirm-Blanking..."
for CMDLINE in /boot/cmdline.txt /boot/firmware/cmdline.txt; do
    if [ -f "$CMDLINE" ]; then
        sed -i 's/ splash//g; s/splash //g; s/^splash$//g' "$CMDLINE"
        sed -i 's/ quiet//g; s/quiet //g; s/^quiet$//g' "$CMDLINE"
        if ! grep -q "consoleblank=0" "$CMDLINE"; then
            sed -i 's/$/ consoleblank=0/' "$CMDLINE"
        fi
    fi
done

echo ""
echo -e "${GREEN}Installation der Systemkomponenten abgeschlossen!${NC}"
echo ""
echo "Benutzer: $TARGET_USER"
echo "Installationsverzeichnis: $INSTALL_DIR"
echo ""
echo "============================================"
echo ""

read -p "Möchtest du jetzt die Kameras einrichten? [J/n]: " DO_SETUP
if [[ ! "$DO_SETUP" =~ ^[Nn]$ ]]; then
    bash "$INSTALL_DIR/setup.sh"
    
    echo ""
    echo -e "${GREEN}======================================"
    echo "   Installation komplett!"
    echo -e "======================================${NC}"
    echo ""
    echo "System wird in 5 Sekunden neu gestartet..."
    echo "(Strg+C zum Abbrechen)"
    sleep 5
    reboot
else
    echo ""
    echo "Setup übersprungen."
    echo ""
    echo "Kameras später einrichten mit:"
    echo "  sudo bash $INSTALL_DIR/setup.sh"
    echo ""
    echo "Danach: sudo reboot"
fi
