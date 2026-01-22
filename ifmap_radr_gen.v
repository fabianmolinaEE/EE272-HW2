module ifmap_radr_gen
#( 
  parameter BANK_ADDR_WIDTH = 8
)(
  input clk,
  input rst_n,
  input adr_en,
  output [BANK_ADDR_WIDTH - 1 : 0] adr,
  input config_en,
  input [BANK_ADDR_WIDTH*8 - 1 : 0] config_data
);

  reg [BANK_ADDR_WIDTH - 1 : 0] config_OX0, config_OY0, config_FX, config_FY, 
    config_STRIDE, config_IX0, config_IY0, config_IC1;
  
  always @ (posedge clk) begin
    if (rst_n) begin
      if (config_en) begin
        {config_OX0, config_OY0, config_FX, config_FY, config_STRIDE, 
         config_IX0, config_IY0, config_IC1} <= config_data; 
      end
    end else begin
      {config_OX0, config_OY0, config_FX, config_FY, config_STRIDE, 
       config_IX0, config_IY0, config_IC1} <= 0;
    end
  end
  
  // This is the read address generator for the input double buffer. It is
  // more complex than the sequential address generator because there are
  // overlaps between the input tiles that are read out.  We have already
  // instantiated for you all the configuration registers that will hold the
  // various tiling parameters (OX0, OY0, FX, FY, STRIDE, IX0, IY0, IC1).
  // You need to generate address (adr) for the input buffer in the same
  // sequence as the C++ tiled convolution that you implemented. Make sure you
  // increment/step the address generator only when adr_en is high. Also reset
  // all registers when rst_n is low.  
  
   // first, instantiate loop counters that go with ic1, fy, fx, oy0, ox0
  reg [BANK_ADDR_WIDTH-1:0] ctr_ox0, ctr_oy0, ctr_fx, ctr_fy, ctr_ic1;

  // the indeces within the input feature map tile
  wire [BANK_ADDR_WIDTH-1:0] ix = ctr_ox0 * config_STRIDE + ctr_fx;
  wire [BANK_ADDR_WIDTH-1:0] iy = ctr_oy0 * config_STRIDE + ctr_fy;

  // Flatten (ix, iy, ic1) into a linear address ix + IX0*(iy + IY0*ic1) because of the nature of looping scheme
  wire [BANK_ADDR_WIDTH-1:0] adr_w =
      ix + (config_IX0 * (iy + (config_IY0 * ctr_ic1)));

  assign adr = adr_w;

  // Counter update logic
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ctr_ox0 <= 0;
      ctr_oy0 <= 0;
      ctr_fx  <= 0;
      ctr_fy  <= 0;
      ctr_ic1 <= 0;
    end else if (adr_en) begin
      // increment in loop order: ox0 (fastest), then oy0, fx, fy, ic1 (slowest)
      if (ctr_ox0 + 1 < config_OX0) begin
        ctr_ox0 <= ctr_ox0 + 1;
      // else reset ctr_ox0 and increment next counter
      end else begin
        ctr_ox0 <= 0;
        if (ctr_oy0 + 1 < config_OY0) begin
          ctr_oy0 <= ctr_oy0 + 1;
        // if not max, reset ctr_oy0 and increment next counter
        end else begin
          ctr_oy0 <= 0;
          // check fx counter 
          if (ctr_fx + 1 < config_FX) begin
            ctr_fx <= ctr_fx + 1;
          // if not max, reset ctr_fx and increment next counter
          end else begin
            ctr_fx <= 0;
            if (ctr_fy + 1 < config_FY) begin
              ctr_fy <= ctr_fy + 1;
            end else begin
              // if not max, reset ctr_fy and increment next counter
              ctr_fy <= 0;
              if (ctr_ic1 + 1 < config_IC1) begin
                ctr_ic1 <= ctr_ic1 + 1;
              end else begin
                // if not max, reset ctr_ic1
                ctr_ic1 <= 0;
              end
            end
          end
        end
      end
    end
  end

endmodule
