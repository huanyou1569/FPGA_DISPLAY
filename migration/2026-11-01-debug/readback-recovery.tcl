# Restore only debug-port sticky error state after the failed read.
# No target reset/halt, firmware download, or PS/PL register writes.
set evidence [open {C:/Users/1569/Desktop/test/migration/2026-11-01-debug/readback-recovery.txt} w]
connect -url tcp:localhost:3121
targets -set -filter {name == "APU"}
set status [lindex [mrd -address-space DPR -value 4] 0]
puts $evidence "DAP_CTRL_STAT_BEFORE=$status"
# JTAG-DP CTRL/STAT STICKYERR is write-one-to-clear; preserve requests.
mwr -address-space DPR 4 [expr {$status | 0x20}]
puts $evidence "DAP_CTRL_STAT_AFTER=[mrd -address-space DPR -value 4]"
foreach {name address count} {ddr1 0x100000 1024 ddr2 0x100000 1024 flash_header 0xfc000000 1024 flash_app 0xfc3fc940 1024} {
    set path "C:/Users/1569/Desktop/test/migration/2026-11-01-debug/$name.bin"
    if {[catch {mrd -address-space AP0 -bin -file $path $address $count} result]} {puts $evidence "$name ERROR $result"} else {puts $evidence "$name READ_OK"}
    flush $evidence
}
disconnect
close $evidence
exit
