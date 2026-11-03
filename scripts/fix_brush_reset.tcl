# Explicit target: C:/Users/1569/Desktop/test/test.xpr, design_1.
if {[file normalize [get_property DIRECTORY [current_project]]] ne [file normalize {C:/Users/1569/Desktop/test}]} {error {Unexpected project root}}
set cell [get_bd_cells brush_reset]
# C_EXT_RESET_HIGH is derived from the PS reset pin's active-low interface.
if {[get_property CONFIG.C_EXT_RESET_HIGH $cell] != 0} {error {PS reset polarity must be active low}}
puts [ipcfg::require $cell [dict create CONFIG.C_AUX_RESET_HIGH 1] {Unused aux_reset_in is tied to zero and must be active high}]
validate_bd_design
set audit [ipcfg::audit_requirements]
puts $audit
if {![string match {REQ:OK *} $audit]} {error {Reset requirements failed}}
save_bd_design
