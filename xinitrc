#!/bin/sh
# xinitrc - Startet den minimalen Window Manager und Viewer

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_FILE="$SCRIPT_DIR/cam-viewer.log"

echo "=== xinitrc: $(date) ===" >> "$LOG_FILE"
echo "DISPLAY=$DISPLAY" >> "$LOG_FILE"

# Bildschirmschoner deaktivieren
xset s off
xset -dpms
xset s noblank

# Schwarzer Hintergrund
xsetroot -solid "#000000"

# Openbox als minimaler Window Manager (im Hintergrund)
openbox &

# Kurz warten bis Openbox bereit ist
sleep 2

# Kamera-Viewer starten (Output ins Log)
cd "$SCRIPT_DIR"
exec python3 cam-viewer.py >> "$LOG_FILE" 2>&1
