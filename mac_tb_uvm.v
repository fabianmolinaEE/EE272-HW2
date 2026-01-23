// *****************************************************************************
// MAC UVM test
// *****************************************************************************

`define IFMAP_WIDTH 16
`define WEIGHT_WIDTH 16
`define OFMAP_WIDTH 32
`define TEST_LENGTH 500

interface mac_if (input bit clk);
  logic rst_n;
  logic en;
  logic weight_wen;

  logic signed [`IFMAP_WIDTH - 1 : 0] ifmap_in;
  logic signed [`WEIGHT_WIDTH - 1 : 0] weight_in;
  logic signed [`OFMAP_WIDTH - 1 : 0] ofmap_in;

  logic signed [`IFMAP_WIDTH - 1 : 0] ifmap_out;
  logic signed [`OFMAP_WIDTH - 1 : 0] ofmap_out;
endinterface

// Transaction Object
class mac_item;
  bit rst_n;

  // driven inputs 
  rand bit en;
  rand bit weight_wen;

  rand logic signed [`IFMAP_WIDTH - 1 : 0] ifmap_in;
  rand logic signed [`WEIGHT_WIDTH - 1 : 0] weight_in;
  rand logic signed [`OFMAP_WIDTH - 1 : 0]  ofmap_in;

  // observed outputs
  logic signed [`IFMAP_WIDTH - 1 : 0] ifmap_out;
  logic signed [`OFMAP_WIDTH - 1 : 0] ofmap_out;

  // Random stalls +  weight updates
  constraint en_stalls { en dist {1 := 70, 0 := 30}; }
  constraint weight_updates  { weight_wen dist {1 := 10, 0 := 90}; }

  function void print(int id = "");
    $display("T=%0t [id=%0d] rst_n=%0b en=%0b wwen=%0b ifmap_in=%0d weight_in=%0d ofmap_in=%0d | ifmap_out=%0d ofmap_out=%0d",
             $time, id, rst_n, en, weight_wen, ifmap_in, weight_in, ofmap_in, ifmap_out, ofmap_out);
  endfunction
endclass

// Driver
class driver;
  virtual mac_if vif;
  mailbox drv_mbx;

  task run();
    $display("T=%0t [MAC driver] Starting ...", $time);

    // drive at falling edges so stable at next posedge
    @(negedge vif.clk);
    forever begin
      mac_item transaction;
      drv_mbx.get(transaction);

      vif.en = transaction.en;
      vif.weight_wen = transaction.weight_wen;
      vif.ifmap_in = transaction.ifmap_in;
      vif.weight_in = transaction.weight_in;
      vif.ofmap_in = transaction.ofmap_in;

      @(negedge vif.clk);
    end
  endtask
endclass

// Monitor
class monitor;
  virtual mac_if vif;
  mailbox scb_mbx;

    task run();
    $display("T=%0t [MAC monitor] Starting ...", $time);
    forever begin
        mac_item transaction= new;

        @(posedge vif.clk);

        // Sample reset + inputs immediately at posedge (same time DUT evaluates them)
        transaction.rst_n = vif.rst_n;
        transaction.en = vif.en;
        transaction.weight_wen = vif.weight_wen;

        transaction.ifmap_in = vif.ifmap_in;
        transaction.weight_in = vif.weight_in;
        transaction.ofmap_in = vif.ofmap_in;

        // Then wait a tick and sample outputs after NBAs settle
        #1ps;
        transaction.ifmap_out = vif.ifmap_out;
        transaction.ofmap_out = vif.ofmap_out;

        scb_mbx.put(transaction);
    end
    endtask

endclass

// Scoreboard
class scoreboard;
  mailbox scb_mbx;
  int resp_id;

  logic signed [`WEIGHT_WIDTH-1:0] weight_r_ref;
  logic signed [`IFMAP_WIDTH-1:0] ifmap_r_ref;
  logic signed [`OFMAP_WIDTH-1:0] ofmap_r_ref;

  logic signed [`OFMAP_WIDTH-1:0] expected_ofmap_next;

  task run();
    mac_item transaction;
    resp_id = 0;

    // skip initial pre-stimulus sample (like FIFO)
    scb_mbx.get(transaction);

    weight_r_ref = '0;
    ifmap_r_ref = '0;
    ofmap_r_ref = '0;

    while (resp_id < `TEST_LENGTH) begin
      scb_mbx.get(transaction);
      transaction.print(resp_id);

      if (!transaction.rst_n) begin
        weight_r_ref = '0;
        ifmap_r_ref = '0;
        ofmap_r_ref = '0;
      end else begin
        
        // if en, perform MAC
        if (transaction.en) begin
          ifmap_r_ref = transaction.ifmap_in;
          expected_ofmap_next = (transaction.ifmap_in * weight_r_ref) + transaction.ofmap_in;
          ofmap_r_ref = expected_ofmap_next;
        end

        // update weight
        if (transaction.weight_wen) begin
          weight_r_ref = transaction.weight_in;
        end
      end

      if (transaction.ifmap_out !== ifmap_r_ref) begin
        $display("T=%0t [Scoreboard] IFMAP mismatch: got=%0d expected=%0d",
                 $time, transaction.ifmap_out, ifmap_r_ref);
        $fatal(1);
      end

      if (transaction.ofmap_out !== ofmap_r_ref) begin
        $display("T=%0t [Scoreboard] OFMAP mismatch: got=%0d expected=%0d",
                 $time, transaction.ofmap_out, ofmap_r_ref);
        $fatal(1);
      end

      $display("T=%0t [Scoreboard] Pass", $time);
      resp_id++;
    end

    $display("T=%0t [Scoreboard] Finished %0d checks", $time, resp_id);
    $finish;
  endtask
endclass

// Environment
class env;
  driver d0;
  monitor m0;
  scoreboard s0;

  mailbox scb_mbx;
  virtual mac_if vif;

  function new();
    d0 = new();
    m0 = new();
    s0 = new();
    scb_mbx = new();

    m0.scb_mbx = scb_mbx;
    s0.scb_mbx = scb_mbx;
  endfunction

  virtual task run();
    d0.vif = vif;
    m0.vif = vif;

    fork
      s0.run();
      d0.run();
      m0.run();
    join_any
  endtask
endclass

// Test
class test;
  env e0;
  mailbox drv_mbx;
  int stim_id;

  function new();
    drv_mbx = new();
    e0 = new();
  endfunction

  virtual task run();
    // connect test mailbox -> driver mailbox
    e0.d0.drv_mbx = drv_mbx;

    fork
      e0.run();
    join_none

    apply_stim();
  endtask

  virtual task apply_stim();
    mac_item transaction;
    $display("T=%0t [Test] Starting MAC stimulus ...", $time);

    stim_id = 0;
    while (stim_id < `TEST_LENGTH) begin
      transaction= new();
      void'(transaction.randomize());
      drv_mbx.put(transaction);
      stim_id++;
    end
  endtask
endclass

// Top-level TB module (like fifo_tb)
module mac_tb;

  reg clk;
  reg rst_n;

  always #10 clk = ~clk;

  mac_if _if (clk);

  mac #(
    .IFMAP_WIDTH(`IFMAP_WIDTH),
    .WEIGHT_WIDTH(`WEIGHT_WIDTH),
    .OFMAP_WIDTH(`OFMAP_WIDTH)
  ) dut (
    .clk(_if.clk),
    .rst_n(_if.rst_n),
    .en(_if.en),
    .weight_wen(_if.weight_wen),
    .ifmap_in(_if.ifmap_in),
    .weight_in(_if.weight_in),
    .ofmap_in(_if.ofmap_in),
    .ifmap_out(_if.ifmap_out),
    .ofmap_out(_if.ofmap_out)
  );

  assign _if.rst_n = rst_n;

  initial begin
    test t0;

    clk <= 0;
    rst_n <= 0;

    _if.en <= 0;
    _if.weight_wen <= 0;
    _if.ifmap_in <= '0;
    _if.weight_in <= '0;
    _if.ofmap_in <= '0;

    // synchronous reset low for 2 cycles
    repeat (2) @(posedge clk);
    rst_n <= 1;

    // run test
    t0 = new();
    t0.e0.vif = _if;
    t0.run();

  end

  initial begin
    $vcdplusfile("dump.vcd");
    $vcdplusmemon();
    $vcdpluson(0, mac_tb);
    `ifdef FSDB
      $fsdbDumpfile("dump.fsdb");
      $fsdbDumpvars(0, mac_tb);
      $fsdbDumpMDA();
    `endif
    #20000000;
    $finish(2);
  end

endmodule
