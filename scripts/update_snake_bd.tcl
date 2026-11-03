# Explicit project root; refresh widened 2-bit mode RTL and add qualified canvas input.
if {[file normalize [get_property DIRECTORY [current_project]]] ne [file normalize {C:/Users/1569/Desktop/test}]} {
    error {Unexpected project root; snake integration stopped}
}
update_compile_order -fileset sources_1
open_bd_design {C:/Users/1569/Desktop/test/test.srcs/sources_1/bd/design_1/design_1.bd}
update_module_reference [get_ips design_1_test_panel_0_0]
update_module_reference [get_ips design_1_brush_axi_0_0]
if {![llength [get_bd_nets -of_objects [get_bd_pins test_panel_0/canvas_mode_ready]]]} {
    connect_bd_net [get_bd_pins brush_axi_0/canvas_ready] [get_bd_pins test_panel_0/canvas_mode_ready]
}
foreach pin {test_panel_0/brush_mode test_panel_0/brush_mode_value brush_axi_0/mode_active brush_axi_0/mode_value} {
    if {[get_property LEFT [get_bd_pins $pin]] != 1} { error "Expected 2-bit mode at $pin" }
}
validate_bd_design
save_bd_design
generate_target all [get_files {C:/Users/1569/Desktop/test/test.srcs/sources_1/bd/design_1/design_1.bd}]
