`timescale 1ns/1ps
module tb_projection;
    reg clk=0;
    always #4 clk=~clk;
    reg rst_n=0,start=0;
    reg [7:0] phase=0;
    wire busy,done,fb_we;
    wire [5:0] fb_row;
    wire [12:0] vaddr;
    wire [127:0] w_r,w_g,w_b;
    proj_engine dut(.clk(clk),.rst_n(rst_n),.start(start),.phase(phase),.busy(busy),.done(done),
        .vaddr(vaddr),.vq_r({128{1'b1}}),.vq_g(128'd0),.vq_b(128'd0),
        .fb_we(fb_we),.fb_row(fb_row),.w_r(w_r),.w_g(w_g),.w_b(w_b));
    integer p,c,cv,sv,ex,ey,qx,qy,rows=0;
    function integer nearest(input real x);
        nearest=x>=0 ? $rtoi(x+0.5) : $rtoi(x-0.5);
    endfunction
    always @(negedge clk) if(rst_n && fb_we) begin
        if(fb_row != rows%64) $fatal(1,"projection row order");
        if(w_r !== {128{1'b1}} || w_g !== 0 || w_b !== 0) $fatal(1,"projection pixel pipeline");
        rows=rows+1;
    end
    initial begin #10000000; $fatal(1,"projection watchdog"); end
    initial begin
        repeat(6) @(negedge clk); rst_n=1;
        for(p=0;p<120;p=p+1) begin
            phase=p;
            repeat(3) @(negedge clk);
            start=1; @(negedge clk); start=0;
            wait(dut.st==2); @(negedge clk);
            cv=nearest($cos(6.283185307179586*p/120)*32767);
            sv=nearest($sin(6.283185307179586*p/120)*32767);
            for(c=0;c<128;c=c+1) begin
                qx=((2*c-127)*cv+32768) >>> 16;
                qy=((2*c-127)*sv+32768) >>> 16;
                ex=64+qx; ey=64-qy;
                if(ex<0) ex=0; if(ex>127) ex=127;
                if(ey<0) ey=0; if(ey>127) ey=127;
                if(dut.xy_tab[c] !== ((ex<<7)|ey)) $fatal(1,"coordinate phase=%d col=%d got=%h x=%d y=%d",p,c,dut.xy_tab[c],ex,ey);
            end
            wait(done); @(negedge clk);
        end
        if(rows != 120*64) $fatal(1,"missing rows");
        $display("TEST_PASS projection: 120x128 Q15 coordinates/clamps, 7680 rows, RGB pipeline unchanged");
        $finish;
    end
endmodule
