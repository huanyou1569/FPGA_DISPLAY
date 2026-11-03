# Run through Vivado MCP with test.xpr/design_1 open. Project root is explicit.
if {[file normalize [get_property DIRECTORY [current_project]]] ne [file normalize {C:/Users/1569/Desktop/test}]} {
    error {Unexpected project root; brush integration stopped}
}
connect_bd_intf_net [get_bd_intf_pins processing_system7_0/M_AXI_GP0] [get_bd_intf_pins brush_interconnect/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins brush_interconnect/M00_AXI] [get_bd_intf_pins brush_axi_0/S_AXI]
connect_bd_net [get_bd_ports clk] [get_bd_pins processing_system7_0/M_AXI_GP0_ACLK] \
    [get_bd_pins brush_interconnect/ACLK] [get_bd_pins brush_interconnect/S00_ACLK] \
    [get_bd_pins brush_interconnect/M00_ACLK] [get_bd_pins brush_axi_0/s_axi_aclk] \
    [get_bd_pins brush_reset/slowest_sync_clk]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_RESET0_N] [get_bd_pins brush_reset/ext_reset_in]
puts [ipcfg::require [get_bd_cells brush_reset] [dict create CONFIG.C_AUX_RESET_HIGH 1] {Unused auxiliary reset is tied to zero}]
connect_bd_net [get_bd_pins brush_one/dout] [get_bd_pins brush_reset/dcm_locked]
connect_bd_net [get_bd_pins brush_zero/dout] [get_bd_pins brush_reset/aux_reset_in] [get_bd_pins brush_reset/mb_debug_sys_rst]
connect_bd_net [get_bd_pins brush_reset/interconnect_aresetn] [get_bd_pins brush_interconnect/ARESETN]
connect_bd_net [get_bd_pins brush_reset/peripheral_aresetn] [get_bd_pins brush_interconnect/S00_ARESETN] \
    [get_bd_pins brush_interconnect/M00_ARESETN] [get_bd_pins brush_axi_0/s_axi_aresetn]
foreach {panel_pin bridge_pin} {
    brush_rgb rgb
    brush_mode mode_active
    brush_mode_set mode_set
    brush_mode_value mode_value
    canvas_changed canvas_changed
    canvas_mode_ready canvas_ready
    canvas_commit_pending commit_pending
    canvas_swap_safe canvas_swap_safe
    brush_px px
    brush_py py
    brush_pz pz
    revolution_count revolution_count
    revolution_period revolution_period
    sensor_locked sensor_locked
    period_valid period_valid
    sync_flags sync_flags
    sync_edges sync_edges
    sync_accepted sync_accepted
    sync_rejected sync_rejected
    scan_period scan_period
} {
    connect_bd_net [get_bd_pins test_panel_0/$panel_pin] [get_bd_pins brush_axi_0/$bridge_pin]
}
set_property -dict [list CONFIG.FREQ_HZ 125000000] [get_bd_ports clk]
assign_bd_address
validate_bd_design
puts [ipcfg::audit_requirements]
save_bd_design
puts "BRUSH_ADDRESS_SEGMENTS:[get_bd_addr_segs -of_objects [get_bd_intf_pins brush_axi_0/S_AXI]]"
