// =====================================================================
//  content_test.v  --  a stand-in for the voxel store
//
//  This is the block the snake and the brush will later replace with a
//  real BRAM volume.  It answers the same question they will:
//
//      "what colour is the voxel at (x, y, z) ?"
//
//  It answers with a formula instead of a memory, so there is nothing
//  to load and nothing to initialise -- which is exactly what makes it
//  a good first test of the projection path.
//
//  ---------------------------------------------------------------------
//  WHAT IT DRAWS
//  ---------------------------------------------------------------------
//  A spherical shell of radius 30 centred on (64, 64, 32), with
//  everything at x < 64 REMOVED.
//
//  Why that shape:
//
//   * a plain sphere looks identical at every phase, so it proves the
//     projection is stable but says nothing about the phase sweep
//   * with the x < 64 half cut away the visible arc changes with the
//     phase -- full ring, then half, then nothing, then half again --
//     so one slow sweep of the 100 phases shows the rotation working
//
//  Colour is split top/bottom so the vertical mapping is obvious:
//      z >= 32  ->  blue
//      z <  32  ->  red
//
//  ---------------------------------------------------------------------
//  HOW THE RANGE TEST IS DONE WITHOUT MULTIPLIES
//  ---------------------------------------------------------------------
//  d2 = (x-64)^2 + (y-64)^2 + (z-32)^2
//
//  The three squares come from small lookup tables built at power up,
//  so the per-voxel work is two additions and two comparisons.
// =====================================================================

module content_test (
    input  wire [6:0] x,
    input  wire [6:0] y,
    input  wire [5:0] z,
    output wire [2:0] rgb          // {r, g, b} -- each bit is one LED
);

    // ------------------------------------------------------------------
    //  squared-distance lookup tables
    // ------------------------------------------------------------------
    reg [12:0] xy_sq [0:127];      // (i - 64)^2   largest is 64*64 = 4096
    reg [10:0] z_sq  [0:63];       // (i - 32)^2   largest is 32*32 = 1024

    integer i;
    initial begin
        for (i = 0; i < 128; i = i + 1) xy_sq[i] = (i - 64) * (i - 64);
        for (i = 0; i <  64; i = i + 1) z_sq [i] = (i - 32) * (i - 32);
    end

    // largest sum is 4096 + 4096 + 1024 = 9216, so 14 bits
    wire [13:0] d2 = { 1'b0, xy_sq[x]}
                   + { 1'b0, xy_sq[y]}
                   + { 3'b000, z_sq[z]};

    // ------------------------------------------------------------------
    //  the shell : 28.5^2 <= d2 <= 31.5^2  gives a ring about 3 voxels thick
    // ------------------------------------------------------------------
    localparam [13:0] R2_LO = 14'd810;
    localparam [13:0] R2_HI = 14'd990;

    wire in_shell = (d2 >= R2_LO) && (d2 <= R2_HI);
    wire in_half  = (x >= 7'd64);          // the cut-away half
    wire lit      = in_shell & in_half;

    assign rgb = lit ? (z[5] ? 3'b001 : 3'b100)   // blue above, red below
                     : 3'b000;

endmodule
