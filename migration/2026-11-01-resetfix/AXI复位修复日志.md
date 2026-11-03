# 2026-11-01 画笔AXI复位修复

工程根目录 `C:/Users/1569/Desktop/test`。用户已烧录clockfix镜像，但画笔仍空白。此轮直接读取USB调试串口并检查运行中的CPU。

## 实机证据

- 实际板卡USB串口为COM16，FTDI VID0403/PID6010/SER1234；COM3/COM4为系统蓝牙串口。
- 新Flash的启动头和应用首4096字节与clockfix BOOT.bin完全一致。DDR中应用首4096字节连续读取两次也均一致，先前PS时钟错误导致的数据异常在此样本中已消失。
- 整板断电会使USB串口设备同时断开，首次开机捕获因设备消失而中止。用户随后明确授权**一次**JTAG系统复位并捕获日志，已执行 `rst -system -start`；未擦写Flash、下载ELF或主动暂停CPU。
- 保持USB打开后收到136字节真实启动输出，内容如下（已将CRCRLF整理成普通换行）：

```text
VX brush: UART0 ready; enabling caches
VX brush: UART1 115200 8N1; BTN2 demo/brush
DDR 4 KiB probe PASS
Reading brush AXI ID...
```

- 运行中PC多次采样为0x0010052c，对应reg_read/Xil_In32调用位置，与停在画布AXI读操作相符。原始串口和JTAG证据位于 `../2026-11-01-debug/`。

## 根因和修正

实际生成的 `design_1_brush_reset_0` 中 `C_EXT_RESET_HIGH=0`、`C_AUX_RESET_HIGH=0`。外部复位接PS FCLK_RESET0_N，低有效正确；辅助复位接常量0，却也配置为低有效，从而一直请求复位，画布AXI和互连无法正常应答。

已显式设置 **C_AUX_RESET_HIGH=1**，保持辅助输入常量0；外部复位继续低有效。C_EXT_RESET_HIGH在已连接PS复位接口后是派生只读参数，修复脚本只校验它、不再写它。最终21/21配置审计通过。同步修正 `scripts/connect_brush_bd.tcl`，避免重建时复发；独立修复脚本为 `scripts/fix_brush_reset.tcl`。

## 回归验证

扩展 `tests/rtl/tb_brush_axi.sv`，定义VX_TEST_REAL_RESET时直接实例化本工程**实际生成的复位IP wrapper**，不使用手写替代模型。sim_brush_reset_chain仿真集使用该定义、实际VHDL wrapper及AMD proc_sys_reset模型。

- 旧配置在2560ns明确失败：Peripheral reset never released。
- 修正后于328392ns完成TEST_PASS：互连/外设复位释放、AXI分离AW/W和背压、WSTRB、非法访问、整帧上传、活动银行不变、完整提交、像素流水，以及再次复位后的恢复均通过。
- 证据为evidence/reset-chain-before.log、reset-chain-after.log、actual-reset-wrapper-after.vhd和reset-config-confirmed.tcldict。

## 交付进度

`vx_display_resetfix` 硬件已重新综合、实现并生成BIT/XSA。实现日志为0个错误、0个严重警告；已约束路径WNS=+0.009ns、WHS=+0.037ns、TNS/THS=0。外部接口既有未完整约束情况及BUFG连接警告仍保留，内部时序通过不能代替屏幕外部时序验证。报告位于 `evidence/timing-summary.rpt`、`drc.rpt`、`utilization.rpt`。

匹配的 `vx_display_resetfix` 平台/BSP/FSBL及 `vx_brush_resetfix` 应用均已构建成功。应用经Vitis-PS预览后按用户既有授权执行，返回status=0；首次因平台服务尚未释放工作区而未执行，等待服务退出后重试成功，没有删除锁或终止其他工作区。全局 `build_enabled` 已恢复false。PS_CLK50MHz、CPU650MHz、DDR525MHz、UART0/1配置及原屏幕扫描路径保持时钟修复版本的设置。

- `hardware/BOOT.bin`：4256304字节，SHA256 `f3037ae82a0d931b9b4e2a8c1baf981754126a5fb832f005fd0c201221836719`。
- `hardware/vx_display_resetfix.xsa`：包含本次BIT，SHA256 `eddacdd5b2107d56905d3c467039a131739695a49174b2c2dbd6b6b4a0925ebf`。
- 同目录包含 `fsbl.elf`、`vx_display_resetfix.bit`、`vx_brush_resetfix.elf`、`boot.bif`、`manifest.json`。
- `scripts/verify_resetfix_delivery.py`核对实际XSA复位极性和接线、PS时钟、AXI映射、BSP宏、导入源码及ARM32 ELF，结果PASS；证据为 `evidence/delivery-check.json`。
- `scripts/create_resetfix_boot.py`使用Bootgen 2026.1打包FSBL→BIT→应用，校验启动头、全部分区头校验和及ELF加载内容，结果PASS。大小小于板载16MiB QSPI容量。

## 烧录与实机验收

将上述新 `hardware/BOOT.bin` 烧到QSPI偏移 **0x00000000**。烧录工具如要求FSBL，选择同目录 `hardware/fsbl.elf`。不要继续使用boot或clockfix目录下的旧BOOT.bin。烧录后按QSPI启动设置重新上电。

COM16配置115200、8N1、无流控、ASCII接收。新的验收点应为DDR PASS后继续出现 `Brush AXI ID=0x56584231`、`UART1 ready; canvas uploader running` 和周期 `VX mode=... uploaded=...`。按BTN2后LED3点亮，模式应变为BRUSH并显示闪烁画笔光标；蓝牙操作后观察画布更新。上述为待验证预期，并非已取得的板上结果。

USB UART0仅输出日志，向它发送 `VX brush: ...` 不会触发回复；该文字是启动横幅。画笔指令由蓝牙UART1输入，可使用原上位机B进入、P落笔、W/S/A/D移动，或发送带换行的BRUSH、STATUS行命令。

当前尚未把resetfix镜像下载或烧入板卡。用户本轮的一次复位授权已经执行，不代表后续下载、烧录或再次复位授权。
