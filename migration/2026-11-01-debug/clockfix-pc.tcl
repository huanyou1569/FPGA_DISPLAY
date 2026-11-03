# Sample running CPU PC and reset/clock control; no writes or halt.
set evidence [open {C:/Users/1569/Desktop/test/migration/2026-11-01-debug/clockfix-pc.txt} w]
connect -url tcp:localhost:3121
targets -set -filter {name == "APU"}
foreach address {0xf8000170 0xf8000240} {puts $evidence [mrd -address-space AP0 $address]}
foreach address {0x80090088 0x80090084 0x80090084 0x80090084 0x80090084} {puts $evidence [mrd -address-space AP1 $address]}
disconnect
close $evidence
exit
