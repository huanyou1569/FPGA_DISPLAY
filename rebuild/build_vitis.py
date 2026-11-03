"""Run with Vitis 2026.1: vitis -s rebuild/build_vitis.py. No hardware access."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import xml.etree.ElementTree as ET
import zipfile
import vitis

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build_submission'
WORKSPACE = BUILD / 'vitis_workspace'
if WORKSPACE.exists():
    raise RuntimeError(f'Refusing to overwrite existing workspace: {WORKSPACE}')
fresh_xsa = BUILD/'hardware/vx_display_small.xsa'
XSA = Path(os.environ.get('VX_SUBMISSION_XSA', str(fresh_xsa if fresh_xsa.exists() else
    ROOT/'migration/2026-11-03-small-voxels/hardware/vx_display_small.xsa'))).resolve()
with zipfile.ZipFile(XSA) as archive:
    hwh = ET.fromstring(archive.read(next(n for n in archive.namelist() if n.endswith('.hwh'))))
    ranges = {(int(n.get('BASEVALUE'),0),int(n.get('HIGHVALUE'),0))
              for n in hwh.iter('MEMRANGE') if n.get('INSTANCE')=='brush_axi_0'}
    if len(ranges)!=1:
        raise RuntimeError(f'Unexpected actual brush AXI mapping: {ranges}')
    base, high = ranges.pop()
SOURCE = BUILD/'application_sources'
SOURCE.mkdir(parents=True)
for path in (ROOT/'software/brush_app').iterdir():
    if path.suffix in {'.c','.h'}:
        shutil.copyfile(path,SOURCE/path.name)
snapshot = ROOT/'rebuild/application_config'
for name in ['UserConfig.cmake','lscript.ld']:
    shutil.copyfile(snapshot/name,SOURCE/name)
digest=hashlib.sha256(XSA.read_bytes()).hexdigest()
(SOURCE/'vx_hardware.h').write_text(
    f'/* Generated from selected XSA, SHA256 {digest} */\n'
    '#ifndef VX_HARDWARE_H\n#define VX_HARDWARE_H\n#include <stdint.h>\n'
    f'#define VX_BRUSH_BASEADDR UINT32_C(0x{base:08x})\n'
    f'#define VX_BRUSH_HIGHADDR UINT32_C(0x{high:08x})\n#endif\n',encoding='utf-8')
client=vitis.create_client()
try:
    client.set_workspace(path=str(WORKSPACE))
    platform=client.create_platform_component(name='vx_display_small',hw_design=str(XSA),
        cpu='ps7_cortexa9_0',os='standalone',domain_name='standalone_ps7_cortexa9_0')
    domain=platform.get_domain(name='standalone_ps7_cortexa9_0')
    domain.set_lib(lib_name='xilffs')
    domain.set_config(option='lib',lib_name='xilffs',param='XILFFS_use_lfn',value='1')
    if str(platform.build())!='0':
        raise RuntimeError('Platform/BSP/FSBL build failed')
    xpfm=WORKSPACE/'vx_display_small/export/vx_display_small/vx_display_small.xpfm'
    app=client.create_app_component(name='vx_brush_small',platform=str(xpfm),
        domain='standalone_ps7_cortexa9_0',template='empty_application')
    app.import_files(from_loc=str(SOURCE),files=sorted(p.name for p in SOURCE.iterdir()),dest_dir_in_cmp='src')
    if str(app.build(target='hw'))!='0':
        raise RuntimeError('Application build failed')
    elf=WORKSPACE/'vx_brush_small/build/vx_brush_small.elf'
    data=elf.read_bytes()
    if data[:6]!=b'\x7fELF\x01\x01' or data[18:20]!=b'\x28\x00':
        raise RuntimeError('Output is not an ELF32 ARM application')
    (BUILD/'vitis-build.json').write_text(json.dumps({'xsa':str(XSA),'xsa_sha256':digest,
        'workspace':str(WORKSPACE),'application_elf':str(elf),'status':'PASS'},indent=2),encoding='utf-8')
    print('VITIS_BUILD_PASS',elf)
finally:
    vitis.dispose()
