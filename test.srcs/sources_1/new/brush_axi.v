// 32x32x24 RGB111 canvas, two banks, AXI4-Lite control.
// Upload is always to the inactive bank, in 768 (z,y) rows. BEGIN ->
// R/G/B + WRITE_ROW repeated 768 times -> COMMIT. COMMIT waits until the
// display filler is idle, so a whole fill uses one immutable source bank.
module brush_axi (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 s_axi_aclk CLK", X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF S_AXI, ASSOCIATED_RESET s_axi_aresetn, FREQ_HZ 125000000" *)
    input wire s_axi_aclk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 s_axi_aresetn RST", X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input wire s_axi_aresetn,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWADDR", X_INTERFACE_PARAMETER = "PROTOCOL AXI4LITE, DATA_WIDTH 32, ADDR_WIDTH 8, READ_WRITE_MODE READ_WRITE" *)
    input wire [7:0] s_axi_awaddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWPROT" *) input wire [2:0] s_axi_awprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWVALID" *) input wire s_axi_awvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWREADY" *) output wire s_axi_awready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WDATA" *) input wire [31:0] s_axi_wdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WSTRB" *) input wire [3:0] s_axi_wstrb,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WVALID" *) input wire s_axi_wvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WREADY" *) output wire s_axi_wready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BRESP" *) output reg [1:0] s_axi_bresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BVALID" *) output reg s_axi_bvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BREADY" *) input wire s_axi_bready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARADDR" *) input wire [7:0] s_axi_araddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARPROT" *) input wire [2:0] s_axi_arprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARVALID" *) input wire s_axi_arvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARREADY" *) output wire s_axi_arready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RDATA" *) output reg [31:0] s_axi_rdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RRESP" *) output reg [1:0] s_axi_rresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RVALID" *) output reg s_axi_rvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RREADY" *) input wire s_axi_rready,

    input wire canvas_swap_safe,
    input wire [1:0] mode_active,
    input wire [31:0] revolution_count,
    input wire [25:0] revolution_period,
    input wire sensor_locked,
    input wire period_valid,
    input wire [31:0] sync_flags, sync_edges, sync_accepted, sync_rejected, scan_period,
    output reg mode_set,
    output reg [1:0] mode_value,
    output reg canvas_changed,
    output reg commit_pending,
    output wire canvas_ready,
    input wire [6:0] px, py,
    input wire [5:0] pz,
    output reg [2:0] rgb
);
    reg aw_full, w_full;
    reg [7:0] aw_addr;
    reg [31:0] w_data;
    reg [3:0] w_strb;
    reg [31:0] row_r, row_g, row_b;
    reg [9:0] upload_row;
    reg uploading, active_bank;
    reg bank_valid;
    reg [1:0] upload_mode, bank_mode;
    reg [31:0] snapshot_flags, snapshot_edges, snapshot_accepted, snapshot_rejected, snapshot_scan;
    // ACKs are independent of mode, but only a canvas tagged for this mode
    // may feed the volume filler. An old in-flight commit still completes.
    assign canvas_ready = bank_valid && bank_mode == mode_active;
    (* ram_style = "block" *) reg [31:0] mem_r [0:1535];
    (* ram_style = "block" *) reg [31:0] mem_g [0:1535];
    (* ram_style = "block" *) reg [31:0] mem_b [0:1535];
    wire [10:0] write_addr = (active_bank ? 11'd0 : 11'd768) + {1'b0, upload_row};

    assign s_axi_awready = !aw_full && !s_axi_bvalid;
    assign s_axi_wready = !w_full && !s_axi_bvalid;
    assign s_axi_arready = !s_axi_rvalid;
    function [31:0] merge_bytes;
        input [31:0] old_value, new_value;
        input [3:0] strobes;
        integer i;
        begin
            for (i=0; i<4; i=i+1)
                merge_bytes[i*8 +: 8] = strobes[i] ? new_value[i*8 +: 8] : old_value[i*8 +: 8];
        end
    endfunction

    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            aw_full <= 0; w_full <= 0; aw_addr <= 0; w_data <= 0; w_strb <= 0;
            s_axi_bvalid <= 0; s_axi_bresp <= 0;
            s_axi_rvalid <= 0; s_axi_rresp <= 0; s_axi_rdata <= 0;
            row_r <= 0; row_g <= 0; row_b <= 0; upload_row <= 0;
            uploading <= 0; active_bank <= 0; commit_pending <= 0;
            bank_valid <= 0; upload_mode <= 0; bank_mode <= 0;
            canvas_changed <= 0; mode_set <= 0; mode_value <= 0;
            snapshot_flags <= 0; snapshot_edges <= 0; snapshot_accepted <= 0;
            snapshot_rejected <= 0; snapshot_scan <= 0;
        end else begin
            mode_set <= 0;
            canvas_changed <= 0;
            if (commit_pending && canvas_swap_safe) begin
                active_bank <= ~active_bank;
                commit_pending <= 0;
                bank_valid <= 1;
                bank_mode <= upload_mode;
                canvas_changed <= 1;
            end
            if (s_axi_awvalid && s_axi_awready) begin
                aw_full <= 1;
                aw_addr <= s_axi_awaddr;
            end
            if (s_axi_wvalid && s_axi_wready) begin
                w_full <= 1;
                w_data <= s_axi_wdata;
                w_strb <= s_axi_wstrb;
            end
            if (s_axi_bvalid && s_axi_bready) s_axi_bvalid <= 0;
            if (aw_full && w_full && !s_axi_bvalid) begin
                aw_full <= 0; w_full <= 0;
                s_axi_bvalid <= 1; s_axi_bresp <= 0;
                case (aw_addr)
                8'h10: row_r <= merge_bytes(row_r, w_data, w_strb);
                8'h14: row_g <= merge_bytes(row_g, w_data, w_strb);
                8'h18: row_b <= merge_bytes(row_b, w_data, w_strb);
                8'h1c: begin
                    if (w_strb[0]) begin
                        case (w_data[7:0])
                        8'h01: begin // BEGIN: abandon an incomplete back frame, never a pending commit.
                            if (commit_pending) s_axi_bresp <= 2;
                            else begin upload_row <= 0; uploading <= 1; upload_mode <= mode_active; end
                        end
                        8'h02: begin // WRITE_ROW, auto-increment z*32+y
                            if (commit_pending || !uploading || upload_row >= 768) s_axi_bresp <= 2;
                            else begin
                                mem_r[write_addr] <= row_r;
                                mem_g[write_addr] <= row_g;
                                mem_b[write_addr] <= row_b;
                                upload_row <= upload_row + 1'b1;
                            end
                        end
                        8'h04: begin // COMMIT is accepted only for a complete frame.
                            if (commit_pending || !uploading || upload_row != 768) s_axi_bresp <= 2;
                            else begin commit_pending <= 1; uploading <= 0; end
                        end
                        default: s_axi_bresp <= 2;
                        endcase
                    end
                end
                8'h20: if (w_strb[0]) begin
                    if(w_data[7:0] <= 3) begin mode_value <= w_data[1:0]; mode_set <= 1; end
                    else s_axi_bresp <= 2;
                end
                default: s_axi_bresp <= 2;
                endcase
            end
            if (s_axi_rvalid && s_axi_rready) s_axi_rvalid <= 0;
            if (s_axi_arvalid && s_axi_arready) begin
                s_axi_rvalid <= 1;
                s_axi_rresp <= 0;
                case (s_axi_araddr)
                8'h00: s_axi_rdata <= 32'h56584234; // VXB4: coherent rotation/scan diagnostics
                8'h04: s_axi_rdata <= {24'd0, (mode_active == 2), period_valid, sensor_locked,
                    (upload_row == 768), active_bank, bank_valid, commit_pending, (mode_active != 0)};
                8'h08: s_axi_rdata <= {22'd0, upload_row};
                8'h10: s_axi_rdata <= row_r;
                8'h14: s_axi_rdata <= row_g;
                8'h18: s_axi_rdata <= row_b;
                8'h20: s_axi_rdata <= {30'd0, mode_active};
                8'h24: s_axi_rdata <= revolution_count;
                8'h28: begin // Read PERIOD first to latch a coherent diagnostic snapshot.
                    s_axi_rdata <= {6'd0, revolution_period};
                    snapshot_flags <= sync_flags; snapshot_edges <= sync_edges;
                    snapshot_accepted <= sync_accepted; snapshot_rejected <= sync_rejected;
                    snapshot_scan <= scan_period;
                end
                8'h2c: s_axi_rdata <= snapshot_flags;
                8'h30: s_axi_rdata <= snapshot_edges;
                8'h34: s_axi_rdata <= snapshot_accepted;
                8'h38: s_axi_rdata <= snapshot_rejected;
                8'h3c: s_axi_rdata <= snapshot_scan;
                default: begin s_axi_rdata <= 0; s_axi_rresp <= 2; end
                endcase
            end
        end
    end

    // The exact same model-space transform and six-cycle latency as model_rom.
    wire signed [11:0] dx = $signed({1'b0, px}) - 12'sd64;
    wire signed [11:0] dy = $signed({1'b0, py}) - 12'sd64;
    wire signed [11:0] dz = $signed({1'b0, pz}) - 12'sd32;
    wire signed [11:0] xs = ((dx * 12'sd3) >>> 3) + 12'sd16;
    wire signed [11:0] ys = ((dy * 12'sd3) >>> 3) + 12'sd16;
    wire signed [11:0] zs = ((dz * 12'sd3) >>> 3) + 12'sd12;
    wire inside = xs >= 0 && xs < 32 && ys >= 0 && ys < 32 && zs >= 0 && zs < 24;
    wire [9:0] model_row = {zs[4:0], ys[4:0]};
    reg [10:0] read_addr;
    reg [4:0] x1, x2;
    reg valid1, valid2;
    reg [31:0] line_r, line_g, line_b;
    reg [2:0] rgb3, rgb4, rgb5;
    always @(posedge s_axi_aclk) begin
        read_addr <= inside ? ((active_bank ? 11'd768 : 11'd0) + {1'b0, model_row}) : 11'd0;
        x1 <= xs[4:0];
        // A mode change must not alter a fill already in progress. The top
        // gates new fills with canvas_ready; active_bank stays fixed until safe.
        valid1 <= inside && bank_valid && s_axi_aresetn;
        line_r <= mem_r[read_addr]; line_g <= mem_g[read_addr]; line_b <= mem_b[read_addr];
        x2 <= x1; valid2 <= valid1;
        rgb3 <= valid2 ? {line_r[x2], line_g[x2], line_b[x2]} : 3'd0;
        rgb4 <= rgb3;
        rgb5 <= rgb4;
        rgb <= rgb5;
    end
endmodule
