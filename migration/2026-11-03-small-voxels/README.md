# 画笔与贪吃蛇缩小版

- 启动镜像：[hardware/BOOT.bin](hardware/BOOT.bin)
- QSPI 起始偏移：`0x00000000`；大小：4273712 字节。
- SHA256：`70011dff210114672cbc419277ec4b603d839181377da65fe7e8aeced14e2692`
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
