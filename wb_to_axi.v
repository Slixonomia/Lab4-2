module wb_to_axi (
    // Wishbone Interface
    input         wb_clk_i,
    input         wb_rst_i,
    input         wbs_stb_i,
    input         wbs_cyc_i,
    input         wbs_we_i,
    input  [3:0]  wbs_sel_i,
    input  [31:0] wbs_dat_i,
    input  [31:0] wbs_adr_i,
    output        wbs_ack_o,
    output [31:0] wbs_dat_o,

    // AXI-Lite Interface
    output        axi_awvalid,
    input         axi_awready,
    output [31:0] axi_awaddr,
    output        axi_wvalid,
    input         axi_wready,
    output [31:0] axi_wdata,
    output [3:0]  axi_wstrb,
    input         axi_bvalid,
    output        axi_bready,
    output        axi_arvalid,
    input         axi_arready,
    output [31:0] axi_araddr,
    input         axi_rvalid,
    output        axi_rready,
    input  [31:0] axi_rdata,

    // AXI-Stream Interface (X input to FIR)
    output        axis_tvalid_x,
    input         axis_tready_x,
    output [31:0] axis_tdata_x,
    output        axis_tlast_x,

    // AXI-Stream Interface (Y output from FIR)
    input         axis_tvalid_y,
    output        axis_tready_y,
    input  [31:0] axis_tdata_y,
    input         axis_tlast_y
);

    // Configuration registers
    reg ap_start;
    reg ap_done;
    reg ap_idle;
    reg x_ready;
    reg y_ready;
    reg [31:0] data_length;
    reg [31:0] num_taps;
    reg [31:0] tap_params[0:31]; // Max 32 taps

    // Internal signals
    reg [31:0] wb_data_out;
    reg wb_ack;
    reg axis_x_sent;
    reg axis_y_received;
    reg [31:0] y_buffer;

    // Address decoding
    wire is_config_space = (wbs_adr_i >= 32'h3000_0000) && (wbs_adr_i <= 32'h3000_007F);
    wire is_x_addr = (wbs_adr_i >= 32'h3000_0040) && (wbs_adr_i <= 32'h3000_0043);
    wire is_y_addr = (wbs_adr_i >= 32'h3000_0044) && (wbs_adr_i <= 32'h3000_0047);
    wire is_tap_params = (wbs_adr_i >= 32'h3000_0080) && (wbs_adr_i <= 32'h3000_00FF);

    // AXI-Lite control signals
    reg axi_write_active;
    reg axi_read_active;

    // Wishbone to AXI-Lite FSM
    always @(posedge wb_clk_i or posedge wb_rst_i) begin
        if (wb_rst_i) begin
            ap_start <= 1'b0;
            ap_done <= 1'b0;
            ap_idle <= 1'b1;
            x_ready <= 1'b1;
            y_ready <= 1'b0;
            data_length <= 32'h0;
            num_taps <= 32'h0;
            wb_data_out <= 32'h0;
            wb_ack <= 1'b0;
            axi_write_active <= 1'b0;
            axi_read_active <= 1'b0;
            axis_x_sent <= 1'b0;
            axis_y_received <= 1'b0;
            y_buffer <= 32'h0;
        end else begin
            wb_ack <= 1'b0;
            axis_x_sent <= 1'b0;
            
            // Handle AXI-Lite responses
            if (axi_write_active && axi_bvalid) begin
                axi_write_active <= 1'b0;
                wb_ack <= 1'b1;
            end
            
            if (axi_read_active && axi_rvalid) begin
                axi_read_active <= 1'b0;
                wb_data_out <= axi_rdata;
                wb_ack <= 1'b1;
            end
            
            // Handle AXI-Stream Y data
            if (axis_tvalid_y && axis_tready_y) begin
                y_buffer <= axis_tdata_y;
                y_ready <= 1'b1;
                if (axis_tlast_y) begin
                    ap_done <= 1'b1;
                    ap_idle <= 1'b1;
                end
            end
            
            // Wishbone transaction handling
            if (wbs_stb_i && wbs_cyc_i && !wb_ack) begin
                if (is_x_addr) begin
                    if (wbs_we_i) begin
                        if (x_ready) begin
                            axis_x_sent <= 1'b1;
                            x_ready <= 1'b0;
                            wb_ack <= 1'b1;
                        end
                    end else begin
                        wb_data_out <= 32'hFFFF_FFFF;
                        wb_ack <= 1'b1;
                    end
                end else if (is_y_addr) begin
                    if (!wbs_we_i) begin
                        if (y_ready) begin
                            wb_data_out <= y_buffer;
                            y_ready <= 1'b0;
                            wb_ack <= 1'b1;
                        end
                    end else begin
                        wb_ack <= 1'b1;
                    end
                end else if (is_config_space) begin
                    if (wbs_we_i) begin
                        // Write operation
                        case (wbs_adr_i[7:0])
                            8'h00: begin
                                ap_start <= wbs_dat_i[0];
                                if (wbs_dat_i[0]) begin
                                    ap_idle <= 1'b0;
                                    ap_done <= 1'b0;
                                end
                                if (wbs_dat_i[1]) ap_done <= 1'b0;
                            end
                            8'h10: data_length <= wbs_dat_i;
                            8'h14: num_taps <= wbs_dat_i;
                            default: begin
                                if (is_tap_params) begin
                                    tap_params[wbs_adr_i[6:2]] <= wbs_dat_i;
                                end
                            end
                        endcase
                        wb_ack <= 1'b1;
                    end else begin
                        // Read operation
                        case (wbs_adr_i[7:0])
                            8'h00: wb_data_out <= {26'b0, y_ready, x_ready, 1'b0, ap_idle, ap_done, ap_start};
                            8'h10: wb_data_out <= data_length;
                            8'h14: wb_data_out <= num_taps;
                            default: begin
                                if (is_tap_params) begin
                                    wb_data_out <= tap_params[wbs_adr_i[6:2]];
                                end else begin
                                    wb_data_out <= 32'h0;
                                end
                            end
                        endcase
                        wb_ack <= 1'b1;
                    end
                end else begin
                    if (wbs_we_i) begin
                        if (!axi_write_active) begin
                            axi_write_active <= 1'b1;
                        end
                    end else begin
                        if (!axi_read_active) begin
                            axi_read_active <= 1'b1;
                        end
                    end
                end
            end
        end
    end

    // AXI-Lite interface assignments
    assign axi_awvalid = axi_write_active && !axi_awready;
    assign axi_awaddr = wbs_adr_i;
    assign axi_wvalid = axi_write_active && !axi_wready;
    assign axi_wdata = wbs_dat_i;
    assign axi_wstrb = wbs_sel_i;
    assign axi_bready = 1'b1;
    
    assign axi_arvalid = axi_read_active && !axi_arready;
    assign axi_araddr = wbs_adr_i;
    assign axi_rready = 1'b1;

    // AXI-Stream interface assignments
    assign axis_tvalid_x = axis_x_sent;
    assign axis_tdata_x = wbs_dat_i;
    assign axis_tlast_x = 1'b0; // Adjust based on your protocol
    
    assign axis_tready_y = 1'b1; // Always ready to receive Y data

    // Wishbone outputs
    assign wbs_ack_o = wb_ack;
    assign wbs_dat_o = wb_data_out;

endmodule