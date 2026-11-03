"""Verify rotation telemetry without touching the board."""
from pathlib import Path
import subprocess
root=Path(__file__).resolve().parents[1]
out=root/'tests/out'; out.mkdir(parents=True,exist_ok=True)
src=root/'software/brush_app'; exe=out/'test_sync.exe'
subprocess.run(['gcc','-std=c11','-Wall','-Wextra','-Werror','-O2',f'-I{src}',
                str(root/'tests/host/test_sync.c'),str(src/'vx_sync.c'),'-o',str(exe)],check=True)
subprocess.run([str(exe)],check=True,timeout=15)
