"""Create a fresh source-only publishing tree, preserving the working repository."""
import hashlib
import json
from pathlib import Path
import shutil

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'github_publish/FPGA_DISPLAY'
if OUT.exists():
    raise RuntimeError(f'Refusing to replace an existing publishing tree: {OUT}')
OUT.mkdir(parents=True)
skip_dirs={'__pycache__','out','baseline','evidence','ipshared','.git','.metadata','build','Debug','Release'}
skip_extensions={'.bit','.xsa','.elf','.o','.obj','.a','.exe','.dll','.so','.dcp','.pdi','.wdb','.pb','.rst',
    '.rpt','.log','.jou','.str','.wdf','.rpx','.vdi','.vds','.bda','.bxml','.bin','.mcs','.prm','.ltx',
    '.pyc','.pyo','.rar','.zip','.7z','.tar','.gz','.tmp','.bak'}
original_files={}

def copy_file(path,relative=None):
    relative=Path(relative) if relative else path.relative_to(ROOT)
    dest=OUT/relative
    dest.parent.mkdir(parents=True,exist_ok=True)
    shutil.copyfile(path,dest)
    original_files[relative.as_posix()]=hashlib.sha256(path.read_bytes()).hexdigest()

for name in ['README.md','AI_HANDOFF.md','CH9141上位机说明.md','.gitignore','test.xpr','output.bif',
             'ch9141_upper.py','ch9141_ble.py','requirements_ch9141.txt','start_ch9141.cmd']:
    copy_file(ROOT/name)
for directory in ['test.srcs','software','scripts','tests','docs','migration','upper_computer_original','.vscode']:
    for path in (ROOT/directory).rglob('*'):
        if not path.is_file():continue
        parts=path.relative_to(ROOT/directory).parts
        if any(p in skip_dirs for p in parts[:-1]) or path.suffix.lower() in skip_extensions:continue
        if path.name in {'.env','.ch9141_settings.json','compile_commands.json'}:continue
        copy_file(path)
# Keep the portable project entry points and two small application build inputs.
for name in ['create_vivado.tcl','build_vitis.py','make_boot.py']:
    copy_file(ROOT/'scripts/submission_assets'/name,Path('rebuild')/name)
for name in ['UserConfig.cmake','lscript.ld']:
    copy_file(ROOT/'vitis_workspace/vx_brush_small/src'/name,Path('rebuild/application_config')/name)
script=OUT/'rebuild/build_vitis.py'
text=script.read_text(encoding='utf-8').replace(
    "snapshot = ROOT/'vitis_workspace/vx_brush_small/src'", "snapshot = ROOT/'rebuild/application_config'")
script.write_text(text,encoding='utf-8')
ignore=(OUT/'.gitignore').read_text(encoding='utf-8')
ignore+='''
# Source-only GitHub publication: local contest bundles and tool downloads.
/submission/
/submission_tools/
/github_publish/
/build_submission/
*.rar
*.zip
*.7z
*.tar
*.gz
/migration/**/*.bin
'''
(OUT/'.gitignore').write_text(ignore,encoding='utf-8')
readme=(OUT/'README.md').read_text(encoding='utf-8')
title,body=readme.split('\n',1)
readme='# FPGA_DISPLAY：PYNQ-Z2 FPGA 体积显示器\n\n'+(
    '**GitHub 源码仓库说明：** 本仓库保留项目源码、工程配置、上位机、测试、构建脚本与开发文档。'
    '按上传要求，不包含比赛RAR/解压副本、Vivado/Vitis缓存或BIT/XSA/ELF/BOOT等编译产物。'
    '下文镜像路径和校验值是本地交付记录；从GitHub克隆后请按[源码重建说明](docs/source-checkout.md)生成产物。\n')+body
(OUT/'README.md').write_text(readme,encoding='utf-8')
doc='''# 源码仓库与重建

本仓库为2026-11-03画笔/贪吃蛇缩小版的源码快照。原本地Git仓库和历史不做修改，
此仓库以干净初始提交保存源文件，避免将已跟踪的历史编译输出一并推送。

## 内容

- `test.srcs/`：完整RTL、BD、IP配置及XDC，模型常量内嵌在RTL中。
- `software/brush_app/`：PS应用源码和必要头文件。
- `ch9141_upper.py` / `ch9141_ble.py`：当前上位机。
- `tests/` / `scripts/`：测试台、回归和构建脚本。
- `migration/` / `docs/`：历史开发说明、BD导出Tcl、源文件快照及镜像manifest记录。
- `rebuild/`：不依赖原电脑工具配置的重建入口；`application_config/`包含链接脚本与编译配置。

不包含RAR包/解压副本、压缩工具、Git旧历史、生成缓存、Vitis生成工作区、波形、
编译对象、BIT/XSA/ELF/BOOT、历史baseline/evidence目录。必要的派生地址头作为编译输入保留，
重新构建时会根据实际XSA重新生成。

## 重新生成工程与硬件

使用Vivado 2026.1，器件为xc7z020clg400-1。在本仓库根目录、Vivado命令环境运行：

```powershell
vivado -mode batch -source rebuild/create_vivado.tcl -tclargs --build
```

输出到新建的`build_submission/`，不会覆盖源码。若仅恢复工程，去掉`-tclargs --build`。
原`test.xpr`也保留作为工程配置记录；其生成wrapper和复位仿真文件将在BD生成阶段恢复。

## PS应用和BOOT

在Vitis 2026.1命令环境继续执行：

```powershell
vitis -s rebuild/build_vitis.py
python rebuild/make_boot.py
```

Vitis脚本使用刚生成的XSA创建新的Cortex-A9 CPU0 Standalone平台、BSP、FSBL和应用，
并从该XSA提取AXI地址。Bootgen需在PATH中，或通过`--bootgen`指定绝对路径。
输出目录已存在时脚本会停止，重复重建请使用新克隆目录。
这些新增便携入口已完成静态检查；原交付的综合、实现和应用编译已在本地完成。
本次GitHub发布不运行新的综合、编译或硬件操作。

## 主机回归与上位机

Python 3.10+（含tkinter）、GCC，以及`requirements_ch9141.txt`中的Python依赖。

```powershell
python scripts/test_brush_host.py
python scripts/test_snake_host.py
python scripts/test_tetris_host.py
python scripts/test_sync_host.py
python -m unittest discover -s tests -p 'test_ch9141_*.py' -q
python ch9141_upper.py
```

历史delivery验证、旧画面差分和RAR清单校验脚本依赖本地未上传的产物/快照，
不作为本源码仓库的直接检查入口。原文档中的本机绝对路径、旧镜像名按历史记录理解。
最新尺寸版尚未实机验收；TF存储/文件播放业务尚未完成。
'''
(OUT/'docs/source-checkout.md').write_text(doc,encoding='utf-8')
changed={'.gitignore','README.md','rebuild/build_vitis.py'}
for relative,digest in original_files.items():
    if relative not in changed:
        assert hashlib.sha256((OUT/relative).read_bytes()).hexdigest()==digest,relative
files=[p for p in OUT.rglob('*') if p.is_file()]
for p in files:
    assert p.suffix.lower() not in skip_extensions,p
    assert not any(part in {'submission','submission_tools','vitis_workspace','test.runs','test.sim','test.gen'} for part in p.relative_to(OUT).parts),p
metadata={'repository':'huanyou1569/FPGA_DISPLAY','visibility':'public','files':len(files),
    'bytes':sum(p.stat().st_size for p in files),'source_consistency':'PASS',
    'excluded':['contest archives and extracted copies','downloaded RAR tools','Vivado/Vitis outputs','original Git history'],
    'original_repository_modified':False}
(ROOT/'github_publish/source-publication.json').write_text(json.dumps(metadata,indent=2),encoding='utf-8')
print(json.dumps(metadata,indent=2))
