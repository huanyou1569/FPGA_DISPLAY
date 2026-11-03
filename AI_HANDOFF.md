# 给下一个 AI 的工程交接

更新日期：2026-11-03。工程根目录：`C:/Users/1569/Desktop/test`。先读 [README.md](README.md) 获取功能和接线概览；本文件记录当前约束、源码入口与恢复工作所需信息。

## 本轮最新交付：蛇与画笔缩小（优先于下文旧版记录）

- 用户随后授权缩小贪吃蛇与画笔，并重新综合、生成 BIT 和制作 BOOT；已完成，未烧录或复位。
- 最新目录：`migration/2026-11-03-small-voxels/`，参见其 README、hardware/manifest.json 和 evidence/final-validation.json。
- 最新 BOOT：4273712 字节，SHA256 `70011dff210114672cbc419277ec4b603d839181377da65fe7e8aeced14e2692`；QSPI 偏移0。
- 平台 / 应用：`vitis_workspace/vx_display_small` / `vx_brush_small`；硬件 `vx_display_small.bit/.xsa`，桥 ID 仍为 VXB4。
- `vx_snake.c` 的蛇头/蛇身/食物以及 `vx_brush.c` 的笔迹/光标改为单画布体素。PL 8/3 倍映射后，每轴为2～3体素，约3×3×3。移动、碰撞和计分规则未改。
- 主机画笔/蛇/方块/测速回归通过。PL源码哈希与 rotation-sync 一致，本轮重新综合、实现并生成BIT；WNS +0.070593ns、WHS +0.012110ns，既有25个外部I/O延时约束缺口和6个DSP流水线建议保留。未重跑RTL仿真，未实机验收。
- 新XSA内BIT与重建BIT一致，HWH与上一版逐字节一致；新平台/BSP/FSBL和MCP应用编译成功，BOOT头/分区/ELF载荷核对通过。全局 build_enabled 已恢复false。
- 原Vivado会话载入实现结果时卡在恢复约束，未结束该进程；新建只读会话完成导出和报告。只读导出警告已用HWH一致性及新BIT载荷一致性核对，不升级BD/IP。
- 复查使用 `scripts/verify_small_delivery.py`、`scripts/create_small_boot.py --verify-only`；准备脚本 `scripts/prepare_small_vitis.py`。保留 rotation-sync 及更早交付。下文的“本轮仅文档”、旧镜像路径、游戏源码逐字节不变与3000步完整画面差分结论属于缩小前基线，不能用于新尺寸画面的声明。

## 先遵守用户当前要求

1. **实际转速为960 RPM，当前代码可以支持，用户要求可以就不要动。** 本轮只增加根目录项目和交接说明，未改 HDL、C/Python运行代码、XPR/BD、BIT/XSA/ELF/BOOT，也未重建或操作硬件。
2. 不要仅因 `VX_TARGET_RPS=15` 而修改为16。15是默认参考/失锁自由显示值；有效灰度周期会覆盖扫描时序。每转120面保持不变。
3. 用户此前明确贪吃蛇尚未烧录验收，希望后续改动尽量不影响它。画笔已获用户确认正常，蛇和方块不得将软件测试通过写成实机验收通过。
4. 最新灰度修复镜像已完成构建，尚无用户确认其上板效果的记录；用户只确认过灰度调零面正常，并报告实际960 RPM。不要假定板上已经是最新BOOT。
5. 后续改动以用户新任务为准；保留现有源码改动和历史交付，不要用 Git reset/clean、删除生成目录等方式整理交接。

## 960 RPM 的核对结果

按当前源码：

```text
clock_hz = 125000000
960 RPM = 16 rps
period_clocks = 60 * clock_hz / 960 = 7812500
revolution_period = 62.5 ms
line_clocks = floor(7812500 / (120*32)) = 2034
hold_max = 2034 - 840 = 1194       // 在80..6000范围内
actual_slice_clocks = 32 * 2034 = 65088
actual_slice_us = 520.704
reported RPM = 960; DLY/SLICE_US = 520; SCAN_HZ = 1920
```

62.5 ms 大于36 ms拒绝窗口，小于500 ms超时；每120面的分频取整误差1940时钟，小于3840时钟的 `TRACK` 判定阈值。因此无需为960改程序。以上是源码公式核对，未新增960专用RTL仿真或实机测试。

## 当前硬件与镜像合同

| 项目 | 当前值 |
|---|---|
| 器件 / 工程 / BD | `xc7z020clg400-1` / `test.xpr` / `design_1` |
| 工程顶层 / 模块引用 | `design_1_wrapper` / `test_panel_0`、`brush_axi_0` |
| PS | `processing_system7_0`，Cortex-A9 CPU0，Standalone/SDT，非FreeRTOS |
| 时钟 | 外部PL125MHz；PS输入50MHz；CPU650MHz；DDR525MHz |
| AXI基址 / 范围 | `0x40000000..0x40000fff`，以当前XSA与BSP为依据 |
| 桥ID | **0x56584234 / VXB4**，硬件与应用需匹配 |
| 最新交付 | `migration/2026-11-03-rotation-sync/hardware/` |
| 平台 / 应用 | `vitis_workspace/vx_display_rotation` / `vx_brush_rotation` |
| 烧录镜像 | 上述目录的 `BOOT.bin`，4274160字节，QSPI偏移0 |

BOOT SHA256：`adcf81b9aa95a75c2bda9b772167c9ffbd6143031d12b6f0b9dce8142cf3ea2c`。

XSA SHA256：`7664a601c25fd5940e293d54831c86732a33208c0fea52877020f43129adb967`。

历史回退镜像保持在 `migration/2026-11-01-snake/hardware/`（VXB2、三模式）及 `migration/2026-11-02-tetris/hardware/`（VXB3、四模式）。根目录另有旧产物，不能默认使用根目录BOOT。完整校验值见各自 `manifest.json`。

## 关键接口，改动前先核对

模式数值固定为 `0=DEMO, 1=BRUSH, 2=SNAKE, 3=TETRIS`。BTN2循环四态，BTN3恢复PL原显示状态。`STATUS` bit7只表示蛇，判断四种模式须读 `0x20` 或文本 `MODE`。

| AXI偏移 | 含义 |
|---|---|
| `0x00` / `0x04` | 桥ID / 状态 |
| `0x08` | 上传行号 |
| `0x10/0x14/0x18` | 当前行R/G/B的32位位图 |
| `0x1c` | `BEGIN=1`、`WRITE_ROW=2`、`COMMIT=4` |
| `0x20` / `0x24` | 模式 / 圈事件计数 |
| `0x28` | 实测一转周期，同时锁存以下诊断快照 |
| `0x2c` | flags：bit0 DO、bit1滤波电平、bit2锁定、bit3周期有效、bit4扫描范围可支持、bit5限幅 |
| `0x30/0x34/0x38` | 滤波上升沿数 / 接受脉冲数 / 拒绝脉冲数 |
| `0x3c` | 实际相邻 `frame_done` 间隔时钟数 |

PS应先读 `0x28` 再读诊断字，避免跨圈不一致。`0x24` 计数包含自由显示合成事件；这影响原动画和蛇步进，不能无意改成只数实测脉冲。

画布双缓冲：一次快照上传768个 `(z,y)` 行，每行32像素，R/G/B分别打包。完整上传后才能COMMIT，PL在填充器安全时刻换源；银行带模式标签，旧模式的在途提交可以完成，但不应成为新模式的填充数据。保持 `canvas_mode_ready`、`canvas_swap_safe`、提交确认和六周期模型读取延迟的合同，避免撕裂或串模式。

BLE保留原行协议：可选冒号、以换行结束；上位机20字节分包、25ms间隔、串行写入及行组包。CH9141 `FFF1 Notify / FFF2 Write`，板端UART1为115200 8N1。USB UART0仅作日志，不将启动横幅当成命令。引脚与模式键盘操作见README及 [CH9141说明](CH9141上位机说明.md)。

## 重要文件与已知历史问题

- `test.srcs/sources_1/new/test.v` 的模块名是 `test_panel`；文件顶部有部分历史注释，真实模式/开关常量以当前赋值和状态机为准。
- 测速链为 `index_sync.v → rev_timing.v → panel_scan.v`；诊断经 `test.v → brush_axi.v → vx_sync.c → main.c` 回传。旧600..1200RPM范围已移除，首圈只建基准，500ms失锁清测量并恢复默认扫描；整面32行共用同一保持值。
- `panel_scan` 的 `col_ofs=3` 对应129个移位脉冲和每行840时钟固定开销，是现有能显示的屏幕驱动条件；不要随意换成128脉冲或不同开销。屏幕型号用户不清楚，涉及板外时序先参考现有RTL并与PL队友对接。
- `proj_engine.v` 曾修复六周期流水线与投影完整性，当前保持。不要为新游戏重写投影和HUB75扫描。
- PS输入晶振曾错误配置为33.333MHz，已改为 **50MHz** 并解决DDR启动问题；禁止从其他开发板模板覆盖PS配置。
- AXI复位曾因未用辅助复位极性错误造成CPU访问挂住。当前 `C_EXT_RESET_HIGH=0`、`C_AUX_RESET_HIGH=1`，辅助/调试复位输入接0，`dcm_locked`接1；实际复位IP仿真已通过。
- `vx_brush.c/.h`、`vx_snake.c/.h`、`vx_tetris.c/.h` 在最近测速修复中与上一版Vitis应用逐字节相同。游戏模块源码和旧镜像校验依据在最新 `evidence/preserved-files.json`。
- 画笔、蛇和方块的会话状态在PS RAM中；最高分不等于已完成TF持久化。原上位机参考副本带TF界面，也不能据此认为FPGA固件已经实现TF命令。

## 验证入口与证据边界

以下为已有回归入口，按后续实际改动选择运行；本次文档交接不重跑这些构建/仿真：

```powershell
cd C:\Users\1569\Desktop\test
python scripts/test_brush_host.py
python scripts/test_snake_host.py
python scripts/test_tetris_host.py
python scripts/test_sync_host.py
python -m unittest discover -s tests -p 'test_ch9141_*.py' -q
python scripts/check_snake_preservation.py
```

主机C回归使用GCC；Tk测试只使用模拟事件，不会主动连接实物BLE。`check_snake_preservation.py`依赖 `migration/2026-11-02-tetris/baseline/` 和旧交付，比较原三模式3000步轨迹。基线/产物被Git忽略，缺失时应先确认交接文件是否完整。

Vivado现有仿真集：`sim_rotation_feedback`（直接驱动原始输入，连续变速）、`sim_rotation_timing`（角度/分频/边界）、`sim_brush_axi`、`sim_brush_reset_chain`（实际复位IP）、`sim_brush_panel`、`sim_projection`。使用Vivado MCP，切换当前simset后再启动；读取完整日志并要求 `TEST_PASS`，不能只凭工具退出码判成功。

最新构建证据位于 `migration/2026-11-03-rotation-sync/evidence/`：`final-validation.json`、`delivery-check.json`、各主机/仿真日志、时序/资源/DRC报告。内部WNS +0.071ns、WHS +0.012ns；25项既有TIMING-18外部I/O延时警告、6项DSP流水线建议保留。没有完成最新镜像实机验收，也未完成HUB75板外时序签核。

## 后续确需构建时的流程

本节为交接流程，不代表本轮要求重新构建。用户提供的AGENTS规则及相关技能优先适用；当前任务只是说明文档。

1. 根据新任务读取相应技能。全局工具配置在 `C:/Users/1569/ZynqCodexToolkit/config/toolchain.json`，当前 `build_enabled=false`；复用已安装Vivado/Vitis 2026.1和全局MCP。
2. 每次指定绝对工程根目录；Vivado先核对会话、工程目录、器件和顶层。重新连接时发现会话，**不要复用聊天历史里的会话ID或PID**。
3. 先确认当前XSA和真实BSP。地址从XSA生成，SDT的 `XUartPs_LookupConfig` 使用基地址。不要套用A53/R5、UltraScale+或Versal API。
4. 在授权范围内完成HDL/BD改动及相关仿真，再综合/实现/生成BIT，导出匹配XSA。保留旧交付；新功能宜建独立日期目录、平台与应用。
5. 最新平台脚本为 `scripts/prepare_rotation_vitis.py`，由安装目录的 `vitis.bat -s` 执行；它会生成地址头、构建平台/BSP/FSBL并导入应用源码。现有脚本固定了输出路径，改版本时先审查目标和覆盖行为，不要直接覆盖已交付版本。
6. 应用编译经 Vitis-PS `build_ps_application`，先 `execute=false` 预览依赖，再按授权编译。若临时打开全局编译开关，成功或失败后都恢复原值。平台服务刚退出时可能尚未释放工作区；先等服务释放重试，不要删除锁文件或结束用户IDE。
7. 核对新鲜ELF为ELF32 ARM（machine40），源码导入与XSA/BIT一致。现有 `verify_rotation_delivery.py` 和 `create_rotation_boot.py --verify-only` 可复查当前交付；新版本需要匹配的新检查脚本。Bootgen顺序FSBL→BIT→应用，镜像检查包括头校验和和ELF加载段载荷。
8. 修改既有工程、重建BSP/平台、删除文件、JTAG/Flash烧录、硬件复位遵循用户明确授权范围；尤其不能用过去一次复位/烧录许可替代本轮相应授权。不要为了“验证”自动下载、暂停CPU或复位板卡。

参考原工程与板卡资料路径、最新镜像入口及接线见README。后续未完成的原始目标是TF数据存储/文件播放；开始前应先接用户新任务，避免自行扩展范围或改动当前960RPM显示链。
