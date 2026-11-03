// Grayscale DIGITAL index: one rising edge per physical revolution.
// Both levels are filtered for 256 clocks. The 36 ms refractory rejects
// a second mark halfway through a nominal 900 RPM turn. Every complete
// accepted turn from 36 ms to 500 ms is reported (120..1666 RPM).
// rev_timing separately clamps periods beyond the panel scan capabilities.
`include "display_timing.vh"
module index_sync (
    input wire clk, rst_n, raw,
    output wire pulse, lock, hit,
    output reg [25:0] period = 0,
    output reg period_ok = 0,
    output reg period_new = 0,
    output wire raw_level, filtered_level,
    output reg [31:0] edge_count = 0,
    output reg [31:0] accepted_count = 0,
    output reg [31:0] rejected_count = 0
);
    (* ASYNC_REG = "TRUE" *) reg s1 = 0, s2 = 0;
    always @(posedge clk) begin
        if (!rst_n) begin s1 <= 0; s2 <= 0; end
        else begin s1 <= raw; s2 <= s1; end
    end
    reg [7:0] hi_cnt = 0, lo_cnt = 0;
    reg armed = 1, real_pulse = 0;
    always @(posedge clk) begin
        real_pulse <= 0;
        if (!rst_n) begin
            hi_cnt <= 0; lo_cnt <= 0; armed <= 1;
        end else if (s2) begin
            lo_cnt <= 0;
            if (hi_cnt != 255) hi_cnt <= hi_cnt + 1'b1;
            if (armed && hi_cnt == 255) begin real_pulse <= 1; armed <= 0; end
        end else begin
            hi_cnt <= 0;
            if (lo_cnt != 255) lo_cnt <= lo_cnt + 1'b1;
            if (lo_cnt == 255) armed <= 1;
        end
    end
    assign raw_level = s2;
    assign filtered_level = !armed;
    localparam [25:0] REFRACTORY = `VX_CLOCK_HZ / 1000 * 36;
    localparam [25:0] TMO_WAIT = `VX_CLOCK_HZ / `VX_TARGET_RPS - 1;
    localparam [25:0] TMO_RUN = `VX_CLOCK_HZ / 2 - 1;
    reg [25:0] pcnt = 0, idle = 0;
    reg locked = 0, seen_edge = 0, synth = 0;
    wire accept = real_pulse && (!seen_edge || pcnt >= REFRACTORY-1);
    wire timeout_real = locked && idle == TMO_RUN;
    wire [25:0] tmo = locked ? TMO_RUN : TMO_WAIT;
    always @(posedge clk) begin
        period_new <= 0;
        if (!rst_n) begin
            pcnt <= 0; period <= 0; period_ok <= 0; seen_edge <= 0;
            edge_count <= 0; accepted_count <= 0; rejected_count <= 0;
        end else begin
            if (real_pulse) edge_count <= edge_count + 1'b1;
            if (real_pulse && !accept) rejected_count <= rejected_count + 1'b1;
            if (accept) begin
                accepted_count <= accepted_count + 1'b1;
                pcnt <= 0;
                seen_edge <= 1;
                // The first edge after reset/loss is a timestamp, NOT a turn.
                if (seen_edge && !timeout_real) begin
                    period <= pcnt + 1'b1;
                    period_ok <= 1;
                    period_new <= 1;
                end else begin period <= 0; period_ok <= 0; end
            end else if (timeout_real) begin
                seen_edge <= 0; period <= 0; period_ok <= 0; pcnt <= 0;
            end else if (pcnt != 26'h3ffffff) pcnt <= pcnt + 1'b1;
        end
    end
    always @(posedge clk) begin
        synth <= 0;
        if (!rst_n) begin idle <= 0; locked <= 0; end
        else if (accept) begin idle <= 0; locked <= 1; end
        else if (idle == tmo) begin idle <= 0; synth <= 1; locked <= 0; end
        else idle <= idle + 1'b1;
    end
    assign pulse = accept | synth;
    assign lock = locked;
    assign hit = accept;
endmodule
