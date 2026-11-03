"""Package a fresh rebuilt FSBL/BIT/application with Bootgen from PATH."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import struct
import subprocess
import zipfile

root=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--bootgen',default=shutil.which('bootgen') or shutil.which('bootgen.bat'))
args=parser.parse_args()
if not args.bootgen:
    parser.error('Add Vitis bin to PATH or provide --bootgen with the full Bootgen path')
record=json.loads((root/'build_submission/vitis-build.json').read_text(encoding='utf-8'))
workspace=Path(record['workspace'])
xsa=Path(record['xsa'])
assert hashlib.sha256(xsa.read_bytes()).hexdigest()==record['xsa_sha256']
out=root/'build_submission/boot'
if out.exists():
    raise RuntimeError(f'Refusing to overwrite existing boot directory: {out}')
out.mkdir(parents=True)
fsbl=workspace/'vx_display_small/export/vx_display_small/sw/boot/fsbl.elf'
app=Path(record['application_elf'])
for path,name in [(fsbl,'fsbl.elf'),(app,'vx_brush_small.elf')]:
    data=path.read_bytes()
    assert data[:6]==b'\x7fELF\x01\x01' and struct.unpack_from('<H',data,18)[0]==40
    shutil.copyfile(path,out/name)
with zipfile.ZipFile(xsa) as archive:
    (out/'vx_display_small.bit').write_bytes(archive.read(next(n for n in archive.namelist() if n.endswith('.bit'))))
(out/'boot.bif').write_text('the_ROM_image:\n{\n [bootloader] fsbl.elf\n vx_display_small.bit\n vx_brush_small.elf\n}\n',encoding='ascii')
subprocess.run([args.bootgen,'-arch','zynq','-image','boot.bif','-o','BOOT.bin'],cwd=out,check=True)
data=(out/'BOOT.bin').read_bytes()
assert 0<len(data)<16*1024*1024
assert struct.unpack_from('<II',data,0x20)==(0xaa995566,0x584c4e58)
assert sum(struct.unpack_from('<11I',data,0x20))&0xffffffff==0xffffffff
result={'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest(),'flash_offset':'0x00000000',
        'hardware_programming':'NOT_PERFORMED'}
(out/'manifest.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print('BOOT_CREATED',json.dumps(result))
