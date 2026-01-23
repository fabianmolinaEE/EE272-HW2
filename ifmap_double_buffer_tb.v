// Write a directed test for the ifmap double buffer module. Make sure you test 
// all its ports and its behaviour when your switch banks.


// *************************************************************************************
// Your code starts here
// *************************************************************************************

`define DATA_WIDTH 64
`define BANK_ADDR_WIDTH 12
`define BANK_DEPTH 4096

module ifmap_double_buffer_tb;

    logic clk;
    logic rst_n;
    logic switch_banks;
    logic ren;
    logic [`BANK_ADDR_WIDTH - 1 : 0] radr;
    logic [`DATA_WIDTH - 1 : 0] rdata;
    logic wen;
    logic [`BANK_ADDR_WIDTH - 1: 0] wadr;
    logic [`DATA_WIDTH - 1 : 0] wdata;

    always #10 clk = ~clk;

    // DUT
    double_buffer #(
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
        .wdata(wdata)
    );

    integer i;
    integer prev;
    integer rep;

    logic have_prev;

    initial begin
        // Initialize signals
        clk = 0;
        rst_n = 0;
        switch_banks = 0;
        wen = 0;
        ren = 0;
        wadr = 0;
        radr = 0;
        wdata = 0;

        // Reset
        repeat (2) @(posedge clk);
        rst_n = 1;

        // Write into write bank
        for (i = 0; i < `BANK_DEPTH; i = i + 1) begin
            @(negedge clk);
            wadr  = i;
            wdata = i + 10;
            wen   = 1;

            @(negedge clk);
            wen   = 0;
        end

        @(posedge clk);
        wen = 0;

        for (rep = 0; rep < 5; rep = rep + 1) begin

            // Switch banks (swap read/write banks)
            @(posedge clk);
            switch_banks = 1;
            @(posedge clk);
            switch_banks = 0;

            have_prev = 0;
            prev = 0;

            ren = 1;
            wen = 1;

            // Read + check (1-cycle latency) + write 
            for (i = 0; i < `BANK_DEPTH; i = i + 1) begin
                // launch read address i
                @(negedge clk);
                radr = i;
                wadr = i;
                wdata = i * rep + 10;

                // data updates on next posedge
                @(posedge clk);
                if (rep == 0) begin
                    // check previous address (skip very first)
                    if (have_prev) begin
                        $display("t=%0t: addr=%0d expected=%0d got=%0d", $time, prev, (prev + 10), rdata);
                        if (rdata !== (prev + 10)) begin
                            $fatal(1, "Mismatch @t=%0t: addr=%0d expected=%0d got=%0d",
                                $time, prev, (prev + 10), rdata);
                        end
                    end
                end
                else if (rep > 0) begin 
                    // check previous address (skip very first)
                    if (have_prev) begin
                        $display("t=%0t: addr=%0d expected=%0d got=%0d", $time, prev, (prev * (rep - 1) + 10), rdata);
                        if (rdata !== (prev * (rep - 1) + 10)) begin
                            $fatal(1, "Mismatch @t=%0t: addr=%0d expected=%0d got=%0d",
                                $time, prev, (prev * (rep - 1) + 10), rdata);
                        end
                    end
                end

                prev = i;
                have_prev = 1;
            end

            // check last address
            @(posedge clk);

            if (rep == 0) begin 
                $display("t=%0t: addr=%0d expected=%0d got=%0d", $time, prev, (prev + 10), rdata);
                if (rdata !== (prev + 10)) begin
                    $fatal(1, "Mismatch(last) @t=%0t: addr=%0d expected=%0d got=%0d",
                        $time, prev, (prev + 10), rdata);
                end
            end

            else if (rep > 0) begin                
                $display("t=%0t: addr=%0d expected=%0d got=%0d", $time, prev, (prev * (rep - 1) + 10), rdata);
                if (rdata !== (prev * (rep - 1) + 10)) begin
                    $fatal(1, "Mismatch(last) @t=%0t: addr=%0d expected=%0d got=%0d",
                        $time, prev, (prev * (rep - 1) + 10), rdata);
                end
            end

            @(negedge clk);
            ren = 0;
            wen = 0;
        end


        $display("Tests Passed!");

        $finish(0);
    end

    initial begin
        $vcdplusfile("dump.vcd");
        $vcdplusmemon();
        $vcdpluson(0, ifmap_double_buffer_tb);
        `ifdef FSDB
          $fsdbDumpfile("dump.fsdb");
          $fsdbDumpvars(0, ifmap_double_buffer_tb);
          $fsdbDumpMDA();
        `endif
        #20000000;
        $finish(2);
    end

endmodule

// *************************************************************************************
// Your code ends here
// *************************************************************************************
