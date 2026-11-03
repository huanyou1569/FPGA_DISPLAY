# Explicit project root: C:/Users/1569/Desktop/test.
# Execute only after user authorization for ONE system reset.
# No Flash programming, bitstream programming, ELF download, or CPU halt.
connect -url tcp:localhost:3121
targets -set -filter {name == "ARM Cortex-A9 MPCore #0" && jtag_cable_serial == "1234-tulA"}
rst -system -start
disconnect
exit
