# 灰度测速 / 显示同步修复版

- 烧录文件：[hardware/BOOT.bin](hardware/BOOT.bin)
- QSPI 起始偏移：`0x00000000`；大小：4274160 字节。
- SHA256：`adcf81b9aa95a75c2bda9b772167c9ffbd6143031d12b6f0b9dce8142cf3ea2c`
- 版本：VXB4（`0x56584234`），15 转/秒目标、120 面/转，四种显示模式和原按键协议保留。
- 重新烧录、上电后使用根目录 `start_ch9141.cmd`；正常旋转时检查 RPM 和“同步反馈”。`TRACK` 表示实际扫描间隔已跟随测量转速。
- [完整修复与验证日志](../../docs/rotation-sync.md)
- [启动镜像分区与校验记录](hardware/manifest.json)、[硬件/平台/源码核对](evidence/delivery-check.json)。

工程根目录：`C:/Users/1569/Desktop/test`。硬件平台和应用分别为 `vitis_workspace/vx_display_rotation`、`vitis_workspace/vx_brush_rotation`。

**验证范围：** 主机与 RTL 仿真、综合、布局布线、ARM 编译、Bootgen 镜像核对均完成；尚未烧录或进行本次实机测试。原蛇、方块 BOOT 保留在原日期目录。

在上述根目录中，复查已生成交付物：

```powershell
python scripts/verify_rotation_delivery.py
python scripts/create_rotation_boot.py --verify-only
```

完整构建需要先通过 Vivado MCP 重建、导出同名新 XSA，再执行 `scripts/prepare_rotation_vitis.py`，由 Vitis-PS 预览并获授权编译 `vx_brush_rotation`，最后运行打包脚本。打包脚本拒绝无意覆盖已有 BOOT。
