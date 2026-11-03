# Explicit project: C:/Users/1569/Desktop/test. Read-only target enumeration.
set evidence [open {C:/Users/1569/Desktop/test/migration/2026-11-01-debug/jtag-targets.txt} w]
if {[catch {connect -url tcp:localhost:3121} connection]} {
    puts $evidence "CONNECT_FAILED: $connection"
} else {
    puts $evidence [targets]
    puts $evidence [targets -target-properties]
    disconnect
}
close $evidence
exit
