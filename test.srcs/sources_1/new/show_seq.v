// =====================================================================
//  show_seq.v  --  what plays, and when it changes
//
//  ---------------------------------------------------------------------
//  TWO MODES
//  ---------------------------------------------------------------------
//  one_item = 1  --  a TEST build.  Set ONE_ITEM to 1'b1 in test.v to get
//                   this back.
//
//      The item only ever changes when a button says so, and the item's
//      own frames keep looping, so one animation can be watched for as
//      long as it takes to judge it :
//
//          btn[0]   next item           btn[1]   previous item
//          btn[2]   one frame on
//
//      The animation still advances on `rev`, so the donut still grows
//      once per revolution -- it just never moves on to the next item.
//
//  one_item = 0  --  the show, and what test.v asks for now.
//
//      ball  10 s  ->  donut  10 s  ->  chicken  10 s
//                                   -> walker  10 s  ->  DNA  10 s  -> ...
//
//      driven by `rev`, one pulse per revolution. At the 15 rps target,
//      ten seconds is 150 revolutions:
//
//          5 items x 150 revolutions = 750 revolutions = 50 s a round
//
//      Inside an item `frame` keeps looping 0..8, once per revolution. The
//      STM32 project had the same idea and wrote it down in snake_game.c
//      -- `#define STEP_DIVIDER 2  /* every N hall edges */`.  Its `rev`
//      came from a hall sensor; ours comes from an index sensor looking
//      at a mark on the base, or from index_sync's watchdog when there is
//      no rotation at all.
//
//  ---------------------------------------------------------------------
//  ONLY REDRAW WHEN SOMETHING MOVED
//  ---------------------------------------------------------------------
//  A redraw walks the whole volume and takes 8.9 ms, which is 8% of a
//  revolution spent reading a half-written volume.  The chicken and the
//  ball have a single frame each, so repainting them nine times a turn
//  would buy nothing at all and show that tear nine times for it.  Only
//  the donut (growing) and the walker (nine poses) change shape, so only
//  those two ask for a redraw every revolution.
// =====================================================================

`include "display_timing.vh"
module show_seq (
    input  wire       clk,
    input  wire       rst_n,

    input  wire       rev,          // one pulse : a whole phase sweep finished
    input  wire       next,         // one pulse : jump to the next item
    input  wire       prev,         // one pulse : jump to the previous item
    input  wire       step,         // one pulse : one frame forward
    input  wire       one_item,     // 1 = stay on one item, loop its frames

    output reg  [2:0] item,         // 0 ball, 1 donut, 2 chicken, 3 walker, 4 DNA
    output reg  [3:0] frame,        // 0..8 within the item

    output reg        fill_req,     // one pulse : repaint the volume now

    output reg  [6:0] r_major,      // the donut's radii
    output reg  [6:0] r_minor,
    output reg  [1:0] model_sel     // model_rom : 0 chicken, 1 walker, 2 DNA
);

    localparam [3:0] LAST_FRAME = 4'd8;      // nine animation frames per item
    localparam [2:0] LAST_ITEM  = 3'd4;

    // ------------------------------------------------------------------
    //  TEN SECONDS AN ITEM
    // ------------------------------------------------------------------
    // At the 15 rps target, 150 revolutions keep each item up for 10s.
    // Animation frames still advance once per accepted/synthetic turn.
    // ------------------------------------------------------------------
    localparam [7:0] LAST_HOLD  = `VX_TARGET_RPS * 10 - 1; // 150 turns = 10 s at 15 rps

    // ------------------------------------------------------------------
    //  the running order
    // ------------------------------------------------------------------
    wire item_end  = (frame == LAST_FRAME);
    wire animating = (item == 3'd1) || (item == 3'd3);   // donut, walker

    reg [7:0] hold_cnt = 8'd0;      // revolutions this item has been up

    always @(posedge clk) begin
        fill_req <= 1'b0;

        if (!rst_n) begin
            item     <= 3'd0;
            frame    <= 4'd0;
            hold_cnt <= 8'd0;
        end

        // ---- picking an item by hand -------------------------------
        //  These work in BOTH modes, so the show can still be stepped
        //  through by hand with the buttons once one_item goes back to 0.
        else if (next) begin
            frame     <= 4'd0;
            hold_cnt  <= 8'd0;           // the new item gets its whole 10 s
            item      <= (item == LAST_ITEM) ? 3'd0 : (item + 3'd1);
            fill_req  <= 1'b1;
        end else if (prev) begin
            frame     <= 4'd0;
            hold_cnt  <= 8'd0;
            item      <= (item == 3'd0) ? LAST_ITEM : (item - 3'd1);
            fill_req  <= 1'b1;
        end else if (step) begin
            frame     <= item_end ? 4'd0 : (frame + 4'd1);
            fill_req  <= 1'b1;           // the donut has a new size
        end

        // ---- or let the revolutions count them out -----------------
        else if (rev) begin
            hold_cnt <= (hold_cnt == LAST_HOLD) ? 8'd0 : (hold_cnt + 8'd1);
            frame    <= item_end ? 4'd0 : (frame + 4'd1);

            if (hold_cnt == LAST_HOLD) begin
                //  this item has had its ten seconds
                frame <= 4'd0;
                if (!one_item) begin
                    item     <= (item == LAST_ITEM) ? 3'd0 : (item + 3'd1);
                    fill_req <= 1'b1;    // a new item : repaint
                end else if (animating) begin
                    fill_req <= 1'b1;    // frame 8 on screen, frame 0 next
                end
            end else if (animating) begin
                fill_req <= 1'b1;        // the donut or the walker moved
            end
        end
    end

    // ------------------------------------------------------------------
    //  frame 0..8 -> donut size step 0..6, small to large
    //
    //  Seven steps over nine frames, so two of them are held twice.  The
    //  table is stepped rather than computed because every arithmetic
    //  route into tor_pattern's radius wants a divider, and a divider on
    //  a control path is a divider that will one day eat the clock.
    // ------------------------------------------------------------------
    reg [2:0] zl;

    always @(*) begin
        case (frame)
        4'd0:    zl = 3'd0;
        4'd1:    zl = 3'd0;
        4'd2:    zl = 3'd1;
        4'd3:    zl = 3'd2;
        4'd4:    zl = 3'd3;
        4'd5:    zl = 3'd4;
        4'd6:    zl = 3'd5;
        4'd7:    zl = 3'd6;
        default: zl = 3'd6;              // frame 8
        endcase
    end

    // ------------------------------------------------------------------
    //  size step -> radii
    //
    //  R + r never passes 61, which keeps the torus pattern's d2 inside
    //  its 4096 entry square root table.  Push these up and that table
    //  silently runs out of range.
    // ------------------------------------------------------------------
    always @(*) begin
        case (zl)
        3'd0:    begin r_major = 7'd20; r_minor = 7'd8;  end
        3'd1:    begin r_major = 7'd24; r_minor = 7'd9;  end
        3'd2:    begin r_major = 7'd28; r_minor = 7'd11; end
        3'd4:    begin r_major = 7'd36; r_minor = 7'd14; end
        3'd5:    begin r_major = 7'd40; r_minor = 7'd15; end
        3'd6:    begin r_major = 7'd44; r_minor = 7'd17; end
        default: begin r_major = 7'd32; r_minor = 7'd12; end   // step 3
        endcase
    end

    // ------------------------------------------------------------------
    //  which ROM table the pattern engine should read
    // ------------------------------------------------------------------
    always @(*) begin
        case (item)
        3'd4:    model_sel = 2'd2;       // DNA
        3'd3:    model_sel = 2'd1;       // walking figure
        default: model_sel = 2'd0;       // chicken
        endcase
    end

endmodule
