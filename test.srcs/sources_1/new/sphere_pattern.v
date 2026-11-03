// =====================================================================
//  sphere_pattern.v  --  the ball
//
//  A shell of radius 30, four voxels thick, centred in the volume.
//
//  The STM32 project's ball was 200 points scattered by a Fibonacci
//  spiral at one voxel each.  Scaled up by the same 8/3 everything else
//  uses, each of those points becomes a cube nearly three voxels on a
//  side and the ball stops reading as a ball.  A shell is smoother, it
//  is cheaper, and at this resolution it is what the eye wants.
//
//  ---------------------------------------------------------------------
//  THE SHAPE
//  ---------------------------------------------------------------------
//      ax = |x - 64|      az = |z - 32|      (and ay)
//      d2 = ax*ax + ay*ay + az*az
//      lit  if  28*28 <= d2 <= 32*32
//
//  which is a hollow ball four voxels thick.  Radius 32 is the ceiling
//  here : the volume is only 64 tall, so 32 is all the room there is in
//  z.  The ball therefore fills the height and half the width, exactly
//  like the models.
//
//  ---------------------------------------------------------------------
//  NO MULTIPLIERS, AND SIX CLOCKS
//  ---------------------------------------------------------------------
//  The squares come from small tables.  Multiplying them out instead
//  gave a path nearly 18 ns long against an 8 ns clock, which does not
//  fail as a wrong picture -- it fails as noise.  Do not "simplify" the
//  tables back into multiplies.
//
//  Six registers, matching torus_pattern, because vol_fill primes its
//  shift register by a fixed LAT and every pattern it can select has to
//  agree or the rows tear sideways.
// =====================================================================

module sphere_pattern (
    input  wire        clk,

    input  wire [6:0]  x,
    input  wire [6:0]  y,
    input  wire [5:0]  z,

    output reg  [2:0]  rgb         // {r, g, b}, valid 6 clocks after x/y/z
);

    localparam [2:0] BALL = 3'b011;    // cyan

    // ==================================================================
    //  stage 1 : distance from the middle, per axis
    // ==================================================================
    wire [6:0] ax = (x >= 7'd64) ? (x - 7'd64) : (7'd64 - x);
    wire [6:0] ay = (y >= 7'd64) ? (y - 7'd64) : (7'd64 - y);
    wire [6:0] az = (z >= 6'd32) ? ({1'b0, z} - 7'd32) : (7'd32 - {1'b0, z});

    reg [6:0] p1_ax, p1_ay, p1_az;

    always @(posedge clk) begin
        p1_ax <= ax;
        p1_ay <= ay;
        p1_az <= az;
    end

    // ==================================================================
    //  stage 2 : the squared distance
    // ==================================================================
    wire [13:0] d2 = sq_x[p1_ax] + sq_x[p1_ay] + sq_z[p1_az];

    reg [13:0] p2_d2;

    always @(posedge clk) p2_d2 <= d2;

    // ==================================================================
    //  stage 3 : inside the shell or not
    // ==================================================================
    localparam [13:0] R2_LO = 14'd784;    // 28 * 28
    localparam [13:0] R2_HI = 14'd1024;   // 32 * 32

    wire lit = (p2_d2 >= R2_LO) && (p2_d2 <= R2_HI);

    reg [2:0] p3_rgb;

    always @(posedge clk) p3_rgb <= lit ? BALL : 3'b000;

    // ==================================================================
    //  stages 4, 5 and 6 : padding for latency
    // ==================================================================
    reg [2:0] p4_rgb, p5_rgb;

    always @(posedge clk) begin
        p4_rgb <= p3_rgb;
        p5_rgb <= p4_rgb;
        rgb    <= p5_rgb;
    end

    // ==================================================================
    //  the tables
    // ==================================================================
    reg [13:0] sq_x [0:127];      // i*i
    reg [10:0] sq_z [0:63];       // i*i

    integer i;

    initial begin
        for (i = 0; i < 128; i = i + 1) sq_x[i] = i * i;
        for (i = 0; i <  64; i = i + 1) sq_z[i] = i * i;
    end

endmodule
