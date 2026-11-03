// =====================================================================
//  panel_scan.v  --  HUB75 scan engine for the 128x64 P2.5 panel
//
//  This module knows NOTHING about what is being displayed.  Every line
//  cycle it asks for one row (128 bits x 3 colours x 2 halves) and puts
//  whatever answers onto the panel.
//
//  Swapping in BCM greyscale or an SD card stream therefore does not
//  touch this file -- only what drives rd_line / d_* changes.
//
//  ---------------------------------------------------------------------
//  ONE LINE CYCLE
//  ---------------------------------------------------------------------
//      S_LOAD     present the address, let the frame store settle,
//                 put the FIRST bit on the data lines
//      S_SHIFT    exactly 128 shift clocks, OE blanked
//      S_LATCH    LS pulse, commits the 128 bits into the panel
//      S_HOLD     OE low, the row is lit for hold_max + 1 clocks
//
//  After S_HOLD the scan address advances.  After address 31 a whole
//  frame has been shown and frame_done pulses for one clock.
//
//  ---------------------------------------------------------------------
//  THE THREE THINGS v23 GOT AWAY WITH
//  ---------------------------------------------------------------------
//  All three were invisible while a whole row was a single on/off value,
//  and all three break the moment real pixels arrive.
//
//  1) p_clk MUST BE GATED TO S_SHIFT.
//     A HUB75 panel shifts on every clock edge it sees.  A free running
//     clock would push the 1200 clocks of S_HOLD into the panel as well,
//     overwriting the row with a copy of its own last bit.  v23 survived
//     only because every bit in its row was identical.
//
//  2) THE DATA MUST CHANGE ON THE FALLING EDGE.
//     v23 detected the shift edge with "clk_r & ~clk_q", which is one
//     125 MHz clock LATE.  Driving the output flops from that signal
//     makes the data move after the panel has already sampled it.
//     Here the data changes on the falling edge, which leaves a full
//     half period -- three clocks, 24 ns -- of set-up before the next
//     rising edge clocks it in.
//
//  3) THE FIRST BIT MUST ALREADY BE ON THE WIRE WHEN S_SHIFT STARTS.
//     clk_r has to sit at 0 through S_LOAD, otherwise the 0 -> 1 at the
//     S_LOAD/S_SHIFT boundary is one EXTRA rising edge the panel counts.
//     A 128 bit shift register fed 129 edges loses its first bit and the
//     whole row slides one position sideways -- which shows up as the
//     border being missing on one side and doubled on the other.
//     So S_LOAD presets the first bit and pre-shifts the register, and
//     S_SHIFT then emits exactly 128 rising edges, bit 127 first.
//
//  ---------------------------------------------------------------------
//  TIMING  (clk = 125 MHz)
//  ---------------------------------------------------------------------
//      shift clock  = 125 / 6             = 20.83 MHz
//      S_LOAD       = 8 clocks            = 64 ns
//      S_SHIFT      = 771 clocks          = 6.17 us   (129 bits)
//      S_LATCH      = 60 clocks           = 0.48 us
//      S_HOLD       = hold_max + 1
//      ---- one line = 840 + hold_max clocks ----
//      with hold_max = 1330 : 2170 clocks = 17.36 us
//      x 32 addresses       = 555.5 us    -> 1800 Hz
//
//  S_SHIFT is 771 clocks, not 765, because this panel needs 129 shift
//  clocks (col_ofs = 3).  128 pulses would be 3 + 127*6 = 765.  Anything
//  that computes a line length from hold_max must use 840.
//
//  hold_max is latched at the end of a whole frame, then copied to hold_r
//  in S_LATCH. All 32 lines of a slice use the same period; neither a line
//  nor a slice can change speed halfway through its scan.
// =====================================================================

module panel_scan (
    input  wire         clk,          // 125 MHz
    input  wire         rst_n,        // 0 = hold in reset
    input  wire         en,           // 1 = scanning
    input  wire         mirror,       // 1 = shift the bits out reversed (H flip)
    input  wire [1:0]   col_ofs,      // rotate the row by one column (see below)
    input  wire [12:0]  hold_max,     // display clocks per line

    // ---------------- row request / row data ----------------
    output wire [4:0]   rd_line,      // scan address 0..31
    input  wire [127:0] d_r1,         // top    half, row = rd_line
    input  wire [127:0] d_g1,
    input  wire [127:0] d_b1,
    input  wire [127:0] d_r2,         // bottom half, row = rd_line + 32
    input  wire [127:0] d_g2,
    input  wire [127:0] d_b2,

    // ---------------- panel pins ----------------
    output wire         p_clk,        // -> CK
    output reg          p_lat,        // -> LS
    output reg          p_oe,         // -> OE   (low = lit)
    output wire [4:0]   p_addr,       // -> A B C D E
    output reg          p_r1, p_g1, p_b1,
    output reg          p_r2, p_g2, p_b2,

    // ---------------- status ----------------
    output reg          frame_done    // 1-clock pulse after address 31
);

    // ------------------------------------------------------------------
    //  constants
    // ------------------------------------------------------------------
    localparam [3:0] CLK_HALF  = 4'd2;      // shift clock = 125/6 = 20.83 MHz
    localparam [4:0] LINE_MAX  = 5'd31;     // 32 scan addresses
    localparam [7:0] LATCH_CLK = 8'd59;     // LS high for 60 clocks = 0.48 us
    localparam [7:0] LOAD_CLK  = 8'd7;      // S_LOAD lasts 8 clocks

    localparam [1:0] S_LOAD  = 2'd0;
    localparam [1:0] S_SHIFT = 2'd1;
    localparam [1:0] S_LATCH = 2'd2;
    localparam [1:0] S_HOLD  = 2'd3;

    // ------------------------------------------------------------------
    //  optional one-column rotation
    //
    //  A HUB75 panel's shift register is 128 stages for 128 columns, but
    //  the FIRST stage does not always drive the FIRST column -- on some
    //  panels the chain is one position out.  The symptom is a picture
    //  that is otherwise perfect but sits one column sideways, so the
    //  border closes on one edge, is doubled on the other, or is missing.
    //
    //  Rotating the row by one position slides the whole picture one
    //  column without disturbing anything else, and because it rotates
    //  rather than shifts, the column that would fall off one edge
    //  reappears at the other instead of leaving a gap.
    //
    //      col_ofs = 0 : as stored                              128 pulses
    //      col_ofs = 1 : rotate one column one way              128 pulses
    //      col_ofs = 2 : rotate one column the other way        128 pulses
    //      col_ofs = 3 : no rotation, ONE EXTRA shift clock     129 pulses
    //                    appended after the 128 data bits
    //
    //  0/1/2 slide the whole picture sideways.  Rotating and shifting
    //  differ only in what happens to the column that leaves the end of
    //  the chain: rotating brings it back at the opposite edge, shifting
    //  turns it black.  Neither can ADD or REMOVE a column.
    //
    //  3 is the one to use when the panel's chain has a spare stage that
    //  no column uses -- the picture then arrives one position short and
    //  the last column is fed by that spare stage.  One extra clock at
    //  the end pushes the spare stage out of the picture.  See the note
    //  further down.
    // ------------------------------------------------------------------
    function [127:0] rot_col;
        input [127:0] d;
        input [1:0]   ofs;
        begin
            case (ofs)
            2'd1:    rot_col = {d[126:0], d[127]};
            2'd2:    rot_col = {d[0], d[127:1]};
            default: rot_col = d;            // 0 and 3 : no rotation
            endcase
        end
    endfunction

    //  col_ofs = 3 : one EXTRA shift clock, appended AFTER the 128 data bits
    //
    //  The panel's chain has one stage more than it has columns.  The
    //  spare stage sits at the input end of the chain and drives nothing,
    //  so the whole picture arrives one stage short: the last column
    //  ends up fed by that spare stage and the rest of the picture slides
    //  one place.  Sending one extra clock after the data pushes the
    //  spare stage out of the picture and lines everything up.
    //
    //  The extra clock shifts a 0 into the chain, which lands in the
    //  spare stage and is never seen.
    // ------------------------------------------------------------------
    wire       extra   = (col_ofs == 2'd3);
    wire [7:0] bit_last = extra ? 8'd128 : 8'd127;   // 129 pulses vs 128

    // ------------------------------------------------------------------
    //  registers
    // ------------------------------------------------------------------
    reg [1:0]  st   = S_LOAD;
    reg [3:0]  cdiv = 4'd0;         // shift clock divider
    reg        clk_r = 1'b0;        // the shift clock itself
    reg [7:0]  cnt  = 8'd0;         // S_LOAD / S_LATCH counter
    reg [7:0]  bitc = 8'd0;         // how many bits have gone out
    reg [12:0] hc   = 13'd0;        // S_HOLD counter
    reg [12:0] hold_r = 13'd0;      // frame_hold, latched once per line
    reg [12:0] frame_hold = 13'd1330; // one timing value for all 32 rows
    reg [4:0]  line = 5'd0;         // scan address

    reg [127:0] sh_r1, sh_g1, sh_b1;
    reg [127:0] sh_r2, sh_g2, sh_b2;

    // the row after the optional one-column rotation
    wire [127:0] e_r1 = rot_col(d_r1, col_ofs);
    wire [127:0] e_g1 = rot_col(d_g1, col_ofs);
    wire [127:0] e_b1 = rot_col(d_b1, col_ofs);
    wire [127:0] e_r2 = rot_col(d_r2, col_ofs);
    wire [127:0] e_g2 = rot_col(d_g2, col_ofs);
    wire [127:0] e_b2 = rot_col(d_b2, col_ofs);

    // ------------------------------------------------------------------
    //  shift clock -- runs ONLY inside S_SHIFT, and idles LOW everywhere
    //  else, including S_LOAD.  That is what keeps the S_LOAD/S_SHIFT
    //  boundary from being counted as a shift.
    // ------------------------------------------------------------------
    always @(posedge clk) begin
        if (st == S_SHIFT) begin
            if (cdiv == CLK_HALF) begin
                cdiv  <= 4'd0;
                clk_r <= ~clk_r;
            end else begin
                cdiv <= cdiv + 4'd1;
            end
        end else begin
            cdiv  <= 4'd0;
            clk_r <= 1'b0;
        end
    end

    wire toggle    = (st == S_SHIFT) && (cdiv == CLK_HALF);
    wire next_rise = toggle && (clk_r == 1'b0);   // panel latches on this edge
    wire next_fall = toggle && (clk_r == 1'b1);   // safe moment to change data

    // ------------------------------------------------------------------
    //  sequencer
    // ------------------------------------------------------------------
    always @(posedge clk) begin
        frame_done <= 1'b0;

        if (!rst_n || !en) begin
            st    <= S_LOAD;
            cnt   <= 8'd0;
            bitc  <= 8'd0;
            hc    <= 13'd0;
            line  <= 5'd0;
            hold_r <= hold_max;         // ready for the very first line
            frame_hold <= hold_max;
            p_lat <= 1'b0;
            p_oe  <= 1'b1;              // blanked
            p_r1 <= 1'b0; p_g1 <= 1'b0; p_b1 <= 1'b0;
            p_r2 <= 1'b0; p_g2 <= 1'b0; p_b2 <= 1'b0;
            sh_r1 <= 128'd0; sh_g1 <= 128'd0; sh_b1 <= 128'd0;
            sh_r2 <= 128'd0; sh_g2 <= 128'd0; sh_b2 <= 128'd0;
        end else begin
            case (st)

            // ---- wait for the frame store, then arm the row ----
            //   the first bit goes straight onto the data lines and the
            //   register is pre-shifted by one, so the very first rising
            //   edge inside S_SHIFT already carries a real bit and no
            //   edge is wasted.
            S_LOAD: begin
                p_oe  <= 1'b1;
                p_lat <= 1'b0;
                if (cnt == LOAD_CLK) begin
                    if (mirror) begin
                        p_r1 <= e_r1[0]; sh_r1 <= {1'b0, e_r1[127:1]};
                        p_g1 <= e_g1[0]; sh_g1 <= {1'b0, e_g1[127:1]};
                        p_b1 <= e_b1[0]; sh_b1 <= {1'b0, e_b1[127:1]};
                        p_r2 <= e_r2[0]; sh_r2 <= {1'b0, e_r2[127:1]};
                        p_g2 <= e_g2[0]; sh_g2 <= {1'b0, e_g2[127:1]};
                        p_b2 <= e_b2[0]; sh_b2 <= {1'b0, e_b2[127:1]};
                    end else begin
                        p_r1 <= e_r1[127]; sh_r1 <= {e_r1[126:0], 1'b0};
                        p_g1 <= e_g1[127]; sh_g1 <= {e_g1[126:0], 1'b0};
                        p_b1 <= e_b1[127]; sh_b1 <= {e_b1[126:0], 1'b0};
                        p_r2 <= e_r2[127]; sh_r2 <= {e_r2[126:0], 1'b0};
                        p_g2 <= e_g2[127]; sh_g2 <= {e_g2[126:0], 1'b0};
                        p_b2 <= e_b2[127]; sh_b2 <= {e_b2[126:0], 1'b0};
                    end
                    bitc <= 8'd0;
                    cnt  <= 8'd0;
                    st   <= S_SHIFT;
                end else begin
                    cnt <= cnt + 8'd1;
                end
            end

            // ---- exactly 128 shift clocks, blanked ----
            //   data changes on the falling edge, three clocks before the
            //   rising edge the panel samples on
            //   normal : bit 127 first   mirror : bit 0 first
            S_SHIFT: begin
                p_oe  <= 1'b1;
                p_lat <= 1'b0;

                if (next_fall) begin
                    if (mirror) begin
                        p_r1 <= sh_r1[0]; sh_r1 <= {1'b0, sh_r1[127:1]};
                        p_g1 <= sh_g1[0]; sh_g1 <= {1'b0, sh_g1[127:1]};
                        p_b1 <= sh_b1[0]; sh_b1 <= {1'b0, sh_b1[127:1]};
                        p_r2 <= sh_r2[0]; sh_r2 <= {1'b0, sh_r2[127:1]};
                        p_g2 <= sh_g2[0]; sh_g2 <= {1'b0, sh_g2[127:1]};
                        p_b2 <= sh_b2[0]; sh_b2 <= {1'b0, sh_b2[127:1]};
                    end else begin
                        p_r1 <= sh_r1[127]; sh_r1 <= {sh_r1[126:0], 1'b0};
                        p_g1 <= sh_g1[127]; sh_g1 <= {sh_g1[126:0], 1'b0};
                        p_b1 <= sh_b1[127]; sh_b1 <= {sh_b1[126:0], 1'b0};
                        p_r2 <= sh_r2[127]; sh_r2 <= {sh_r2[126:0], 1'b0};
                        p_g2 <= sh_g2[127]; sh_g2 <= {sh_g2[126:0], 1'b0};
                        p_b2 <= sh_b2[127]; sh_b2 <= {sh_b2[126:0], 1'b0};
                    end
                end

                if (next_rise) begin
                    if (bitc == bit_last) begin
                        bitc <= 8'd0;
                        st   <= S_LATCH;
                    end else begin
                        bitc <= bitc + 8'd1;
                    end
                end
            end

            // ---- LS pulse : commit the row into the panel ----
            S_LATCH: begin
                p_lat <= 1'b1;
                if (cnt == LATCH_CLK) begin
                    p_lat  <= 1'b0;
                    cnt    <= 8'd0;
                    hc     <= 13'd0;
                    hold_r <= frame_hold; // do not mix two speeds in one slice
                    st     <= S_HOLD;
                end else begin
                    cnt <= cnt + 8'd1;
                end
            end

            // ---- OE low : the row is lit ----
            //
            //  hold_r is a COPY, refreshed only in S_LATCH.  While the
            //  motor is tracked, hold_max is recomputed once a revolution
            //  and can move by tens of clocks; if S_HOLD compared against
            //  hold_max itself, a drop below hc would make `hc == hold_max`
            //  miss for ever and that one line would hang for 8192 clocks.
            //  Latching it removes the question.
            default: begin
                p_oe <= 1'b0;
                if (hc == hold_r) begin
                    hc <= 13'd0;
                    if (line == LINE_MAX) begin
                        line       <= 5'd0;
                        frame_done <= 1'b1;
                        frame_hold <= hold_max;
                    end else begin
                        line <= line + 5'd1;
                    end
                    cnt <= 8'd0;
                    st  <= S_LOAD;
                end else begin
                    hc <= hc + 13'd1;
                end
            end

            endcase
        end
    end

    // ------------------------------------------------------------------
    //  outputs that just follow a register
    // ------------------------------------------------------------------
    assign rd_line = line;
    assign p_addr  = line;
    assign p_clk   = clk_r;

endmodule
