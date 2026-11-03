"""Record the small-voxel delivery after the hardware/application/BOOT checks."""
import hashlib
import json
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'migration/2026-11-03-small-voxels'
PREVIOUS = ROOT / 'migration/2026-11-03-rotation-sync'
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
manifest = json.loads((OUT/'hardware/manifest.json').read_text(encoding='utf-8'))
checks = json.loads((OUT/'evidence/delivery-check.json').read_text(encoding='utf-8'))
assert checks['hardware_platform_sources'] == 'PASS'
sources = {str(p.relative_to(ROOT)).replace('\\','/'): sha(p)
           for p in (ROOT/'software/brush_app').iterdir() if p.suffix in {'.c','.h'}}
(OUT/'evidence/software-sources.json').write_text(json.dumps(sources,indent=2),encoding='utf-8')
for name in ['main.c','vx_sync.c','vx_sync.h','vx_tetris.c','vx_tetris.h','vx_upload.c','vx_upload.h']:
    assert (ROOT/'software/brush_app'/name).read_bytes() == (ROOT/'vitis_workspace/vx_brush_rotation/src'/name).read_bytes(), name
previous_manifest = json.loads((PREVIOUS/'hardware/manifest.json').read_text(encoding='utf-8'))
for name, info in previous_manifest['files'].items():
    assert sha(PREVIOUS/'hardware'/name) == info['sha256'], name
for run in ['synth_1','impl_1']:
    shutil.copyfile(ROOT/'test.runs'/run/'runme.log', OUT/'evidence'/f'{run}.log')
for path in ['vx_brush.c','vx_snake.c']:
    dst=OUT/'source'/path
    dst.parent.mkdir(exist_ok=True)
    shutil.copyfile(ROOT/'software/brush_app'/path,dst)
result = {
    'host_regressions': {'brush':'PASS','snake':'PASS','tetris':'PASS','sync':'PASS'},
    'rtl_sources': 'identical to rotation-sync baseline; hash verified',
    'rtl_simulations': 'NOT_RERUN: no RTL changes; previous evidence retained in rotation-sync',
    'previous_delivery_hashes': 'PASS',
    'main_sync_tetris_upload_sources_unchanged': True,
    'synthesis_implementation_bitstream': 'PASS',
    'hardware_platform_sources': checks['hardware_platform_sources'],
    'boot_checksums_and_elf_payloads': manifest['header_checksums_and_elf_payloads'],
    'board_execution': 'SKIPPED', 'programming_reset': 'NOT_PERFORMED',
}
(OUT/'evidence/final-validation.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
boot=manifest['files']['BOOT.bin']
readme=f'''# 画笔与贪吃蛇缩小版

- 启动镜像：[hardware/BOOT.bin](hardware/BOOT.bin)
- QSPI 起始偏移：`0x00000000`；大小：{boot['bytes']} 字节。
- SHA256：`{boot['sha256']}`
- 桥版本仍为 VXB4（`0x56584234`），寄存器和四模式协议兼容。
- 配套平台 / 应用：`vitis_workspace/vx_display_small` / `vx_brush_small`。
- 工程根目录：`C:/Users/1569/Desktop/test`。

画笔笔迹、闪烁光标、蛇头、蛇身和食物均从 2×2×2 画布像素缩为 1×1×1。
现有 PL 映射倍率为 8/3，因此显示尺寸由约 5～6 缩为约 3 个体素；
受坐标取整影响，每轴实际占 2 或 3 个体素，并非固定整数 3。
蛇的步距、转向、碰撞、得分和长度规则保留；笔迹不覆盖原有颜色。
灰度测速、960 RPM 支持、120 面/转、失锁默认 15 转/秒、方块和扫描逻辑保留。

已重新通过 Vivado MCP 综合、布局布线、生成 BIT 和导出含 BIT 的 XSA，
创建独立平台 / BSP / FSBL，经 Vitis-PS MCP 编译 ARM32 应用，Bootgen 打包。
画笔、蛇、方块和测速主机回归通过；本次 RTL 无改动，未重跑 RTL 仿真。
内部时序、资源和 DRC 报告位于 evidence；外部 I/O 约束警告需按报告理解，
不能据此声称完成 HUB75 板外时序验收。未执行烧录、硬件复位或实机验收。

## 文件与复查

- `hardware/`：BIT、XSA、FSBL、应用 ELF、BOOT、BIF、Bootgen 日志与 manifest。
- `evidence/`：构建日志、报告、源码摘要及验证结果。
- `source/`：本次修改的两个渲染源文件快照。
- 上一版 rotation-sync 交付保留；其文件摘要已核对。

```powershell
python scripts/verify_small_delivery.py
python scripts/create_small_boot.py --verify-only
```

重新构建使用 `scripts/prepare_small_vitis.py`，由安装目录的 `vitis.bat -s` 执行；
应用编译须先经 Vitis-PS 预览。打包脚本拒绝覆盖已有 BOOT。
'''
(OUT/'README.md').write_text(readme,encoding='utf-8')
print(json.dumps(result,indent=2))
