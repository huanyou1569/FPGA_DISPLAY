`timescale 1ns/1ps
module tb_brush_panel;
    reg clk=0;
    always #4 clk=~clk;
    reg [1:0] sw=0;
    reg [3:0] btn=8;
    reg sensor=0;
    reg [2:0] brush_rgb=3'b101;
    reg canvas_changed=0, canvas_commit_pending=0, canvas_mode_ready=1;
    reg brush_mode_set=0;
    reg [1:0] brush_mode_value=0;
    wire [1:0] brush_mode;
    wire canvas_swap_safe, sensor_locked, period_valid;
    wire [6:0] brush_px, brush_py;
    wire [5:0] brush_pz;
    wire [31:0] revolution_count;
    wire [25:0] revolution_period;
    wire [31:0] sync_flags, sync_edges, sync_accepted, sync_rejected, scan_period;
    wire [3:0] led;
    wire [4:0] p_addr;
    wire p_clk,p_lat,p_oe,p_r1,p_g1,p_b1,p_r2,p_g2,p_b2;
    test_panel #(.DEBOUNCE_CYCLES(3)) dut(.*);
    integer frames=0;
    always @(posedge clk) if(dut.frame_done) frames=frames+1;
    task automatic fill_finished;
        wait(dut.fill_busy === 1);
        wait(dut.fill_done === 1);
        repeat(4) @(negedge clk);
    endtask
    initial begin #50000000; $fatal(1,"panel watchdog"); end
    initial begin
        repeat(8) @(negedge clk); btn=0;
        fill_finished();
        if(!dut.u_vol.vol_g[4160][94] || !dut.u_vol.vol_b[4160][94]) $fatal(1,"legacy ball missing");
        canvas_commit_pending=1;
        brush_mode_value=1; brush_mode_set=1;
        @(negedge clk); brush_mode_set=0;
        repeat(30) @(negedge clk);
        if(!brush_mode || dut.fill_go || dut.fill_busy) $fatal(1,"fill started before commit completed");
        canvas_commit_pending=0; canvas_changed=1;
        @(negedge clk); canvas_changed=0;
        fill_finished();
        if(dut.u_vol.vol_r[4160] !== {128{1'b1}} || dut.u_vol.vol_g[4160] !== 0 ||
           dut.u_vol.vol_b[4160] !== {128{1'b1}}) $fatal(1,"brush not selected");
        // One short bounce then one stable press. Other buttons cannot retrigger it.
        btn[2]=1; @(negedge clk); btn[2]=0;
        repeat(12) @(negedge clk);
        if(!brush_mode) $fatal(1,"bounce toggled mode");
        canvas_mode_ready=0; // incoming mode has no matching complete frame yet
        wait(!dut.fill_busy && !dut.fill_go);
        btn[2]=1;
        repeat(20) @(negedge clk);
        if(brush_mode != 2) $fatal(1,"BTN2 did not select snake");
        if(dut.fill_busy || dut.fill_go) $fatal(1,"snake fill started with wrong-mode bank");
        canvas_mode_ready=1; canvas_changed=1;
        @(negedge clk); canvas_changed=0;
        fill_finished();
        btn[0]=1; repeat(20) @(negedge clk); btn[0]=0;
        repeat(20) @(negedge clk);
        if(brush_mode != 2) $fatal(1,"held BTN2 retriggered on another button");
        btn[2]=0; repeat(20) @(negedge clk);
        btn[2]=1; repeat(20) @(negedge clk);
        if(brush_mode != 3) $fatal(1,"BTN2 did not select tetris");
        btn[2]=0; repeat(20) @(negedge clk);
        btn[2]=1; repeat(20) @(negedge clk);
        if(brush_mode != 0) $fatal(1,"fourth mode did not wrap to demo");
        // Let any queued demo redraw complete; top must continue scanning.
        repeat(2300000) @(negedge clk);
        if(frames < 10) $fatal(1,"panel scan stopped");
        // Exercise the real top-level phase controller with accelerated ready/frame events.
        // Pixel projection and physical frame duration are covered separately.
        force dut.idx_lock=0;
        force dut.idx_pulse=0;
        force dut.idx_pend=0;
        force dut.proj_ready=1;
        force dut.frame_done=1;
        dut.proj_phase=0;
        repeat(119) @(negedge clk);
        if(dut.proj_phase != 119) $fatal(1,"phase sweep did not reach slice119");
        @(negedge clk);
        if(dut.proj_phase != 0) $fatal(1,"phase sweep did not wrap after120 slices");
        force dut.idx_lock=1;
        dut.proj_phase=119;
        repeat(3) @(negedge clk);
        if(dut.proj_phase != 119) $fatal(1,"locked final slice wrapped without mark");
        release dut.idx_lock;
        release dut.idx_pulse;
        release dut.idx_pend;
        release dut.proj_ready;
        release dut.frame_done;
        btn=8; repeat(10) @(negedge clk);
        if(brush_mode) $fatal(1,"reset did not select demo");
        $display("TEST_PASS brush_panel: legacy fill, safe commit, brush source, debounce, held button, scan, reset");
        $finish;
    end
endmodule
