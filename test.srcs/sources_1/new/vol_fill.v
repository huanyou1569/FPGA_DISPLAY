// =====================================================================
//  vol_fill.v  --  write a whole picture into the voxel volume
//
//  Walks every voxel once, asking a pattern block "what colour is the
//  voxel at (x, y, z) ?", and writes the answer into voxel_mem.
//
//  This is the ONLY thing that writes the volume today.  The snake and
//  the brush will sit beside it: they write a few voxels per tick
//  instead of all of them once.
//
//  ---------------------------------------------------------------------
//  WHY IT IS A STATE MACHINE AND NOT AN `initial` BLOCK
//  ---------------------------------------------------------------------
//  The volume is 1048576 voxels.  Initialising that from an initial
//  block means the synthesiser has to unroll a million-iteration loop
//  at elaboration time, which is slow and easy to get wrong.  Walking
//  it in hardware takes 1064960 clocks -- 8.5 ms at 125 MHz -- and
//  costs nothing.
//
//  ---------------------------------------------------------------------
//  ORDER OF WORK
//  ---------------------------------------------------------------------
//  One 128 bit word per (y, z), built one voxel at a time :
//
//      S_WORD    134 clocks : prime the pattern's pipe, then collect 128
//      S_WR        1 clock  : hand them to voxel_mem
//      S_NEXTW     1 clock  : next (y, z), or done
//
//  136 clocks per word, 8192 words, 8.9 ms for the whole volume.
//
//  The x walk goes 127 DOWN to 0 and each bit is shifted in at position
//  0, so x = 127 goes in first and ends up in bit 127 :
//
//      bit i  =  the voxel at x = i
//
//  That is the order voxel_mem and proj_engine agreed on.  Walking x
//  upwards instead would pack bit i with x = 127 - i and the picture
//  would come out mirrored.
//
//  ---------------------------------------------------------------------
//  THE PATTERN IS PIPELINED, SO THE SHIFT STARTS LATE
//  ---------------------------------------------------------------------
//  torus_pattern is six registers deep : the answer for the voxel asked
//  about on cycle N turns up on cycle N + 6.  pcnt runs 0 .. LAT + 127
//  and px is derived from it, so the x walk itself is unchanged, but
//  nothing is shifted in until pcnt reaches LAT -- the first six cycles
//  are spent priming the pipe.
//
//  LAT MUST MATCH the stage count in torus_pattern.  Get it wrong by one
//  and every voxel lands one x to the side.
//
//  ---------------------------------------------------------------------
//  clear
//  ---------------------------------------------------------------------
//  With `clear` high the pattern is ignored and the volume is erased.
//  Still a full 8.5 ms walk -- erasing is just drawing with nothing.
// =====================================================================

module vol_fill (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,        // one clock pulse : fill once
    input  wire         clear,        // 1 = erase, 0 = use the pattern

    output reg          busy,
    output reg          done,         // one clock pulse when finished

    // ---------------- voxel_mem write port ----------------
    output reg          we,
    output reg  [12:0]  waddr,
    output reg  [127:0] w_r, w_g, w_b,

    // ---------------- pattern lookup, one voxel at a time ----------------
    output wire [6:0]   px,           // x of the voxel being asked about
    output wire [6:0]   py,           // y, straight out of waddr
    output wire [5:0]   pz,           // z, straight out of waddr
    input  wire [2:0]   p_rgb         // valid LAT clocks AFTER px changes
);

    // ------------------------------------------------------------------
    //  the (y, z) of the word being built, and the x inside it
    //
    //  px counts DOWN from 127.  See the bit order note above.
    // ------------------------------------------------------------------
    reg [12:0] wa;
    assign py = wa[6:0];
    assign pz = wa[12:7];

    // ------------------------------------------------------------------
    //  the pattern's pipeline latency
    //
    //  torus_pattern is six registers deep, so the answer for the voxel
    //  asked about on cycle N turns up on cycle N + LAT.  px still walks
    //  127 down to 0, but the word is not shifted until the answers start
    //  arriving -- that is what pcnt is for.
    //
    //  LAT MUST MATCH the number of stages in torus_pattern.  Get it
    //  wrong and every voxel lands one x to the side.
    // ------------------------------------------------------------------
    localparam [7:0] LAT = 8'd6;

    reg  [7:0] pcnt;                  // 0 .. LAT + 127
    wire [7:0] pxf = 8'd127 - pcnt;   // garbage once pcnt passes 127,
                                      // but nothing captures it
    assign px = pxf[6:0];

    wire [2:0] pat = clear ? 3'b000 : p_rgb;

    // ------------------------------------------------------------------
    //  sequencer
    // ------------------------------------------------------------------
    localparam [2:0] S_IDLE  = 3'd0,
                     S_WORD  = 3'd1,
                     S_WR    = 3'd2,
                     S_NEXTW = 3'd3,
                     S_END   = 3'd4;

    reg [2:0] st = 3'd0;

    always @(posedge clk) begin
        if (!rst_n) begin
            st    <= S_IDLE;
            busy  <= 1'b0;
            done  <= 1'b0;
            we    <= 1'b0;
            wa    <= 13'd0;
            pcnt  <= 8'd0;
            waddr <= 13'd0;
            w_r   <= 128'd0; w_g <= 128'd0; w_b <= 128'd0;
        end else begin
            done <= 1'b0;

            case (st)

            S_IDLE: begin
                we <= 1'b0;
                if (start) begin
                    busy <= 1'b1;
                    wa   <= 13'd0;
                    pcnt <= 8'd0;
                    w_r  <= 128'd0; w_g <= 128'd0; w_b <= 128'd0;
                    st   <= S_WORD;
                end
            end

            // ---- LAT clocks to prime the pipe, then 128 to collect ----
            S_WORD: begin
                if (pcnt >= LAT) begin
                    w_r <= {w_r[126:0], pat[2]};
                    w_g <= {w_g[126:0], pat[1]};
                    w_b <= {w_b[126:0], pat[0]};
                end
                if (pcnt == LAT + 8'd127) st   <= S_WR;
                else                      pcnt <= pcnt + 8'd1;
            end

            // ---- one word per colour ----
            S_WR: begin
                we    <= 1'b1;
                waddr <= wa;
                st    <= S_NEXTW;
            end

            // ---- next word, or done ----
            S_NEXTW: begin
                we <= 1'b0;
                if (wa == 13'd8191) begin
                    st <= S_END;
                end else begin
                    wa   <= wa + 13'd1;
                    pcnt <= 8'd0;
                    w_r  <= 128'd0; w_g <= 128'd0; w_b <= 128'd0;
                    st   <= S_WORD;
                end
            end

            S_END: begin
                busy <= 1'b0;
                done <= 1'b1;
                st   <= S_IDLE;
            end

            default: st <= S_IDLE;

            endcase
        end
    end

endmodule
