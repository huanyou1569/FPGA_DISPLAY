# Project-specific correction. Do not apply a whole-board preset: UART1 and PL
# wiring are intentionally customized. Values come from TUL pynq-z2/A.0/preset.xml.
if {[file normalize [get_property DIRECTORY [current_project]]] ne [file normalize {C:/Users/1569/Desktop/test}]} {
    error {Unexpected project root}
}
if {[get_property PART [current_project]] ne {xc7z020clg400-1}} {error {Unexpected part}}
set ps [get_bd_cells processing_system7_0]
set desired [dict create \
 CONFIG.PCW_CRYSTAL_PERIPHERAL_FREQMHZ {50} \
 CONFIG.PCW_APU_PERIPHERAL_FREQMHZ {650} \
 CONFIG.PCW_UART_PERIPHERAL_FREQMHZ {100} \
 CONFIG.PCW_UIPARAM_DDR_FREQ_MHZ {525} \
 CONFIG.PCW_UIPARAM_DDR_PARTNO {MT41J256M16 RE-125} \
 CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_0 {0.0} \
 CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_1 {0.0} \
 CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_2 {0.0} \
 CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_3 {0.0} \
 CONFIG.PCW_UIPARAM_DDR_BOARD_DELAY0 {0.279} \
 CONFIG.PCW_UIPARAM_DDR_BOARD_DELAY1 {0.260} \
 CONFIG.PCW_UIPARAM_DDR_BOARD_DELAY2 {0.085} \
 CONFIG.PCW_UIPARAM_DDR_BOARD_DELAY3 {0.092} \
 CONFIG.PCW_UIPARAM_DDR_TRAIN_WRITE_LEVEL {1} \
 CONFIG.PCW_UIPARAM_DDR_TRAIN_READ_GATE {1} \
 CONFIG.PCW_UIPARAM_DDR_TRAIN_DATA_EYE {1}]
# TUL's legacy preset has negative DQS starting values. Vivado 2026.1 issues
# PSU-1..4 critical warnings for them. Use zero nonnegative training seeds,
# retaining measured board delays and all three runtime training stages.
set receipt [ipcfg::capture {C:/Users/1569/Desktop/test/migration/2026-11-01-debug/ps-clock-accepted.tcldict} \
 [list ipcfg::require $ps $desired {PYNQ-Z2 manual specifies 50MHz PS_CLK; TUL board preset supplies DDR routing and timing}] {REQ:pinned+applied}]
puts $receipt
if {[dict get $receipt status] ne {OK}} {error {PS clock configuration failed; inspect evidence}}
validate_bd_design
set audit [ipcfg::audit_requirements]
puts $audit
if {![string match {REQ:OK *} $audit]} {error {Final PS parameter audit failed}}
save_bd_design
foreach property {PCW_CRYSTAL_PERIPHERAL_FREQMHZ PCW_APU_PERIPHERAL_FREQMHZ PCW_UIPARAM_ACT_DDR_FREQ_MHZ PCW_UART1_UART1_IO PCW_UART0_UART0_IO PCW_USE_M_AXI_GP0} {
    puts "$property=[get_property CONFIG.$property $ps]"
}
