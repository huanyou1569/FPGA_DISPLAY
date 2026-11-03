"""Check that the delivered brush hardware, platform and sources agree."""
import hashlib
import json
from pathlib import Path
import struct
import zipfile
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1]
out = root / 'migration/2026-10-31-brush'
xsa = out / 'hardware/vx_display_brush.xsa'
digest = hashlib.sha256(xsa.read_bytes()).hexdigest()
with zipfile.ZipFile(xsa) as z:
    bits = [n for n in z.namelist() if n.endswith('.bit')]
    assert len(bits) == 1
    assert z.read(bits[0]) == (out / 'hardware/vx_display_brush.bit').read_bytes()
    hwh = ET.fromstring(z.read(next(n for n in z.namelist() if n.endswith('.hwh'))))
    ranges = {(int(n.get('BASEVALUE'), 0), int(n.get('HIGHVALUE'), 0))
              for n in hwh.iter('MEMRANGE') if n.get('INSTANCE') == 'brush_axi_0'}
    assert ranges == {(0x40000000, 0x40000fff)}, ranges
header = (root / 'software/brush_app/vx_hardware.h').read_text()
assert digest in header and '0x40000000' in header
platform = root / 'vitis_workspace/vx_display_brush'
assert (platform / 'hw' / xsa.name).read_bytes() == xsa.read_bytes()
assert (platform / 'export/vx_display_brush/vx_display_brush.xpfm').is_file()
app = root / 'vitis_workspace/vx_brush'
source_names = []
for source in (root / 'software/brush_app').iterdir():
    if source.suffix in {'.c', '.h'}:
        assert (app / 'src' / source.name).read_bytes() == source.read_bytes(), source.name
        source_names.append(source.name)
elfs = list((app / 'build').rglob('vx_brush.elf'))
elf_evidence = []
for elf in elfs:
    data = elf.read_bytes()
    assert data[:4] == b'\x7fELF' and data[4:6] == b'\x01\x01'
    assert struct.unpack_from('<H', data, 18)[0] == 40
    elf_evidence.append({'path': str(elf), 'size': len(data),
                         'sha256': hashlib.sha256(data).hexdigest()})
result = {'xsa_sha256': digest, 'hardware_platform_sources': 'PASS',
          'sources': sorted(source_names), 'elf': elf_evidence,
          'application_build': 'PASS' if elf_evidence else 'NOT_BUILT',
          'board_execution': 'SKIPPED'}
(out / 'evidence/delivery-check.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
print(json.dumps(result, indent=2))
