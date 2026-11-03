set xsa {C:/Users/1569/Desktop/test/migration/2026-10-31/hardware/vx_display_ps.xsa}
hsi::open_hw_design $xsa
puts "PROCESSORS:[hsi::get_cells -hier -filter {IP_TYPE == PROCESSOR}]"
puts "HARDWARE:[hsi::get_hw_designs]"
set_dt_param -xsa $xsa -dir {C:/Users/1569/Desktop/test/migration/2026-10-31/evidence/sdt-probe} -debug enable
generate_sdt
