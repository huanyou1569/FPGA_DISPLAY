"""Compile and run deterministic snake/scene regression without hardware."""
from pathlib import Path
import subprocess
root=Path(__file__).resolve().parents[1]
source=root/'software/brush_app'
out=root/'tests/out'
out.mkdir(parents=True,exist_ok=True)
exe=out/'test_snake.exe'
subprocess.run(['gcc','-std=c11','-Wall','-Wextra','-Werror','-O2',f'-I{source}',
    str(root/'tests/host/test_snake.c'),str(source/'vx_brush.c'),str(source/'vx_snake.c'),str(source/'vx_tetris.c'),
    '-o',str(exe)],check=True)
subprocess.run([str(exe)],check=True)
