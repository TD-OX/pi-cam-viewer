#!/usr/bin/env python3
"""
Kamera-Viewer für Raspberry Pi (DRM-Mode, ohne X11)
- 1 Kamera: mpv direkt im Vollbild
- Mehrere Kameras: ffmpeg kombiniert die Streams zu einem Mosaic, mpv zeigt es an
"""

import subprocess
import sys
import os
import signal
import time
import yaml
import math
from pathlib import Path

processes = []

def load_config(config_path: str) -> dict:
    with open(config_path, 'r', encoding='utf-8') as f:
        return yaml.safe_load(f)

def build_rtsp_url(camera: dict, defaults: dict) -> str:
    ip = camera['ip']
    port = camera.get('port', defaults.get('port', 554))
    username = camera.get('username', '')
    password = camera.get('password', '')
    rtsp_path = camera.get('rtsp_path', defaults.get('rtsp_path', '/stream1'))
    
    if username and password:
        auth = f"{username}:{password}@"
    elif username:
        auth = f"{username}@"
    else:
        auth = ""
    
    return f"rtsp://{auth}{ip}:{port}{rtsp_path}"

def safe_url_for_log(url: str) -> str:
    if '@' in url:
        prefix, suffix = url.split('@', 1)
        return prefix.split('://')[0] + '://***@' + suffix
    return url

def cleanup(signum=None, frame=None):
    print("\n[cleanup] Beende alle Prozesse...", flush=True)
    for proc in processes:
        try:
            os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
        except (ProcessLookupError, OSError):
            pass
    time.sleep(1)
    for proc in processes:
        try:
            os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
        except (ProcessLookupError, OSError):
            pass
    
    # Konsole zurücksetzen, sonst bleibt der Bildschirm schwarz
    try:
        # Display/Konsole zurücksetzen
        subprocess.run(['setterm', '--reset'], check=False, stderr=subprocess.DEVNULL)
        # Cursor wieder einblenden
        sys.stdout.write('\033[?25h\033c')
        sys.stdout.flush()
        # TTY neu zeichnen
        subprocess.run(['chvt', '1'], check=False, stderr=subprocess.DEVNULL)
    except Exception:
        pass
    
    print("[cleanup] Beendet.", flush=True)
    sys.exit(0)

def run_camera(camera: dict, defaults: dict, duration: int = None):
    """Zeigt eine Kamera fullscreen auf DRM. Optional: Begrenzte Dauer in Sekunden."""
    rtsp_url = build_rtsp_url(camera, defaults)
    transport = camera.get('transport', defaults.get('transport', 'tcp'))
    
    print(f"[main] Zeige: {camera['name']} ({safe_url_for_log(rtsp_url)})", flush=True)
    
    cmd = [
        'mpv',
        '--no-terminal',
        '--no-osc',
        '--no-input-default-bindings',
        '--vo=drm',
        '--hwdec=auto-safe',
        '--fullscreen',
        '--keepaspect=no',
        # Latenz-Optimierungen
        '--profile=low-latency',
        '--cache=no',
        '--untimed',
        '--no-correct-pts',
        '--video-sync=desync',
        '--demuxer-lavf-o-set=fflags=+nobuffer+flush_packets',
        '--demuxer-lavf-o-set=flags=+low_delay',
        '--vd-lavc-threads=1',
        f'--rtsp-transport={transport}',
        '--network-timeout=10',
        rtsp_url
    ]
    
    try:
        proc = subprocess.Popen(cmd, start_new_session=True)
        processes.append(proc)
        try:
            proc.wait(timeout=duration)
        except subprocess.TimeoutExpired:
            # Cycle-Wechsel: mpv beenden
            try:
                os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
                proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
        if processes and processes[-1] == proc:
            processes.pop()
    except FileNotFoundError:
        print("[main] FEHLER: mpv nicht gefunden!", flush=True)
        sys.exit(1)
    except Exception as e:
        print(f"[main] Fehler: {e}", flush=True)

def run_single_camera(camera: dict, defaults: dict):
    """Eine Kamera dauerhaft fullscreen."""
    while True:
        run_camera(camera, defaults, duration=None)
        print(f"[main] mpv beendet, neu in 5s...", flush=True)
        time.sleep(5)

def get_grid_layout(n: int) -> tuple:
    """Gibt (cols, rows) für n Kameras zurück."""
    if n <= 1: return (1, 1)
    if n == 2: return (2, 1)
    if n == 3: return (3, 1)
    if n == 4: return (2, 2)
    if n <= 6: return (3, 2)
    if n <= 9: return (3, 3)
    if n <= 12: return (4, 3)
    return (4, 4)

def build_lavfi_complex(num_cams: int, screen_w: int = 1920, screen_h: int = 1080) -> tuple:
    """Baut den lavfi-complex Filter-Graph für n Kameras.
    Gibt (filter_string, cell_w, cell_h) zurück."""
    cols, rows = get_grid_layout(num_cams)
    
    cell_w = (screen_w // cols) - ((screen_w // cols) % 2)
    cell_h = (screen_h // rows) - ((screen_h // rows) % 2)
    
    parts = []
    
    # Jede Kamera skalieren (vid1 = erste Kamera, vid2 = zweite, ...)
    for i in range(num_cams):
        parts.append(f'[vid{i+1}]scale={cell_w}:{cell_h}:force_original_aspect_ratio=disable,setsar=1[s{i}]')
    
    # Bei nicht-quadratischen Kamera-Anzahlen mit schwarzen Slots auffüllen
    total_slots = cols * rows
    for i in range(num_cams, total_slots):
        parts.append(f'color=size={cell_w}x{cell_h}:color=black:duration=999999[s{i}]')
    
    # xstack mit absoluten Pixelpositionen
    inputs = ''.join([f'[s{i}]' for i in range(total_slots)])
    layout_parts = []
    for i in range(total_slots):
        col = i % cols
        row = i // cols
        layout_parts.append(f'{col * cell_w}_{row * cell_h}')
    layout = '|'.join(layout_parts)
    
    parts.append(f'{inputs}xstack=inputs={total_slots}:layout={layout}[vo]')
    
    return ';'.join(parts), cell_w, cell_h

def run_multi_camera(cameras: list, defaults: dict):
    """Alle Kameras gleichzeitig in einem Mosaic - via mpv lavfi-complex."""
    num_cameras = len(cameras)
    transport = defaults.get('transport', 'tcp')
    
    cols, rows = get_grid_layout(num_cameras)
    print(f"[main] Mosaic: {cols}x{rows} Grid für {num_cameras} Kameras", flush=True)
    
    # Filter-Graph bauen
    lavfi, cell_w, cell_h = build_lavfi_complex(num_cameras)
    print(f"[main] Jede Kamera: {cell_w}x{cell_h}", flush=True)
    
    # URLs bauen
    urls = [build_rtsp_url(cam, defaults) for cam in cameras]
    
    # mpv-Befehl
    cmd = [
        'mpv',
        '--no-terminal',
        '--no-osc',
        '--no-input-default-bindings',
        '--vo=drm',
        '--hwdec=no',
        '--fullscreen',
        '--keepaspect=no',
        # Latenz-Optimierungen
        '--profile=low-latency',
        '--cache=no',
        '--untimed',
        '--no-correct-pts',
        '--video-sync=desync',
        '--demuxer-lavf-o-set=fflags=+nobuffer+flush_packets',
        '--demuxer-lavf-o-set=flags=+low_delay',
        f'--rtsp-transport={transport}',
        '--network-timeout=10',
        f'--lavfi-complex={lavfi}',
    ]
    
    # Kameras 2..N als external_file
    for url in urls[1:]:
        cmd.append(f'--external-file={url}')
    
    # Hauptkamera (vid1) am Ende
    cmd.append(urls[0])
    
    print(f"[main] Starte mpv mit lavfi-complex Mosaic...", flush=True)
    
    while True:
        try:
            proc = subprocess.Popen(cmd, start_new_session=True)
            processes.append(proc)
            proc.wait()
            print(f"[main] mpv beendet (Code: {proc.returncode})", flush=True)
        except FileNotFoundError:
            print("[main] FEHLER: mpv nicht gefunden!", flush=True)
            sys.exit(1)
        except Exception as e:
            print(f"[main] Fehler: {e}", flush=True)
        
        if processes and processes[-1] == proc:
            processes.pop()
        print(f"[main] Neu starten in 5s...", flush=True)
        time.sleep(5)

def main():
    print("[main] === Kamera-Viewer Start (DRM-Mode) ===", flush=True)
    
    signal.signal(signal.SIGINT, cleanup)
    signal.signal(signal.SIGTERM, cleanup)
    
    script_dir = Path(__file__).parent.resolve()
    config_path = script_dir / 'config.yaml'
    
    if not config_path.exists():
        print(f"[main] FEHLER: Konfigurationsdatei nicht gefunden: {config_path}", flush=True)
        sys.exit(1)
    
    print("[main] Lade Konfiguration...", flush=True)
    config = load_config(config_path)
    
    cameras = config.get('cameras', [])
    defaults = config.get('defaults', {})
    cycle_interval = config.get('display', {}).get('cycle_interval', 10)
    
    if not cameras:
        print("[main] FEHLER: Keine Kameras in der Konfiguration!", flush=True)
        sys.exit(1)
    
    print(f"[main] Gefunden: {len(cameras)} Kamera(s)", flush=True)
    for cam in cameras:
        print(f"[main]   - {cam['name']} ({cam['ip']})", flush=True)
    
    try:
        subprocess.run(['setterm', '--blank', '0', '--powerdown', '0'], check=False)
    except FileNotFoundError:
        pass
    
    if len(cameras) == 1:
        print("[main] Modus: Single-Camera (Vollbild)", flush=True)
        run_single_camera(cameras[0], defaults)
    else:
        print(f"[main] Modus: Mosaic - alle Kameras gleichzeitig", flush=True)
        run_multi_camera(cameras, defaults)

if __name__ == '__main__':
    main()
