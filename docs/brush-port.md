# 画笔移植与使用

本次工程：`C:/Users/1569/Desktop/test`，PYNQ-Z2 / XC7Z020，Vivado/Vitis 2026.1。参考工程只读：`C:/Users/1569/Desktop/vx-display/VX-Display-main`。

**2026-11-03更新：修复灰度测速范围、失锁扫描时序和蓝牙回传，新增实际每面间隔与同步状态。** 最新独立烧录文件为 `migration/2026-11-03-rotation-sync/hardware/BOOT.bin`，桥 ID 为 VXB4；目标仍为15转/秒、120面/转，BTN2仍在四种模式间循环。参见 [灰度测速与显示同步修复日志](rotation-sync.md)。下方早期移植记录保留用于追溯。

**2026-11-02更新：独立新增3D俄罗斯方块，保持15转/秒、120面/转。** 新版目录为 `migration/2026-11-02-tetris/hardware/`，平台/应用为 `vx_display_tetris`、`vx_brush_tetris`，状态以该目录上级《3D俄罗斯方块开发日志》为准。BTN2循环原显示→画笔→贪吃蛇→方块，AXI ID为VXB3；新硬件和应用配套。蛇游戏模块及旧镜像保持，原三模式3000步差分轨迹一致；蛇和方块均尚待用户实机验证。

## 板卡与上位机

- 上电默认原显示模式。BTN2每次按下循环原显示/画笔/贪吃蛇，带独立消抖；LED3亮表示PS画布模式，LED2灭为画笔、亮为蛇（演示模式下LED2仍表示原内容）。
- 原显示模式保留 BTN0/BTN1 切换内容；BTN3 恢复原显示默认状态。切换模式保留 PS 内的画布。
- 蓝牙 UART1：115200、8N1，PMODB pin9 / V12 为板端 TX，接模块 RX；pin10 / W13 为板端 RX，接模块 TX；共地、3.3V 电平。UART0 为 USB 调试串口。
- 运行参考工程 `vx-display/upper_computer/main.py`，扫描并选择 BLE 设备后连接。该程序使用 bleak 直接访问 FFF1 Notify / FFF2 Write，不需要选择 COM 口。CH9141 若要求配对码，先在 Windows 蓝牙设置中按模块要求输入 `0000` 完成配对，再回上位机连接；原界面本身没有配对码输入功能。B 进入画笔，C 清空，W/S/A/D 移动，Shift+W/S 升降，P 落笔/抬笔，K 换色，方括号调整视角，E 返回演示。仅通过板载 BTN2 进入画笔时，也兼容上位机 D 键发出的 `J+`。
- 可经蓝牙透传至UART1发送行命令测试：依次发送 `BRUSH\n`、`JP\n`、`JR\n`、`STATUS\n`。所有命令必须以换行结束。也接受 `:BRUSH`、`:CLEAR` 等可选冒号写法。板卡USB调试串口对应UART0，仅输出日志和周期状态；`VX brush: ...` 是启动日志内容，不是待发送的命令。

| 原指令 | 行为 |
| --- | --- |
| BRUSH / CLEAR | 进入画笔 / 清空画布 |
| JU / JD / JL / JR | 按当前视角移动 |
| JB1 / JB0 | 按住 / 松开升降修饰键 |
| JP / JK | 切换落笔 / 循环六色 |
| JH数字 | 设置 0..99 的环向视角（取模） |
| J+ / J- | 画笔模式兼容右移 / 左移 |
| JE / DEMO | 返回原显示 |
| STATUS | 原上位机可解析的状态行，附加画笔字段 |

保留原工程32×32×24画布、2×2×2画笔、六色、视角相关移动、不覆盖已有颜色及闪烁光标。当前显示通道为RGB111，不能复现原WS2812半亮度。新增SNAKE/JG进入/重开和JL/JR/JU/JD/JE蛇控制；TF文件、亮度等指令尚未移植。SD0和xilffs仍保留。

## PS / PL 约定

`software/brush_app` 是应用源码的维护位置。PS 轮询 UART1，处理分包、粘包和坏行，使用有界收发预算；每次循环最多上传一行，避免一次上传长时间阻塞蓝牙。落笔后的每次移动均保留到画布；上传使用不可变快照，合并尚未显示的更新。

PL 新增 `brush_axi.v`，经 PS M_AXI_GP0、AXI interconnect 接入。PS 与 PL 使用 AXI 寄存器传输，不使用共享 DDR / DMA。画布双缓冲使用 6 个 BRAM36 等效资源，仅在 `vol_fill` 空闲时换银行，填充期间锁定数据源。原投影、帧缓存和 HUB75 扫描模块保持原实现。

实际 XSA 分配地址为 **0x40000000..0x40000FFF**。`scripts/prepare_brush_vitis.py` 从 XSA 的 HWH 生成 `vx_hardware.h`，同时记录 XSA SHA256；更换硬件必须重新生成。

| 偏移 | 用途 |
| --- | --- |
| 0x00 | 只读 ID：0x56584233（tetris四模式VXB3） |
| 0x04 | 状态：bit0 任意PS画布模式、bit1 等待提交、bit2 已提交画布、bit3 活动银行、bit4 已上传768行、bit5 锁定、bit6 周期有效、bit7 贪吃蛇 |
| 0x08 | 当前已上传行数 |
| 0x10 / 0x14 / 0x18 | 一行 R/G/B 位图，bit x 对应 x 坐标 |
| 0x1C | 命令：1 BEGIN、2 WRITE_ROW、4 COMMIT |
| 0x20 | 模式读写：0 原显示，1 画笔，2 贪吃蛇，3 方块；低字节4..255写入SLVERR |
| 0x24 / 0x28 | 转数 / 一圈的125MHz时钟计数 |

顺序为 BEGIN → 按 `z*32+y` 上传768行 → COMMIT → 等待 pending 清零。未满帧禁止提交，提交只在安全窗口发生。超时进入上传故障状态并报告，避免继续改写活动画布。BTN2 同周期与软件模式请求冲突时，以物理按键优先。

## 工程、构建与验证

- Vivado 主工程：`test.xpr`；源代码和 BD 已直接更新。新硬件：`migration/2026-10-31-brush/hardware/vx_display_brush.bit`、同名 `.xsa`。
- 新平台：`vitis_workspace/vx_display_brush`；新应用：`vitis_workspace/vx_brush`；处理器 `ps7_cortexa9_0`，Standalone。保留此前 `vx_display_ps` 平台。应用已授权编译通过，ELF 位于 `vitis_workspace/vx_brush/build/vx_brush.elf`，并另存到本次 hardware 目录。
- `scripts/prepare_brush_vitis.py` 创建新平台/BSP，导入应用源码；应用编译须先通过 Vitis-PS 的预览与授权开关。它不会编译应用或下载硬件。重复使用时须先确认应用同名目录没有手工修改。
- `python scripts/test_brush_host.py`：主机逻辑回归。XSim 测试为 `tests/rtl/tb_brush_axi.sv` 和 `tb_brush_panel.sv`，分别验证 AXI/换银行与真实显示链路集成。
- `.gitignore` 忽略生成目录、工作区、日志和构建产物；保留手写代码、BD/XPR/XDC、脚本和文档，不笼统忽略 XML/BIN。已经被 Git 跟踪的生成文件仍会显示变更，此次未修改索引或删除历史文件。

实际验证结果与当前限制见 `migration/2026-10-31-brush/画笔移植日志.md`。未执行上板下载、复位或蓝牙实物联调。
