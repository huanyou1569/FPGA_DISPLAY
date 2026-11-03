// =====================================================================
//  frame_buf.v  --  the picture store, now writable and double buffered
//
//  Same job as the old frame_mem.v, with two changes:
//
//    * the contents are WRITTEN by the projection engine instead of
//      being built from a fixed test pattern
//    * there are TWO pictures side by side, so the projection can fill
//      the next one while the panel is still showing the current one
//
//  ---------------------------------------------------------------------
//  LAYOUT
//  ---------------------------------------------------------------------
//      fb[{buffer, row}] = {b[127:0], g[127:0], r[127:0]}
//
//  128 entries : 2 buffers x 64 rows, each entry one whole row of all
//  three colours.  Both the projection and the panel work a row at a
//  time, so one wide word per row is the natural shape.
//
//  ---------------------------------------------------------------------
//  BOTH HALVES AT ONCE
//  ---------------------------------------------------------------------
//  A 1/32 scan lights row `line` and row `line + 32` from the same
//  address, so the panel asks for two rows every line cycle.  The two
//  reads are issued from the same port; `line` is stable for the whole
//  line cycle (two thousand clocks) so there is no hurry.
//
//  `flip_v` maps the scan address to the stored row, exactly as the old
//  frame_mem did -- this panel's rows run bottom to top.
// =====================================================================

module frame_buf (
    input  wire         clk,

    // ---------------- read port : the scan engine ----------------
    input  wire         disp_buf,     // which picture is on screen
    input  wire [4:0]   line,         // scan address 0 .. 31
    input  wire         flip_v,
    output wire [127:0] d_r1, d_g1, d_b1,   // row `line`
    output wire [127:0] d_r2, d_g2, d_b2,   // row `line + 32`

    // ---------------- write port : the projection engine ----------------
    input  wire         we,
    input  wire         wbuf,
    input  wire [5:0]   wrow,
    input  wire [127:0] w_r, w_g, w_b
);

    reg [383:0] fb [0:127];

    wire [5:0] row_a = flip_v ? (6'd63 - {1'b0, line}) : {1'b0, line};
    wire [5:0] row_b = flip_v ? (6'd31 - {1'b0, line}) : ({1'b0, line} + 6'd32);

    reg [383:0] qa, qb;

    always @(posedge clk) begin
        qa <= fb[{disp_buf, row_a}];
        qb <= fb[{disp_buf, row_b}];
        if (we) fb[{wbuf, wrow}] <= {w_b, w_g, w_r};
    end

    assign {d_b1, d_g1, d_r1} = qa;
    assign {d_b2, d_g2, d_r2} = qb;

endmodule
