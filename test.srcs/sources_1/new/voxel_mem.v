// =====================================================================
//  voxel_mem.v  --  the 128 x 128 x 64 volume, 3 bits per voxel
//
//  Eight colours : {r, g, b}, one bit each, exactly the three LED
//  channels the panel has.
//
//  ---------------------------------------------------------------------
//  LAYOUT
//  ---------------------------------------------------------------------
//  Stored one whole x line at a time :
//
//      vol[{z, y}] = 128 bits,   bit i = the voxel at (x = i, y, z)
//
//  so a word read gives every x for one (y, z), and picking a voxel out
//  of it is a 128 : 1 bit mux.  Three of these, one per colour.
//
//  13 address bits, 8192 words :
//
//      waddr[6:0]  = y
//      waddr[12:7] = z
//
//  ---------------------------------------------------------------------
//  WHY THIS SHAPE
//  ---------------------------------------------------------------------
//  The projection engine walks the plane's 128 columns and needs one
//  ARBITRARY voxel per clock.  Storing x as the fast axis turns that
//  into one BRAM read plus a cheap mux, and it is the same shape as
//  frame_buf, so the two halves of the pipeline read alike.
//
//  ---------------------------------------------------------------------
//  SIZE
//  ---------------------------------------------------------------------
//      8192 x 128 = 1048576 bits per colour
//      three colours = 3145728 bits
//
//  which is 96 of the Z020's 140 BRAM36 blocks, about 70 % of them.
//
//  ---------------------------------------------------------------------
//  TWO PORTS, NO ARBITER
//  ---------------------------------------------------------------------
//  One read port and one write port, so the projection can read while a
//  fill or a brush stroke writes.  If both hit the same address on the
//  same clock the read returns whatever the BRAM's write mode gives, and
//  one voxel is briefly wrong -- once, for one phase, then gone.  Not
//  worth the logic to prevent.
// =====================================================================

module voxel_mem (
    input  wire         clk,

    // ---------------- read port : the projection engine ----------------
    input  wire [12:0]  raddr,
    output reg  [127:0] q_r, q_g, q_b,

    // ---------------- write port : fill / brush ----------------
    input  wire         we,
    input  wire [12:0]  waddr,
    input  wire [127:0] w_r, w_g, w_b
);

    reg [127:0] vol_r [0:8191];
    reg [127:0] vol_g [0:8191];
    reg [127:0] vol_b [0:8191];

    always @(posedge clk) begin
        q_r <= vol_r[raddr];
        q_g <= vol_g[raddr];
        q_b <= vol_b[raddr];

        if (we) begin
            vol_r[waddr] <= w_r;
            vol_g[waddr] <= w_g;
            vol_b[waddr] <= w_b;
        end
    end

endmodule
