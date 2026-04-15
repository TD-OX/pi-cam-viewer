#!/bin/bash
# Startskript für den Kamera-Viewer
# Startet X11 mit minimalem Openbox und dann den Viewer

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Warte auf Netzwerk (wichtig für Kameras)
echo "Warte auf Netzwerk..."
for i in {1..30}; do
    if ping -c 1 -W 1 8.8.8.8 &>/dev/null || ip route | grep -q default; then
        echo "Netzwerk verfügbar."
        break
    fi
    sleep 1
done

# Warte noch etwas für DHCP etc.
sleep 3

# X11 starten mit Openbox als Window Manager
# Der Viewer wird als einzige Anwendung gestartet
export DISPLAY=:0

echo "Starte X-Server..."
exec startx "$SCRIPT_DIR/xinitrc" -- -nocursor vt1
