# Pi Kamera-Viewer

Zeigt RTSP-Streams von Netzwerkkameras (Burgwächter/ONVIF) auf einem Raspberry Pi ohne Desktop an.

## Features

- **Interaktives Setup** - Kameras einfach per Assistent einrichten
- Automatischer Start beim Booten
- Automatisches Grid-Layout (1-16 Kameras)
- Automatischer Reconnect bei Verbindungsabbruch
- Minimales System (kein Desktop nötig)

## Voraussetzungen

- Raspberry Pi 3/4/5 mit Raspberry Pi OS Lite
- Monitor mit HDMI
- Netzwerkkameras mit RTSP-Support
- Internetverbindung (nur für Installation)

## Installation

```bash
# Repository klonen
git clone https://github.com/DEIN-USERNAME/pi-cam-viewer.git
cd pi-cam-viewer

# Installieren (inkl. interaktivem Kamera-Setup)
sudo ./install.sh
```

Das Setup fragt ab:
1. Anzahl der Kameras
2. RTSP-Pfad (Burgwächter/Dahua, Hikvision, etc.)
3. Ob alle Kameras gleiche Zugangsdaten haben
4. Für jede Kamera: Name, IP, Benutzer, Passwort

Nach dem Setup:
```bash
# Service aktivieren
sudo systemctl enable cam-viewer

# Neustart
sudo reboot
```

## Kameras später ändern

```bash
sudo /home/pi/cam-viewer/setup.sh
sudo systemctl restart cam-viewer
```

## Unterstützte Kamera-Typen

| Hersteller | RTSP-Pfad |
|------------|-----------|
| Burgwächter/Dahua | `/cam/realmonitor?channel=1&subtype=0` |
| Hikvision | `/Streaming/Channels/101` |
| ONVIF generisch | `/stream1` |

## Befehle

```bash
# Status
sudo systemctl status cam-viewer

# Logs (live)
journalctl -u cam-viewer -f

# Neustart
sudo systemctl restart cam-viewer

# Stoppen
sudo systemctl stop cam-viewer
```

## Einzelne Kamera testen

```bash
/home/pi/cam-viewer/test-camera.sh 192.168.1.100 admin passwort
```

## Fehlerbehebung

**Schwarzer Bildschirm:**
```bash
journalctl -u cam-viewer -n 50
```

**Kamera nicht erreichbar:**
```bash
ping 192.168.1.100
nc -zv 192.168.1.100 554
```

## Lizenz

MIT
