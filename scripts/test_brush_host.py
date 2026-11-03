"""Build and run the portable brush regression with host GCC (no FPGA access)."""
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
out = root / "tests/out"
out.mkdir(parents=True, exist_ok=True)
src = root / "software/brush_app"
exe = out / "test_brush.exe"
subprocess.run([
    "gcc", "-std=c11", "-Wall", "-Wextra", "-Werror", "-O2", f"-I{src}",
    str(root / "tests/host/test_brush.c"), str(src / "vx_brush.c"),
    str(src / "vx_upload.c"), str(src / "vx_snake.c"), str(src / "vx_tetris.c"), "-lm", "-o", str(exe),
], check=True)
subprocess.run([str(exe)], check=True)
