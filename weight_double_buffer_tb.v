// Write a directed test for the weight double buffer module. Make sure you test
// all its ports and its behaviour when your switch banks.

// *************************************************************************************
// Test bench Implementation Starts
// *************************************************************************************

// Assume: (OY1, OY0, OX1, OX0, OC1, OC0, IC1, IC0, FX, FY, STRIDE) -> (4, 14, 4, 14, 4, 16, 4, 16, 3, 3, 1)
// Assume: Weight width -> 4, Data width -> 16
// Weights per tile: IC0 * OC0 * FX * FY * IC1 -> 9216 
// Weights per SRAM word: Data width / weight width  = 16 / 4 = 4
// SRAM words: 9216 / 4 = 2304 words therefore 2^12 = 4096 (BANK_DEPTH)
// Address width: log_2(4096) = 12


`define DATA_WIDTH 64
`define BANK_ADDR_WIDTH 12
`define BANK_DEPTH 4096
`define WRITE_CYCLE 4

module weight_double_buffer_tb;

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

        // Switch banks (swap read/write banks)
        @(posedge clk);
        switch_banks = 1;
        @(posedge clk);
        switch_banks = 0;

        // Read + check (1-cycle latency)
        have_prev = 0;
        prev = 0;

        ren = 1;

        // Read for bank "rep" times
        for (rep = 0; rep < 5; rep = rep + 1) begin
            if (rep == `WRITE_CYCLE) begin
                wen = 1;
            end

            for (i = 0; i < `BANK_DEPTH; i = i + 1) begin
                @(negedge clk);
                if (rep == 4) begin
                    wadr = i;
                    wdata = i * rep + 10;
                end
                radr = i;

                // data updates on next posedge
                @(posedge clk);

                // check previous address 
                if (have_prev) begin
                    $display("t=%0t: addr=%0d expected=%0d got=%0d", $time, prev, (prev + 10), rdata);
                    if (rdata !== (prev + 10)) begin
                        $fatal(1, "Mismatch @t=%0t: addr=%0d expected=%0d got=%0d",
                            $time, prev, (prev + 10), rdata);
                    end
                end

                prev = i;
                have_prev = 1;
            end

            // check last address
            @(posedge clk);
            if (rdata !== (prev + 10)) begin
                $fatal(1, "Mismatch(last) @t=%0t: addr=%0d expected=%0d got=%0d",
                    $time, prev, (prev + 10), rdata);
            end
        end

        @(negedge clk);
        ren = 0;
        wen = 0;


        // Switch banks (swap read/write banks)
        @(posedge clk);
        switch_banks = 1;
        @(posedge clk);
        switch_banks = 0;

        have_prev = 0;
        prev = 0;

        ren = 1;

        for (i = 0; i < `BANK_DEPTH; i = i + 1) begin
            // launch read address i
            @(negedge clk);
            radr = i;

            // data updates on next posedge
            @(posedge clk);

            // check previous address 
            if (have_prev) begin
                $display("t=%0t: addr=%0d expected=%0d got=%0d", $time, prev, (prev * `WRITE_CYCLE + 10), rdata);
                if (rdata !== (prev * `WRITE_CYCLE + 10)) begin
                    $fatal(1, "Mismatch @t=%0t: addr=%0d expected=%0d got=%0d",
                        $time, prev, (prev * `WRITE_CYCLE + 10), rdata);
                end
            end

            prev = i;
            have_prev = 1;
        end

        // check last address
        @(posedge clk);
        if (rdata !== (prev * 4 + 10)) begin
            $fatal(1, "Mismatch(last) @t=%0t: addr=%0d expected=%0d got=%0d",
                $time, prev, (prev * 4 + 10), rdata);
        end


        $display("Tests Passed!");

        $finish(0);
    end

    initial begin
        $vcdplusfile("dump.vcd");
        $vcdplusmemon();
        $vcdpluson(0, weight_double_buffer_tb);
        `ifdef FSDB
          $fsdbDumpfile("dump.fsdb");
          $fsdbDumpvars(0, weight_double_buffer_tb);
          $fsdbDumpMDA();
        `endif
        #20000000;
        $finish(2);
    end

endmodule

// *************************************************************************************
// Test bench Implementation Stops
// *************************************************************************************
