module wb_decode (
    // Wishbone Slave Interface (from user_project_example)
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

    // Wishbone Master Interface to WB-AXI (3000_xxxx)
    output        wb_axi_stb_o,
    output        wb_axi_cyc_o,
    output        wb_axi_we_o,
    output [3:0]  wb_axi_sel_o,
    output [31:0] wb_axi_dat_o,
    output [31:0] wb_axi_adr_o,
    input         wb_axi_ack_i,
    input  [31:0] wb_axi_dat_i,

    // Wishbone Master Interface to exmem-FIR (3800_xxxx)
    output        wb_fir_stb_o,
    output        wb_fir_cyc_o,
    output        wb_fir_we_o,
    output [3:0]  wb_fir_sel_o,
    output [31:0] wb_fir_dat_o,
    output [31:0] wb_fir_adr_o,
    input         wb_fir_ack_i,
    input  [31:0] wb_fir_dat_i
);

    // Address decoding
    wire to_axi  = (wbs_adr_i[31:16] == 16'h3000);
    wire to_fir  = (wbs_adr_i[31:16] == 16'h3800);

    // Transaction routing
    assign wb_axi_stb_o  = wbs_stb_i & to_axi;
    assign wb_axi_cyc_o  = wbs_cyc_i & to_axi;
    assign wb_axi_we_o   = wbs_we_i;
    assign wb_axi_sel_o  = wbs_sel_i;
    assign wb_axi_dat_o  = wbs_dat_i;
    assign wb_axi_adr_o  = wbs_adr_i;

    assign wb_fir_stb_o  = wbs_stb_i & to_fir;
    assign wb_fir_cyc_o  = wbs_cyc_i & to_fir;
    assign wb_fir_we_o   = wbs_we_i;
    assign wb_fir_sel_o  = wbs_sel_i;
    assign wb_fir_dat_o  = wbs_dat_i;
    assign wb_fir_adr_o  = wbs_adr_i;

    // Response muxing
    reg ack_mux;
    reg [31:0] dat_mux;

    always @(*) begin
        case ({to_axi, to_fir})
            2'b10: begin
                ack_mux = wb_axi_ack_i;
                dat_mux = wb_axi_dat_i;
            end
            2'b01: begin
                ack_mux = wb_fir_ack_i;
                dat_mux = wb_fir_dat_i;
            end
            default: begin
                ack_mux = 1'b0;
                dat_mux = 32'h0;
            end
        endcase
    end

    // Output assignments
    assign wbs_ack_o  = ack_mux;
    assign wbs_dat_o  = dat_mux;

    // Error handling - if address doesn't match either range
    wire addr_error = wbs_stb_i & wbs_cyc_i & !to_axi & !to_fir;

    // Generate error response for invalid addresses
    reg error_ack;
    always @(posedge wb_clk_i or posedge wb_rst_i) begin
        if (wb_rst_i) begin
            error_ack <= 1'b0;
        end else begin
            error_ack <= addr_error & !error_ack;
        end
    end

    // Override outputs for error case
    assign wbs_ack_o  = addr_error ? error_ack : ack_mux;
    assign wbs_dat_o  = addr_error ? 32'hDEADBEEF : dat_mux;

endmodule