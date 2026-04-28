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
: > "$LOG_FILE"

log() {
    echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log "=== Kamera-Viewer Start ==="
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

# Prüfen ob X11 installiert ist
if ! command -v startx &> /dev/null; then
    log "FEHLER: startx nicht installiert!"
    log "Bitte installieren: sudo apt-get install -y xserver-xorg xinit"
    sleep 30
    exit 1
fi

if ! command -v mpv &> /dev/null; then
    log "FEHLER: mpv nicht installiert!"
    sleep 30
    exit 1
fi

log "Starte X-Server (auf VT7)..."
log "(Falls schwarzer Bildschirm: Wechsle zu TTY2 mit Strg+Alt+F2)"
log "(Log: $LOG_FILE)"

# X11 starten auf VT7 (separater virtueller Terminal)
# Dadurch keine Konflikte mit System-Console auf TTY1
startx "$SCRIPT_DIR/xinitrc" -- :0 vt7 -nocursor >> "$LOG_FILE" 2>&1
EXIT_CODE=$?

log "X-Server beendet (Exit-Code: $EXIT_CODE)"
log "Letzte Zeilen des Logs:"
tail -20 "$LOG_FILE"

# Bei Fehler nicht endlos neu starten
log "Warte 30 Sekunden vor Neustart (oder Strg+C zum Abbrechen)..."
sleep 30
