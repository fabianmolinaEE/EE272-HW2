// Write a UVM test for the sequential address generator (adr_gen_sequential).
// Especially make sure that the address generator works correctly with random
// stalls (meaning if adr_en goes low intermittently), that it resets properly, 
// and that it goes back to zero after reaching the maximum configured value.
`timescale 1ns/1ps

// Your code starts here
`define BANK_ADDR_WIDTH 8
`define TEST_LENGTH (50)
// Interface
interface adr_gen_if (input bit clk);
  logic rst_n;
  logic adr_en;
  logic [`BANK_ADDR_WIDTH-1:0] adr;
  logic config_en;
  logic [`BANK_ADDR_WIDTH-1:0] config_data;
endinterface

// Transaction 
class adr_gen_item;
  bit rst_n;
  rand bit adr_en;
  rand bit config_en;
  rand bit [`BANK_ADDR_WIDTH-1:0] config_data;
  bit  [`BANK_ADDR_WIDTH-1:0] adr; // observed

  function void print(int id = -1);
    $display("T=%0t [transaction_id=%0d] rst_n=%0b adr_en=%0b config_en=%0b config_data=0x%0h adr=0x%0h",
             $time, id, rst_n, adr_en, config_en, config_data, adr);
  endfunction
endclass


// Driver: drives inputs at negedge
class driver;
  virtual adr_gen_if vif;
  mailbox drv_mbx;

  task run();
    $display ("T=%0t [adr_gen_sequential Driver] Starting ...", $time);

    // drive inputs at falling edges so that they are ready for the next rising edge
    @ (negedge vif.clk);  // first negative edge is at 40ns
    forever begin
      adr_gen_item transaction;
      drv_mbx.get(transaction);

      // send the signals to interface
      vif.adr_en      = transaction.adr_en;
      vif.config_en   = transaction.config_en;
      vif.config_data = transaction.config_data;

      @ (negedge vif.clk);
    end

  endtask
endclass

// Monitor: samples at posedge and forwards to scoreboard
class monitor;
  virtual adr_gen_if vif;
  mailbox mon_mbx;
    task run();
        $display ("T=%0t [adr_gen_sequential Monitor] Starting ...", $time);
    
        @ (posedge vif.clk);  // first positive edge is at 50ns
        forever begin
          adr_gen_item transaction = new;
    
          // sample signals from interface
          transaction.rst_n       = vif.rst_n;
          transaction.adr_en      = vif.adr_en;
          transaction.config_en   = vif.config_en;
          transaction.config_data = vif.config_data;
          transaction.adr         = vif.adr;
    
          // send to scoreboard
          mon_mbx.put(transaction);
    
          @ (posedge vif.clk);
        end
    endtask
endclass


// Scoreboard: golden model for sequential adr generator
// Requirements per instructions:
//  - random stalls: adr holds when adr_en=0
//  - reset: adr->0 when rst_n=0
//  - wrap: after reaching max configured value, go back to 0

class scoreboard;
  mailbox scb_mbx;
  int resp_id;

  bit [`BANK_ADDR_WIDTH-1:0] exp_adr;
  bit [`BANK_ADDR_WIDTH-1:0] max_val;
  bit [`BANK_ADDR_WIDTH-1:0] exp_next;
  function new();
    exp_adr = '0;
    max_val = {`BANK_ADDR_WIDTH{1'b1}};
    resp_id = 0;
  endfunction

  task run();
    adr_gen_item tr;

    // optionally skip the first sample like FIFO TB
    scb_mbx.get(tr);
    exp_adr = tr.adr;

    while (resp_id < `TEST_LENGTH) begin
      scb_mbx.get(tr);

      if (tr.config_en)
        max_val = tr.config_data;


      if (!tr.rst_n) begin
        exp_next = '0;
      end else if (tr.adr_en) begin
        exp_next = (exp_adr == max_val) ? '0 : (exp_adr + 1);
      end else begin
        exp_next = exp_adr;
      end

      if (tr.adr !== exp_adr) begin
        $display("T=%0t [Scoreboard] FAIL  adr=0x%0h expected=0x%0h rst_n=%0b adr_en=%0b max_val=0x%0h", $time, tr.adr, exp_adr, tr.rst_n, tr.adr_en, max_val);
    end else begin
        $display("T=%0t [Scoreboard] PASS  adr=0x%0h expected=0x%0h",
                $time, tr.adr, exp_adr);
    end

// Then advance model for NEXT cycle
exp_adr = exp_next;
      resp_id++;
    end

    $finish;
  endtask
endclass


// Environment: instantiates driver, monitor, scoreboard
class env;
  driver          d0;
  monitor         m0;
  scoreboard      s0;
  mailbox         scb_mbx;
  mailbox         mon_mbx;
  virtual adr_gen_if vif;

// constructor to initialize components and mailboxes
  function new();
    d0 = new;
    m0 = new;
    s0 = new;
    scb_mbx = new();
    mon_mbx = new();

    m0.mon_mbx = mon_mbx;
    s0.scb_mbx = mon_mbx;  // Changed from scb_mbx
  endfunction

// run task to set virtual interface and start components
  virtual task run();
    d0.vif = vif;
    m0.vif = vif;
    
    //use fork for parallelism 
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
    e0.d0.drv_mbx = drv_mbx;

    fork
      e0.run();
    join_none

    apply_stim();
  endtask
// apply stimulus task to drive config and adr_en signals
  virtual task apply_stim();
    adr_gen_item tr;
    $display("T=%0t [Test] Starting stimulus ...", $time);

    // First drive a config and some stalls
    stim_id = 0;

    // configure max to something small so wrap happens often
    tr = new;
    tr.adr_en = 0;
    tr.config_en = 1;
    tr.config_data = 8'd15; // wrap after 15
    drv_mbx.put(tr);

    // random stall pattern
    while (stim_id < `TEST_LENGTH) begin
        tr = new;
        void'(tr.randomize() with {
            adr_en dist { 1 := 6, 0 := 4 };
            config_en == 0;
            config_data == '0;
        });
        drv_mbx.put(tr);
        stim_id++;
    end
  endtask
endclass


// Top module: instantiates DUT + interface + hooks reset

module adr_gen_sequential_tb;

  reg clk;
  reg rst_n;

  always #10 clk = ~clk;

  adr_gen_if _if(clk);

  // DUT (adjust params/ports if your module differs)
  adr_gen_sequential #(
    .BANK_ADDR_WIDTH(`BANK_ADDR_WIDTH)
  ) dut (
    .clk(_if.clk),
    .rst_n(_if.rst_n),
    .adr_en(_if.adr_en),
    .adr(_if.adr),
    .config_en(_if.config_en),
    .config_data(_if.config_data)
  );

  assign _if.rst_n = rst_n;

  initial begin
    test t0;

    clk  <= 0;
    rst_n <= 0;

    // hold reset a bit
    #40;
    rst_n <= 1;

    t0 = new();
    t0.e0.vif = _if;
    t0.run();
  end

  initial begin
    $vcdplusfile("dump.vcd");
    $vcdplusmemon();
    $vcdpluson(0, adr_gen_sequential_tb);
    `ifdef FSDB
      $fsdbDumpfile("dump.fsdb");
      $fsdbDumpvars(0, adr_gen_sequential_tb);
      $fsdbDumpMDA();
    `endif

    #2000000;
    $finish(2);
  end

endmodule
