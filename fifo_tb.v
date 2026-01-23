`define DATA_WIDTH 4
`define FIFO_DEPTH 3
`define COUNTER_WIDTH 1

module fifo_tb;

  reg clk;
  reg rst_n;
  reg enq;
  reg deq;
  reg clr;
  reg [`DATA_WIDTH-1:0] din;
  wire [`DATA_WIDTH-1:0] dout;
  wire full_n;
  wire empty_n;

  wire full  = ~full_n;
  wire empty = ~empty_n;

  fifo #(
    .DATA_WIDTH(`DATA_WIDTH),
    .FIFO_DEPTH(`FIFO_DEPTH),
    .COUNTER_WIDTH(`COUNTER_WIDTH)
  ) fifo_inst (
    .clk(clk),
    .rst_n(rst_n),
    .din(din),
    .enq(enq),
    .full_n(full_n),
    .dout(dout),
    .deq(deq),
    .empty_n(empty_n),
    .clr(clr)
  );

  always #10 clk = ~clk;

  // Small Helper: enqueue one word (only if not full)
  task do_enq(input [`DATA_WIDTH-1:0] v);
    begin
      @(negedge clk);
      din = v;
      enq = full_n ? 1'b1 : 1'b0;
      deq = 1'b0;
      @(posedge clk);
      @(negedge clk);
      enq = 1'b0;
    end
  endtask

  // Small Helper: dequeue one word and return observed dout (safe: sample 1 cycle later)
  task do_deq(output [`DATA_WIDTH-1:0] v);
    begin
      @(negedge clk);
      deq = empty_n ? 1'b1 : 1'b0;
      enq = 1'b0;
      @(posedge clk);       
      @(negedge clk);
      deq = 1'b0;
      @(posedge clk);       
      v = dout;
    end
  endtask

  initial begin
    clk = 0;
    rst_n = 0;
    enq = 0;
    deq = 0;
    clr = 0;
    din = 0;

    // 1) Reset behavior
    $display("1 -- Testing reset behavior");
    repeat (2) @(posedge clk);
    rst_n = 1;
    @(posedge clk);

    assert(empty == 1) else $fatal("FIFO not empty after reset");
    assert(full  == 0) else $fatal("FIFO full after reset");
    $display("Reset behavior test passed");


    // 2) Write until full
    $display("2 -- Testing write until full");
    for (int i = 0; i < `FIFO_DEPTH; i++) begin
      do_enq(i + 1);
      @(posedge clk);
      assert(empty == 0) else $fatal("FIFO empty after write");
      assert(full == (i == `FIFO_DEPTH - 1)) else $fatal("Full flag incorrect at i=%0d", i);
    end
    $display("Write until full test passed");

    // 3) Reset while full
    $display("3 -- Testing reset while full");
    @(negedge clk);
    rst_n = 0;
    @(posedge clk);
    @(negedge clk);
    rst_n = 1;
    @(posedge clk);

    assert(empty == 1) else $fatal("FIFO not empty after reset");
    assert(full  == 0) else $fatal("FIFO full after reset");
    $display("Reset while full test passed");

    // 4) Read until empty

    $vcdpluson(0, fifo_tb);
    `ifdef FSDB
    $fsdbDumpfile("dump.fsdb");
    $fsdbDumpvars(0, fifo_tb);
    $fsdbDumpMDA();
    `endif
    #20000000;
    $finish(2);
  end

endmodule
