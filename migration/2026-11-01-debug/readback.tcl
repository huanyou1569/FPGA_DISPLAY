set evidence [open {C:/Users/1569/Desktop/test/migration/2026-11-01-debug/readback.txt} w]
connect -url tcp:localhost:3121
targets -set -filter {name == "APU"}
foreach {name address count} {ddr1 0x100000 1024 ddr2 0x100000 1024 flash_header 0xfc000000 1024 flash_app 0xfc3fc940 1024} {
    set path "C:/Users/1569/Desktop/test/migration/2026-11-01-debug/$name.bin"
    if {[catch {mrd -address-space AP0 -bin -file $path $address $count} result]} {puts $evidence "$name ERROR $result"} else {puts $evidence "$name READ_OK"}
    flush $evidence
}
disconnect
close $evidence
exit
