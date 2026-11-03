$ErrorActionPreference = 'Stop'
$vxRoot = Split-Path -Parent $PSScriptRoot
$vxOutput = Join-Path $vxRoot 'tests/out'
New-Item -ItemType Directory -Path $vxOutput -Force | Out-Null
$vxExecutable = Join-Path $vxOutput 'test_brush.exe'
$vxSource = Join-Path $vxRoot 'software/brush_app'
& gcc -std=c11 -Wall -Wextra -Werror -O2 "-I$vxSource" (Join-Path $vxRoot 'tests/host/test_brush.c') (Join-Path $vxSource 'vx_brush.c') (Join-Path $vxSource 'vx_upload.c') (Join-Path $vxSource 'vx_snake.c') (Join-Path $vxSource 'vx_tetris.c') -lm -o $vxExecutable
if ($LASTEXITCODE -ne 0) { throw 'Host C build failed' }
& $vxExecutable
if ($LASTEXITCODE -ne 0) { throw 'Host brush regression failed' }
