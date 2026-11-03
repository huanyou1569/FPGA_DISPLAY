@echo off
setlocal
cd /d "%~dp0"
set "PYTHONUTF8=1"
set "VX_PYTHON=python"
if exist "%~dp0.venv\Scripts\python.exe" set "VX_PYTHON=%~dp0.venv\Scripts\python.exe"
"%VX_PYTHON%" -c "import bleak, tkinter; from importlib.metadata import version; assert 3 <= int(version('bleak').split('.')[0]) < 4" >nul 2>&1
if errorlevel 1 (
  echo Python, tkinter or a compatible bleak 3.x is missing.
  echo Run: python -m pip install -r requirements_ch9141.txt
  pause
  exit /b 1
)
"%VX_PYTHON%" "%~dp0ch9141_upper.py"
if errorlevel 1 pause
