# =====================================================================
#  test_panel_slow  --  PYNQ-Z2 (XC7Z020-1CLG400C) -> 128x64 HUB75 panel
#  Module name : test_panel_slow        Top file : test.v
#
#  v15 : 14 panel signals only.  These are the same pin numbers that were
#        already wired for the previous panel, so nothing new to run.
#
#  IMPORTANT (Tcl syntax):
#    A '#' only starts a comment at the BEGINNING of a line.
#    Never put a trailing comment after a set_property command --
#    Tcl passes it as an extra argument and the whole command fails,
#    which silently drops the pin constraint and makes write_bitstream
#    fail with DRC NSTD-1 / UCIO-1.
# =====================================================================

# ---------------- system clock : H16 = 125 MHz ----------------
set_property -dict { PACKAGE_PIN H16   IOSTANDARD LVCMOS33 } [get_ports { clk }]
create_clock -name sys_clk_pin -period 8.00 -waveform {0 4} [get_ports { clk }]

# ---------------- slide switches : up = 1, down = 0 ----------------
set_property -dict { PACKAGE_PIN M20   IOSTANDARD LVCMOS33 } [get_ports { sw[0] }]
set_property -dict { PACKAGE_PIN M19   IOSTANDARD LVCMOS33 } [get_ports { sw[1] }]

# ---------------- push buttons : released = 0, pressed = 1 ----------------
set_property -dict { PACKAGE_PIN D19   IOSTANDARD LVCMOS33 } [get_ports { btn[0] }]
set_property -dict { PACKAGE_PIN D20   IOSTANDARD LVCMOS33 } [get_ports { btn[1] }]
set_property -dict { PACKAGE_PIN L20   IOSTANDARD LVCMOS33 } [get_ports { btn[2] }]
set_property -dict { PACKAGE_PIN L19   IOSTANDARD LVCMOS33 } [get_ports { btn[3] }]

# ---------------- on-board LEDs : active high ----------------
set_property -dict { PACKAGE_PIN R14   IOSTANDARD LVCMOS33 } [get_ports { led[0] }]
set_property -dict { PACKAGE_PIN P14   IOSTANDARD LVCMOS33 } [get_ports { led[1] }]
set_property -dict { PACKAGE_PIN N16   IOSTANDARD LVCMOS33 } [get_ports { led[2] }]
set_property -dict { PACKAGE_PIN M14   IOSTANDARD LVCMOS33 } [get_ports { led[3] }]

# =====================================================================
#  Panel connector, 14 signals.  Do NOT change these pin numbers.
#  Connect them to the panel by the NAMES printed on the panel silk.
# =====================================================================

# ---- Pmod A : CLK / LAT / OE / A / B / C / R1 / G1 ----
set_property -dict { PACKAGE_PIN Y18   IOSTANDARD LVCMOS33 } [get_ports { p_clk }]
set_property -dict { PACKAGE_PIN Y19   IOSTANDARD LVCMOS33 } [get_ports { p_lat }]
set_property -dict { PACKAGE_PIN Y16   IOSTANDARD LVCMOS33 } [get_ports { p_oe }]
set_property -dict { PACKAGE_PIN Y17   IOSTANDARD LVCMOS33 } [get_ports { p_addr[0] }]
set_property -dict { PACKAGE_PIN U18   IOSTANDARD LVCMOS33 } [get_ports { p_addr[1] }]
set_property -dict { PACKAGE_PIN U19   IOSTANDARD LVCMOS33 } [get_ports { p_addr[2] }]
set_property -dict { PACKAGE_PIN W18   IOSTANDARD LVCMOS33 } [get_ports { p_r1 }]
set_property -dict { PACKAGE_PIN W19   IOSTANDARD LVCMOS33 } [get_ports { p_g1 }]

# ---- Pmod B : B1 / R2 / G2 / B2 ----
set_property -dict { PACKAGE_PIN W14   IOSTANDARD LVCMOS33 } [get_ports { p_b1 }]
set_property -dict { PACKAGE_PIN Y14   IOSTANDARD LVCMOS33 } [get_ports { p_r2 }]
set_property -dict { PACKAGE_PIN T11   IOSTANDARD LVCMOS33 } [get_ports { p_g2 }]
set_property -dict { PACKAGE_PIN T10   IOSTANDARD LVCMOS33 } [get_ports { p_b2 }]

# ---- Arduino header : D and E, the two extra row address bits ----
set_property -dict { PACKAGE_PIN U13   IOSTANDARD LVCMOS33 } [get_ports { p_addr[3] }]
set_property -dict { PACKAGE_PIN V13   IOSTANDARD LVCMOS33 } [get_ports { p_addr[4] }]

# =====================================================================
#  Index sensor
#
#  PMODB pin 7 = V16.  Pins 1..4 of PMODB are the panel's B1/R2/G2/B2,
#  so 7 is the first free signal pin.  Power it from pin 6 (3.3 V) and
#  pin 5 (GND).  The pull-up keeps the input defined if the module is
#  unplugged, which would otherwise float and chatter.
# =====================================================================
set_property -dict { PACKAGE_PIN V16   IOSTANDARD LVCMOS33 PULLUP true } [get_ports { sensor }]

# PS UART1 via EMIO: PMODB 9 (TX -> module RX), 10 (RX <- module TX).
# 3.3 V logic, common ground. UART0 remains the onboard USB console.
set_property -dict { PACKAGE_PIN V12 IOSTANDARD LVCMOS33 } [get_ports { bt_uart_tx }]
set_property -dict { PACKAGE_PIN W13 IOSTANDARD LVCMOS33 PULLUP true } [get_ports { bt_uart_rx }]
