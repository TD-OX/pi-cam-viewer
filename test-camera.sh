#!/bin/bash
# Testet RTSP-Verbindungen zu Kameras
# Verwendung: ./test-camera.sh <IP> <USER> <PASS> [RTSP_PATH]

if [ -z "$1" ]; then
    echo "Verwendung: $0 <IP> <USER> <PASS> [RTSP_PATH]"
    echo ""
    echo "Beispiele:"
    echo "  $0 192.168.1.100 admin passwort123"
    echo "  $0 192.168.1.100 admin passwort123 /Streaming/Channels/101"
    echo ""
    echo "Häufige RTSP-Pfade:"
    echo "  Burgwächter/Dahua: /cam/realmonitor?channel=1&subtype=0"
    echo "  Hikvision:         /Streaming/Channels/101"
    echo "  ONVIF generisch:   /stream1 oder /live/main"
    exit 1
fi

IP="$1"
USER="$2"
PASS="$3"
RTSP_PATH="${4:-/cam/realmonitor?channel=1&subtype=0}"

# URL zusammenbauen
if [ -n "$USER" ] && [ -n "$PASS" ]; then
    URL="rtsp://${USER}:${PASS}@${IP}:554${RTSP_PATH}"
    URL_DISPLAY="rtsp://${USER}:***@${IP}:554${RTSP_PATH}"
else
    URL="rtsp://${IP}:554${RTSP_PATH}"
    URL_DISPLAY="$URL"
fi

echo "======================================"
echo "Kamera-Test"
echo "======================================"
echo ""
echo "IP:        $IP"
echo "Benutzer:  ${USER:-<keiner>}"
echo "RTSP-Pfad: $RTSP_PATH"
echo "URL:       $URL_DISPLAY"
echo ""

# Ping-Test
echo "1. Ping-Test..."
if ping -c 2 -W 2 "$IP" > /dev/null 2>&1; then
    echo "   ✓ Kamera erreichbar"
else
    echo "   ✗ Kamera nicht erreichbar (Ping fehlgeschlagen)"
    echo "   → Prüfe IP-Adresse und Netzwerkverbindung"
    exit 1
fi

# Port-Test
echo ""
echo "2. Port-Test (554)..."
if nc -zw2 "$IP" 554 2>/dev/null; then
    echo "   ✓ RTSP-Port offen"
else
    echo "   ✗ RTSP-Port 554 nicht erreichbar"
    echo "   → Prüfe ob die Kamera RTSP aktiviert hat"
    exit 1
fi

# RTSP-Test mit ffprobe
echo ""
echo "3. RTSP-Stream-Test..."
if command -v ffprobe &> /dev/null; then
    echo "   Verbinde mit ffprobe (Timeout: 10s)..."
    if ffprobe -v error -show_entries stream=codec_name,width,height -of csv=p=0 \
        -rtsp_transport tcp -timeout 10000000 "$URL" 2>/dev/null; then
        echo "   ✓ Stream erfolgreich erkannt!"
    else
        echo "   ✗ Stream konnte nicht geöffnet werden"
        echo ""
        echo "   Mögliche Ursachen:"
        echo "   - Falscher RTSP-Pfad"
        echo "   - Falsche Zugangsdaten"
        echo "   - Kamera unterstützt kein RTSP"
        echo ""
        echo "   Teste andere RTSP-Pfade:"
        echo "   $0 $IP $USER $PASS /cam/realmonitor?channel=1&subtype=0"
        echo "   $0 $IP $USER $PASS /Streaming/Channels/101"
        echo "   $0 $IP $USER $PASS /stream1"
        echo "   $0 $IP $USER $PASS /live/main"
    fi
else
    echo "   ⚠ ffprobe nicht installiert, überspringe Stream-Test"
fi

# mpv-Test (optional, nur wenn Display verfügbar)
echo ""
echo "4. Video-Test mit mpv..."
if command -v mpv &> /dev/null; then
    if [ -n "$DISPLAY" ]; then
        echo "   Starte mpv (10 Sekunden, dann automatisch beenden)..."
        echo "   Drücke 'q' zum manuellen Beenden."
        timeout 10 mpv --no-terminal --rtsp-transport=tcp "$URL" 2>/dev/null || true
        echo "   Test beendet."
    else
        echo "   ⚠ Kein Display verfügbar, überspringe mpv-Test"
        echo "   (Führe das Skript mit aktivem X-Server aus für Video-Test)"
    fi
else
    echo "   ⚠ mpv nicht installiert"
fi

echo ""
echo "======================================"
echo "Test abgeschlossen"
echo "======================================"
