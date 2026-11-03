"""Verify the hardware handoff and built Vitis platform without accessing hardware."""
import hashlib
import json
from pathlib import Path
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "migration/2026-10-31"
XSA = OUT / "hardware/vx_display_ps.xsa"
BIT = OUT / "hardware/vx_display_ps.bit"

expected = {
    "PCW_UART0_PERIPHERAL_ENABLE": "1",
    "PCW_UART0_UART0_IO": "MIO 14 .. 15",
    "PCW_UART1_PERIPHERAL_ENABLE": "1",
    "PCW_UART1_UART1_IO": "EMIO",
    "PCW_SD0_PERIPHERAL_ENABLE": "1",
    "PCW_SD0_SD0_IO": "MIO 40 .. 45",
    "PCW_SD0_GRP_CD_ENABLE": "1",
    "PCW_SD0_GRP_CD_IO": "MIO 47",
    "PCW_SD0_GRP_WP_ENABLE": "0",
}
with zipfile.ZipFile(XSA) as archive:
    hwh_name = next(n for n in archive.namelist() if n.endswith(".hwh"))
    hwh = ET.fromstring(archive.read(hwh_name))
    ps = next(m for m in hwh.iter("MODULE")
              if m.get("INSTANCE") == "processing_system7_0")
    params = {p.get("NAME"): p.get("VALUE") for p in ps.iter("PARAMETER")}
    for key, value in expected.items():
        if params.get(key) != value:
            raise RuntimeError(f"XSA mismatch: {key}={params.get(key)!r}, want {value!r}")
    bit_name = next(n for n in archive.namelist() if n.endswith(".bit"))
    if archive.read(bit_name) != BIT.read_bytes():
        raise RuntimeError("Exported XSA bitstream differs from standalone bitstream")

artifacts = {}
for path in [XSA, BIT, OUT / "hardware/design_1.tcl"]:
    artifacts[str(path.relative_to(ROOT))] = {
        "bytes": path.stat().st_size,
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
    }
result = {
    "xsa_parameters": {key: params[key] for key in expected},
    "embedded_bitstream_matches": True,
    "artifacts": artifacts,
}
(OUT / "evidence/hardware-verification.json").write_text(
    json.dumps(result, indent=2), encoding="utf-8")
print(json.dumps(result, indent=2))

platform_root = ROOT / "vitis_workspace/vx_display_ps"
export = platform_root / "export/vx_display_ps"
bsp = platform_root / "ps7_cortexa9_0/standalone_ps7_cortexa9_0/bsp"
for path in [platform_root / "hw/vx_display_ps.xsa", export / "hw/vx_display_ps.xsa"]:
    if path.read_bytes() != XSA.read_bytes():
        raise RuntimeError(f"Platform uses a different XSA: {path}")
ET.parse(export / "vx_display_ps.xpfm")
header = (bsp / "include/xparameters.h").read_text()
for declaration in ["#define XPAR_XUARTPS_NUM_INSTANCES 2",
                    "#define XPAR_XSDPS_NUM_INSTANCES 1"]:
    if declaration not in header:
        raise RuntimeError(f"BSP declaration missing: {declaration}")
if "#define STDOUT_BASEADDRESS 0xe0000000" not in (bsp / "include/bspconfig.h").read_text():
    raise RuntimeError("Debug console is not UART0")
if "#define FILE_SYSTEM_USE_LFN 1" not in (bsp / "include/xilffs_config.h").read_text():
    raise RuntimeError("FatFS long filenames are not enabled")
for filename in ["libxil.a", "libxilffs.a"]:
    for path in [bsp / "lib" / filename,
                 export / "sw/standalone_ps7_cortexa9_0/lib" / filename]:
        if path.read_bytes()[:8] != b"!<arch>\n":
            raise RuntimeError(f"Missing or invalid library archive: {path}")
elf = (export / "sw/boot/fsbl.elf").read_bytes()
if elf[:4] != b"\x7fELF" or elf[4] != 1 or int.from_bytes(elf[18:20], "little") != 40:
    raise RuntimeError("Boot FSBL is not ELF32 ARM")
platform_result = {
    "xpfm": str(export / "vx_display_ps.xpfm"),
    "hardware_import_and_export_match": True,
    "uart_instances": 2, "sd_instances": 1,
    "stdout": "UART0", "long_filenames": True,
    "libraries_verified": ["libxil.a", "libxilffs.a"],
    "boot_fsbl": "ELF32 ARM", "hardware_test": "SKIPPED",
}
(OUT / "evidence/platform-verification.json").write_text(
    json.dumps(platform_result, indent=2), encoding="utf-8")
print(json.dumps(platform_result, indent=2))
