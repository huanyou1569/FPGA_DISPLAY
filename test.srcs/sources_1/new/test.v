// =====================================================================
//  test_panel  --  PYNQ-Z2 (XC7Z020-1CLG400C) -> 128x64 HUB75 panel
//
//  ***  TEST BUILD : one item at a time, chosen with the buttons  ***
//
//  Four things, one second each, round and round :
//
//      chicken  1 s  ->  ball  1 s  ->  donut  1 s  ->  walker  1 s  -> ...
//
//  ...except that ONE_ITEM is set, so in this build the item stays put
//  until a button moves it.  See CONTROLS below.
//
//  Two of them are models cut on the STM32 side (32 x 32 x 24 voxels),
//  one is a formula, one is a formula the original project already had.
//
//  ---------------------------------------------------------------------
//  STRUCTURE
//  ---------------------------------------------------------------------
//      test_panel                 top : pins, clock, switches, pacing
//        |
//        +-- voxel_mem            128x128x64, 3 bits per voxel  (the volume)
//        |
//        +-- vol_fill             walks the volume once, writes a pattern
//        |     +-- model_rom      chicken / walker, stored small + zoomed
//        |     +-- sphere_pattern the ball
//        |     +-- torus_pattern  the donut   (the original's, rescaled)
//        |
//        +-- show_seq             which of the four, and when to repaint
//        |
//        +-- proj_engine          reads the volume, one phase -> one picture
//        |     +-- sincos_rom     the 120 phase steps as Q15 sine / cosine
//        |
//        +-- frame_buf            two 128x64x3 pictures, write / read
//        |
//        +-- panel_scan           shift / latch / OE / scan address
//
//  The bottom four are untouched since stage 3.  Everything this stage
//  adds hangs off the pattern side of vol_fill.
//
//  ---------------------------------------------------------------------
//  TIMING : 15 TURNS/SECOND, 120 SLICES/TURN
//  ---------------------------------------------------------------
//  Target: 900 RPM, 3 degrees/slice, 1800 slices/second.
//  120 x 32 x (840 + hold_max) clocks = measured revolution period.
//  hold_max = period / 3840 - 840. At 125 MHz the default is 1330,
//  giving 555.52 us/frame (integer-clock quantization, sensor aligned).
//  The index sensor measures each turn and keeps the projection aligned.
//  With no sensor the fallback reference advances at 15 turns/second.
//  Motor speed is controlled by the external motor driver, not this RTL.
//
//  ---------------------------------------------------------------------
//  CONTROLS  --  this build is a TEST build
//  ---------------------------------------------------------------------
//      sw[0]  up   : mirror left/right          (this panel needs it)
//      sw[1]  up   : flip top/bottom            (this panel needs it)
//
//      btn[0]      : the next item           chicken > ball > donut > walker
//      btn[1]      : the previous item       ...and round the other way
//      btn[2]      : one frame on            (steps the donut one size)
//      btn[3]      : reset
//
//  A press is debounced for 4 ms, so one push is one step, and holding a
//  button down does not repeat.
//
//  ---------------------------------------------------------------------
//  TEST BUILD vs THE SHOW
//  ---------------------------------------------------------------------
//  ONE_ITEM below is 1, so the item NEVER changes by itself : whatever is
//  picked with btn[0]/btn[1] stays on screen, and its frames keep looping
//  underneath.  That is what makes it possible to stare at one animation
//  long enough to judge it.
//
//  Set ONE_ITEM back to 1'b0 for the real thing :
//
//      chicken 1 s > ball 1 s > donut 1 s > walker 1 s > ...
//
//  The buttons keep working either way, as a manual override.
//
//      led[3:2]    = which item is playing
//      led[1]      = blinks once per REAL sensor pulse
//      led[0]      = ON while the measured revolution is being believed
//
//  led[1] is the sensor's own heartbeat and does not blink on the
//  free-run watchdog, so it answers "is the sensor switching at all?"
//  without a scope : pass something dark under it with the display still,
//  or turn the shaft one revolution slowly -- one pass, one blink.
//
//  led[0] lights after two accepted edges establish a complete period.
//  The period is no longer restricted to the old 600..1200 RPM band.
//  Scan clamping/settling and actual frame intervals are reported by SYNC.
//
//  If led[1] is dark while the display turns, check the wiring, the
//  black mark, and the threshold pot on the module.
//
//  A quick check on how many pulses the sensor makes per turn : pick the
//  donut and time one whole grow-from-small-to-large cycle.  That is nine
//  revolutions, so 0.6 s at 900 RPM.  Half of that means the sensor is
//  handing out two pulses a turn, and the show would run at double speed
//  while still looking perfectly clean -- which is exactly the symptom
//  that sent us looking at index_sync's filter.
//
//  (Turning the shaft by hand does not work as a test : with no steady
//  train of pulses the free-run watchdog keeps advancing frames.)
//
//  The column offset is fixed at 3 : the panel's shift chain has one
//  stage more than it has columns, and this panel needs one extra clock
//  at the end of each row.  See panel_scan.v.
//
//  ---------------------------------------------------------------------
//  WIRING  --  14 signals, connect BY THE NAMES PRINTED ON THE PANEL
//  ---------------------------------------------------------------------
//      panel label   PYNQ-Z2        where
//      -----------   --------       ---------------------------
//         R1         W18            PMODA pin 9
//         G1         W19            PMODA pin 10
//         B1         W14            PMODB pin 1
//         R2         Y14            PMODB pin 2
//         G2         T11            PMODB pin 3
//         B2         T10            PMODB pin 4
//         A          Y17            PMODA pin 4
//         B          U18            PMODA pin 7
//         C          U19            PMODA pin 8
//         D          U13            Arduino AR2
//         E          V13            Arduino AR3
//         CK  (=CLK) Y18            PMODA pin 1
//         LS  (=LAT) Y19            PMODA pin 2
//         OE         Y16            PMODA pin 3
//         N   (=GND) GND            PYNQ-Z2 GND  (both, must be common)
//
//  Panel supply 5.0 V, common ground, current limit about 3 A.
//
//  ---------------------------------------------------------------------
//  INDEX SENSOR  --  1 signal, on the spare Pmod B pins
//  ---------------------------------------------------------------------
//      sensor module   PYNQ-Z2        PMODB silk
//      -------------   --------       -----------
//         VCC          3.3 V          pin 6  (or pin 12)
//         GND          GND            pin 5  (or pin 11)
//         DO / OUT     V16            pin 7
//
//  Use the module's DIGITAL output.  Most line-following grayscale
//  modules bring out both DO and AO; AO is an analogue voltage and the
//  PL cannot read it without an XADC.  If the module has a threshold
//  pot, set it so DO swings cleanly between the plain base and the
//  black mark.
//
//  3.3 V ONLY.  A Pmod has no 5 V, and a 5 V output would damage the pin.
// =====================================================================

`include "display_timing.vh"
module test_panel #(
    parameter integer DEBOUNCE_CYCLES = 524287
) (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk CLK", X_INTERFACE_PARAMETER = "FREQ_HZ 125000000" *)
    input  wire       clk,                 // H16 = 125 MHz
    input  wire [1:0] sw,
    input  wire [3:0] btn,
    input  wire       sensor,              // index sensor : one mark per turn
    // Canvas producer and controls share the external 125 MHz clock.
    input wire [2:0] brush_rgb,
    input wire canvas_changed, canvas_commit_pending, canvas_mode_ready,
    input wire brush_mode_set,
    input wire [1:0] brush_mode_value,
    output reg [1:0] brush_mode = 2'd0, // 0 demo, 1 brush, 2 snake, 3 tetris
    output wire canvas_swap_safe,
    output wire [6:0] brush_px, brush_py,
    output wire [5:0] brush_pz,
    output reg [31:0] revolution_count = 32'd0,
    output wire [25:0] revolution_period,
    output wire sensor_locked, period_valid,
    output wire [31:0] sync_flags, sync_edges, sync_accepted, sync_rejected,
    output reg [31:0] scan_period = 0,
    output wire [3:0] led,

    // ---------------- panel, 14 signals ----------------
    (* X_INTERFACE_IGNORE = "true" *) output wire p_clk, // -> CK, external panel strobe
    output wire       p_lat,               // -> LS
    output wire       p_oe,                // -> OE   (low = lit)
    output wire [4:0] p_addr,              // -> A B C D E
    output wire       p_r1, p_g1, p_b1,    // -> top half
    output wire       p_r2, p_g2, p_b2     // -> bottom half
);

    // ------------------------------------------------------------------
    //  fixed settings
    // ------------------------------------------------------------------
    // 120 frames/revolution, retimed from the measured 125 MHz counter.
    // The target remains 1800 frames/s, preserving the existing scan waveform.
    localparam [1:0]  COL_OFS    = 2'd3;      // this panel's chain is one out
    localparam [8:0]  PACE_MAX   = 9'd0;      // frames per phase, minus one
    localparam [7:0]  LAST_PHASE = `VX_ANGLE_SLICES - 1; // 120 phases, 0..119

    // TEST BUILD switch.  1 = the item never changes by itself, so one
    // animation can be studied; the buttons still choose which one.
    // 0 = the show : ball, donut, chicken, walker, DNA, ten seconds each.
    localparam        ONE_ITEM   = 1'b0;

    // ------------------------------------------------------------------
    //  controls
    // ------------------------------------------------------------------
    wire rst_n = ~btn[3];

    reg [1:0] sw_q1 = 2'b00, sw_q2 = 2'b00;
    reg [3:0] bt_q1 = 4'b0000, bt_q2 = 4'b0000;
    always @(posedge clk) begin
        sw_q1 <= sw;    sw_q2 <= sw_q1;
        bt_q1 <= btn;   bt_q2 <= bt_q1;
    end

    wire mirror = sw_q2[0];
    wire flip_v = sw_q2[1];

    // ------------------------------------------------------------------
    //  buttons : one pulse per press, 4 ms of debounce
    //
    //  PYNQ-Z2 buttons are active HIGH, so a press is a rising edge.  A
    //  mechanical switch bounces for a millisecond or two, and without
    //  this one push would step two or three frames.
    //
    //  btn_ok reads the button level only once it has been unchanged for
    //  4.19 ms, and reads zero until then, so both the make and the break
    //  arrive as one clean edge.
    // ------------------------------------------------------------------
    localparam [19:0] DB_MAX = DEBOUNCE_CYCLES; // 4.19 ms at 125 MHz

    reg [3:0]  btn_last = 4'b0000;
    reg [19:0] db_cnt   = 20'd0;

    always @(posedge clk) begin
        if (!rst_n) begin
            btn_last <= 4'b0000;
            db_cnt   <= 20'd0;
        end else if (bt_q2 != btn_last) begin
            btn_last <= bt_q2;
            db_cnt   <= 20'd0;
        end else if (db_cnt != DB_MAX) begin
            db_cnt   <= db_cnt + 20'd1;
        end
    end

    wire [3:0] btn_ok = (db_cnt == DB_MAX) ? btn_last : 4'b0000;

    reg [3:0] btn_ok_q = 4'b0000;
    always @(posedge clk) btn_ok_q <= btn_ok;

    wire [3:0] press = btn_ok & ~btn_ok_q;      // one clock per press

    // BTN2 has its own debounce state: holding it while another button is
    // pressed must not create a second mode toggle.
    reg mode_btn = 1'b0, mode_btn_q = 1'b0;
    reg [19:0] mode_db = 20'd0;
    always @(posedge clk) begin
        mode_btn_q <= mode_btn;
        if (!rst_n) begin mode_btn <= 0; mode_btn_q <= 0; mode_db <= 0; end
        else if (bt_q2[2] == mode_btn) mode_db <= 0;
        else if (mode_db == DB_MAX) begin mode_btn <= bt_q2[2]; mode_db <= 0; end
        else mode_db <= mode_db + 1'b1;
    end
    always @(posedge clk) begin
        if (!rst_n) brush_mode <= 0;
        else if (mode_btn && !mode_btn_q) brush_mode <= brush_mode + 2'd1; // wraps 3 -> 0
        else if (brush_mode_set) brush_mode <= brush_mode_value;
    end
    reg [1:0] brush_mode_q = 2'd0;
    always @(posedge clk) brush_mode_q <= brush_mode;
    wire mode_changed = brush_mode != brush_mode_q;

    // ------------------------------------------------------------------
    //  the volume
    // ------------------------------------------------------------------
    wire         v_we;
    wire [12:0]  v_waddr, v_raddr;
    wire [127:0] v_wr, v_wg, v_wb;
    wire [127:0] v_qr, v_qg, v_qb;

    voxel_mem u_vol (
        .clk   (clk),
        .raddr (v_raddr),
        .q_r   (v_qr), .q_g (v_qg), .q_b (v_qb),
        .we    (v_we),
        .waddr (v_waddr),
        .w_r   (v_wr), .w_g (v_wg), .w_b (v_wb)
    );

    // ------------------------------------------------------------------
    //  the show : four items, nine frames each, one second each
    // ------------------------------------------------------------------
    wire       seq_fill;
    wire [2:0] seq_item;
    wire [1:0] model_sel;
    wire [3:0] seq_frame;
    wire [6:0] seq_R, seq_r;

    show_seq u_seq (
        .clk       (clk),
        .rst_n     (rst_n),
        .rev       (seq_rev && !brush_mode),
        .next      (press[0] && !brush_mode),
        .prev      (press[1] && !brush_mode),
        .step      (1'b0), // BTN2 now switches demo / brush.
        .one_item  (ONE_ITEM),

        .item      (seq_item),
        .frame     (seq_frame),
        .fill_req  (seq_fill),

        .r_major   (seq_R),
        .r_minor   (seq_r),
        .model_sel (model_sel)
    );

    // ------------------------------------------------------------------
    //  filling the volume
    // ------------------------------------------------------------------
    wire         fill_we, fill_busy, fill_done;
    wire [12:0]  fill_waddr;
    wire [127:0] fill_wr, fill_wg, fill_wb;
    wire [6:0]   pat_x, pat_y;
    wire [5:0]   pat_z;
    wire [2:0]   pat_rgb;

    // latched the instant a fill starts, so one 8.9 ms sweep always uses
    // one consistent set even if the show moves on halfway through
    reg [2:0] fill_item = 3'd0;
    reg [1:0] fill_msel = 2'd0;
    reg [3:0] fill_fr   = 4'd0;
    reg [6:0] fill_R    = 7'd32;
    reg [6:0] fill_r    = 7'd12;

    reg       fill_go = 1'b0;
    reg       filled  = 1'b0;      // the volume has been drawn once
    reg       pend    = 1'b0;
    reg       fill_brush = 1'b0;
    assign canvas_swap_safe = !fill_busy && !fill_go;
    assign brush_px = pat_x;
    assign brush_py = pat_y;
    assign brush_pz = pat_z;

    always @(posedge clk) begin
        fill_go <= 1'b0;

        if (!rst_n) begin
            filled <= 1'b0;
            pend   <= 1'b0;
        end else begin
            if ((seq_fill && !brush_mode) || mode_changed ||
                (canvas_changed && brush_mode)) pend <= 1'b1;

            // POWER UP draws once without waiting for anything --
            // rst_n is HIGH at power up, so nothing else would ask.
            if ((!filled || pend) && !fill_busy && !fill_go && !canvas_commit_pending &&
                (!brush_mode || canvas_mode_ready)) begin
                fill_go   <= 1'b1;
                fill_brush <= (brush_mode != 0);
                fill_item <= seq_item;
                fill_msel <= model_sel;
                fill_fr   <= seq_frame;
                fill_R    <= seq_R;
                fill_r    <= seq_r;
                filled    <= 1'b1;
                pend      <= 1'b0;
            end
        end
    end

    // ------------------------------------------------------------------
    //  the three patterns, all six clocks deep, muxed by what is playing
    // ------------------------------------------------------------------
    wire [2:0] rgb_model, rgb_ball, rgb_torus;

    model_rom u_model (
        .clk (clk),
        .x   (pat_x), .y (pat_y), .z (pat_z),
        .sel (fill_msel),
        .fr  (fill_fr),
        .rgb (rgb_model)
    );

    sphere_pattern u_ball (
        .clk (clk),
        .x   (pat_x), .y (pat_y), .z (pat_z),
        .rgb (rgb_ball)
    );

    torus_pattern u_torus (
        .clk     (clk),
        .x       (pat_x), .y (pat_y), .z (pat_z),
        .r_major (fill_R),
        .r_minor (fill_r),
        .rgb     (rgb_torus)
    );

    //  item 0 = ball, 1 = donut, 2 = chicken (ROM),
    //  item 3 = walker (ROM), 4 = DNA (ROM)
    assign pat_rgb = fill_brush ? brush_rgb
                   : (fill_item == 3'd0) ? rgb_ball
                   : (fill_item == 3'd1) ? rgb_torus
                   :                       rgb_model;

    vol_fill u_fill (
        .clk    (clk),
        .rst_n  (rst_n),
        .start  (fill_go),
        .clear  (1'b0),          // every pattern is zero outside its shape,
                                 // so a full sweep erases as it draws
        .busy   (fill_busy),
        .done   (fill_done),

        .we     (fill_we),
        .waddr  (fill_waddr),
        .w_r    (fill_wr), .w_g (fill_wg), .w_b (fill_wb),

        .px     (pat_x),
        .py     (pat_y),
        .pz     (pat_z),
        .p_rgb  (pat_rgb)
    );

    assign v_we    = fill_we;
    assign v_waddr = fill_waddr;
    assign v_wr    = fill_wr;
    assign v_wg    = fill_wg;
    assign v_wb    = fill_wb;

    // ------------------------------------------------------------------
    //  projection  ->  frame buffer
    // ------------------------------------------------------------------
    wire        proj_busy, proj_done;
    wire        fb_we;
    wire [5:0]  fb_row;
    wire [127:0] w_r, w_g, w_b;

    // ------------------------------------------------------------------
    //  frame buffer  <->  scan engine
    // ------------------------------------------------------------------
    wire [4:0]   rd_line;
    wire [127:0] d_r1, d_g1, d_b1;
    wire [127:0] d_r2, d_g2, d_b2;
    wire         frame_done;

    // ------------------------------------------------------------------
    //  which picture is on screen, and how long a phase lasts
    // ------------------------------------------------------------------
    reg [7:0] proj_phase = 8'd0;      // the phase being drawn
    reg       disp_buf   = 1'b0;      // which buffer the panel reads
    reg       proj_ready = 1'b0;      // a finished picture is waiting
    reg [8:0] paced      = 9'd0;      // frames spent on this phase
    reg       proj_go    = 1'b0;      // one clock pulse : project one frame
    reg       started    = 1'b0;      // the first picture has been asked for
    reg       ever_done  = 1'b0;      // sticky : the engine made a picture
    reg       idx_pend   = 1'b0;      // a sensor pulse is waiting to be used

    wire wbuf = ~disp_buf;            // the projection always fills the other

    // ------------------------------------------------------------------
    //  the revolution reference
    //
    //  A grayscale sensor turns with the display and sees one black mark
    //  on the base per turn.  That pulse does three jobs :
    //
    //      * times the revolution          -> rev_timing
    //      * forces the phase sweep back to phase 0
    //      * advances the animation by one frame
    //
    //  "Times the revolution" is the one that keeps the picture still, and
    //  it is handled by rev_timing below.  The phase reset alone is not
    //  enough : it re-aligns at the mark and nowhere else, so a sweep
    //  running at the wrong rate still drifts across the rest of the turn.
    // ------------------------------------------------------------------
    wire idx_pulse;

    wire        idx_pok, idx_pnew;
    wire [25:0] idx_period;

    wire        idx_hit, idx_lock;
    wire idx_raw, idx_level;

    index_sync u_index (
        .clk        (clk),
        .rst_n      (rst_n),
        .raw        (sensor),
        .pulse      (idx_pulse),
        .lock       (idx_lock),
        .hit        (idx_hit),
        .period     (idx_period),
        .period_ok  (idx_pok),
        .period_new (idx_pnew),
        .raw_level(idx_raw), .filtered_level(idx_level),
        .edge_count(sync_edges), .accepted_count(sync_accepted),
        .rejected_count(sync_rejected)
    );

    // ------------------------------------------------------------------
    //  and how long a panel frame has to be for 120 of them to fill it
    // ------------------------------------------------------------------
    //  This is the half of the fix that actually keeps the picture still.
    //  Resetting the phase on the mark only re-aligns at ONE point of the
    //  revolution; in between, a sweep running at a fixed rate drifts
    //  against the real angle, and an asymmetric model like the chicken
    //  visibly turns.  Re-timing the frame to the measured revolution
    //  keeps every phase on top of the angle it belongs to.
    //
    //  Without a sensor period it falls back to 900 RPM and the free-run
    //  behaviour is exactly what it was before.
    // ------------------------------------------------------------------
    wire [12:0] run_hold;

    rev_timing u_timing (
        .clk        (clk),
        .rst_n      (rst_n),
        .period_new (idx_pnew),
        .period_ok  (idx_pok),
        .period     (idx_period),
        .hold_max   (run_hold)
    );

    // one sensor pulse IS one revolution, so it is what advances the show
    wire seq_rev = idx_pulse;
    assign revolution_period = idx_period;
    assign sensor_locked = idx_lock;
    assign period_valid = idx_pok;
    // Physical scan limits, separate from validity of the RPM measurement.
    wire scan_in_range = idx_period >= (`VX_ANGLE_SLICES*32*(840+80)) &&
                         idx_period <= (`VX_ANGLE_SLICES*32*(840+6000));
    assign sync_flags = {26'd0, (idx_pok && !scan_in_range),
        (idx_pok && scan_in_range), idx_pok, idx_lock, idx_level, idx_raw};
    // Measure the REAL frame_done interval, rather than echoing an ideal
    // period/120 calculation. Readback includes divider clamps/quantization.
    reg [31:0] scan_elapsed = 0;
    reg scan_seen = 0;
    always @(posedge clk) begin
        if (!rst_n) begin scan_period <= 0; scan_elapsed <= 0; scan_seen <= 0; end
        else if (frame_done) begin
            if (scan_seen) scan_period <= scan_elapsed + 1'b1;
            scan_seen <= 1;
            scan_elapsed <= 0;
        end else if (scan_elapsed != 32'hffffffff) scan_elapsed <= scan_elapsed + 1'b1;
    end
    always @(posedge clk) begin
        if (!rst_n) revolution_count <= 0;
        else if (idx_pulse) revolution_count <= revolution_count + 1'b1;
    end

    always @(posedge clk) begin
        proj_go <= 1'b0;

        if (proj_done) ever_done <= 1'b1;

        if (!rst_n) begin
            proj_phase <= 8'd0;
            disp_buf   <= 1'b0;
            proj_ready <= 1'b0;
            paced      <= 9'd0;
            started    <= 1'b0;
            ever_done  <= 1'b0;
            idx_pend   <= 1'b0;
        end else if (!started) begin
            // POWER UP.  rst_n is HIGH at power up because nothing is
            // pressed, so the reset branch above never runs -- which is
            // exactly why the engine used to sit idle forever.  Ask for
            // the very first picture here instead of waiting for a button.
            proj_go <= 1'b1;
            started <= 1'b1;
        end else begin
            if (proj_done) proj_ready <= 1'b1;

            // A sensor edge can land at any moment, including halfway
            // through a projection -- and proj_engine reads its phase all
            // through S_XY, so moving it mid-flight would build half the
            // table from one angle and half from another.  Park it until
            // the next frame boundary, where the engine is idle anyway.
            if (idx_pulse) idx_pend <= 1'b1;

            if (frame_done) begin
                if (paced == PACE_MAX) begin
                    paced <= 9'd0;
                    if (proj_ready) begin
                        disp_buf   <= ~disp_buf;   // show the finished picture
                        proj_ready <= 1'b0;

                        if (idx_pend) begin
                            idx_pend   <= 1'b0;
                            proj_phase <= 8'd0;    // the mark came round
                        end else if (proj_phase != LAST_PHASE) begin
                            proj_phase <= proj_phase + 8'd1;
                        end else if (!idx_lock) begin
                            proj_phase <= 8'd0;    // no sensor : free run
                        end
                        // locked and already at the last phase : hold it
                        // until the mark arrives.  The last slice is at
                        // 357 degrees, so holding it over the remaining
                        // few degrees is right -- and wrapping round here
                        // instead would paint a second sweep on top of
                        // the first whenever the motor ran slightly slow.

                        proj_go <= 1'b1;        // and start the next one
                    end
                end else begin
                    paced <= paced + 9'd1;
                end
            end
        end
    end

    // ------------------------------------------------------------------
    //  the rest of the pipeline
    // ------------------------------------------------------------------
    proj_engine u_proj (
        .clk    (clk),
        .rst_n  (rst_n),
        .start  (proj_go),
        .phase  (proj_phase),

        .busy   (proj_busy),
        .done   (proj_done),

        .vaddr  (v_raddr),
        .vq_r   (v_qr), .vq_g (v_qg), .vq_b (v_qb),

        .fb_we  (fb_we),
        .fb_row (fb_row),
        .w_r    (w_r), .w_g (w_g), .w_b (w_b)
    );

    frame_buf u_fbuf (
        .clk      (clk),

        .disp_buf (disp_buf),
        .line     (rd_line),
        .flip_v   (flip_v),
        .d_r1     (d_r1), .d_g1 (d_g1), .d_b1 (d_b1),
        .d_r2     (d_r2), .d_g2 (d_g2), .d_b2 (d_b2),

        .we       (fb_we),
        .wbuf     (wbuf),
        .wrow     (fb_row),
        .w_r      (w_r), .w_g (w_g), .w_b (w_b)
    );

    panel_scan u_scan (
        .clk       (clk),
        .rst_n     (rst_n),
        .en        (1'b1),
        .mirror    (mirror),
        .col_ofs   (COL_OFS),
        .hold_max  (run_hold),

        .rd_line   (rd_line),
        .d_r1      (d_r1), .d_g1 (d_g1), .d_b1 (d_b1),
        .d_r2      (d_r2), .d_g2 (d_g2), .d_b2 (d_b2),

        .p_clk     (p_clk),
        .p_lat     (p_lat),
        .p_oe      (p_oe),
        .p_addr    (p_addr),
        .p_r1      (p_r1), .p_g1 (p_g1), .p_b1 (p_b1),
        .p_r2      (p_r2), .p_g2 (p_g2), .p_b2 (p_b2),

        .frame_done(frame_done)
    );

    // ------------------------------------------------------------------
    //  LEDs
    //
    //      led[3:2]  which item is playing
    //      led[1]    blinks once per REAL sensor pulse
    //      led[0]    ON while the measured revolution is being believed
    //
    //  led[1] is a 60 ms stretch of the one clock `hit` pulse, so it can
    //  be seen.  It deliberately does NOT fire on the free-run watchdog :
    //  on the bench that ticks every 66.667 ms, and an LED driven from it
    //  would light up whether or not a sensor was connected at all.
    //
    //      led[1] dark while turning -> the sensor is not switching
    //      led[1] blinking           -> it is, and led[0] says whether
    //                                   the period measured was believable
    //
    //  It can be checked without spinning the motor : hold the display
    //  still and pass something dark under the sensor.  One pass, one
    //  blink.
    // ------------------------------------------------------------------
    localparam [22:0] BLINK_MAX = 23'd7500000;   // 60 ms at 125 MHz

    reg [22:0] blink = 23'd0;

    always @(posedge clk) begin
        if (!rst_n) begin
            blink <= 23'd0;
        end else if (idx_hit) begin
            blink <= BLINK_MAX;
        end else if (blink != 23'd0) begin
            blink <= blink - 23'd1;
        end
    end

    //  led[0] additionally requires `lock`, which goes low as soon as the
    //  watchdog has to fill in : period_ok on its own would stay lit for
    //  ever after the sensor stopped.
    //  Five items no longer fit in two LEDs, so led[3:2] shows item[1:0] :
    //  item 4 (DNA) looks the same as item 0 (chicken) up there.  The panel
    //  itself is the real indicator.
    // LED3: PS canvas mode; LED2 distinguishes snake from brush in canvas modes.
    assign led = { (brush_mode != 0), brush_mode ? (brush_mode == 2) : seq_item[0],
        (blink != 23'd0), (idx_pok & idx_lock) };

endmodule
