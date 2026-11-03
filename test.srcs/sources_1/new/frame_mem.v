// =====================================================================
//  frame_mem.v  --  the picture store for the 128x64 panel
//
//  One picture = 64 rows x 128 columns x 3 colours = 24576 bits.
//
//  The scan engine asks for one row per line cycle and this module
//  answers two rows at once, because a 1/32-scan HUB75 panel lights
//  row `line` and row `line + 32` from the same address:
//
//      d_r1/g1/b1  ->  row `line`           (top    half, 0 .. 31)
//      d_r2/g2/b2  ->  row `line + 32`      (bottom half, 32 .. 63)
//
//  ---------------------------------------------------------------------
//  BIT ORDER
//  ---------------------------------------------------------------------
//  Column 0 is stored in bit 127 and is shifted out first, so
//
//      bit 127 = column 0        bit 0 = column 127
//
//  If the picture turns out mirrored on the real panel, flip sw[0] --
//  do NOT rewire the data.  (sw[0] reverses the shift order inside
//  panel_scan.)  If it turns out upside down instead, flip sw[1], which
//  is the flip_v input handled by the read port below.
//
//  ---------------------------------------------------------------------
//  STAGE 1 : a built-in test pattern
//  ---------------------------------------------------------------------
//      RED    8x8 checkerboard over the whole panel
//      GREEN  1 pixel border
//      BLUE   one 8x8 block in the corner of the stored image
//
//  What it tells you at a glance:
//      blue block in the top left  -> rows and columns both start at 0
//      blue block in the top right -> the panel wants sw[0] flipped
//      green border complete       -> all 128 columns and 64 rows arrive
//      no red checkerboard         -> a data line or a stitch is wrong
//
//  ---------------------------------------------------------------------
//  STAGE 3 : many pictures
//  ---------------------------------------------------------------------
//  To hold a whole animation, change the memory declarations only:
//
//      reg [127:0] mem_r [0:63];        ->  reg [127:0] mem_r [0:4479];
//      ... and feed `frame` from a counter that counts frame_done pulses.
//
//  The read port below already addresses {frame, row}, so nothing else
//  has to change.
// =====================================================================

module frame_mem (
    input  wire         clk,
    input  wire [6:0]   frame,        // which picture (only 0 exists so far)
    input  wire [4:0]   line,         // scan address 0 .. 31
    input  wire         flip_v,       // 1 = the panel's rows run bottom to top

    output reg  [127:0] d_r1, d_g1, d_b1,   // top    half, row = line
    output reg  [127:0] d_r2, d_g2, d_b2    // bottom half, row = line + 32
);

    // ------------------------------------------------------------------
    //  the store
    // ------------------------------------------------------------------
    reg [127:0] mem_r [0:63];
    reg [127:0] mem_g [0:63];
    reg [127:0] mem_b [0:63];

    // ------------------------------------------------------------------
    //  read port
    //
    //  All arithmetic is done in 6 bits : `line` is 0..31 and
    //  `line + 32` is 32..63.  Doing the + 32 in 5 bits would wrap
    //  31 + 32 back to 31 and the bottom half would repeat the top.
    //
    //  THIS PANEL'S ROWS RUN BOTTOM TO TOP, so with flip_v set the whole
    //  64 row picture is mirrored :
    //      R1 (scan address a) shows stored row 63 - a
    //      R2 (scan address a) shows stored row 31 - a
    //  (no flip : R1 shows row a, R2 shows row a + 32)
    // ------------------------------------------------------------------
    wire [5:0] l6 = {1'b0, line};

    wire [5:0] row_a = flip_v ? (6'd63 - l6) : l6;            // -> R1
    wire [5:0] row_b = flip_v ? (6'd31 - l6) : (l6 + 6'd32);  // -> R2

    wire [12:0] adr_a = {frame, row_a};
    wire [12:0] adr_b = {frame, row_b};

    always @(posedge clk) begin
        d_r1 <= mem_r[adr_a];
        d_g1 <= mem_g[adr_a];
        d_b1 <= mem_b[adr_a];
        d_r2 <= mem_r[adr_b];
        d_g2 <= mem_g[adr_b];
        d_b2 <= mem_b[adr_b];
    end

    // ==================================================================
    //  TEST PATTERN   --   replace this block with real picture data
    // ==================================================================
    integer     i, j;
    reg         br, bg, bb;
    reg [127:0] wr, wg, wb;

    initial begin
        for (i = 0; i < 64; i = i + 1) begin
            wr = 128'd0;
            wg = 128'd0;
            wb = 128'd0;
            for (j = 0; j < 128; j = j + 1) begin
                if ((i < 8) && (j < 8)) begin
                    // corner marker -- blue, and it covers the border there
                    br = 1'b0; bg = 1'b0; bb = 1'b1;
                end else if ((i == 0) || (i == 63) || (j == 0) || (j == 127)) begin
                    // one pixel border -- green
                    br = 1'b0; bg = 1'b1; bb = 1'b0;
                end else begin
                    // interior -- red 8x8 checkerboard
                    br = (((i / 8) + (j / 8)) % 2) == 0;
                    bg = 1'b0; bb = 1'b0;
                end
                wr = {wr[126:0], br};       // new bit lands in bit 0,
                wg = {wg[126:0], bg};       // so j = 0 ends up in bit 127
                wb = {wb[126:0], bb};
            end
            mem_r[i] = wr;
            mem_g[i] = wg;
            mem_b[i] = wb;
        end
    end
    // ==================================================================
    //  END OF TEST PATTERN
    // ==================================================================

endmodule
