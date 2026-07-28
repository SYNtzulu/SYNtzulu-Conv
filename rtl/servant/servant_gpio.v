module servant_gpio
  (input wire i_wb_clk,
   input wire i_wb_rst,
   input wire [31:0] i_wb_adr,
   input wire [31:0] i_wb_dat,
   input wire i_wb_we,
   input wire i_wb_cyc,
   output reg [31:0] o_wb_rdt,
   output wire [3:0] led,
   input wire [2:0] buttons
   );

/*   always @(posedge i_wb_clk) begin
      o_wb_rdt <= {buttons,27'b0,o_gpio};
      if (i_wb_cyc & i_wb_we)
		o_gpio <= i_wb_dat[1:0];
   end*/

reg [3:0] o_gpio_reg;

// ASIC: senza reset i pad led restano al valore casuale di power-up finche'
// il firmware non scrive il registro GPIO.
always @(posedge i_wb_clk or posedge i_wb_rst) begin
      if (i_wb_rst) begin
         o_wb_rdt <= 0;
         o_gpio_reg <= 0;
      end
      else begin
         o_wb_rdt <= {buttons,25'b0,o_gpio_reg};
         if (i_wb_cyc & i_wb_we)
            o_gpio_reg <= i_wb_dat[3:0];
      end
   end

assign led = o_gpio_reg;

/*
always @(posedge i_wb_clk) begin
      o_wb_rdt <= {buttons,o_gpio[28:0]};
      if (i_wb_cyc & i_wb_we)
		o_gpio <= i_wb_dat;
   end
*/
endmodule
