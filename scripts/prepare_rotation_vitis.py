"""Prepare this task's new Vitis platform and application using installed 2026.1 APIs.

This builds only the new platform/BSP. Application compilation is separately
previewed and executed by the vitis-ps build_ps_application tool.
"""
import hashlib
import json
from pathlib import Path
import threading
import xml.etree.ElementTree as ET
import zipfile
import vitis

ROOT = Path(__file__).resolve().parents[1]
WORKSPACE = ROOT / "vitis_workspace"
OUT = ROOT / "migration/2026-11-03-rotation-sync"
XSA = OUT / "hardware/vx_display_rotation.xsa"
SOURCE = ROOT / "software/brush_app"
PLATFORM = "vx_display_rotation"
APP = "vx_brush_rotation"
DOMAIN = "standalone_ps7_cortexa9_0"

with zipfile.ZipFile(XSA) as archive:
    name = next(n for n in archive.namelist() if n.endswith(".hwh"))
    tree = ET.fromstring(archive.read(name))
    ranges = {(int(n.get("BASEVALUE"),0),int(n.get("HIGHVALUE"),0))
              for n in tree.iter("MEMRANGE") if n.get("INSTANCE")=="brush_axi_0"}
    if len(ranges)!=1:
        raise RuntimeError(f"Expected one actual brush AXI mapping, got {ranges}")
    base,high = ranges.pop()
    if high-base+1 < 0x40:
        raise RuntimeError("Brush register aperture is too small")
digest = hashlib.sha256(XSA.read_bytes()).hexdigest()
(SOURCE / "vx_hardware.h").write_text(
    "/* Generated from vx_display_rotation.xsa, SHA256 " + digest + " */\n"
    "#ifndef VX_HARDWARE_H\n#define VX_HARDWARE_H\n#include <stdint.h>\n"
    f"#define VX_BRUSH_BASEADDR UINT32_C(0x{base:08x})\n"
    f"#define VX_BRUSH_HIGHADDR UINT32_C(0x{high:08x})\n#endif\n",encoding="utf-8")

client = vitis.create_client()
def retain_server_log():
    with (OUT / "evidence/vitis-server.log").open("wb") as log:
        for line in iter(client._serverObj.cp.stdout.readline,b""):
            log.write(line)
            log.flush()
threading.Thread(target=retain_server_log,daemon=True).start()
try:
    client.log_level(level="INFO")
    client.set_workspace(path=str(WORKSPACE))
    platform_root = WORKSPACE / PLATFORM
    if platform_root.exists():
        imported = platform_root / "hw" / XSA.name
        if not imported.is_file() or imported.read_bytes()!=XSA.read_bytes():
            raise RuntimeError("Existing platform has different hardware; refusing replacement")
        platform = client.get_component(name=PLATFORM)
    else:
        platform = client.create_platform_component(
            name=PLATFORM,hw_design=str(XSA),cpu="ps7_cortexa9_0",
            os="standalone",domain_name=DOMAIN,
            desc="VX brush: UART1 BLE, AXI double canvas, original HUB75 display")
    domain = platform.get_domain(name=DOMAIN)
    domain.set_lib(lib_name="xilffs")
    domain.set_config(option="lib",lib_name="xilffs",param="XILFFS_use_lfn",value="1")
    status = platform.build()
    if str(status)!="0":
        raise RuntimeError(f"Platform build failed: {status}")
    xpfm = platform_root / "export" / PLATFORM / f"{PLATFORM}.xpfm"
    if not xpfm.is_file():
        raise RuntimeError("Platform export missing")
    if (WORKSPACE / APP).exists():
        app = client.get_component(name=APP)
        if app.component_type!="APPLICATION":
            raise RuntimeError("Existing component is not the intended application")
    else:
        app = client.create_app_component(
            name=APP,platform=str(xpfm),domain=DOMAIN,template="empty_application")
    source_files = sorted(p.name for p in SOURCE.iterdir() if p.suffix in {".c",".h"})
    app.import_files(from_loc=str(SOURCE),files=source_files,dest_dir_in_cmp="src")
    result = {
        "workspace":str(WORKSPACE),"platform":PLATFORM,"application":APP,
        "domain":DOMAIN,"xpfm":str(xpfm),"xsa":str(XSA),"xsa_sha256":digest,
        "bridge_base":hex(base),"bridge_high":hex(high),"sources":source_files,
        "application_build":"PENDING vitis-ps preview and authorized execution",
        "hardware_execution":"SKIPPED",
    }
    (OUT / "evidence/brush-platform.json").write_text(json.dumps(result,indent=2),encoding="utf-8")
    print("APP_PREPARED",json.dumps(result),flush=True)
finally:
    vitis.dispose()
