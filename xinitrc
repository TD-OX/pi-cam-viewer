#!/bin/sh
# xinitrc - Startet den minimalen Window Manager und Viewer

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_FILE="$SCRIPT_DIR/cam-viewer.log"

log_x() {
    echo "[xinitrc] $*" >> "$LOG_FILE"
}

log_x "=== xinitrc Start: $(date) ==="
log_x "DISPLAY=$DISPLAY"
log_x "PWD=$(pwd)"
log_x "USER=$(whoami)"

# Bildschirmschoner deaktivieren
xset s off 2>>"$LOG_FILE"
xset -dpms 2>>"$LOG_FILE"
xset s noblank 2>>"$LOG_FILE"

# Schwarzer Hintergrund
xsetroot -solid "#000000" 2>>"$LOG_FILE"

# Openbox als minimaler Window Manager (im Hintergrund)
log_x "Starte Openbox..."
openbox >> "$LOG_FILE" 2>&1 &
OPENBOX_PID=$!
log_x "Openbox PID: $OPENBOX_PID"

# Kurz warten bis Openbox bereit ist
sleep 2

# Prüfen ob config.yaml existiert
if [ ! -f "$SCRIPT_DIR/config.yaml" ]; then
    log_x "FEHLER: config.yaml nicht gefunden in $SCRIPT_DIR"
    log_x "Verfügbare Dateien:"
    ls -la "$SCRIPT_DIR" >> "$LOG_FILE" 2>&1
    sleep 30
    exit 1
fi

log_x "config.yaml gefunden, starte Python..."
log_x "Python-Version: $(python3 --version 2>&1)"

# Kamera-Viewer starten - Output ins Log
cd "$SCRIPT_DIR"
python3 cam-viewer.py >> "$LOG_FILE" 2>&1
PYTHON_EXIT=$?

log_x "Python beendet (Exit-Code: $PYTHON_EXIT)"
log_x "=== Ende xinitrc ==="

# Bei Fehler nicht sofort X beenden, damit Logs lesbar sind
sleep 30
