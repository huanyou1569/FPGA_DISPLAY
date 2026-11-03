# 2026-11-01 PS时钟修复与启动验证

**后续板端结果：本版本不再作为最终启动镜像。** PS时钟修正已实测生效：Flash抽样一致，DDR两次代码读回均正确，USB捕获到DDR自检PASS。但应用停在读取画布AXI ID。进一步发现辅助复位极性配置错误，使AXI画布接口常驻复位。下一修正交付在 `../2026-11-01-resetfix/`；此目录保留时钟修复阶段证据。

目标：`C:/Users/1569/Desktop/test`，PYNQ-Z2 / XC7Z020。用户报告画笔模式空白、USB无接收。板端只读检查及冷启动对比确认Flash代码抽样正确，DDR代码读回不稳定。详情见 `../2026-11-01-debug/无串口输出排查.md`。

## 修正

原工程按33.333333MHz计算PS时钟，但板卡PS_CLK实际50MHz。现修正为50MHz、CPU650MHz、DDR525MHz、UART目标100MHz；PL仍用原独立125MHz。采用TUL板文件的DDR板级延迟，保持三项训练开启；针对2026.1负DQS初值警告采用0训练初值，并使用当前器件模型派生时序。配置审计19/19通过。

未改变屏幕扫描、投影或画笔协议。增加USB启动分阶段提示、DDR 4KiB自检和周期状态，避免只有一次启动提示不便排查。DDR自检只是小范围读写检查，不能替代完整DDR压力测试。

为保留旧版本证据，创建独立 `vx_display_clockfix` 平台、`vx_brush_clockfix` 应用；旧平台和旧BOOT.bin保留，但旧BOOT.bin已标记停用。脚本：`fix_pynq_ps_clock.tcl`、`prepare_clockfix_vitis.py`、`create_clockfix_boot.py`、`verify_clockfix_delivery.py`。

## 构建和板端状态

新硬件综合、实现、比特流与XSA导出均已完成，无错误、无严重警告。最终内部时序WNS+0.009ns、TNS0、WHS+0.037ns、THS0；已知外部IO延迟约束缺项与原投影DSP/BUFG优化建议未在本次修改。

新XSA SHA256：`d4ad5f1498d5d63bb01d88d26138efb4d62a5808d4182227ae82adf0285c1a7e`。本次导出仍为xc7z020clg400-1，AXI画布地址仍为0x40000000..0x40000FFF。

本次尚未执行修正镜像的JTAG下载、Flash编程或硬件复位；之前的冷启动由用户执行。不得将旧镜像的板端读回检查计为修正镜像已经上板通过。

平台、BSP及FSBL构建成功。检查生成头文件：CPU650000000Hz，UART0/1参考时钟100000000Hz，USB调试标准输出地址0xe0000000。Vitis-PS先预览再执行修正版画笔应用编译，工具返回status=0；ELF32、小端、ARM machine40验证通过。构建沿用用户此前明确授权的画笔编译范围，共享构建开关临时启用后已恢复false。应用编译没有警告；FSBL生成代码沿用其signedness警告。

`hardware/BOOT.bin` 已打包完成，4256304字节。包含本次新FSBL、新BIT和vx_brush_clockfix.elf。应用入口0x00100000；text74063、data1888、bss80752字节。BOOT.bin SHA256：`1f539a536b28d5f3576b330148346a7d827ed093b6a5128347861e74d28d0e18`。

`verify_clockfix_delivery.py` 已核对实际XSA参数、BSP时钟/地址、导入硬件及六份源码的一致性，并确认ELF架构。`create_clockfix_boot.py` 已检查新FSBL的ps7_init.c与XSA逐字节一致、BIT与XSA内嵌BIT一致、全部启动/分区头校验和，以及FSBL/应用每个文件数据段与最终BOOT.bin负载逐字节一致。结果均PASS，证据为evidence/delivery-check.json和hardware/manifest.json。

## 用户烧录与验收

烧录文件必须选择本目录 `hardware/BOOT.bin`，不要选 `../2026-11-01-boot/BOOT.bin`。板载单片16MB QSPI，偏移0x00000000；如果工具要求FSBL，选择本目录 `hardware/fsbl.elf`。擦除、编程、校验后断电，以QSPI模式重新上电。

USB串口仍为115200 8N1、无流控。正常预期依次输出：

```text
VX brush: UART0 ready; enabling caches
VX brush: UART1 115200 8N1; BTN2 demo/brush
DDR 4 KiB probe PASS
Reading brush AXI ID...
Brush AXI ID=0x56584231
UART1 ready; canvas uploader running
VX mode=DEMO uploaded=... state=... row=... status=...
```

随后每秒输出一行状态。按BTN2后应切到BRUSH，LED3亮，空画布应有小白色闪烁光标。若停在某行或出现FAIL，保留完整串口日志。这里是验收预期，尚未在修正镜像上实测。
