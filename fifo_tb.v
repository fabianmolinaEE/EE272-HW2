`define DATA_WIDTH 4
`define FIFO_DEPTH 3
`define COUNTER_WIDTH 1

module fifo_tb;

  // Write five directed tests for the fifo module that test different corner
  // cases. For example, whether it raises the empty and full flags correctly,
  // whether it clears (empties) when you assert the clr signal. Verify its
  // behaviour on reset. You should also test whether the fifo gives the
  // expected latency between when a data goes in and the earliest it can come
  // out. 

  // Your code starts here
  reg clk;
  reg rst_n;
  reg enq;
  reg deq;
  reg clr;
  reg [`DATA_WIDTH-1:0] din;
  wire [`DATA_WIDTH-1:0] dout;
  wire full_n;
  wire empty_n;
  wire full   = ~full_n;
  wire empty  = ~empty_n;

  fifo #( .DATA_WIDTH(`DATA_WIDTH), .FIFO_DEPTH(`FIFO_DEPTH), .COUNTER_WIDTH(`COUNTER_WIDTH) ) fifo_inst (
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

  
  initial begin
    // first let's test reset behavior
    $display("1 -- Testing reset behavior");
    clk = 0;
    rst_n = 0;
    enq = 0;
    deq = 0;
    clr = 0;
    din = 0;
    #20;
    rst_n = 1;
    #20;
    assert(empty == 1);
    assert(full == 0);
    $display("Reset behavior test passed");
    // now let's test writing to the fifo until full
    $display("2 -- Testing write until full");
    for (int i = 0; i < `FIFO_DEPTH; i = i + 1) begin
      din = i + 1;
      enq = 1;
      #20;
      enq = 0;
      #20;
      assert(empty == 0); // should not be empty after first write
      assert(full == (i == `FIFO_DEPTH - 1)); // full should be true only on last write
    end
    $display("Write until full test passed");
    // now try resetting again
    $display("3 -- Testing reset while full");
    rst_n = 0;
    #20;
    rst_n = 1;
    #20;
    assert(empty == 1);
    assert(full == 0);
    $display("Reset while full test passed");
    // now test reading from the fifo until empty
    $display("4 -- Testing read until empty");
    // first fill it again
    for (int i = 0; i < `FIFO_DEPTH; i = i + 1) begin
      din = i + 1;
      enq = 1;
      #20;
      enq = 0;
      #20;
    end 
    for (int i = 0; i < `FIFO_DEPTH; i = i + 1) begin
      deq = 1;
      #20;
      deq = 0;
      #20;
      assert(dout == i + 1); // check data correctness
      assert(full == 0); // should not be full after read
      assert(empty == (i == `FIFO_DEPTH - 1)); // empty should be true only on last read
    end
    $display("Dequeue until empty test passed");
    //  test simultaneous queue and dequeue
    $display("5 -- Testing simultaneous queue and dequeue");
    // first fill it halfway
    for (int i = 0; i < `FIFO_DEPTH / 2; i = i + 1) begin
      din = i + 1;
      enq = 1;
      #20;  
      enq = 0;
      #20;
    end
    // now do simultaneous queue and dequeue
    for (int i = 0; i < `FIFO_DEPTH; i = i + 1) begin
      din = i + 100; // different data to distinguish
      enq = 1;
      deq = 1;    
      #20;
      enq = 0;
      deq = 0;
      #20;
      assert(dout == i + 1); // check data correctness
    end 
    $display("Simultaneous queue and dequeue test passed");

    //now raise clr bit high and see if fifo empties
    $display("6 -- Testing clr signal");
    // first fill it again
    for (int i = 0; i < `FIFO_DEPTH; i = i + 1) begin
      din = i + 1;
      enq = 1;
      #20;
      enq = 0;
      #20;
    end
    // now assert clr
    clr = 1;
    #20;    
    clr = 0;
    #20;
    assert(empty == 1);
    assert(full == 0);
    $display("Clr signal test passed");

    // now expected latency between when a data goes in and the earliest it can come out
    $display("7 -- Testing latency");
    din = 42;
    enq = 1;
    #20;
    enq = 0;
    #20;
    assert(empty == 0); // data should now be present
    deq = 1;
    #20;
    deq = 0;
    #20;
    assert(dout == 42); // now it should be out
    $display("Latency test passed");
    $display("All tests passed!");
    //

  end

  // Your code ends here

  initial begin
    $vcdplusfile("dump.vcd");
    $vcdplusmemon();
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
