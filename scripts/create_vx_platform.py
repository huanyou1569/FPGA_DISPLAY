"""Create a fresh Vitis 2026.1 Cortex-A9 platform from the verified export.

Run with D:/APP/2026.1/Vitis/bin/vitis.bat -s <this absolute path>.
Refuses to overwrite an existing platform. VX_PLATFORM_RESUME=1 resumes only
this platform after checking its imported XSA. Builds the standard boot FSBL
with the platform, without creating a display application or programming hardware.
"""
import json
import os
import threading
from pathlib import Path
import vitis

ROOT = Path(__file__).resolve().parents[1]
WORKSPACE = ROOT / "vitis_workspace"
XSA = ROOT / "migration/2026-10-31/hardware/vx_display_ps.xsa"
NAME = "vx_display_ps"
DOMAIN = "standalone_ps7_cortexa9_0"
EVIDENCE = ROOT / "migration/2026-10-31/evidence"

if not XSA.is_file():
    raise FileNotFoundError(XSA)
resume = os.environ.get("VX_PLATFORM_RESUME") == "1"
exists = (WORKSPACE / NAME).exists()
if exists and not resume:
    raise FileExistsError(f"Refusing to replace existing platform: {WORKSPACE / NAME}")
if resume:
    imported_xsa = WORKSPACE / NAME / "hw" / XSA.name
    if not imported_xsa.is_file() or imported_xsa.read_bytes() != XSA.read_bytes():
        raise RuntimeError("Cannot resume: platform hardware does not match this task's XSA")

client = vitis.create_client()
def retain_server_log():
    with (EVIDENCE / "vitis-server-debug.log").open("wb") as output:
        for line in iter(client._serverObj.cp.stdout.readline, b""):
            output.write(line)
            output.flush()

server_log_thread = threading.Thread(target=retain_server_log, daemon=True)
server_log_thread.start()
try:
    client.log_level(level="INFO")
    client.set_workspace(path=str(WORKSPACE))
    print("PROCESSORS", client.get_processor_os_list(xsa=str(XSA)), flush=True)
    if resume:
        platform = client.get_component(name=NAME)
    else:
        platform = client.create_platform_component(
            name=NAME, hw_design=str(XSA), os="standalone",
            cpu="ps7_cortexa9_0", domain_name=DOMAIN,
            desc="PYNQ-Z2 voxel display: USB UART0, Bluetooth UART1 EMIO, SD0",
        )
    domain = platform.get_domain(name=DOMAIN)
    os_parameters = domain.list_params(option="os")
    (EVIDENCE / "vitis-os-parameters.json").write_text(
        json.dumps(os_parameters, ensure_ascii=False, indent=2, default=list), encoding="utf-8")
    print("OS_PARAMETERS", os_parameters)
    domain.set_lib(lib_name="xilffs")
    lib_parameters = domain.list_params(option="lib", lib_name="xilffs")
    (EVIDENCE / "vitis-xilffs-parameters.json").write_text(
        json.dumps(lib_parameters, ensure_ascii=False, indent=2, default=list), encoding="utf-8")
    lfn_keys = [p["parameter_name"] for p in lib_parameters
                if p["parameter_name"].lower() == "xilffs_use_lfn"]
    if len(lfn_keys) != 1:
        raise RuntimeError("Installed xilffs LFN parameter was not identified uniquely")
    domain.set_config(option="lib", param=lfn_keys[0], value="1", lib_name="xilffs")
    print("LIBRARIES", domain.get_libs())
    build_status = platform.build()
    print("BUILD_PLATFORM", build_status)
    if str(build_status) != "0":
        raise RuntimeError(f"Vitis 2026.1 platform build did not report SUCCESS (0): {build_status}")
    xpfm = WORKSPACE / NAME / "export" / NAME / f"{NAME}.xpfm"
    if not xpfm.is_file():
        raise RuntimeError(f"Platform export missing: {xpfm}")
    result = {
        "workspace": str(WORKSPACE), "platform": NAME,
        "domain": DOMAIN, "cpu": "ps7_cortexa9_0", "os": "standalone",
        "xsa": str(XSA), "xpfm": str(xpfm),
        "domains": str(platform.list_domains()), "build_status": str(build_status),
        "hardware_test": "SKIPPED: no programming or reset requested",
    }
    (EVIDENCE / "vitis-platform.json").write_text(
        json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print("PLATFORM_VERIFIED", xpfm)
finally:
    vitis.dispose()
