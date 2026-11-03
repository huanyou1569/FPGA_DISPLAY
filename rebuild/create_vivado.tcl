# Vivado 2026.1: recreate in a new directory; --build also synthesizes and routes.
# Run: vivado -mode batch -source rebuild/create_vivado.tcl -tclargs --build
set root [file normalize [file join [file dirname [info script]] ..]]
if {![string match "2026.1*" [version -short]]} { error "Vivado 2026.1 is required" }
set out [file join $root build_submission vivado]
if {[file exists $out]} { error "Output already exists: $out. Choose a fresh extracted copy; no files were deleted." }
create_project vx_display $out -part xc7z020clg400-1
set_property target_language Verilog [current_project]
add_files -norecurse [glob [file join $root test.srcs sources_1 new *.v]]
add_files -norecurse [glob [file join $root test.srcs sources_1 new *.vh]]
set_property include_dirs [list [file join $root test.srcs sources_1 new]] [get_filesets sources_1]
add_files -fileset constrs_1 -norecurse [file join $root test.srcs constrs_1 new test.xdc]
# Copy the BD before generating targets, keeping the submitted source untouched.
set bd_dir [file join $out vx_display.srcs sources_1 bd design_1]
file mkdir $bd_dir
file copy [file join $root test.srcs sources_1 bd design_1 design_1.bd] [file join $bd_dir design_1.bd]
add_files -norecurse [file join $bd_dir design_1.bd]
set bd [get_files design_1.bd]
set_property synth_checkpoint_mode None $bd
update_compile_order -fileset sources_1
open_bd_design $bd
validate_bd_design
generate_target all $bd
add_files -norecurse [make_wrapper -files $bd -top]
set_property top design_1_wrapper [get_filesets sources_1]
set_property strategy Performance_ExplorePostRoutePhysOpt [get_runs impl_1]
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]
foreach {name top runtime file} {
    sim_brush_axi tb_brush_axi 2ms tb_brush_axi.sv
    sim_brush_panel tb_brush_panel 30ms tb_brush_panel.sv
    sim_rotation_timing tb_rotation_timing 10ms tb_rotation_timing.sv
    sim_projection tb_projection 20ms tb_projection.sv
    sim_rotation_feedback tb_rotation_feedback 1800ms tb_rotation_feedback.sv
    sim_brush_reset_chain tb_brush_axi 2ms tb_brush_axi.sv
} {
    create_fileset -simset $name
    add_files -fileset $name -norecurse [file join $root tests rtl $file]
    set_property top $top [get_filesets $name]
    set_property source_set sources_1 [get_filesets $name]
    set_property xsim.simulate.runtime $runtime [get_filesets $name]
}
set_property verilog_define VX_TEST_REAL_RESET [get_filesets sim_brush_reset_chain]
set reset_files [get_files -all -quiet *design_1_brush_reset_0.vhd]
if {[llength $reset_files]} {
    add_files -fileset sim_brush_reset_chain -norecurse $reset_files
}
update_compile_order -fileset sources_1
puts "PROJECT_RECREATED: [get_property DIRECTORY [current_project]]"
if {[lsearch -exact $argv --build] >= 0} {
    launch_runs synth_1 -jobs 4
    wait_on_run synth_1
    if {![string match "*Complete*" [get_property STATUS [get_runs synth_1]]]} { error "Synthesis failed" }
    launch_runs impl_1 -to_step write_bitstream -jobs 4
    wait_on_run impl_1
    if {![string match "*Complete*" [get_property STATUS [get_runs impl_1]]]} { error "Implementation failed" }
    set hw [file join $root build_submission hardware]
    file mkdir $hw
    file copy [file join $out vx_display.runs impl_1 design_1_wrapper.bit] [file join $hw vx_display_small.bit]
    write_hw_platform -fixed -include_bit -file [file join $hw vx_display_small.xsa]
    puts "HARDWARE_BUILD_PASS: $hw"
}
