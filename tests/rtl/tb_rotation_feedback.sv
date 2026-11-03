`timescale 1ns/1ps
// Production 125 MHz clock, REAL raw pulses, no forced internal counters.
module tb_rotation_feedback;
    reg clk=0;
    always #4 clk=~clk;
    reg rst_n=0, raw=0;
    wire pulse, lock, hit, period_ok, period_new, raw_level, filtered_level;
    wire [25:0] period;
    wire [31:0] edge_count, accepted_count, rejected_count;
    index_sync sensor(.*);
    wire [12:0] hold_max;
    rev_timing timing(.clk(clk),.rst_n(rst_n),.period_new(period_new),.period_ok(period_ok),.period(period),.hold_max(hold_max));
    wire frame_done;
    panel_scan scan(.clk(clk),.rst_n(rst_n),.en(1'b1),.mirror(1'b0),.col_ofs(2'd3),.hold_max(hold_max),
        .d_r1(128'd0),.d_g1(128'd0),.d_b1(128'd0),.d_r2(128'd0),.d_g2(128'd0),.d_b2(128'd0),.frame_done(frame_done));
    integer cycles=0, last_frame=0, last_delta=0, frames=0;
    integer expected_frame=69440, legal_new=69440, verified_frames=0, last_raw_cycle=0;
    reg monitor_frames=1;
    always @(posedge clk) begin
        cycles=cycles+1;
        if(rst_n && frame_done) begin
            last_delta=cycles-last_frame;
            if(frames>0 && last_delta!=expected_frame && last_delta!=legal_new)
                $fatal(1,"mixed-speed frame interval %0d, legal %0d/%0d",last_delta,expected_frame,legal_new);
            if(frames>0 && monitor_frames) begin
                if(last_delta!=expected_frame) $fatal(1,"actual scan interval got=%0d want=%0d",last_delta,expected_frame);
                verified_frames=verified_frames+1;
            end
            last_frame=cycles; frames=frames+1;
        end
    end
    task automatic edge_raw;
        @(negedge clk); raw=1; last_raw_cycle=cycles;
        repeat(512) @(negedge clk);
        raw=0;
    endtask
    task automatic revolution(input integer clocks);
        if(cycles-last_raw_cycle>=clocks) $fatal(1,"stimulus missed next revolution");
        while(cycles-last_raw_cycle<clocks-1) @(negedge clk);
        edge_raw();
    endtask
    task automatic settle_scan(input integer clocks, input integer expected_hold);
        repeat(35) @(negedge clk);
        if(period!==clocks || !period_ok || !lock) $fatal(1,"measurement p=%0d got=%0d valid=%b lock=%b",clocks,period,period_ok,lock);
        if(hold_max!=expected_hold) $fatal(1,"divider hold=%0d want=%0d",hold_max,expected_hold);
        repeat(3) begin @(posedge frame_done); @(negedge clk); end
        expected_frame=32*(840+expected_hold);
        monitor_frames=1;
        repeat(3) begin @(posedge frame_done); @(negedge clk); end
        if(clocks-expected_frame*120>=3840 || clocks<expected_frame*120) $fatal(1,"120-slice quantization");
        $display("CHECK_PASS raw-input period=%0d RPM=%0d hold=%0d actual_frame=%0d cycles slice_us=%f",period,7500000000.0/period,hold_max,last_delta,last_delta*0.008);
        monitor_frames=0;
    endtask
    initial begin #1800000000; $fatal(1,"feedback watchdog"); end
    initial begin
        repeat(8) @(negedge clk); rst_n=1;
        // Less than 256 clocks high is electrical noise and must not count.
        raw=1; repeat(100) @(negedge clk); raw=0;
        repeat(300) @(negedge clk);
        if(edge_count || period_ok) $fatal(1,"short glitch passed filter");
        edge_raw();
        if(accepted_count!=1 || period_ok || period!=0) $fatal(1,"first edge is not a complete revolution");
        // All subsequent rising edges are exactly clocks cycles apart.
        monitor_frames=0;
        legal_new=115712;
        revolution(13888889);
        settle_scan(13888889,2776);
        // Change speed on a continuously running sensor, without DUT reset.
        legal_new=69440; revolution(8333333); settle_scan(8333333,1330);
        legal_new=47328; revolution(5681818); settle_scan(5681818,639);
        // A filtered second mark just 1 ms later is rejected for EVERY consumer.
        repeat(125000) @(negedge clk); edge_raw();
        if(accepted_count!=4 || rejected_count!=1 || edge_count!=5) $fatal(1,"refractory diagnostics");
        legal_new=69440;
        repeat(62500000) @(negedge clk);
        if(lock || period_ok || period!=0 || hold_max!=1330) $fatal(1,"loss left stale RPM/timing");
        repeat(3) begin @(posedge frame_done); @(negedge clk); end
        if(last_delta!=69440) $fatal(1,"fallback frame timing");
        expected_frame=69440;
        edge_raw();
        if(period_ok || period!=0 || !lock) $fatal(1,"reacquisition used stale timestamp");
        legal_new=115712; revolution(13888889); settle_scan(13888889,2776);
        if(verified_frames<12) $fatal(1,"insufficient actual scan checks");
        $display("TEST_PASS rotation_feedback: real 125MHz raw pulses, 540/900/1320RPM, actual panel intervals, 120 slices, filter/refractory, 500ms loss/fallback/reacquire");
        $finish;
    end
endmodule
