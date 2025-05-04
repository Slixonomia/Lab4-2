`timescale 10ns / 100ps

module tb_fir_core_fixed_v2();

  reg clk = 0;
  reg rst_n = 0;

  parameter pADDR_WIDTH = 12;
  parameter pDATA_WIDTH = 32;
  parameter Tape_Num    = 11;
  parameter INPUT_FILE  = "samples_triangular_wave.txt";
  parameter OUTPUT_FILE = "out_gold.txt";
  parameter NUM_SAMPLES = 256;

  // AXI-Lite interface
  reg awvalid = 0;
  reg [pADDR_WIDTH-1:0] awaddr = 0;
  reg wvalid = 0;
  reg [pDATA_WIDTH-1:0] wdata = 0;
  reg arvalid = 0;
  reg [pADDR_WIDTH-1:0] araddr = 0;
  wire awready;
  wire wready;
  wire arready;
  wire [pDATA_WIDTH-1:0] rdata;
  wire rvalid;

  // AXI-Stream interface
  reg ss_tvalid = 0;
  reg [pDATA_WIDTH-1:0] ss_tdata = 0;
  wire ss_tready;
  wire sm_tvalid;
  wire [pDATA_WIDTH-1:0] sm_tdata;

  // BRAM interface
  wire [3:0] tap_WE;
  wire [pADDR_WIDTH-1:0] tap_A;
  wire [3:0] data_WE;
  wire [pADDR_WIDTH-1:0] data_A;
  
  // Test data storage
  integer input_data [0:NUM_SAMPLES-1];
  integer golden_output [0:NUM_SAMPLES-1];
  integer actual_output [0:NUM_SAMPLES-1];
  integer sample_count = 0;
  integer error_count = 0;

  // Clock generation
  always #5 clk = ~clk;

  fir_core_fixed_v2 #(
    .pADDR_WIDTH(pADDR_WIDTH),
    .pDATA_WIDTH(pDATA_WIDTH),
    .Tape_Num(Tape_Num)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .awready(awready),
    .awvalid(awvalid),
    .awaddr(awaddr),
    .wready(wready),
    .wvalid(wvalid),
    .wdata(wdata),
    .arready(arready),
    .arvalid(arvalid),
    .araddr(araddr),
    .rdata(rdata),
    .rvalid(rvalid),
    .ss_tvalid(ss_tvalid),
    .ss_tdata(ss_tdata),
    .ss_tready(ss_tready),
    .sm_tvalid(sm_tvalid),
    .sm_tdata(sm_tdata),
    .tap_WE(tap_WE),
    .tap_A(tap_A),
    .data_WE(data_WE),
    .data_A(data_A),
    .tap_Do(32'b0),
    .data_Do(32'b0)
  );

  initial begin
    $readmemh(samples_triangular_wave, input_data);
    $readmemh(out_gold, golden_output);
  end

  initial begin

    #10 rst_n = 1;
    #20;
    
    program_coefficients();
    
    start_fir();
    
    for (sample_count = 0; sample_count < NUM_SAMPLES; sample_count++) begin
      send_sample(input_data[sample_count]);
      wait_for_result();
      verify_result(sample_count);
    end
    
    $display("\nTest Complete");
    $display("Processed %0d samples", sample_count);
    $display("Found %0d errors", error_count);
    
    if (error_count == 0) begin
      $display("TEST PASSED");
    end else begin
      $display("TEST FAILED");
    end
    
    $finish;
  end

  task program_coefficients();
    integer i;
    begin
      $display("Programming FIR coefficients...");
      
      integer coeffs [0:Tape_Num-1] = '{0, -10, -9, 23, 56, 63, 56, 23, -9, -10, 0};
      
      for (i = 0; i < Tape_Num; i++) begin
        write_register(12'h10 + (i << 2), coeffs[i]);
      end
      
      write_register(12'h14, NUM_SAMPLES);
      
      $display("Coefficient programming complete");
    end
  endtask

  task start_fir();
    begin
      $display("Starting FIR processing...");
      write_register(12'h0, 1); // Set ap_start
      #10;
    end
  endtask

  task send_sample(input integer sample);
    begin
      ss_tvalid = 1;
      ss_tdata = sample;
      
      @(posedge clk);
      while (!ss_tready) begin
        @(posedge clk);
      end
      
      ss_tvalid = 0;
      $display("Sent sample %0d: %0d", sample_count, sample);
    end
  endtask

  task wait_for_result();
    begin
      @(posedge clk);
      while (!sm_tvalid) begin
        @(posedge clk);
      end
    end
  endtask

  task verify_result(input integer sample_idx);
    integer expected;
    begin
      actual_output[sample_idx] = sm_tdata;
      expected = golden_output[sample_idx];
      
      if (actual_output[sample_idx] !== expected) begin
        $display("ERROR: Sample %0d - Expected: %0d, Got: %0d", 
                sample_idx, expected, actual_output[sample_idx]);
        error_count++;
      end else begin
        $display("Sample %0d OK - Output: %0d", sample_idx, actual_output[sample_idx]);
      end
    end
  endtask

  task write_register(input [pADDR_WIDTH-1:0] addr, input [pDATA_WIDTH-1:0] data);
    begin
      @(posedge clk);
      awvalid = 1;
      awaddr = addr;
      wvalid = 1;
      wdata = data;
      
      @(posedge clk);
      while (!(awready && wready)) begin
        @(posedge clk);
      end
      
      awvalid = 0;
      wvalid = 0;
      #10;
    end
  endtask

  always @(posedge clk) begin
    if (sm_tvalid) begin
      $display("FIR Output: %0d", sm_tdata);
    end
  end

endmodule