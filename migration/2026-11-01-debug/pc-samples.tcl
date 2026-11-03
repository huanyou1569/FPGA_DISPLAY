# Clear debugger error flags, then sample PC without halting either CPU.
set evidence [open {C:/Users/1569/Desktop/test/migration/2026-11-01-debug/pc-samples.txt} w]
connect -url tcp:localhost:3121
targets -set -filter {name == "APU"}
set status [lindex [mrd -address-space DPR -value 4] 0]
mwr -address-space DPR 4 [expr {$status | 0x20}]
foreach address {0x80090000 0x80090088 0x80090084 0x80090084 0x80090084 0x80090084} {
    if {[catch {mrd -address-space AP1 $address} result]} {puts $evidence "$address ERROR $result"} else {puts $evidence $result}
    flush $evidence
}
disconnect
close $evidence
exit
