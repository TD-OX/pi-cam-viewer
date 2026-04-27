#!/bin/bash
# Startskript für den Kamera-Viewer
# Startet X11 mit minimalem Openbox und dann den Viewer

# Sicherstellen dass das Skript mit bash läuft
if [ -z "$BASH_VERSION" ]; then
    exec bash "$0" "$@"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/cam-viewer.log"

# Log-Datei zurücksetzen
exec > >(tee "$LOG_FILE") 2>&1

echo "=== Kamera-Viewer Start: $(date) ==="

# Warte auf Netzwerk (Interface muss aktiv sein)
echo "Warte auf Netzwerk..."
for i in {1..30}; do
    if ip addr | grep -v "127.0.0.1" | grep -q "inet "; then
        echo "Netzwerk verfügbar."
        ip addr | grep "inet " | grep -v "127.0.0.1"
        break
    fi
    sleep 1
done

# Warte noch etwas bis alles stabil ist
sleep 3

# X11 starten - der xinitrc übernimmt den Rest
echo "Starte X-Server..."
exec startx "$SCRIPT_DIR/xinitrc" -- -nocursor 2>&1
