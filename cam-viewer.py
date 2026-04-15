#!/usr/bin/env python3
"""
Kamera-Viewer für Raspberry Pi
Zeigt RTSP-Streams von Netzwerkkameras auf dem Monitor an.
"""

import subprocess
import sys
import os
import signal
import time
import yaml
import math
from pathlib import Path

# Globale Liste der laufenden Prozesse
processes = []

def load_config(config_path: str) -> dict:
    """Lädt die Konfiguration aus der YAML-Datei."""
    with open(config_path, 'r', encoding='utf-8') as f:
        return yaml.safe_load(f)

def get_display_resolution() -> tuple[int, int]:
    """Ermittelt die aktuelle Display-Auflösung."""
    try:
        result = subprocess.run(
            ['xdpyinfo'],
            capture_output=True,
            text=True,
            timeout=5
        )
        for line in result.stdout.split('\n'):
            if 'dimensions:' in line:
                # Format: "dimensions:    1920x1080 pixels"
                dims = line.split()[1]
                w, h = dims.split('x')
                return int(w), int(h)
    except Exception as e:
        print(f"Warnung: Display-Auflösung konnte nicht ermittelt werden: {e}")
    
    # Fallback
    return 1920, 1080

def build_rtsp_url(camera: dict, defaults: dict) -> str:
    """Baut die RTSP-URL für eine Kamera zusammen."""
    ip = camera['ip']
    port = camera.get('port', defaults.get('port', 554))
    username = camera.get('username', '')
    password = camera.get('password', '')
    rtsp_path = camera.get('rtsp_path', defaults.get('rtsp_path', '/stream1'))
    
    # Authentifizierung einbauen falls vorhanden
    if username and password:
        auth = f"{username}:{password}@"
    elif username:
        auth = f"{username}@"
    else:
        auth = ""
    
    return f"rtsp://{auth}{ip}:{port}{rtsp_path}"

def calculate_grid(num_cameras: int, screen_w: int, screen_h: int) -> list[dict]:
    """Berechnet die Positionen für ein Grid-Layout."""
    if num_cameras == 0:
        return []
    
    # Optimale Grid-Größe berechnen
    cols = math.ceil(math.sqrt(num_cameras))
    rows = math.ceil(num_cameras / cols)
    
    cell_w = screen_w // cols
    cell_h = screen_h // rows
    
    positions = []
    for i in range(num_cameras):
        row = i // cols
        col = i % cols
        positions.append({
            'x': col * cell_w,
            'y': row * cell_h,
            'w': cell_w,
            'h': cell_h
        })
    
    return positions

def start_mpv_stream(rtsp_url: str, geometry: dict, name: str, transport: str, buffer_ms: int) -> subprocess.Popen:
    """Startet einen mpv-Prozess für einen Kamera-Stream."""
    
    # mpv-Optionen für stabiles RTSP-Streaming
    cmd = [
        'mpv',
        '--no-terminal',
        '--no-osc',                    # Kein On-Screen-Controller
        '--no-input-default-bindings', # Keine Tastatur-Shortcuts
        '--no-input-cursor',           # Kein Cursor
        '--cursor-autohide=always',    # Cursor immer verstecken
        '--no-border',                 # Kein Fensterrahmen
        '--ontop',                     # Immer im Vordergrund
        '--keepaspect=no',             # Fülle das Fenster komplett
        '--hwdec=auto',                # Hardware-Dekodierung wenn möglich
        '--vo=gpu,x11',                # Video-Output
        f'--geometry={geometry["w"]}x{geometry["h"]}+{geometry["x"]}+{geometry["y"]}',
        f'--rtsp-transport={transport}',
        f'--cache=yes',
        f'--cache-secs={buffer_ms / 1000}',
        f'--demuxer-lavf-o=rtsp_transport={transport}',
        '--demuxer-max-bytes=50M',
        '--demuxer-readahead-secs=3',
        '--network-timeout=10',
        '--stream-lavf-o=timeout=10000000',  # 10 Sekunden Timeout
        '--loop=inf',                  # Bei Verbindungsabbruch neu verbinden
        '--idle=yes',
        '--force-window=yes',
        '--title=' + name,
        rtsp_url
    ]
    
    print(f"Starte {name}: {rtsp_url.replace(rtsp_url.split('@')[0].split('://')[1], '***')}@...")
    
    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        start_new_session=True
    )
    
    return proc

def cleanup(signum=None, frame=None):
    """Beendet alle laufenden Prozesse sauber."""
    print("\nBeende alle Streams...")
    for proc in processes:
        try:
            os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
        except ProcessLookupError:
            pass
    
    # Kurz warten, dann SIGKILL falls nötig
    time.sleep(1)
    for proc in processes:
        try:
            os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
        except ProcessLookupError:
            pass
    
    print("Beendet.")
    sys.exit(0)

def monitor_streams(cameras_config: list, defaults: dict, positions: list):
    """Überwacht Streams und startet sie bei Bedarf neu."""
    global processes
    
    while True:
        for i, (cam, pos) in enumerate(zip(cameras_config, positions)):
            if i < len(processes):
                proc = processes[i]
                if proc.poll() is not None:
                    # Prozess ist beendet, neu starten
                    print(f"Stream {cam['name']} wird neu gestartet...")
                    rtsp_url = build_rtsp_url(cam, defaults)
                    transport = cam.get('transport', defaults.get('transport', 'tcp'))
                    buffer_ms = cam.get('buffer_ms', defaults.get('buffer_ms', 500))
                    processes[i] = start_mpv_stream(rtsp_url, pos, cam['name'], transport, buffer_ms)
                    time.sleep(0.5)
        
        time.sleep(5)  # Alle 5 Sekunden prüfen

def main():
    global processes
    
    # Signal-Handler für sauberes Beenden
    signal.signal(signal.SIGINT, cleanup)
    signal.signal(signal.SIGTERM, cleanup)
    
    # Konfigurationspfad
    script_dir = Path(__file__).parent.resolve()
    config_path = script_dir / 'config.yaml'
    
    if not config_path.exists():
        print(f"Fehler: Konfigurationsdatei nicht gefunden: {config_path}")
        sys.exit(1)
    
    print("Lade Konfiguration...")
    config = load_config(config_path)
    
    cameras = config.get('cameras', [])
    defaults = config.get('defaults', {})
    display_config = config.get('display', {})
    
    if not cameras:
        print("Fehler: Keine Kameras in der Konfiguration definiert!")
        sys.exit(1)
    
    print(f"Gefunden: {len(cameras)} Kamera(s)")
    
    # Display-Auflösung
    resolution = display_config.get('resolution', '')
    if resolution:
        screen_w, screen_h = map(int, resolution.split('x'))
    else:
        screen_w, screen_h = get_display_resolution()
    
    print(f"Display-Auflösung: {screen_w}x{screen_h}")
    
    # Grid-Positionen berechnen
    positions = calculate_grid(len(cameras), screen_w, screen_h)
    
    # Hintergrund setzen (optional, falls gewünscht)
    try:
        subprocess.run(['xsetroot', '-solid', display_config.get('background', '#000000')], check=False)
    except FileNotFoundError:
        pass
    
    # Cursor ausblenden
    try:
        subprocess.Popen(['unclutter', '-idle', '0', '-root'], 
                        stdout=subprocess.DEVNULL, 
                        stderr=subprocess.DEVNULL)
    except FileNotFoundError:
        print("Warnung: unclutter nicht installiert, Cursor bleibt sichtbar")
    
    # Bildschirmschoner deaktivieren
    subprocess.run(['xset', 's', 'off'], check=False)
    subprocess.run(['xset', '-dpms'], check=False)
    subprocess.run(['xset', 's', 'noblank'], check=False)
    
    # Streams starten
    print("\nStarte Kamera-Streams...")
    for cam, pos in zip(cameras, positions):
        rtsp_url = build_rtsp_url(cam, defaults)
        transport = cam.get('transport', defaults.get('transport', 'tcp'))
        buffer_ms = cam.get('buffer_ms', defaults.get('buffer_ms', 500))
        
        proc = start_mpv_stream(rtsp_url, pos, cam['name'], transport, buffer_ms)
        processes.append(proc)
        time.sleep(0.5)  # Kurze Pause zwischen Starts
    
    print(f"\nAlle {len(cameras)} Streams gestartet. Drücke Strg+C zum Beenden.\n")
    
    # Streams überwachen und bei Bedarf neu starten
    monitor_streams(cameras, defaults, positions)

if __name__ == '__main__':
    main()
