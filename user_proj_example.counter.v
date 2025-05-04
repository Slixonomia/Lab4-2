module user_proj_example #(
    parameter BITS = 32,
    parameter DELAYS = 10
)(
`ifdef USE_POWER_PINS
    inout vccd1,    // User area 1 1.8V supply
    inout vssd1,    // User area 1 digital ground
`endif

    // Wishbone Slave ports (WB MI A)
    input wb_clk_i,
    input wb_rst_i,
    input wbs_stb_i,
    input wbs_cyc_i,
    input wbs_we_i,
    input [3:0] wbs_sel_i,
    input [31:0] wbs_dat_i,
    input [31:0] wbs_adr_i,
    output reg wbs_ack_o,
    output reg [31:0] wbs_dat_o,

    // Logic Analyzer Signals
    input  [127:0] la_data_in,
    output [127:0] la_data_out,
    input  [127:0] la_oenb,

    // IOs
    input  [`MPRJ_IO_PADS-1:0] io_in,
    output [`MPRJ_IO_PADS-1:0] io_out,
    output [`MPRJ_IO_PADS-1:0] io_oeb,

    // IRQ
    output [2:0] irq
);
    wire clk = wb_clk_i;
    wire rst = wb_rst_i;

    // BRAM signals
    reg [31:0] bram[0:1023];  // 4KB BRAM (1024 x 32-bit)
    reg [31:0] bram_data_out;
    reg bram_we;
    
    // Delay counter for read operations
    reg [3:0] delay_counter;
    reg read_in_progress;
    reg [31:0] read_address;
    
    // Wishbone state machine
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            wbs_ack_o <= 1'b0;
            wbs_dat_o <= 32'h0;
            delay_counter <= 4'h0;
            read_in_progress <= 1'b0;
            bram_we <= 1'b0;
        end else begin
            // Default values
            wbs_ack_o <= 1'b0;
            bram_we <= 1'b0;
            
            // Wishbone transaction detection
            if (wbs_stb_i && wbs_cyc_i && !wbs_ack_o) begin
                if (wbs_we_i) begin
                    // Write operation
                    bram_we <= 1'b1;
                    wbs_ack_o <= 1'b1;
                end else begin
                    // Read operation - start delay counter
                    read_in_progress <= 1'b1;
                    read_address <= wbs_adr_i[11:2];
                    delay_counter <= DELAYS;
                end
            end
            
            // Read delay handling
            if (read_in_progress) begin
                if (delay_counter > 0) begin
                    delay_counter <= delay_counter - 1;
                end else begin
                    // Delay completed - output data and ack
                    wbs_dat_o <= bram[read_address];
                    wbs_ack_o <= 1'b1;
                    read_in_progress <= 1'b0;
                end
            end
        end
    end
    
    // BRAM write operation
    always @(posedge clk) begin
        if (bram_we) begin
            bram[wbs_adr_i[11:2]] <= wbs_dat_i;
        end
    end
    
    // BRAM instance (combinational read)
    always @(*) begin
        bram_data_out = bram[read_address];
    end
    
    // I/O and IRQ connections (tied off)
    assign io_out = {`MPRJ_IO_PADS{1'b0}};
    assign io_oeb = {`MPRJ_IO_PADS{1'b1}};
    assign la_data_out = {128{1'b0}};
    assign irq = 3'b000;
    
endmodule

`default_nettype wire