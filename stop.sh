#!/bin/bash
# Notfall-Skript: Beendet alle Viewer-Prozesse und setzt das Display zurück
# Verwendung: ./stop.sh oder per SSH

if [ -z "$BASH_VERSION" ]; then
    exec bash "$0" "$@"
fi

echo "Beende alle Viewer-Prozesse..."
sudo killall -9 mpv ffmpeg ffplay gst-launch-1.0 2>/dev/null
sudo pkill -9 -f cam-viewer.py 2>/dev/null

sleep 1

echo "Setze Display zurück..."
sudo chvt 2 2>/dev/null
sleep 1
sudo chvt 1 2>/dev/null

# Cursor wieder anzeigen
echo -e "\033[?25h\033c"

echo "Fertig. Bildschirm sollte wieder verfügbar sein."
echo ""
echo "Viewer manuell starten: cd ~/cam-viewer && ./start.sh"
echo "Reboot: sudo reboot"
