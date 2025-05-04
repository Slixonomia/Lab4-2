`timescale 10ns / 100ps

module fir_core_fixed_v2 #(
  parameter pADDR_WIDTH = 12,
  parameter pDATA_WIDTH = 32,
  parameter Tape_Num    = 11
)(
  input  wire                     clk,
  input  wire                     rst_n,
  // axi-lite
  output wire                     awready,
  input  wire                     awvalid,
  input  wire [pADDR_WIDTH-1:0]   awaddr,
  output wire                     wready,
  input  wire                     wvalid,
  input  wire [pDATA_WIDTH-1:0]   wdata,
  output wire                     arready,
  input  wire                     arvalid,
  input  wire [pADDR_WIDTH-1:0]   araddr,
  output wire [pDATA_WIDTH-1:0]   rdata,
  output wire                     rvalid,
  // axi-stream
  input  wire                     ss_tvalid,
  input  wire [pDATA_WIDTH-1:0]   ss_tdata,
  output wire                     ss_tready,
  output wire                     sm_tvalid,
  output wire [pDATA_WIDTH-1:0]   sm_tdata,
  // bram
  output wire [3:0]               tap_WE,
  output wire [pADDR_WIDTH-1:0]   tap_A,
  input  wire [pDATA_WIDTH-1:0]   tap_Do,
  output wire [3:0]               data_WE,
  output wire [pADDR_WIDTH-1:0]   data_A,
  input  wire [pDATA_WIDTH-1:0]   data_Do
);

  // Control signals
  reg ap_start;
  reg ap_idle;
  reg ap_done;
  wire ap_ready = ap_idle && !ap_start;

  // Coefficient and data buffers
  reg [pDATA_WIDTH-1:0] coeff [0:Tape_Num-1];
  reg [pDATA_WIDTH-1:0] data_buf [0:Tape_Num-1];
  
  // Pipeline registers
  reg [64:0] accumulator;
  reg [4:0] calc_cnt;
  reg [1:0] pipeline_stage; // 0: idle, 1: mult, 2: add

  // Multiplier and adder with pipeline registers
  reg [31:0] mult_a_reg, mult_b_reg;
  reg [64:0] add_a_reg;
  wire [63:0] mult_result;
  wire [64:0] add_result;

  // Overflow protection
  wire overflow = add_result[64] != add_result[63];
  wire [64:0] saturated_result = overflow ? {add_result[64], {63{add_result[63]}}} : add_result;

  // Output registers
  reg [pDATA_WIDTH-1:0] sm_tdata_reg;
  reg sm_tvalid_reg;

  // Multiplier instance
  mul u_mult (
    .a(mult_a_reg),
    .b(mult_b_reg),
    .result(mult_result)
  );

  // Adder instance
  adder u_adder (
    .a(add_a_reg),
    .b({1'b0, mult_result}),
    .sum(add_result),
    .cout()
  );

  // Main processing pipeline
always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    ap_idle <= 1'b1;
    ap_done <= 1'b0;
    calc_cnt <= 0;
    pipeline_stage <= 0;
    accumulator <= 0;
    sm_tdata_reg <= 0;
    sm_tvalid_reg <= 0;
    for (integer i=0; i<Tape_Num; i=i+1) begin
      coeff[i] <= 0;
      data_buf[i] <= 0;
    end
  end else begin
    ap_done <= 1'b0;
    sm_tvalid_reg <= 1'b0;

    case (pipeline_stage)
        // IDLE stage
      0: begin
        if (ap_start && ap_idle) begin
          ap_idle <= 1'b0;
          pipeline_stage <= 1;
          calc_cnt <= 0;
          accumulator <= 0;
        end
      end
        
      // MULT stage
      1: begin
          // Shift data buffer when starting new calculation
        if (calc_cnt == 0 && ss_tvalid) begin
          for (integer i=Tape_Num-1; i>0; i=i-1)
            data_buf[i] <= data_buf[i-1];
            data_buf[0] <= ss_tdata;
        end
          
        // Setup multiplier inputs
        mult_a_reg <= coeff[calc_cnt];
        mult_b_reg <= data_buf[calc_cnt];
        add_a_reg <= accumulator;
        pipeline_stage <= 2;
      end
        
        // ADD stage
      2: begin
        accumulator <= saturated_result;         
        if (calc_cnt < Tape_Num-1) begin
          calc_cnt <= calc_cnt + 1;
          pipeline_stage <= 1;
        end else begin
          // Final result processing
          sm_tdata_reg <= accumulator[63:32];
          sm_tvalid_reg <= 1'b1;
          ap_done <= 1'b1;
          ap_idle <= 1'b1;
          pipeline_stage <= 0;
        end
      end
    endcase
  end
end

  // AXI-Lite interface
  assign awready = ap_ready;
  assign wready = ap_ready;
  assign arready = 1'b1;
  assign rvalid = arvalid;
  
  assign rdata = (araddr[11:6] == 6'h10 && araddr[5:2] < Tape_Num) ? 
                 coeff[araddr[5:2]] : 
                 (araddr == 12'h0) ? {30'b0, ap_idle, ap_start} : 
                 32'hDEADBEEF;

  // BRAM interface
  assign tap_WE = (awvalid && wvalid && (awaddr[11:6] == 6'h10) && ap_ready) ? 4'b1111 : 0;
  assign tap_A = awaddr;
  assign data_WE = (pipeline_stage == 1 && calc_cnt == 0 && ss_tvalid) ? 4'b1111 : 0;
  assign data_A = calc_cnt;

  // AXI-Stream interface (Rule 10)
  assign ss_tready = (pipeline_stage == 1 && calc_cnt == 0);
  assign sm_tvalid = sm_tvalid_reg;
  assign sm_tdata = sm_tdata_reg;

  // Control register updates (Rule 6)
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ap_start <= 1'b0;
      for (integer i=0; i<Tape_Num; i=i+1)
        coeff[i] <= 0;
    end else if (awvalid && wvalid && ap_ready) begin
      if (awaddr[11:6] == 6'h10 && awaddr[5:2] < Tape_Num)
        coeff[awaddr[5:2]] <= wdata;
      else if (awaddr == 12'h0)
        ap_start <= wdata[0];
    end else if (ap_done) begin
      ap_start <= 1'b0;
    end
  end

endmodule