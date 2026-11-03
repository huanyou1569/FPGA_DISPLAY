# Read only: current boot configuration, UART and Flash/DDR samples.
set evidence [open {C:/Users/1569/Desktop/test/migration/2026-11-01-debug/clockfix-board-read.txt} w]
connect -url tcp:localhost:3121
targets -set -filter {name == "APU"}
foreach address {0xf800025c 0xf8000100 0xf8000104 0xf8000108 0xf8000154 0xe0000000 0xe0000018 0xe000002c 0xe0000034} {
 puts $evidence [mrd -address-space AP0 $address]
 flush $evidence
}
foreach {name address count} {clockfix_flash_header 0xfc000000 1024 clockfix_flash_app 0xfc3fc940 1024 clockfix_ddr1 0x100000 1024 clockfix_ddr2 0x100000 1024} {
 set path "C:/Users/1569/Desktop/test/migration/2026-11-01-debug/$name.bin"
 if {[catch {mrd -address-space AP0 -bin -file $path $address $count} result]} {puts $evidence "$name ERROR $result"; flush $evidence; break}
 puts $evidence "$name READ_OK"
 flush $evidence
}
puts $evidence [targets]
disconnect
close $evidence
exit
