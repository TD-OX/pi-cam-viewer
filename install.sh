#!/bin/bash
# Installationsskript für den Kamera-Viewer
# Verwendung: sudo ./install.sh

# Sicherstellen dass das Skript mit bash läuft
if [ -z "$BASH_VERSION" ]; then
    exec bash "$0" "$@"
fi

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Benutzer ermitteln (der das Skript mit sudo aufgerufen hat)
if [ -n "$SUDO_USER" ]; then
    TARGET_USER="$SUDO_USER"
else
    # Fallback: ersten normalen Benutzer finden (UID >= 1000)
    TARGET_USER=$(getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 {print $1; exit}')
fi

if [ -z "$TARGET_USER" ] || [ "$TARGET_USER" = "root" ]; then
    echo "Fehler: Konnte keinen Benutzer ermitteln."
    echo "Bitte mit 'sudo ./install.sh' als normaler Benutzer ausführen."
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
echo -e "======================================${NC}"
echo ""

# Prüfen ob root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Fehler: Bitte als root ausführen (sudo ./install.sh)${NC}"
    exit 1
fi

# Pakete installieren
echo "Installiere benötigte Pakete..."
echo "(Das kann einige Minuten dauern)"
echo ""
apt-get update
apt-get install -y \
    xserver-xorg \
    x11-xserver-utils \
    xinit \
    openbox \
    mpv \
    python3 \
    python3-yaml \
    unclutter \
    xdotool

echo ""
echo "Erstelle Installationsverzeichnis..."
mkdir -p "$INSTALL_DIR"

echo "Kopiere Programmdateien..."
cp "$SCRIPT_DIR/cam-viewer.py" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/start.sh" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/xinitrc" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/test-camera.sh" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/setup.sh" "$INSTALL_DIR/"

# Berechtigungen setzen
chmod +x "$INSTALL_DIR/start.sh"
chmod +x "$INSTALL_DIR/xinitrc"
chmod +x "$INSTALL_DIR/cam-viewer.py"
chmod +x "$INSTALL_DIR/test-camera.sh"
chmod +x "$INSTALL_DIR/setup.sh"
chown -R "$TARGET_USER:$TARGET_USER" "$INSTALL_DIR"

echo "Installiere systemd-Service..."
# Service-Datei mit korrektem Benutzer erstellen
cat > /etc/systemd/system/cam-viewer.service << EOF
[Unit]
Description=Kamera-Viewer für Netzwerkkameras
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$TARGET_USER
Environment=HOME=$TARGET_HOME
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/start.sh
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
TTYPath=/dev/tty1
StandardInput=tty

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload

echo ""
echo "Konfiguriere Auto-Login auf TTY1..."
mkdir -p /etc/systemd/system/getty@tty1.service.d/
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $TARGET_USER --noclear %I \$TERM
EOF

echo "Deaktiviere Bildschirm-Blanking..."
# Für ältere Pi OS Versionen
if [ -f /boot/cmdline.txt ]; then
    if ! grep -q "consoleblank=0" /boot/cmdline.txt; then
        sed -i 's/$/ consoleblank=0/' /boot/cmdline.txt
    fi
fi
# Für neuere Pi OS Versionen (Bookworm+)
if [ -f /boot/firmware/cmdline.txt ]; then
    if ! grep -q "consoleblank=0" /boot/firmware/cmdline.txt; then
        sed -i 's/$/ consoleblank=0/' /boot/firmware/cmdline.txt
    fi
fi

echo ""
echo -e "${GREEN}Installation der Systemkomponenten abgeschlossen!${NC}"
echo ""
echo "Benutzer: $TARGET_USER"
echo "Installationsverzeichnis: $INSTALL_DIR"
echo ""
echo "============================================"
echo ""

# Setup starten
read -p "Möchtest du jetzt die Kameras einrichten? [J/n]: " DO_SETUP
if [[ ! "$DO_SETUP" =~ ^[Nn]$ ]]; then
    bash "$INSTALL_DIR/setup.sh"
    
    echo ""
    echo "Aktiviere Autostart..."
    systemctl enable cam-viewer
    
    echo ""
    echo -e "${GREEN}======================================"
    echo "   Installation komplett!"
    echo -e "======================================${NC}"
    echo ""
    echo "Das System wird jetzt neu gestartet."
    echo "Nach dem Neustart startet der Kamera-Viewer automatisch."
    echo ""
    read -p "Drücke Enter zum Neustarten..." 
    reboot
else
    echo ""
    echo "Setup übersprungen."
    echo ""
    echo "Kameras später einrichten mit:"
    echo "  sudo bash $INSTALL_DIR/setup.sh"
    echo ""
    echo "Dann Service aktivieren:"
    echo "  sudo systemctl enable cam-viewer"
    echo "  sudo reboot"
fi
