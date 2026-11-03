"""Run 3D block-game contracts with host GCC; no board access."""
from pathlib import Path
import subprocess
root=Path(__file__).resolve().parents[1]; src=root/'software/brush_app'; out=root/'tests/out'
out.mkdir(exist_ok=True,parents=True); exe=out/'test_tetris_checked.exe'
subprocess.run(['gcc','-std=c11','-Wall','-Wextra','-Werror','-O2',f'-I{src}',
    str(root/'tests/host/test_tetris.c'),str(src/'vx_tetris.c'),str(src/'vx_snake.c'),str(src/'vx_brush.c'),'-o',str(exe)],check=True)
subprocess.run([str(exe)],check=True,timeout=15)
