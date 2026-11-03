"""Verify the extracted submission using Python standard library only."""
import hashlib
import json
from pathlib import Path
import struct
import xml.etree.ElementTree as ET
import zipfile

root=Path(__file__).resolve().parents[1]
manifest=json.loads((root/'PACKAGE_MANIFEST.json').read_text(encoding='utf-8'))
for relative,info in manifest['files'].items():
    path=root/relative
    if path.stat().st_size!=info['bytes'] or hashlib.sha256(path.read_bytes()).hexdigest()!=info['sha256']:
        raise RuntimeError(f'Package file mismatch: {relative}')
project=ET.parse(root/'test.xpr').getroot()
macros={'$PPRDIR':str(root),'$PSRCDIR':str(root/'test.srcs'),'$PGENDIR':str(root/'test.gen')}
references=[]
for node in project.findall('./FileSets/FileSet/File'):
    name=node.get('Path')
    for key,value in macros.items(): name=name.replace(key,value)
    path=Path(name)
    if not path.is_absolute(): path=root/path
    if not path.is_file(): raise RuntimeError(f'Project input missing: {name}')
    references.append(node.get('Path'))
hw=root/'migration/2026-11-03-small-voxels/hardware'
artifact_manifest=json.loads((hw/'manifest.json').read_text(encoding='utf-8'))
for name,info in artifact_manifest['files'].items():
    assert hashlib.sha256((hw/name).read_bytes()).hexdigest()==info['sha256'],name
with zipfile.ZipFile(hw/'vx_display_small.xsa') as z:
    assert z.read(next(n for n in z.namelist() if n.endswith('.bit')))==(hw/'vx_display_small.bit').read_bytes()
boot=(hw/'BOOT.bin').read_bytes()
word=lambda offset:struct.unpack_from('<I',boot,offset)[0]
assert (word(0x20),word(0x24))==(0xaa995566,0x584c4e58)
assert sum(struct.unpack_from('<11I',boot,0x20))&0xffffffff==0xffffffff
partitions=[]
for index in range(4):
    values=struct.unpack_from('<16I',boot,word(0x9c)+index*64)
    assert sum(values)&0xffffffff==0xffffffff
    length,load,entry,offset,attr=values[0]*4,values[3],values[4],values[5]*4,values[6]
    assert offset+length<=len(boot)
    partitions.append((offset,length,load,entry,attr))
assert [p[4] for p in partitions]==[0x10,0x20,0x10,0x10]
for name,candidates in [('fsbl.elf',partitions[:1]),('vx_brush_small.elf',partitions[2:])]:
    data=(hw/name).read_bytes()
    assert data[:6]==b'\x7fELF\x01\x01' and struct.unpack_from('<H',data,18)[0]==40
    phoff=struct.unpack_from('<I',data,28)[0]
    phsize,phnum=struct.unpack_from('<HH',data,42)
    for i in range(phnum):
        kind,offset,va,pa,size,memsize,flags,align=struct.unpack_from('<8I',data,phoff+i*phsize)
        if kind!=1 or not size:continue
        part=next(p for p in candidates if p[2]<=pa and pa+size<=p[2]+p[1])
        start=part[0]+pa-part[2]
        assert boot[start:start+size]==data[offset:offset+size]
source=root/'software/brush_app'
snapshot=root/'vitis_workspace/vx_brush_small/src'
for p in source.iterdir():
    if p.suffix in {'.c','.h'}:assert p.read_bytes()==(snapshot/p.name).read_bytes(),p.name
for relative,digest in json.loads((root/'migration/2026-11-03-small-voxels/evidence/rtl-sources.json').read_text()).items():
    assert hashlib.sha256((root/relative).read_bytes()).hexdigest()==digest,relative
print(json.dumps({'result':'PASS','manifest_files':len(manifest['files']),
    'project_file_references':len(references),'latest_boot_bytes':len(boot),
    'latest_boot_sha256':hashlib.sha256(boot).hexdigest(),
    'bit_xsa_elf_boot_consistency':'PASS','software_and_rtl_consistency':'PASS'},indent=2))
