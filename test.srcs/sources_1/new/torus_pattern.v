// =====================================================================
//  torus_pattern.v  --  the donut, straight from the STM32 project
//
//  Ported from interaction_sphere.c (IS_SHAPE_TORUS).  It answers the
//  same question vol_fill asks of content_test :
//
//      "what colour is the voxel at (x, y, z) ?"
//
//  ---------------------------------------------------------------------
//  THE SHAPE  (identical maths, only the constants were rescaled)
//  ---------------------------------------------------------------------
//      dx = x - cx                       cy, cz likewise
//      D2 = dx*dx + dy*dy
//      s  = floor(sqrt(D2))              the distance out from the axis
//      d  = s - R                        how far that is from the ring
//      lit  if  |d*d + dz*dz - r*r| <= shell
//
//  That last tolerance is what makes the tube a shell a few voxels thick
//  instead of a mathematical surface -- a voxel display needs the
//  thickness or the ring falls apart into dots.  See the note below on
//  why it is 4*r here and plain r in the original.
//
//  ---------------------------------------------------------------------
//  THE ZERO IS OFF THE AXIS
//  ---------------------------------------------------------------------
//  The original puts the ring's centre at x = 18 in a 32 wide volume
//  whose axis is at 16 : two units off.  That is deliberate.  A torus
//  centred on the axis is rotationally symmetric, so EVERY phase of the
//  sweep would look exactly the same and the display would look flat.
//  Two units of offset breaks that.  Rescaled by the same factor as
//  everything else, 2 becomes 8, so the centre sits at x = 72.
//
//  ---------------------------------------------------------------------
//  RESCALING  x4
//  ---------------------------------------------------------------------
//  Original volume 32 x 32 x 24, this one 128 x 128 x 64.
//
//      R      8  ->  32        r      3  ->  12
//      centre 18 -> 72  (and y 16 -> 64, z 12 -> 32)
//
//  The original's tolerance was `threshold = r_cur`, which makes the
//  shell ONE voxel thick in a 32 wide volume :
//
//      w = sqrt(r^2 + r) - sqrt(r^2 - r)  =  sqrt(12) - sqrt(6)  =  1.0
//
//  Scaled by four that shell has to become four voxels, or the donut
//  arrives as a hairline instead of a tube.  The tolerance that gives
//  w = 4 at r = 12 is 4 * r :
//
//      w = sqrt(144 + 48) - sqrt(144 - 48)  =  13.86 - 9.80  =  4.06
//
//  which is also the original's proportion, one sixth of the tube's
//  diameter, shell to shell.
//
//  ---------------------------------------------------------------------
//  WHY THIS MODULE IS CLOCKED  --  read this before changing anything
//  ---------------------------------------------------------------------
//  The first version of this file was pure combinational, like
//  content_test.  It did not even light the panel wrongly -- it lit it
//  NOISILY, because the path through it was 18 ns against an 8 ns clock
//  and the answer arrived whenever it felt like it.
//
//      Slack -10.219 ns,  28 logic levels,  13 CARRY4
//
//  The thirteen carry chains were five multipliers.  Both problems are
//  fixed here :
//
//    * every square is a lookup table, not a multiply
//    * the rest is cut into six registered stages
//
//  SIX clocks of latency.  vol_fill knows this and primes the pipe, so
//  the voxel it shifts in is always the voxel it asked for.  If you
//  change the number of stages you must change LAT in vol_fill to match.
//
//  ---------------------------------------------------------------------
//  NO SQUARE ROOT UNIT
//  ---------------------------------------------------------------------
//  sqrt(D2) is a 4096 entry table, because D2 only matters while it is
//  near (R + r)^2 -- anything past that is far outside the tube.  D2 can
//  reach 72*72 + 64*64 = 9280, so anything above 4095 is clamped to 64,
//  bigger than any R + r the zoom allows and therefore never lit.
// =====================================================================

module torus_pattern (
    input  wire        clk,

    input  wire [6:0]  x,
    input  wire [6:0]  y,
    input  wire [5:0]  z,

    input  wire [6:0]  r_major,      // ring radius   (32 = the original 8)
    input  wire [6:0]  r_minor,      // tube radius   (12 = the original 3)

    output reg  [2:0]  rgb           // {r, g, b} -- valid 6 clocks later
);

    // ------------------------------------------------------------------
    //  the ring's centre : the axis, pushed 8 units along +x
    // ------------------------------------------------------------------
    localparam [6:0] CX = 7'd72;
    localparam [6:0] CY = 7'd64;
    localparam [5:0] CZ = 6'd32;

    // ==================================================================
    //  stage 1 : how far x, y, z are from the ring's centre
    // ==================================================================
    wire [6:0] ax = (x >= CX) ? (x - CX) : (CX - x);
    wire [6:0] ay = (y >= CY) ? (y - CY) : (CY - y);
    wire [6:0] az = (z >= CZ) ? ({1'b0, z} - {1'b0, CZ})
                              : ({1'b0, CZ} - {1'b0, z});

    reg [6:0] s1_ax, s1_ay, s1_az;

    // ==================================================================
    //  stage 2 : D2 = ax*ax + ay*ay
    // ==================================================================
    wire [13:0] d2 = sq_x[s1_ax] + sq_x[s1_ay];

    reg [13:0] s2_d2;
    reg [6:0]  s2_az;

    // ==================================================================
    //  stage 3 : s = floor(sqrt(D2))
    // ==================================================================
    wire [6:0] s = (s2_d2 > 14'd4095) ? 7'd64 : sq_root[s2_d2[11:0]];

    reg [6:0] s3_s;
    reg [6:0] s3_az;

    // ==================================================================
    //  stage 4 : how far s is from the ring's radius
    // ==================================================================
    wire [6:0] dd = (s3_s >= r_major) ? (s3_s - r_major)
                                      : (r_major - s3_s);

    reg [6:0] s4_dd;
    reg [6:0] s4_az;

    // ==================================================================
    //  stage 5 : the squared distance from the middle of the tube
    // ==================================================================
    wire [13:0] q = sq_x[s4_dd] + sq_z[s4_az];

    reg [13:0] s5_q;

    // ==================================================================
    //  stage 6 : the shell test and the colour
    // ==================================================================
    wire [13:0] r2    = {4'd0, sq_r[r_minor[4:0]]};   // r*r
    wire [14:0] shell = {r_minor, 2'b00};             // r * 4

    wire [14:0] lim_hi = {1'b0, r2} + {6'd0, shell};  // r2 + shell
    wire [14:0] q15    = {1'b0, q};
    wire [14:0] q15_lo = {1'b0, q} + {6'd0, shell};   // q  + shell

    // |q - r2| <= shell   written so nothing ever goes negative
    wire lit = (q15 <= lim_hi) && (q15_lo >= {1'b0, r2});

    // The original cycled through six colours with a key press.  The show
    // only ever wants red, and the SIZE comes in from the sequencer, so
    // what used to be the colour port is now part of r_major/r_minor.
    localparam [2:0] RED = 3'b100;

    // ==================================================================
    //  the pipe
    // ==================================================================
    always @(posedge clk) begin
        s1_ax <= ax;
        s1_ay <= ay;
        s1_az <= az;

        s2_d2 <= d2;
        s2_az <= s1_az;

        s3_s  <= s;
        s3_az <= s2_az;

        s4_dd <= dd;
        s4_az <= s3_az;

        s5_q  <= q;

        rgb   <= lit ? RED : 3'b000;
    end

    // ==================================================================
    //  the tables
    // ==================================================================
    reg [13:0] sq_x    [0:127];      // i*i,   i up to 127
    reg [10:0] sq_z    [0:63];       // i*i,   i up to  63
    reg [9:0]  sq_r    [0:31];       // i*i,   i up to  31
    reg [6:0]  sq_root [0:4095];     // floor(sqrt(i))

    integer i, v;

    initial begin
        for (i = 0; i < 128; i = i + 1) sq_x[i] = i * i;
        for (i = 0; i <  64; i = i + 1) sq_z[i] = i * i;
        for (i = 0; i <  32; i = i + 1) sq_r[i] = i * i;

        // walk i upwards, bumping v whenever i reaches the next square,
        // so v is floor(sqrt(i)) at every step
        v = 0;
        for (i = 0; i < 4096; i = i + 1) begin
            if (i >= (v + 1) * (v + 1)) v = v + 1;
            sq_root[i] = v;
        end
    end

endmodule
