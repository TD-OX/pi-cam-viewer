#!/bin/bash
# Startskript für den Kamera-Viewer
# Startet X11 mit minimalem Openbox und dann den Viewer

# Sicherstellen dass das Skript mit bash läuft
if [ -z "$BASH_VERSION" ]; then
    exec bash "$0" "$@"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Warte auf Netzwerk (Interface muss aktiv sein)
echo "Warte auf Netzwerk..."
for i in {1..30}; do
    # Prüfen ob irgendein Interface eine IP hat (außer loopback)
    if ip addr | grep -v "127.0.0.1" | grep -q "inet "; then
        echo "Netzwerk verfügbar."
        break
    fi
    sleep 1
done

# Warte noch etwas bis alles stabil ist
sleep 3

# X11 starten mit Openbox als Window Manager
# Der Viewer wird als einzige Anwendung gestartet
export DISPLAY=:0

echo "Starte X-Server..."
exec startx "$SCRIPT_DIR/xinitrc" -- -nocursor vt1
