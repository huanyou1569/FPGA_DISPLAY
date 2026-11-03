`timescale 1ns/1ps
module tb_rotation_timing;
    reg clk=0;
    always #4 clk=~clk;
    reg rst_n=0;
    reg [7:0] phase=0;
    wire signed [15:0] cos_v, sin_v;
    sincos_rom trig(.*);
    reg period_new=0, period_ok=0;
    reg [25:0] period=0;
    wire [12:0] hold_max;
    rev_timing timing(.clk(clk),.rst_n(rst_n),.period_new(period_new),
        .period_ok(period_ok),.period(period),.hold_max(hold_max));
    reg raw=0;
    wire pulse, lock, hit, measured_ok, measured_new;
    wire [25:0] measured;
    index_sync sensor(.clk(clk),.rst_n(rst_n),.raw(raw),.pulse(pulse),.lock(lock),.hit(hit),
        .period(measured),.period_ok(measured_ok),.period_new(measured_new));
    wire frame_done;
    panel_scan scan(.clk(clk),.rst_n(rst_n),.en(1'b1),.mirror(1'b0),.col_ofs(2'd3),.hold_max(hold_max),
        .d_r1(128'd0),.d_g1(128'd0),.d_b1(128'd0),
        .d_r2(128'd0),.d_g2(128'd0),.d_b2(128'd0),.frame_done(frame_done));
    reg seq_rev=0;
    wire [2:0] item;
    show_seq show(.clk(clk),.rst_n(rst_n),.rev(seq_rev),.next(1'b0),.prev(1'b0),
        .step(1'b0),.one_item(1'b0),.item(item));
    integer i, expected_cos, expected_sin, cycles=0, last_frame=0, frames=0;
    always @(posedge clk) begin
        cycles=cycles+1;
        if(rst_n && frame_done) begin
            if(frames>0 && cycles-last_frame != 69440) $fatal(1,"panel frame interval %d",cycles-last_frame);
            last_frame=cycles;
            frames=frames+1;
        end
    end
    task automatic measure(input [25:0] p, input bit valid, input integer want);
        @(negedge clk); period=p; period_ok=valid; period_new=1;
        @(negedge clk); period_new=0;
        repeat(30) @(negedge clk);
        if(hold_max != want) $fatal(1,"hold mismatch period=%d got=%d want=%d",p,hold_max,want);
    endtask
    // Boundary acceleration only: seed elapsed counters, then exercise the real acceptance logic.
    task automatic sensor_period(input [25:0] clocks, input bit valid);
        @(negedge clk); sensor.seen_edge=1; sensor.pcnt=clocks-1;
        force sensor.real_pulse=1;
        @(negedge clk); release sensor.real_pulse;
        if(measured != clocks || measured_ok != valid || !measured_new)
            $fatal(1,"sensor range/period mismatch %d",clocks);
        @(negedge clk);
    endtask
    initial begin #3000000; $fatal(1,"rotation timing watchdog"); end
    initial begin
        repeat(5) @(negedge clk); rst_n=1;
        if(hold_max != 1330) $fatal(1,"cold-start target must be 15rps/120 slices");
        for(i=0;i<120;i=i+1) begin
            @(negedge clk); phase=i;
            @(negedge clk);
            expected_cos=$rtoi($cos(6.283185307179586*i/120)*32767);
            expected_sin=$rtoi($sin(6.283185307179586*i/120)*32767);
            if(($signed(cos_v)-expected_cos)>1 || ($signed(cos_v)-expected_cos)<-1 ||
               ($signed(sin_v)-expected_sin)>1 || ($signed(sin_v)-expected_sin)<-1)
                $fatal(1,"trig mismatch at phase %d",i);
        end
        // Observe actual HUB75 scan frames at the nominal rate before changing speed.
        wait(frames==3);
        $display("CHECK_PASS 120 unique Q15 angles, HUB75 69440 clocks/frame (555.52us)");
        // Disable interval monitor for varying-speed tests.
        force scan.frame_done=0;
        measure(8333333,1,1330); // nominal 900RPM
        measure(6250000,1,787);  // 1200RPM range endpoint
        measure(12500000,1,2415); // 600RPM range endpoint
        measure(8333333,0,1330); // lost measurement restores nominal free-run
        measure(0,1,80);        // divider lower clamp
        measure(67108863,1,6000); // divider upper clamp
        measure(8333333,1,1330);
        sensor_period(8333333,1);
        sensor_period(6250000,1);
        sensor_period(12500000,1);
        sensor_period(6249999,1); // no artificial 1200RPM ceiling
        sensor_period(13888889,1); // 540RPM used to be rejected
        // A second mark halfway round a 900RPM turn must be rejected completely.
        @(negedge clk); sensor.pcnt=4166666;
        force sensor.real_pulse=1;
        if(hit) $fatal(1,"half-turn noise accepted");
        @(negedge clk); release sensor.real_pulse;
        if(measured_new) $fatal(1,"refractory event updated period");
        // 500ms watchdog must fit without 25-bit truncation.
        if(sensor.TMO_RUN != 62499999 || $bits(sensor.idle)!=26) $fatal(1,"watchdog width regression");
        @(negedge clk); sensor.locked=1; sensor.idle=62499998;
        @(negedge clk); if(!lock || pulse) $fatal(1,"watchdog expired early");
        @(negedge clk); if(lock || !pulse) $fatal(1,"watchdog did not expire at 500ms");
        @(negedge clk); sensor.idle=8333331;
        @(negedge clk); if(pulse) $fatal(1,"free-run early");
        @(negedge clk); if(!pulse) $fatal(1,"free-run not 15rps");
        // 10s at the target rate = 150 revolution events, not the old 90.
        for(i=0;i<149;i=i+1) begin
            @(negedge clk); seq_rev=1;
            @(negedge clk); seq_rev=0;
        end
        if(item != 0) $fatal(1,"show advanced before 150 turns");
        @(negedge clk); seq_rev=1;
        @(negedge clk); seq_rev=0;
        if(item != 1) $fatal(1,"show did not advance at 150 turns");
        $display("TEST_PASS rotation_timing: 120 angles, panel interval, divider/range/clamps, sensor range/refractory, 26-bit timeout, 15rps free-run, 10s show");
        $finish;
    end
endmodule
