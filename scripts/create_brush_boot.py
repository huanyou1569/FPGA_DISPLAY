"""Package the verified Cortex-A9 brush delivery; never program hardware."""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import struct
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--verify-only', action='store_true')
args = parser.parse_args()
OUT = ROOT / 'migration/2026-11-01-boot'
OUT.mkdir(parents=True, exist_ok=True)
HW = ROOT / 'migration/2026-10-31-brush/hardware'
PLATFORM = ROOT / 'vitis_workspace/vx_display_brush'
FSBL = PLATFORM / 'export/vx_display_brush/sw/boot/fsbl.elf'
APP = ROOT / 'vitis_workspace/vx_brush/build/vx_brush.elf'
XSA = HW / 'vx_display_brush.xsa'
config = json.loads((Path.home() / 'ZynqCodexToolkit/config/toolchain.json').read_text())
BOOTGEN = Path(config['vitis']).parent / 'bootgen.bat'

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def elf32_arm(path):
    data = path.read_bytes()
    assert data[:6] == b'\x7fELF\x01\x01', path
    assert struct.unpack_from('<H', data, 18)[0] == 40, path
    return hex(struct.unpack_from('<I', data, 24)[0])

assert (PLATFORM / 'hw' / XSA.name).read_bytes() == XSA.read_bytes()
assert FSBL.read_bytes() == (PLATFORM / 'zynq_fsbl/build/fsbl.elf').read_bytes()
assert APP.read_bytes() == (HW / 'vx_brush.elf').read_bytes()
for source in (ROOT / 'software/brush_app').iterdir():
    if source.suffix in {'.c', '.h'}:
        assert source.read_bytes() == (ROOT / 'vitis_workspace/vx_brush/src' / source.name).read_bytes()
with zipfile.ZipFile(XSA) as archive:
    bit_name = next(n for n in archive.namelist() if n.endswith('.bit'))
    assert archive.read(bit_name) == (HW / 'vx_display_brush.bit').read_bytes()
    assert archive.read('ps7_init.c') == (PLATFORM / 'zynq_fsbl/ps7_init.c').read_bytes()

entries = {'fsbl.elf': elf32_arm(FSBL), 'vx_brush.elf': elf32_arm(APP)}
inputs = {'fsbl.elf': FSBL, 'vx_display_brush.bit': HW / 'vx_display_brush.bit',
          'vx_brush.elf': APP}
for name, src in inputs.items():
    dst = OUT / name
    if dst.exists():
        assert dst.read_bytes() == src.read_bytes(), f'Refusing to replace changed input: {dst}'
    else:
        shutil.copyfile(src, dst)

bif = '''// Zynq-7000, Cortex-A9 CPU0, PYNQ-Z2; QSPI offset 0.
the_ROM_image:
{
    [bootloader] fsbl.elf
    vx_display_brush.bit
    vx_brush.elf
}
'''
(OUT / 'boot.bif').write_text(bif, encoding='ascii')
boot = OUT / 'BOOT.bin'
if boot.exists() and not args.verify_only:
    raise RuntimeError('BOOT.bin already exists; retain it and review before regenerating')
if not args.verify_only:
    with (OUT / 'bootgen.log').open('w', encoding='utf-8') as log:
        subprocess.run([str(BOOTGEN), '-arch', 'zynq', '-image', 'boot.bif',
                        '-o', 'BOOT.bin'], cwd=OUT, stdout=log,
                       stderr=subprocess.STDOUT, check=True)
assert 0 < boot.stat().st_size < 16 * 1024 * 1024
with (OUT / 'bootgen-read.log').open('w', encoding='utf-8') as log:
    subprocess.run([str(BOOTGEN), '-arch', 'zynq', '-read', 'BOOT.bin'],
                   cwd=OUT, stdout=log, stderr=subprocess.STDOUT, check=True)
data = boot.read_bytes()
word = lambda offset: struct.unpack_from('<I', data, offset)[0]
assert word(0x20) == 0xaa995566 and word(0x24) == 0x584c4e58
assert sum(struct.unpack_from('<11I', data, 0x20)) & 0xffffffff == 0xffffffff
partitions = []
for index in range(4):
    values = struct.unpack_from('<16I', data, word(0x9c) + index * 64)
    assert sum(values) & 0xffffffff == 0xffffffff
    length, load, entry, offset, attr = values[0]*4, values[3], values[4], values[5]*4, values[6]
    assert offset+length <= len(data)
    partitions.append({'offset': offset, 'bytes': length, 'load': load,
                       'entry': entry, 'attributes': attr})
assert [p['attributes'] for p in partitions] == [0x10, 0x20, 0x10, 0x10]
assert partitions[0]['load'] == 0 and partitions[2]['entry'] == 0x100000
# Compare every ELF file-backed load segment to the bytes in the final image.
for elf, candidates in [(FSBL, partitions[:1]), (APP, partitions[2:])]:
    source = elf.read_bytes()
    phoff = struct.unpack_from('<I', source, 28)[0]
    phsize, phnum = struct.unpack_from('<HH', source, 42)
    for index in range(phnum):
        kind, offset, va, pa, size, memsize, flags, align = struct.unpack_from('<8I', source, phoff+index*phsize)
        if kind != 1 or not size:
            continue
        part = next(p for p in candidates if p['load'] <= pa and pa+size <= p['load']+p['bytes'])
        start = part['offset'] + pa-part['load']
        assert data[start:start+size] == source[offset:offset+size]
result = {'project_root': str(ROOT), 'bootgen': str(BOOTGEN),
          'architecture': 'zynq', 'flash_offset': '0x00000000',
          'xsa_sha256': sha(XSA), 'elf_entry_points': entries,
          'files': {name: {'bytes': (OUT/name).stat().st_size, 'sha256': sha(OUT/name)}
                    for name in [*inputs, 'BOOT.bin']},
          'partitions': partitions, 'header_checksums_and_elf_payloads': 'PASS',
          'hardware_programming': 'NOT_PERFORMED', 'board_boot_test': 'SKIPPED'}
(OUT / 'manifest.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
print(json.dumps(result, indent=2))
