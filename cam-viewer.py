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
    print("[cleanup] Beendet.", flush=True)
    sys.exit(0)

def run_single_camera(camera: dict, defaults: dict):
    """Eine Kamera direkt fullscreen auf DRM."""
    rtsp_url = build_rtsp_url(camera, defaults)
    transport = camera.get('transport', defaults.get('transport', 'tcp'))
    
    print(f"[main] Starte Kamera: {camera['name']} ({safe_url_for_log(rtsp_url)})", flush=True)
    
    cmd = [
        'mpv',
        '--no-terminal',
        '--no-osc',
        '--no-input-default-bindings',
        '--vo=drm',
        '--hwdec=auto-safe',
        '--profile=low-latency',
        '--fullscreen',
        '--keepaspect=no',
        f'--rtsp-transport={transport}',
        '--cache=yes',
        '--demuxer-max-bytes=20M',
        '--network-timeout=10',
        '--loop=inf',
        rtsp_url
    ]
    
    while True:
        print(f"[main] Starte mpv...", flush=True)
        try:
            proc = subprocess.Popen(cmd, start_new_session=True)
            processes.append(proc)
            proc.wait()
            print(f"[main] mpv beendet (Code: {proc.returncode}), neu in 5s...", flush=True)
        except FileNotFoundError:
            print("[main] FEHLER: mpv nicht gefunden!", flush=True)
            sys.exit(1)
        except Exception as e:
            print(f"[main] Fehler: {e}", flush=True)
        
        if processes and processes[-1] == proc:
            processes.pop()
        time.sleep(5)

def run_multi_camera(cameras: list, defaults: dict):
    """Mehrere Streams via ffmpeg mosaic + mpv auf DRM."""
    num_cameras = len(cameras)
    cols = math.ceil(math.sqrt(num_cameras))
    rows = math.ceil(num_cameras / cols)
    
    target_w = (1920 // cols) - ((1920 // cols) % 2)
    target_h = (1080 // rows) - ((1080 // rows) % 2)
    
    print(f"[main] Mosaic: {cols}x{rows} Grid, {target_w}x{target_h} pro Kamera", flush=True)
    
    cmd = ['ffmpeg', '-loglevel', 'warning']
    for cam in cameras:
        rtsp_url = build_rtsp_url(cam, defaults)
        transport = cam.get('transport', defaults.get('transport', 'tcp'))
        cmd.extend(['-rtsp_transport', transport, '-i', rtsp_url])
    
    filter_parts = []
    for i in range(num_cameras):
        filter_parts.append(f'[{i}:v]scale={target_w}:{target_h},setpts=PTS-STARTPTS[s{i}]')
    
    layout_parts = []
    for i in range(num_cameras):
        col = i % cols
        row = i // cols
        layout_parts.append(f'{col * target_w}_{row * target_h}')
    
    inputs_str = ''.join([f'[s{i}]' for i in range(num_cameras)])
    filter_parts.append(f'{inputs_str}xstack=inputs={num_cameras}:layout={"|".join(layout_parts)}[out]')
    
    cmd.extend([
        '-filter_complex', ';'.join(filter_parts),
        '-map', '[out]',
        '-c:v', 'rawvideo',
        '-pix_fmt', 'yuv420p',
        '-f', 'rawvideo',
        '-'
    ])
    
    mpv_cmd = [
        'mpv', '--no-terminal', '--no-osc',
        '--no-input-default-bindings',
        '--vo=drm', '--hwdec=no', '--fullscreen',
        '--demuxer=rawvideo',
        f'--demuxer-rawvideo-w={cols * target_w}',
        f'--demuxer-rawvideo-h={rows * target_h}',
        '--demuxer-rawvideo-mp-format=yuv420p',
        '--demuxer-rawvideo-fps=15',
        '-'
    ]
    
    while True:
        print(f"[main] Starte ffmpeg + mpv...", flush=True)
        try:
            ffmpeg_proc = subprocess.Popen(cmd, stdout=subprocess.PIPE,
                                           stderr=subprocess.STDOUT, start_new_session=True)
            mpv_proc = subprocess.Popen(mpv_cmd, stdin=ffmpeg_proc.stdout, start_new_session=True)
            processes.extend([ffmpeg_proc, mpv_proc])
            mpv_proc.wait()
            print(f"[main] mpv beendet (Code: {mpv_proc.returncode})", flush=True)
            try:
                ffmpeg_proc.terminate()
                ffmpeg_proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                ffmpeg_proc.kill()
        except FileNotFoundError as e:
            print(f"[main] FEHLER: {e}", flush=True)
            sys.exit(1)
        except Exception as e:
            print(f"[main] Fehler: {e}", flush=True)
        
        processes.clear()
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
        print("[main] Modus: Single-Camera", flush=True)
        run_single_camera(cameras[0], defaults)
    else:
        print(f"[main] Modus: Multi-Camera Mosaic", flush=True)
        run_multi_camera(cameras, defaults)

if __name__ == '__main__':
    main()
