# Explicit root C:/Users/1569/Desktop/test; read only; no PL accesses.
set evidence [open {C:/Users/1569/Desktop/test/migration/2026-11-01-debug/cold-readback.txt} w]
connect -url tcp:localhost:3121
targets -set -filter {name == "APU"}
puts $evidence [mrd -address-space AP0 0xf800025c]
foreach {name address count} {cold_flash_header 0xfc000000 1024 cold_flash_app 0xfc3fc940 1024 cold_ddr1 0x100000 1024 cold_ddr2 0x100000 1024} {
    set path "C:/Users/1569/Desktop/test/migration/2026-11-01-debug/$name.bin"
    if {[catch {mrd -address-space AP0 -bin -file $path $address $count} result]} {
        puts $evidence "$name ERROR $result"
        flush $evidence
        break
    } else {puts $evidence "$name READ_OK"}
    flush $evidence
}
puts $evidence [targets]
disconnect
close $evidence
exit
