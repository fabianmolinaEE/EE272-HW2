`timescale 1ns/1ps

`define DATA_WIDTH      64
`define BANK_ADDR_WIDTH 7
`define BANK_DEPTH      128

module accumulation_buffer_tb;

  reg clk;
  reg rst_n;
  reg switch_banks;

  reg ren;
  reg [`BANK_ADDR_WIDTH - 1 : 0] radr;
  wire [`DATA_WIDTH - 1 : 0] rdata;

  reg wen;
  reg [`BANK_ADDR_WIDTH - 1 : 0] wadr;
  reg [`DATA_WIDTH - 1 : 0] wdata;

  reg ren_wb;
  reg [`BANK_ADDR_WIDTH - 1 : 0] radr_wb;
  wire [`DATA_WIDTH - 1 : 0] rdata_wb;

  // Clock: 20ns period
  always #10 clk = ~clk;

  accumulation_buffer
  #(
    .DATA_WIDTH(`DATA_WIDTH),
    .BANK_ADDR_WIDTH(`BANK_ADDR_WIDTH),
    .BANK_DEPTH(`BANK_DEPTH)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .switch_banks(switch_banks),
    .ren(ren),
    .radr(radr),
    .rdata(rdata),
    .wen(wen),
    .wadr(wadr),
    .wdata(wdata),
    .ren_wb(ren_wb),
    .radr_wb(radr_wb),
    .rdata_wb(rdata_wb)
  );

  // ----------------------------
  // Helper tasks
  // ----------------------------

  task write_word(
    input [`BANK_ADDR_WIDTH-1:0] addr,
    input [`DATA_WIDTH-1:0] data
  );
  begin
    wen   = 1;
    wadr  = addr;
    wdata = data;
    @(posedge clk);
    wen = 0;
  end
  endtask

  task read_word(
    input [`BANK_ADDR_WIDTH-1:0] addr,
    output [`DATA_WIDTH-1:0] data
  );
  begin
    ren  = 1;
    radr = addr;
    @(posedge clk);   // issue read
    ren = 0;
    @(posedge clk);   // wait for SRAM latency
    data = rdata;
  end
  endtask

  task read_word_wb(
    input [`BANK_ADDR_WIDTH-1:0] addr,
    output [`DATA_WIDTH-1:0] data
  );
  begin
    ren_wb  = 1;
    radr_wb = addr;
    @(posedge clk);
    ren_wb = 0;
    @(posedge clk);
    data = rdata_wb;
  end
  endtask

  // ----------------------------
  // Scoreboard
  // ----------------------------
  reg [`DATA_WIDTH-1:0] exp_mem [1:0][`BANK_DEPTH-1:0];
  integer i;
  reg current_bank_tb;

  // ----------------------------
  // Test sequence
  // ----------------------------
  reg [`DATA_WIDTH-1:0] tmp;

  initial begin
    // Init
    clk          = 0;
    rst_n        = 0;
    switch_banks = 0;
    ren          = 0;
    wen          = 0;
    ren_wb       = 0;
    radr         = 0;
    wadr         = 0;
    radr_wb      = 0;
    wdata        = 0;

    current_bank_tb = 0;
    for (i = 0; i < `BANK_DEPTH; i = i + 1) begin
      exp_mem[0][i] = '0;
      exp_mem[1][i] = '0;
    end

    // Apply reset
    repeat (2) @(posedge clk);
    rst_n = 1;
    @(posedge clk);
    $display("\n=== TEST: Reset brings bank select to 0 ===");
    assert(current_bank_tb == 0);
    $display("OK: TB current_bank_tb = %0d", current_bank_tb);

    // ---- Test 1: Write/read bank0 as systolic ----
    $display("\n=== TEST 1: Write & read from systolic bank0 ===");
    write_word(7'd10, 64'h1111_2222_3333_4444);
    exp_mem[current_bank_tb][7'd10] = 64'h1111_2222_3333_4444;
    read_word(7'd10, tmp);
    assert(tmp === exp_mem[current_bank_tb][7'd10])
      else begin $error("Mismatch bank%0d addr10 got %h exp %h", current_bank_tb, tmp, exp_mem[current_bank_tb][7'd10]); $fatal; end;

    // ---- Test 2: Switch banks ----
    $display("\n=== TEST 2: Switch banks (bank1 becomes systolic) ===");
    switch_banks = 1;
    @(posedge clk);
    switch_banks = 0;
    current_bank_tb = ~current_bank_tb;
    @(posedge clk);

    // ---- Test 3: Write/read bank1 as systolic; wb reads old bank0 ----
    $display("\n=== TEST 3: Write/read new systolic bank1; WB reads old bank0 ===");
    write_word(7'd20, 64'hAAAA_BBBB_CCCC_DDDD);
    exp_mem[current_bank_tb][7'd20] = 64'hAAAA_BBBB_CCCC_DDDD;
    read_word(7'd20, tmp);
    assert(tmp === exp_mem[current_bank_tb][7'd20])
      else begin $error("Mismatch bank%0d addr20 got %h exp %h", current_bank_tb, tmp, exp_mem[current_bank_tb][7'd20]); $fatal; end;

    read_word_wb(7'd10, tmp);
    assert(tmp === exp_mem[~current_bank_tb][7'd10])
      else begin $error("WB mismatch bank%0d addr10 got %h exp %h", ~current_bank_tb, tmp, exp_mem[~current_bank_tb][7'd10]); $fatal; end;

    // ---- Test 4: Switch back; persistence check both ports ----
    $display("\n=== TEST 4: Switch back to bank0 systolic; verify persistence ===");
    switch_banks = 1;
    @(posedge clk);
    switch_banks = 0;
    current_bank_tb = ~current_bank_tb;
    @(posedge clk);

    read_word(7'd10, tmp);
    assert(tmp === exp_mem[current_bank_tb][7'd10])
      else begin $error("Mismatch after switch-back bank%0d addr10 got %h exp %h", current_bank_tb, tmp, exp_mem[current_bank_tb][7'd10]); $fatal; end;

    read_word_wb(7'd20, tmp);
    assert(tmp === exp_mem[~current_bank_tb][7'd20])
      else begin $error("WB mismatch after switch-back bank%0d addr20 got %h exp %h", ~current_bank_tb, tmp, exp_mem[~current_bank_tb][7'd20]); $fatal; end;

    // ---- Test 5: Overwrite in current systolic bank; ensure other bank untouched ----
    $display("\n=== TEST 5: Overwrite systolic bank and verify other bank unchanged ===");
    write_word(7'd10, 64'hDEAD_BEEF_CAFE_F00D);
    exp_mem[current_bank_tb][7'd10] = 64'hDEAD_BEEF_CAFE_F00D;

    read_word(7'd10, tmp);
    assert(tmp === exp_mem[current_bank_tb][7'd10])
      else begin $error("Overwrite mismatch bank%0d addr10 got %h exp %h", current_bank_tb, tmp, exp_mem[current_bank_tb][7'd10]); $fatal; end;

    read_word_wb(7'd20, tmp);
    assert(tmp === exp_mem[~current_bank_tb][7'd20])
      else begin $error("WB corruption bank%0d addr20 got %h exp %h", ~current_bank_tb, tmp, exp_mem[~current_bank_tb][7'd20]); $fatal; end;

    // ---- Test 6: Multiple addresses per bank; alternating switch ----
    $display("\n=== TEST 6: Fill multiple addresses across switches ===");
    // switch to bank1
    switch_banks = 1; @(posedge clk); switch_banks = 0; current_bank_tb = ~current_bank_tb; @(posedge clk);
    write_word(7'd30, 64'h0123_4567_89AB_CDEF); exp_mem[current_bank_tb][7'd30] = 64'h0123_4567_89AB_CDEF;
    write_word(7'd31, 64'h0F0F_0F0F_F0F0_F0F0); exp_mem[current_bank_tb][7'd31] = 64'h0F0F_0F0F_F0F0_F0F0;
    read_word(7'd30, tmp); assert(tmp === exp_mem[current_bank_tb][7'd30]) else begin $error("bank%0d addr30 mismatch", current_bank_tb); $fatal; end;
    read_word(7'd31, tmp); assert(tmp === exp_mem[current_bank_tb][7'd31]) else begin $error("bank%0d addr31 mismatch", current_bank_tb); $fatal; end;

    // switch back to bank0 and confirm its contents still good
    switch_banks = 1; @(posedge clk); switch_banks = 0; current_bank_tb = ~current_bank_tb; @(posedge clk);
    read_word(7'd10, tmp); assert(tmp === exp_mem[current_bank_tb][7'd10]) else begin $error("bank%0d addr10 mismatch", current_bank_tb); $fatal; end;
    read_word_wb(7'd30, tmp); assert(tmp === exp_mem[~current_bank_tb][7'd30]) else begin $error("WB bank%0d addr30 mismatch", ~current_bank_tb); $fatal; end;

    $display("\n=== ALL ASSERTIONS PASSED ===");
    $finish;
  end

initial begin
  $vcdplusfile("dump.vcd");
  $vcdplusmemon();
  $vcdpluson(0, accumulation_buffer_tb);
  `ifdef FSDB
  $fsdbDumpfile("dump.fsdb");
  $fsdbDumpvars(0, accumulation_buffer_tb);
  $fsdbDumpMDA();
  `endif
  #20000000;
  $finish(2);
end

// ...existing code...
endmodule
