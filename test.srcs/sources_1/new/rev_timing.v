// 120 slices/revolution, target 15 revolutions/second at 125 MHz.
// panel_scan fixed line overhead=840 clocks (col_ofs=3), 32 rows/frame.
// hold_max = period/(120*32)-840, clamped to the scan counter range.
// A sequential divider avoids a large combinational path. The result takes
// 28 clocks and is consumed by panel_scan at a frame boundary.
`include "display_timing.vh"
module rev_timing (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        period_new,    // one clock pulse : a new period arrived
    input  wire        period_ok,     // ...and it is a believable speed
    input  wire [25:0] period,        // clocks per revolution

    output reg  [12:0] hold_max      // -> panel_scan
);

    localparam [25:0] DIVISOR  = `VX_ANGLE_SLICES * 32;
    localparam [12:0] LINE_OH  = 13'd840;    // panel_scan's fixed part

    localparam [12:0] HOLD_DEF = `VX_CLOCK_HZ / (`VX_TARGET_RPS * `VX_ANGLE_SLICES * 32) - LINE_OH;
    // Reported RPM remains independent of these physical scan limits.
    localparam [12:0] HOLD_MIN = 13'd80;
    localparam [12:0] HOLD_MAX = 13'd6000;

    // ------------------------------------------------------------------
    //  shift-and-subtract divider, one quotient bit per clock
    // ------------------------------------------------------------------
    reg [25:0] dv_x    = 26'd0;      // the dividend, shifted left
    reg [13:0] dv_rem  = 14'd0;      // running remainder, always < 2*3840
    reg [25:0] dv_quo  = 26'd0;      // the quotient, shifted in
    reg [4:0]  dv_i    = 5'd0;       // 0 .. 26
    reg        dv_run  = 1'b0;

    wire [13:0] rem_sh = {dv_rem[12:0], dv_x[25]};
    wire        ge     = (rem_sh >= DIVISOR[13:0]);
    wire [13:0] rem_nx = ge ? (rem_sh - DIVISOR[13:0]) : rem_sh;

    // ------------------------------------------------------------------
    //  POWER UP.  rst_n is HIGH at power up, because nothing is pressed,
    //  so the reset branch below NEVER RUNS on a cold start.  Everything
    //  therefore has to come up right from the flip-flop's own initial
    //  value -- which is the same trap that once left the projection
    //  engine idle for ever, and would here leave hold_max at 0 : a line
    //  of 840 clocks, a frame 8x too short and a picture nobody can read.
    // ------------------------------------------------------------------
    initial begin
        dv_x     = 26'd0;
        dv_rem   = 14'd0;
        dv_quo   = 26'd0;
        dv_i     = 5'd0;
        dv_run   = 1'b0;
        hold_max = HOLD_DEF;
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            dv_x     <= 26'd0;
            dv_rem   <= 14'd0;
            dv_quo   <= 26'd0;
            dv_i     <= 5'd0;
            dv_run   <= 1'b0;
            hold_max <= HOLD_DEF;
        end else if (!period_ok) begin
            // Restore the same 15 rps timing used by the fallback reference.
            dv_run <= 1'b0;
            hold_max <= HOLD_DEF;
        end else if (!dv_run) begin
            if (period_new && period_ok) begin
                dv_x   <= period;
                dv_rem <= 14'd0;
                dv_quo <= 26'd0;
                dv_i   <= 5'd0;
                dv_run <= 1'b1;
            end
        end else if (dv_i == 5'd26) begin
            // the quotient is complete : it ran 26 shifts
            dv_run <= 1'b0;
            if (dv_quo < (LINE_OH + HOLD_MIN)) begin
                hold_max <= HOLD_MIN;
            end else if (dv_quo > (LINE_OH + HOLD_MAX)) begin
                hold_max <= HOLD_MAX;
            end else begin
                hold_max <= dv_quo[12:0] - LINE_OH;
            end
        end else begin
            dv_rem <= rem_nx;
            dv_quo <= {dv_quo[24:0], ge};
            dv_x   <= {dv_x[24:0], 1'b0};
            dv_i   <= dv_i + 5'd1;
        end
    end

endmodule
