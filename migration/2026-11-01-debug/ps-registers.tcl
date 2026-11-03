# Read-only AP access. No stop, reset, download, or memory writes.
set evidence [open {C:/Users/1569/Desktop/test/migration/2026-11-01-debug/ps-registers.txt} w]
connect -url tcp:localhost:3121
targets -set -filter {name == "APU"}
foreach address {0xf8000258 0xf800025c 0xf800012c 0xf8000154 0xf8000228 0xf8000240 0xf8000738 0xf800073c 0xe0000000 0xe0000004 0xe0000018 0xe000002c 0xe0000034} {
    if {[catch {mrd -address-space AP0 $address} result]} {puts $evidence "$address ERROR $result"} else {puts $evidence $result}
    flush $evidence
}
puts $evidence "APPLICATION_ENTRY_MEMORY"
puts $evidence [mrd -address-space AP0 0x00100000 16]
puts $evidence "OCM_ENTRY_MEMORY"
puts $evidence [mrd -address-space AP0 0x00000000 8]
disconnect
close $evidence
exit
