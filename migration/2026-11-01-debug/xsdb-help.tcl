set evidence [open {C:/Users/1569/Desktop/test/migration/2026-11-01-debug/xsdb-help.txt} w]
puts $evidence [help connect]
puts $evidence [help targets]
puts $evidence [help mrd]
close $evidence
exit
