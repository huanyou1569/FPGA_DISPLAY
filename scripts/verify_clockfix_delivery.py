"""Check that the delivered brush hardware, platform and sources agree."""
import hashlib
import json
from pathlib import Path
import struct
import re
import zipfile
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1]
out = root / 'migration/2026-11-01-clockfix'
xsa = out / 'hardware/vx_display_clockfix.xsa'
digest = hashlib.sha256(xsa.read_bytes()).hexdigest()
with zipfile.ZipFile(xsa) as z:
    bits = [n for n in z.namelist() if n.endswith('.bit')]
    assert len(bits) == 1
    assert z.read(bits[0]) == (out / 'hardware/vx_display_clockfix.bit').read_bytes()
    hwh = ET.fromstring(z.read(next(n for n in z.namelist() if n.endswith('.hwh'))))
    ranges = {(int(n.get('BASEVALUE'), 0), int(n.get('HIGHVALUE'), 0))
              for n in hwh.iter('MEMRANGE') if n.get('INSTANCE') == 'brush_axi_0'}
    assert ranges == {(0x40000000, 0x40000fff)}, ranges
    ps = next(n for n in hwh.iter('MODULE') if n.get('INSTANCE') == 'processing_system7_0')
    params = {n.get('NAME'): n.get('VALUE') for n in ps.iter('PARAMETER')}
    for key,value in {'PCW_CRYSTAL_PERIPHERAL_FREQMHZ':50,
                      'PCW_APU_PERIPHERAL_FREQMHZ':650,
                      'PCW_UIPARAM_ACT_DDR_FREQ_MHZ':525}.items():
        assert float(params[key]) == value, (key,params.get(key))
    assert params['PCW_UART0_UART0_IO'] == 'MIO 14 .. 15'
    assert params['PCW_UART1_UART1_IO'] == 'EMIO'
header = (root / 'software/brush_app/vx_hardware.h').read_text()
assert digest in header and '0x40000000' in header
platform = root / 'vitis_workspace/vx_display_clockfix'
assert (platform / 'hw' / xsa.name).read_bytes() == xsa.read_bytes()
assert (platform / 'export/vx_display_clockfix/vx_display_clockfix.xpfm').is_file()
bsp = platform / 'export/vx_display_clockfix/sw/standalone_ps7_cortexa9_0'
defines = dict(re.findall(r'^#define\s+(\w+)\s+(0x[0-9a-fA-F]+|[0-9]+)\b',
                         (bsp/'include/xparameters.h').read_text(),re.M))
for macro,value in {'XPAR_CPU_CORE_CLOCK_FREQ_HZ':650000000,
                    'XPAR_UART0_BASEADDR':0xe0000000,
                    'XPAR_UART1_BASEADDR':0xe0001000,
                    'XPAR_UART0_CLOCK_FREQ':100000000,
                    'XPAR_UART1_CLOCK_FREQ':100000000}.items():
    assert int(defines[macro],0) == value, (macro,defines.get(macro))
app = root / 'vitis_workspace/vx_brush_clockfix'
source_names = []
for source in (root / 'software/brush_app').iterdir():
    if source.suffix in {'.c', '.h'}:
        assert (app / 'src' / source.name).read_bytes() == source.read_bytes(), source.name
        source_names.append(source.name)
elfs = list((app / 'build').rglob('vx_brush_clockfix.elf'))
elf_evidence = []
for elf in elfs:
    data = elf.read_bytes()
    assert data[:4] == b'\x7fELF' and data[4:6] == b'\x01\x01'
    assert struct.unpack_from('<H', data, 18)[0] == 40
    elf_evidence.append({'path': str(elf), 'size': len(data),
                         'sha256': hashlib.sha256(data).hexdigest()})
result = {'xsa_sha256': digest, 'hardware_platform_sources': 'PASS',
          'ps_input_mhz':50,'cpu_mhz':650,'ddr_mhz':525,
          'sources': sorted(source_names), 'elf': elf_evidence,
          'application_build': 'PASS' if elf_evidence else 'NOT_BUILT',
          'board_execution': 'SKIPPED'}
(out / 'evidence/delivery-check.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
print(json.dumps(result, indent=2))
