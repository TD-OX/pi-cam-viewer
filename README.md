# Pi Kamera-Viewer

Zeigt RTSP-Streams von Netzwerkkameras (AXIS, Burgwächter, Hikvision, ONVIF) auf einem Raspberry Pi ohne Desktop an.

## Features

- **DRM-Mode** - kein X11/Desktop nötig, sehr stabil
- **Interaktives Setup** - Kameras per Assistent einrichten
- **Statisches Netzwerk** - Pi konfiguriert sich selbst eine IP im Kamera-Netz
- Automatischer Start beim Booten
- Automatisches Mosaic für mehrere Kameras (via ffmpeg)
- Vollbild für Einzelkameras
- Automatischer Reconnect bei Verbindungsabbruch

## Voraussetzungen

- Raspberry Pi 4 oder 5 (empfohlen) mit Raspberry Pi OS Lite (64-bit)
- Monitor mit HDMI
- Netzwerkkameras mit RTSP-Support
- Ethernet-Verbindung zu den Kameras

## Erstinstallation

Pi kurz ans Internet hängen, dann:

```bash
# Repository klonen
cd ~
git clone https://github.com/DEIN-USERNAME/pi-cam-viewer.git
cd pi-cam-viewer

# Installieren (inkl. Setup und automatischem Reboot)
sudo bash install.sh
```

Das Setup fragt dich nacheinander:

1. **Netzwerk:** Welche IP soll der Pi bekommen? (z.B. `192.168.1.50` im Kamera-Netz)
2. **Anzahl Kameras** (1-16)
3. **RTSP-Pfad** der Kameras (AXIS, Burgwächter, Hikvision, ...)
4. **Gleiche Zugangsdaten für alle?** (spart Tipparbeit)
5. **Pro Kamera:** Name, IP, Benutzer, Passwort

Nach dem Setup wird automatisch neu gestartet. Beim Boot startet der Viewer ohne weitere Eingriffe.

## Update

Wenn neue Versionen auf GitHub sind:

```bash
cd ~/pi-cam-viewer
sudo bash update.sh
```

Das Skript holt die neueste Version, installiert ggf. neue Pakete und startet neu.

## Kameras später ändern

```bash
sudo bash ~/cam-viewer/setup.sh
sudo reboot
```

Das Setup fragt alles erneut ab und überschreibt die Konfiguration.

## RTSP-Pfade

| Hersteller | Pfad |
|------------|------|
| AXIS | `/axis-media/media.amp` |
| Burgwächter / Dahua | `/cam/realmonitor?channel=1&subtype=0` |
| Hikvision | `/Streaming/Channels/101` |
| ONVIF generisch | `/stream1` |

## Befehle

```bash
# Logs anzeigen
cat ~/cam-viewer/cam-viewer.log

# Manuelles Starten/Stoppen
cd ~/cam-viewer
./start.sh              # Manuell starten
# Strg+C beendet

# Kamera testen
~/cam-viewer/test-camera.sh 192.168.1.100 admin passwort
```

## Bedienung

- **Strg+Alt+F2** wechselt auf eine Konsole für Wartung/Debug
- **Strg+Alt+F1** zurück zum Kamera-Bild
- Per SSH erreichbar (sofern aktiviert beim Image-Flashen)

## Architektur

- **Single-Camera:** mpv direkt mit `--vo=drm` im Vollbild
- **Multi-Camera:** ffmpeg kombiniert die Streams via `xstack` zu einem Mosaic, mpv zeigt es
- **Auto-Start:** über `.bash_profile` bei Auto-Login auf TTY1
- **Netzwerk:** statische IP via NetworkManager oder dhcpcd

## Fehlerbehebung

**Schwarzer Bildschirm:**
```bash
# Auf TTY2 wechseln (Strg+Alt+F2), einloggen
cat ~/cam-viewer/cam-viewer.log
```

**Kamera nicht erreichbar:**
```bash
ping 192.168.1.100
nc -zv 192.168.1.100 554
```

**RTSP-Pfad falsch:**
```bash
~/cam-viewer/test-camera.sh 192.168.1.100 admin passwort /axis-media/media.amp
```

## Lizenz

MIT
