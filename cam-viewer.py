#!/usr/bin/env python3
"""
Kamera-Viewer für Raspberry Pi (DRM-Mode, ohne X11)
- 1 Kamera: mpv direkt im Vollbild
- Mehrere Kameras: mpv kombiniert die Streams per lavfi-complex zu einem Mosaic
"""

import subprocess
import sys
import os
import signal
import time
import yaml
from pathlib import Path

processes = []
DEFAULT_SCREEN_W = 1920
DEFAULT_SCREEN_H = 1080
VALID_ROTATIONS = {0, 90, 180, 270}

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

def parse_resolution(value: str, default_w: int = DEFAULT_SCREEN_W, default_h: int = DEFAULT_SCREEN_H) -> tuple:
    """Parst Auflösungen wie 1920x1080. Leere/ungültige Werte fallen auf 1920x1080 zurück."""
    if not value:
        return default_w, default_h

    normalized = str(value).lower().replace(' ', '')
    if 'x' not in normalized:
        return default_w, default_h

    width, height = normalized.split('x', 1)
    try:
        parsed_w = int(width)
        parsed_h = int(height)
    except ValueError:
        return default_w, default_h

    if parsed_w <= 0 or parsed_h <= 0:
        return default_w, default_h

    return parsed_w, parsed_h

def get_display_settings(display: dict) -> dict:
    """Ermittelt physische Ausgabe, logische Mosaic-Fläche und mpv-Rotation."""
    display = display or {}
    physical_w, physical_h = parse_resolution(display.get('resolution', ''))
    orientation = display.get('orientation', 'landscape')

    try:
        rotation = int(display.get('rotation', 0))
    except (TypeError, ValueError):
        rotation = 0
    if rotation not in VALID_ROTATIONS:
        rotation = 0

    if orientation == 'portrait' or rotation in {90, 270}:
        logical_w = min(physical_w, physical_h)
        logical_h = max(physical_w, physical_h)
    else:
        logical_w = max(physical_w, physical_h)
        logical_h = min(physical_w, physical_h)

    return {
        'physical_w': physical_w,
        'physical_h': physical_h,
        'logical_w': logical_w,
        'logical_h': logical_h,
        'rotation': rotation,
    }

def add_rotation_option(cmd: list, rotation: int):
    if rotation:
        cmd.append(f'--video-rotate={rotation}')

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

def run_camera(camera: dict, defaults: dict, display_settings: dict, duration: int = None):
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
    ]
    add_rotation_option(cmd, display_settings['rotation'])
    cmd.append(rtsp_url)

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

def run_single_camera(camera: dict, defaults: dict, display_settings: dict):
    """Eine Kamera dauerhaft fullscreen."""
    while True:
        run_camera(camera, defaults, display_settings, duration=None)
        print(f"[main] mpv beendet, neu in 5s...", flush=True)
        time.sleep(5)

def get_grid_layout(n: int, portrait: bool = False) -> tuple:
    """Gibt (cols, rows) für n Kameras zurück."""
    if n <= 1: return (1, 1)

    if portrait:
        if n <= 3: return (1, n)
        if n <= 4: return (2, 2)
        if n <= 6: return (2, 3)
        if n <= 9: return (3, 3)
        if n <= 12: return (3, 4)
        return (4, 4)

    if n == 2: return (1, 2)
    if n == 3: return (3, 1)
    if n == 4: return (2, 2)
    if n <= 6: return (3, 2)
    if n <= 9: return (3, 3)
    if n <= 12: return (4, 3)
    return (4, 4)

def build_lavfi_complex(num_cams: int, screen_w: int = 1920, screen_h: int = 1080) -> tuple:
    """Baut den lavfi-complex Filter-Graph für n Kameras.
    Gibt (filter_string, cell_w, cell_h) zurück."""
    cols, rows = get_grid_layout(num_cams, portrait=screen_h > screen_w)

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

def run_multi_camera(cameras: list, defaults: dict, display_settings: dict):
    """Alle Kameras gleichzeitig in einem Mosaic - via mpv lavfi-complex."""
    num_cameras = len(cameras)
    transport = defaults.get('transport', 'tcp')

    cols, rows = get_grid_layout(
        num_cameras,
        portrait=display_settings['logical_h'] > display_settings['logical_w'],
    )
    print(f"[main] Mosaic: {cols}x{rows} Grid für {num_cameras} Kameras", flush=True)

    # Filter-Graph bauen
    lavfi, cell_w, cell_h = build_lavfi_complex(
        num_cameras,
        display_settings['logical_w'],
        display_settings['logical_h'],
    )
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
    add_rotation_option(cmd, display_settings['rotation'])

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
    display_settings = get_display_settings(config.get('display', {}))
    if not cameras:
        print("[main] FEHLER: Keine Kameras in der Konfiguration!", flush=True)
        sys.exit(1)

    print(f"[main] Gefunden: {len(cameras)} Kamera(s)", flush=True)
    print(
        f"[main] Display: {display_settings['physical_w']}x{display_settings['physical_h']}, "
        f"logisch {display_settings['logical_w']}x{display_settings['logical_h']}, "
        f"Rotation {display_settings['rotation']}°",
        flush=True,
    )
    for cam in cameras:
        print(f"[main]   - {cam['name']} ({cam['ip']})", flush=True)

    try:
        subprocess.run(['setterm', '--blank', '0', '--powerdown', '0'], check=False)
    except FileNotFoundError:
        pass

    if len(cameras) == 1:
        print("[main] Modus: Single-Camera (Vollbild)", flush=True)
        run_single_camera(cameras[0], defaults, display_settings)
    else:
        print(f"[main] Modus: Mosaic - alle Kameras gleichzeitig", flush=True)
        run_multi_camera(cameras, defaults, display_settings)

if __name__ == '__main__':
    main()
