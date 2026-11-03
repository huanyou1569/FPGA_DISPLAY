# Read-only: no CPU halt/reset, no download, no writes.
set evidence [open {C:/Users/1569/Desktop/test/migration/2026-11-01-debug/ps-memory-check.txt} w]
connect -url tcp:localhost:3121
targets -set -filter {name == "APU"}
foreach address {0xf800025c 0xe000d0a0 0x40000000 0x40000004 0x40000008 0x40000024} {
    if {[catch {mrd -address-space AP0 $address} result]} {puts $evidence "$address ERROR $result"} else {puts $evidence $result}
    flush $evidence
}
mrd -address-space AP0 -bin -file {C:/Users/1569/Desktop/test/migration/2026-11-01-debug/app-entry-1.bin} 0x00100000 1024
mrd -address-space AP0 -bin -file {C:/Users/1569/Desktop/test/migration/2026-11-01-debug/app-entry-2.bin} 0x00100000 1024
puts $evidence [targets]
disconnect
close $evidence
exit
