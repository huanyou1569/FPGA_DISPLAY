`timescale 1ns/1ps
module tb_brush_axi;
    reg clk=0;
    always #4 clk=~clk;
    reg reset_request_n=0;
`ifdef VX_TEST_REAL_RESET
    wire s_axi_aresetn;
    wire [0:0] interconnect_aresetn;
    // Use the actual generated IP wrapper/parameters from this project's BD.
    design_1_brush_reset_0 resetter(
        .slowest_sync_clk(clk), .ext_reset_in(reset_request_n),
        .aux_reset_in(1'b0), .mb_debug_sys_rst(1'b0), .dcm_locked(1'b1),
        .peripheral_aresetn(s_axi_aresetn),
        .interconnect_aresetn(interconnect_aresetn));
`else
    wire s_axi_aresetn=reset_request_n;
`endif
    reg [7:0] s_axi_awaddr=0, s_axi_araddr=0;
    reg [2:0] s_axi_awprot=0, s_axi_arprot=0;
    reg s_axi_awvalid=0, s_axi_wvalid=0, s_axi_bready=0;
    reg s_axi_arvalid=0, s_axi_rready=0;
    wire s_axi_awready, s_axi_wready, s_axi_bvalid, s_axi_arready, s_axi_rvalid;
    reg [31:0] s_axi_wdata=0;
    reg [3:0] s_axi_wstrb=0;
    wire [31:0] s_axi_rdata;
    wire [1:0] s_axi_bresp, s_axi_rresp;
    reg canvas_swap_safe=0;
    reg [1:0] mode_active=0;
    reg [31:0] revolution_count=42;
    reg [25:0] revolution_period=13888889;
    reg sensor_locked=1, period_valid=1;
    reg [31:0] sync_flags=28, sync_edges=20, sync_accepted=18, sync_rejected=2, scan_period=115712;
    wire mode_set, canvas_changed, commit_pending, canvas_ready;
    wire [1:0] mode_value;
    reg [6:0] px=64, py=64;
    reg [5:0] pz=32;
    wire [2:0] rgb;
    brush_axi dut(.s_axi_aclk(clk), .*);
    always @(posedge clk) if (mode_set) mode_active <= mode_value;
    task automatic wr(input [7:0] a, input [31:0] d, input [3:0] st,
                      input integer ad, input integer wd, input [1:0] response=0);
        fork
            begin
                repeat(ad+1) @(negedge clk);
                s_axi_awaddr=a; s_axi_awvalid=1;
                do @(posedge clk); while(!s_axi_awready);
                @(negedge clk); s_axi_awvalid=0;
            end
            begin
                repeat(wd+1) @(negedge clk);
                s_axi_wdata=d; s_axi_wstrb=st; s_axi_wvalid=1;
                do @(posedge clk); while(!s_axi_wready);
                @(negedge clk); s_axi_wvalid=0;
            end
        join
        while(!s_axi_bvalid) @(negedge clk);
        if(s_axi_bresp !== response) $fatal(1,"BRESP addr=%h got=%h want=%h",a,s_axi_bresp,response);
        repeat(2) begin @(negedge clk); if(!s_axi_bvalid || s_axi_bresp !== response) $fatal(1,"B backpressure"); end
        s_axi_bready=1;
        @(posedge clk); @(negedge clk); s_axi_bready=0;
    endtask
    task automatic rd(input [7:0] a, input [31:0] expected, input [1:0] response=0);
        @(negedge clk); s_axi_araddr=a; s_axi_arvalid=1;
        do @(posedge clk); while(!s_axi_arready);
        @(negedge clk); s_axi_arvalid=0;
        while(!s_axi_rvalid) @(negedge clk);
        if(s_axi_rdata !== expected || s_axi_rresp !== response) $fatal(1,"read %h got %h",a,s_axi_rdata);
        repeat(2) begin @(negedge clk); if(!s_axi_rvalid || s_axi_rdata !== expected) $fatal(1,"R backpressure"); end
        s_axi_rready=1;
        @(posedge clk); @(negedge clk); s_axi_rready=0;
    endtask
    task automatic pixel(input [2:0] expected);
        repeat(8) @(negedge clk);
        if(rgb !== expected) $fatal(1,"pixel got %h expected %h",rgb,expected);
    endtask
    task automatic frame(input [2:0] colour);
        integer row;
        reg [31:0] r,g,b;
        wr('h1c,1,15,0,1);
        for(row=0;row<768;row=row+1) begin
            r=(row==400 && colour[2]) ? 32'h10000 : 0;
            g=(row==400 && colour[1]) ? 32'h10000 : 0;
            b=(row==400 && colour[0]) ? 32'h10000 : 0;
            wr('h10,r,15,row%3,0); wr('h14,g,15,0,row%3);
            wr('h18,b,15,0,0); wr('h1c,2,15,0,0);
        end
        rd('h08,768);
    endtask
    reg [2:0] expected_pipe [0:5];
    integer i,j;
    initial begin
        #2000000; $fatal(1,"watchdog");
    end
    initial begin
        repeat(20) @(negedge clk); reset_request_n=1;
        repeat(300) @(negedge clk);
        if(s_axi_aresetn !== 1) $fatal(1,"Peripheral reset never released: check actual reset IP polarity and constants");
`ifdef VX_TEST_REAL_RESET
        if(interconnect_aresetn !== 1) $fatal(1,"Interconnect reset never released");
`endif
        rd(0,32'h56584234); rd('h24,42);
        rd('h28,13888889); // snapshot is tied to this exact period read
        sync_flags=0; sync_edges=999; scan_period=69440;
        rd('h2c,28); rd('h30,20); rd('h34,18); rd('h38,2); rd('h3c,115712);
        rd('h28,13888889); rd('h2c,0); rd('h30,999); rd('h3c,69440);
        pixel(0);
        wr('h10,32'h11223344,15,4,0);
        wr('h10,32'haabbccdd,5,0,4);
        rd('h10,32'h11bb33dd); // byte strobes
        wr('h1c,4,15,0,0,2); // cannot commit an incomplete frame
        rd('hfc,0,2);
        frame(4);
        wr('h1c,4,15,0,0);
        if(!commit_pending || canvas_ready) $fatal(1,"unsafe bank swap");
        wr('h1c,1,15,0,0,2); // pending frame is immutable
        pixel(0);
        canvas_swap_safe=1;
        repeat(3) @(negedge clk);
        if(commit_pending || !canvas_ready) $fatal(1,"commit not acknowledged");
        pixel(4);
        for(i=0;i<6;i=i+1) expected_pipe[i]=4;
        for(i=0;i<26;i=i+1) begin
            px=(i%3==0) ? 0 : 64;
            @(posedge clk);
            for(j=5;j>0;j=j-1) expected_pipe[j]=expected_pipe[j-1];
            expected_pipe[0]=(px==64) ? 4 : 0;
            #1;
            if(rgb !== expected_pipe[5]) $fatal(1,"six-cycle pattern alignment at %0d",i);
            @(negedge clk);
        end
        px=64;
        frame(2);
        pixel(4); // writes to back bank must not corrupt the displayed bank
        canvas_swap_safe=0;
        wr('h1c,4,15,0,0);
        pixel(4);
        canvas_swap_safe=1;
        pixel(2);
        wr('h20,1,1,0,2);
        rd('h20,1);
        if(canvas_ready) $fatal(1,"demo-tagged bank exposed in brush mode");
        frame(5);
        canvas_swap_safe=0;
        wr('h1c,4,15,0,0);
        wr('h20,2,1,2,0);
        rd('h20,2);
        canvas_swap_safe=1;
        pixel(5); // immutable old source remains readable; new fills are gated by canvas_ready
        if(commit_pending || canvas_ready) $fatal(1,"brush commit exposed in snake mode or not ACKed");
        frame(6);
        wr('h1c,4,15,0,0);
        pixel(6);
        if(!canvas_ready) $fatal(1,"snake bank not ready");
        wr('h20,3,1,0,0);
        rd('h20,3);
        if(canvas_ready) $fatal(1,"snake bank exposed as tetris");
        frame(3); wr('h1c,4,15,0,0); pixel(3);
        if(!canvas_ready) $fatal(1,"tetris bank not ready");
        wr('h20,4,1,0,0,2);
        rd('h20,3);
        wr('h20,0,0,0,0); // no byte-enable must not change selected mode
        rd('h20,3);
        // Reset while only AW has arrived: discard it, no ghost write.
        @(negedge clk); s_axi_awaddr='h10; s_axi_awvalid=1;
        @(posedge clk); @(negedge clk); s_axi_awvalid=0; reset_request_n=0;
        repeat(300) @(negedge clk);
        if(s_axi_aresetn !== 0) $fatal(1,"External reset not propagated");
        reset_request_n=1;
        repeat(300) @(negedge clk);
        if(s_axi_aresetn !== 1) $fatal(1,"Reset failed to release after restart");
        rd('h10,0); pixel(0);
        $display("TEST_PASS brush_axi: split channels, backpressure, WSTRB, full frame, banks, latency, reset");
        $finish;
    end
endmodule
