#!/bin/bash
# Startskript für den Kamera-Viewer (DRM-Mode, ohne X11)

if [ -z "$BASH_VERSION" ]; then
    exec bash "$0" "$@"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/cam-viewer.log"

: > "$LOG_FILE"

log() {
    echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log "=== Kamera-Viewer Start (DRM-Mode) ==="
log "Benutzer: $(whoami)"
log "TTY: $(tty)"

# Warte auf Netzwerk
log "Warte auf Netzwerk..."
for i in {1..30}; do
    if ip addr | grep -v "127.0.0.1" | grep -q "inet "; then
        log "Netzwerk verfügbar."
        ip addr | grep "inet " | grep -v "127.0.0.1" | tee -a "$LOG_FILE"
        break
    fi
    sleep 1
done

sleep 2

# Konsole/Cursor verstecken
setterm --blank 0 --powerdown 0 --cursor off 2>/dev/null || true
echo -e "\033[?25l" 2>/dev/null || true
clear

# Pakete prüfen
if ! command -v mpv &> /dev/null; then
    log "FEHLER: mpv nicht installiert!"
    sleep 30
    exit 1
fi

if ! command -v python3 &> /dev/null; then
    log "FEHLER: python3 nicht installiert!"
    sleep 30
    exit 1
fi

log "Starte Kamera-Viewer..."
log "(Falls Probleme: Wechsle zu TTY2 mit Strg+Alt+F2)"

cd "$SCRIPT_DIR"
python3 -u cam-viewer.py 2>&1 | tee -a "$LOG_FILE"

log "Kamera-Viewer beendet"
sleep 30
