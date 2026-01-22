module accumulation_buffer
#( 
  parameter DATA_WIDTH = 64,
  parameter BANK_ADDR_WIDTH = 7,
  parameter [BANK_ADDR_WIDTH : 0] BANK_DEPTH = 128
)(
  input clk,
  input rst_n,
  input switch_banks,
  
  input ren,
  input [BANK_ADDR_WIDTH - 1 : 0] radr,
  output [DATA_WIDTH - 1 : 0] rdata,
  
  input wen,
  input [BANK_ADDR_WIDTH - 1 : 0] wadr,
  input [DATA_WIDTH - 1 : 0] wdata,

  input ren_wb,
  input [BANK_ADDR_WIDTH - 1 : 0] radr_wb,
  output [DATA_WIDTH - 1 : 0] rdata_wb
);

  // 0 => bank0 is systolic (R/W), bank1 is writeback (R-only)
  // 1 => bank1 is systolic (R/W), bank0 is writeback (R-only)
  reg current_bank;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      current_bank <= 1'b0;
    else if (switch_banks)
      current_bank <= ~current_bank;
  end

  // --- Declare control wires 
  wire ren_bank0, ren_bank1;
  wire wen_bank0, wen_bank1;
  wire [BANK_ADDR_WIDTH-1:0] radr_bank0, radr_bank1;

  // Mux read ports between systolic and writeback roles
  assign ren_bank0  = (current_bank == 1'b0) ? ren     : ren_wb;
  assign radr_bank0 = (current_bank == 1'b0) ? radr    : radr_wb;
  assign wen_bank0  = (current_bank == 1'b0) ? wen     : 1'b0;

  assign ren_bank1  = (current_bank == 1'b1) ? ren     : ren_wb;
  assign radr_bank1 = (current_bank == 1'b1) ? radr    : radr_wb;
  assign wen_bank1  = (current_bank == 1'b1) ? wen     : 1'b0;

  // SRAM outputs
  wire [DATA_WIDTH - 1 : 0] rdata_bank0;
  wire [DATA_WIDTH - 1 : 0] rdata_bank1;

  // Bank 0 SRAM
  ram_sync_1r1w #(
    .DATA_WIDTH(DATA_WIDTH),
    .ADDR_WIDTH(BANK_ADDR_WIDTH),
    .DEPTH(BANK_DEPTH)
  ) bank0 (
    .clk   (clk),
    .wen   (wen_bank0),
    .wadr  (wadr),
    .wdata (wdata),
    .ren   (ren_bank0),
    .radr  (radr_bank0),
    .rdata (rdata_bank0)
  );

  // Bank 1 SRAM
  ram_sync_1r1w #(
    .DATA_WIDTH(DATA_WIDTH),
    .ADDR_WIDTH(BANK_ADDR_WIDTH),
    .DEPTH(BANK_DEPTH)
  ) bank1 (
    .clk   (clk),
    .wen   (wen_bank1),
    .wadr  (wadr),
    .wdata (wdata),
    .ren   (ren_bank1),
    .radr  (radr_bank1),
    .rdata (rdata_bank1)
  );

  // Output muxing:
  // rdata should reflect the "systolic bank" read port
  // rdata_wb should reflect the "writeback bank" read port
  assign rdata    = (current_bank == 1'b0) ? rdata_bank0 : rdata_bank1;
  assign rdata_wb = (current_bank == 1'b0) ? rdata_bank1 : rdata_bank0;

endmodule
