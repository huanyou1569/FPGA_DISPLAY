// =====================================================================
//  proj_engine.v  --  projects the voxel volume onto the rotating plane
//
//  One pass = one phase = one complete 128x64 picture, written into the
//  frame buffer.  The picture is exactly what the physical plane would
//  see if it were standing at that angle: for every panel column it
//  samples one vertical line of voxels through the volume.
//
//  ---------------------------------------------------------------------
//  THE MAPPING  (same shape as the STM32 project's volume_to_ws2812.c)
//  ---------------------------------------------------------------------
//      dx   = column * 2 - 127          (the axis is between col 63 and 64)
//      x    = 64 + (dx * cos) >> 16
//      y    = 64 - (dx * sin) >> 16
//      z    = panel row, straight through
//
//  x and y are clamped to the volume, z never needs to be.
//
//  The original ran 32 strips over a 32-wide volume and wrote
//  `strip * 2 - 31`; this panel has 128 columns over a 128-wide volume,
//  so the same expression becomes `column * 2 - 127`.  The factor of two
//  is what compensates Q15 (values scaled by 32767) against the >> 16.
//
//  ---------------------------------------------------------------------
//  WHY IT IS SO CHEAP
//  ---------------------------------------------------------------------
//  x and y depend only on (phase, column), never on z.  So they are
//  worked out ONCE per phase into a 128 entry table, and the 64 rows
//  just read that table.  Per phase that is
//
//      128 multiplies          (one per column)
//      64 x 128 voxel reads    (one per voxel)
//
//  about 8600 clocks, 69 us at 125 MHz.  A frame lasts 520 us, so it
//  finishes with three quarters of the frame still to spare.
//
//  ---------------------------------------------------------------------
//  TWO TIMING TRAPS, BOTH ALREADY SPRUNG INCE
//  ---------------------------------------------------------------------
//  This module ran for three hardware builds with two setup violations
//  in it.  Neither showed up as a wrong picture -- they showed up as
//  noise, which is far harder to read.  They are fixed here; do not put
//  them back :
//
//   *  THE COLUMN TABLE IS BUILT THROUGH A PIPELINE.
//      c -> dx -> DSP multiply -> shift -> clamp -> xy_tab was 10.3 ns
//      against an 8 ns clock, and 3.66 ns of that was the DSP48 alone.
//      The multiply's result is now registered (m_px/m_py/m_c) and the
//      shift/clamp and the high-fanout table write have separate registers.
//      S_XY runs 130 cycles: 128 columns plus two flush cycles.
//
//   *  THE VOXEL PICKER USES A REGISTERED x.
//      Reading x straight out of xy_tab in front of the 128:1 voxel mux
//      made a 13 ns path.  `xl` holds it one cycle early instead; the
//      table has been finished for a whole state by then.
//
//  ---------------------------------------------------------------------
//  READING THE VOLUME : WHY THERE IS ANOTHER PIPELINE
//  ---------------------------------------------------------------------
//  voxel_mem answers one clock after its address, so the address has to
//  be issued one column EARLY.  The table already knows every column, so
//  during the cycle that consumes column c the engine also issues the
//  address of column c + 1 :
//
//      cycle n   : counter c, vq holds the word for column c,
//                  xl picks the voxel out of it,
//                  vaddr <= address of column c + 1
//
//  The first address of a row is issued one cycle before the row starts,
//  in S_XYEND and in S_NEXT.
//
//  ---------------------------------------------------------------------
//  BIT ORDER
//  ---------------------------------------------------------------------
//  Column 0 must end up in bit 127 of the row word, because that is
//  what frame_buf and panel_scan agreed on.  Shifting column 0 in first
//  and letting it walk up the register puts it there after 128 shifts.
// =====================================================================

module proj_engine (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,        // one clock pulse : project one frame
    input  wire [7:0]   phase,        // 0 .. 119

    output reg          busy,
    output reg          done,         // one clock pulse when the frame is ready

    // ---------------- volume read port ----------------
    output reg  [12:0]  vaddr,        // {z, y} -- issued one column early
    input  wire [127:0] vq_r, vq_g, vq_b,

    // ---------------- frame buffer write port ----------------
    output reg          fb_we,
    output reg  [5:0]   fb_row,
    output reg  [127:0] w_r, w_g, w_b
);

    // ------------------------------------------------------------------
    //  sine and cosine for the phase being drawn
    // ------------------------------------------------------------------
    wire signed [15:0] cos_v, sin_v;

    sincos_rom u_sincos (
        .clk   (clk),
        .phase (phase),
        .cos_v (cos_v),
        .sin_v (sin_v)
    );

    // ------------------------------------------------------------------
    //  the (x, y) of every column, rebuilt once per phase
    //
    //  256 entries even though only 128 are used : the pipeline writes
    //  with an 8 bit address and one extra column slips past the end of
    //  S_XY.  It never lands anywhere real.
    // ------------------------------------------------------------------
    reg [13:0] xy_tab [0:255];        // {x[6:0], y[6:0]}

    // ------------------------------------------------------------------
    //  column address and the geometry for it
    //
    //  c is eight bits because S_XY needs two columns past 127 to flush
    //  the pipeline.  That last column computes nonsense, and nothing
    //  reads it.
    // ------------------------------------------------------------------
    reg  [7:0]        c;
    wire signed [9:0] dx_i = {1'b0, c, 1'b0} - 10'sd127;   // c*2 - 127

    wire signed [24:0] px = dx_i * cos_v;
    wire signed [24:0] py = dx_i * sin_v;

    // ---- stage 1 : the multiply, registered ----
    // 3.66 ns of DSP48 lives here.  Splitting after it is what takes the
    // path from 10.3 ns to two comfortable halves.
    reg signed [24:0] m_px, m_py;
    reg [7:0]         m_c;

    always @(posedge clk) begin
        m_px <= px;
        m_py <= py;
        m_c  <= c;
    end

    // ---- stage 2 : shift, bias and clamp ----
    wire signed [24:0] ox = (m_px + 25'sd32768) >>> 16;     // (dx*cos) >> 16
    wire signed [24:0] oy = (m_py + 25'sd32768) >>> 16;

    wire signed [24:0] xs = 25'sd64 + ox;
    wire signed [24:0] ys = 25'sd64 - oy;

    wire [6:0] xc = (xs < 25'sd0)   ? 7'd0
                  : (xs > 25'sd127) ? 7'd127
                  : xs[6:0];

    wire [6:0] yc = (ys < 25'sd0)   ? 7'd0
                  : (ys > 25'sd127) ? 7'd127
                  : ys[6:0];

    // Separate coordinate arithmetic from the high-fanout table write.
    // The former direct DSP -> clamp -> 256-entry table path missed 125MHz
    // by 19ps after the three-mode integration. One extra flush cycle keeps
    // the exact same 128 sampled coordinates and panel scan interval.
    reg [13:0] xy_value;
    reg [7:0] xy_column;
    always @(posedge clk) begin
        xy_value <= {xc,yc};
        xy_column <= m_c;
    end

    // ------------------------------------------------------------------
    //  the volume read pipeline
    // ------------------------------------------------------------------
    wire [7:0] cnxt = (c == 8'd127) ? 8'd0 : (c + 8'd1);

    // x of the column being consumed.  REGISTERED rather than read out of
    // xy_tab on the fly : see the timing note at the top.
    reg [6:0] xl;

    wire [2:0] rgb_now = { vq_r[xl], vq_g[xl], vq_b[xl] };

    // ------------------------------------------------------------------
    //  the row being built
    // ------------------------------------------------------------------
    reg [5:0]   zc;
    reg [127:0] acc_r, acc_g, acc_b;

    // ------------------------------------------------------------------
    //  sequencer
    // ------------------------------------------------------------------
    localparam [2:0] S_IDLE  = 3'd0,
                     S_XY    = 3'd1,   // fill the (x,y) table
                     S_XYEND = 3'd2,   // set up row 0, prime the read
                     S_COL   = 3'd3,   // one voxel per clock
                     S_WR    = 3'd4,   // hand the row to the frame buffer
                     S_NEXT  = 3'd5,   // next row
                     S_END   = 3'd6;

    reg [2:0] st = 3'd0;

    always @(posedge clk) begin
        if (!rst_n) begin
            st    <= S_IDLE;
            busy  <= 1'b0;
            done  <= 1'b0;
            fb_we <= 1'b0;
            c     <= 8'd0;
            zc    <= 6'd0;
            vaddr <= 13'd0;
            xl    <= 7'd0;
            fb_row <= 6'd0;
            w_r   <= 128'd0; w_g <= 128'd0; w_b <= 128'd0;
            acc_r <= 128'd0; acc_g <= 128'd0; acc_b <= 128'd0;
        end else begin
            done <= 1'b0;

            // ---- stage 3 : write already computed coordinates ----
            // runs every clock; the state gate is what makes it legal.
            if (st == S_XY) xy_tab[xy_column] <= xy_value;

            case (st)

            S_IDLE: begin
                fb_we <= 1'b0;
                if (start) begin
                    busy <= 1'b1;
                    c    <= 8'd0;
                    st   <= S_XY;
                end
            end

            // ---- work out where each column of the plane lands ----
            // c runs 0..129: flush both registered coordinate stages.
            S_XY: begin
                if (c == 8'd129) st <= S_XYEND;
                else             c  <= c + 8'd1;
            end

            // ---- start row 0 : prime the volume read with column 0 ----
            S_XYEND: begin
                c      <= 8'd0;
                zc     <= 6'd0;
                acc_r  <= 128'd0; acc_g <= 128'd0; acc_b <= 128'd0;
                vaddr  <= {6'd0, xy_tab[7'd0][6:0]};
                xl     <= xy_tab[7'd0][13:7];
                st     <= S_COL;
            end

            // ---- one column per clock ----
            S_COL: begin
                acc_r <= {acc_r[126:0], rgb_now[2]};
                acc_g <= {acc_g[126:0], rgb_now[1]};
                acc_b <= {acc_b[126:0], rgb_now[0]};

                // issue the address of the column we will want next cycle
                vaddr <= {zc, xy_tab[cnxt][6:0]};
                xl    <= xy_tab[cnxt][13:7];

                if (c == 8'd127) begin
                    c  <= 8'd0;
                    st <= S_WR;
                end else begin
                    c  <= c + 8'd1;
                end
            end

            // ---- one 128 bit word per colour ----
            S_WR: begin
                fb_we  <= 1'b1;
                fb_row <= zc;
                w_r    <= acc_r;
                w_g    <= acc_g;
                w_b    <= acc_b;
                st     <= S_NEXT;
            end

            // ---- next row, or done ----
            S_NEXT: begin
                fb_we <= 1'b0;
                if (zc == 6'd63) begin
                    st <= S_END;
                end else begin
                    zc     <= zc + 6'd1;
                    acc_r  <= 128'd0; acc_g <= 128'd0; acc_b <= 128'd0;
                    c      <= 8'd0;
                    vaddr  <= {zc + 6'd1, xy_tab[7'd0][6:0]};
                    xl     <= xy_tab[7'd0][13:7];
                    st     <= S_COL;
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
