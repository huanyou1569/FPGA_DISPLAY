"""Prepare a complete contest submission without changing the working project."""
import hashlib
import json
from pathlib import Path
import shutil
import xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'submission/VX_Display_20261103'
if OUT.exists():
    raise RuntimeError(f'Refusing to overwrite an existing prepared package: {OUT}')
OUT.mkdir(parents=True)
skip_dirs={'.git','__pycache__','.pytest_cache','.metadata','.Xil','node_modules','out','build','Debug','Release','_ide','.cache','submission_assets'}
skip_suffixes={'.pyc','.pyo','.wdb','.pb','.exe','.dll','.o','.obj','.dcp','.jou','.str','.wdf','.rst'}
copied={}

def copy_file(path,relative=None):
    relative=Path(relative) if relative else path.relative_to(ROOT)
    dest=OUT/relative
    dest.parent.mkdir(parents=True,exist_ok=True)
    shutil.copyfile(path,dest)
    copied[relative.as_posix()]=hashlib.sha256(path.read_bytes()).hexdigest()

def copy_tree(relative):
    directory=ROOT/relative
    for path in directory.rglob('*'):
        if not path.is_file():continue
        rel=path.relative_to(directory)
        if any(part in skip_dirs for part in rel.parts[:-1]):continue
        if path.suffix.lower() in skip_suffixes:continue
        if path.name in {'.clangd','.compile_commands','compile_commands.json','CMakeCache.txt','.ch9141_settings.json'}:continue
        copy_file(path)

for name in ['README.md','AI_HANDOFF.md','test.xpr','.gitignore','ch9141_upper.py','ch9141_ble.py',
             'CH9141上位机说明.md','requirements_ch9141.txt','start_ch9141.cmd']:
    copy_file(ROOT/name)
for relative in ['test.srcs','software','scripts','tests','docs','migration','upper_computer_original',
                 'vitis_workspace/vx_display_small','vitis_workspace/vx_brush_small']:
    copy_tree(relative)
# The original XPR references two generated files as inputs. Retain these small
# bridge files, while leaving the large regenerated IP and simulation trees out.
project=ET.parse(ROOT/'test.xpr').getroot()
for node in project.findall('./FileSets/FileSet/File'):
    value=node.get('Path')
    if value.startswith('$PGENDIR/'):
        copy_file(ROOT/'test.gen'/value.removeprefix('$PGENDIR/'))
assets=ROOT/'scripts/submission_assets'
for path in assets.iterdir():
    if path.is_file():copy_file(path,Path('rebuild')/path.name)
settings={'part':next(n.get('Val') for n in project.findall('./Configuration/Option') if n.get('Name')=='Part'),
    'source_project':'test.xpr','simsets':{}}
for fs in project.findall('./FileSets/FileSet'):
    if fs.get('Type')=='SimulationSrcs':
        opts={n.get('Name'):n.get('Val') for n in fs.findall('./Config/Option')}
        settings['simsets'][fs.get('Name')]={'top':opts.get('TopModule'),
            'runtime':opts.get('xsim.simulate.runtime'),
            'defines':[n.get('Name') for n in fs.findall('./Config/Verilog_Define')]}
script=OUT/'rebuild/create_vivado.tcl'
text=script.read_text(encoding='utf-8')
for name,info in settings['simsets'].items():
    if name=='sim_1':continue
    lines=text.splitlines()
    for i,line in enumerate(lines):
        if line.strip().startswith(name+' '):
            tokens=line.split();tokens[2]=info['runtime'];lines[i]='    '+' '.join(tokens)
    text='\n'.join(lines)+'\n'
script.write_text(text,encoding='utf-8')
(OUT/'rebuild/original_project_settings.json').write_text(json.dumps(settings,indent=2),encoding='utf-8')
readme='''# VX-Display 比赛代码提交包（先读本文件）

本包对应2026-11-03画笔与贪吃蛇缩小版，保留完整工程源码、上位机、测试、文档、历史交付及最新配套启动镜像。
器件：PYNQ-Z2 / xc7z020clg400-1；工具：Vivado / Vitis 2026.1；PS：Cortex-A9 CPU0 Standalone。

## 目录与入口

| 目录或文件 | 内容 |
|---|---|
| README.md / CH9141上位机说明.md | 项目原理、接线、功能、操作及验证边界 |
| test.xpr / test.srcs | Vivado工程、全部RTL（含模型数据）、BD、IP配置、XDC |
| test.gen | 仅保留XPR直接引用的顶层wrapper和复位仿真桥接文件；其余可重新生成 |
| software/brush_app | 完整PS应用：画笔、蛇、3D方块、上传、测速和主循环 |
| ch9141_upper.py / ch9141_ble.py | 当前BLE上位机；start_ch9141.cmd启动 |
| vitis_workspace/vx_display_small | 最新平台、SDT、BSP源码/头文件/静态库、FSBL及平台导出快照 |
| vitis_workspace/vx_brush_small/src | 最新应用源文件、链接脚本、CMake配置快照 |
| tests / scripts | 主机测试、RTL测试台、参数生成及各版本构建/验证脚本 |
| migration | 历史交付、移植日志、基线、仿真/构建证据；最新为2026-11-03-small-voxels |
| upper_computer_original | 原上位机移植参考；当前使用根目录上位机 |
| rebuild | 不依赖原电脑路径或个人MCP配置的重建/离线校验入口 |
| PACKAGE_MANIFEST.json | 包内逐文件大小和SHA256（不包含清单自身） |

## 直接使用最新镜像

最新启动文件：`migration/2026-11-03-small-voxels/hardware/BOOT.bin`。
大小4273712字节，SHA256：`70011dff210114672cbc419277ec4b603d839181377da65fe7e8aeced14e2692`。
QSPI起始偏移0x00000000；配套BIT/XSA/FSBL/应用ELF和manifest均在同目录。
桥ID为VXB4。画笔、光标、蛇及食物约3×3×3（取整后每轴2～3体素）。
120面/转；支持960 RPM；默认15转/秒仅为失锁自由显示参考。
本包不包含自动烧录或硬件复位操作。最新尺寸版尚未实机验收。

## 校验解压完整性（无需AMD工具）

建议解压到短英文路径，例如 `D:/VX_Display`。进入包含本文件的目录运行：

```powershell
python rebuild/verify_submission.py
```

该命令核对全部文件摘要、XPR输入完整性、最新BIT/XSA一致性、ARM32 ELF、
BOOT头/分区校验和及ELF实际载荷，以及提交源码与配套应用源文件一致性。

## 打开工程与重新构建

可在Vivado 2026.1打开test.xpr并按提示重新生成BD/IP输出。源码和配置是完整输入，
不需要提交原来的仿真波形、实现缓存或安装目录中的AMD工具文件。
更稳妥的跨电脑入口是在Vivado 2026.1命令环境运行：

```powershell
vivado -mode batch -source rebuild/create_vivado.tcl
```

脚本在新建的build_submission/vivado中恢复工程、BD、顶层和六个RTL仿真集；
加 `-tclargs --build` 才会执行综合、实现、生成BIT并导出XSA。
脚本保留主要实现策略Performance_ExplorePostRoutePhysOpt；原XPR也一并保留供核对。
不覆盖已有重建输出；重复运行请使用新的解压目录。

在Vitis 2026.1命令环境运行：

```powershell
vitis -s rebuild/build_vitis.py
python rebuild/make_boot.py
```

Vitis脚本在build_submission/vitis_workspace中新建平台、Standalone BSP、FSBL和应用。
有新重建XSA时优先使用新XSA，否则使用包内最新配套XSA；地址头从所选XSA提取，
保留原编译配置和链接脚本。make_boot.py使用PATH中的Bootgen，或指定--bootgen路径。
这些新增便携脚本已完成静态检查；本次打包未重新执行AMD综合/平台重建。
包内镜像的实际综合、实现、MCP应用编译与BOOT载荷校验结果见最新migration证据。
Vitis快照中的旧机器绝对路径属于历史生成元数据，跨电脑请用rebuild入口重新生成。

上位机：Python 3.10+（含tkinter），运行`python -m pip install -r requirements_ch9141.txt`，
再运行`python ch9141_upper.py`。主机C回归需要GCC：

```powershell
python scripts/test_brush_host.py
python scripts/test_snake_host.py
python scripts/test_tetris_host.py
python scripts/test_sync_host.py
python -m unittest discover -s tests -p 'test_ch9141_*.py' -q
```

历史脚本中的个人工具路径、旧平台名和原始参考路径按当时环境理解；
较早的源码逐字节保持/画面差分检查不适用于主动缩小后的画面。
TF文件存储与播放业务尚未完成。内部时序通过不等于HUB75板外时序验收，
已有I/O延时约束缺口及DSP流水线建议保留在报告中。

## 精简原则

完整保留现有迁移交付及关键证据。排除Git数据库、个人BLE配对记录、编辑器缓存、
test.sim大型WDB、实现/综合临时目录、重复旧Vitis工作区、编译对象和主机测试可执行文件。
本包不携带Vivado/Vitis/GCC/Python安装程序，使用者需自行安装相应工具。
保留原项目和第三方源码已有版权声明；本次RAR打包工具不放入参赛代码包。
原工作目录未被删除、清理或覆盖。
'''
(OUT/'README_参赛提交.md').write_text(readme,encoding='utf-8')
excluded={'large_simulation_outputs':'test.sim','regenerable_vivado_outputs':['test.cache','test.runs','test.ip_user_files','.Xil'],
    'historical_vitis_workspaces':'only latest vx_display_small/vx_brush_small snapshots retained',
    'other':['.git','.vivado-ai','.ipcfg','.vscode','.ch9141_settings.json','root obsolete BOOT/BIT/XSA','test executables/objects']}
# Every retained original file must still have the same content, except the
# newly supplied portable script, whose simulation runtimes were copied from XPR.
for relative,digest in copied.items():
    if relative=='rebuild/create_vivado.tcl':continue
    assert hashlib.sha256((OUT/relative).read_bytes()).hexdigest()==digest,relative
files={p.relative_to(OUT).as_posix():{'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}
       for p in sorted(OUT.rglob('*')) if p.is_file()}
manifest={'project':'VX-Display','version':'2026-11-03-small-voxels','archive_format':'RAR5',
    'size_limit_bytes':200_000_000,'files':files,'excluded':excluded,
    'validation_note':'Portable scripts statically checked; no new AMD tool build performed during packaging.'}
(OUT/'PACKAGE_MANIFEST.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({'output':str(OUT),'files':len(files)+1,'uncompressed_bytes':sum(n['bytes'] for n in files.values())},indent=2))
