`default_nettype none
//////////////////////////////////////////////////////////////////////////////
// rom_boot : boot ROM (Wishbone slave). GENERATA da scripts/gen_rom_boot.py.
// NON modificare a mano: rigenerare dopo ogni build del firmware.
//
// Mappata a ROM_BASE = 0x8000_0000 (RESET_PC). Carica il firmware dalla flash
// SPI (@0x121000, 408 word) nella RAM CPU (target SPI ID 7), poi salta a RAM[0].
//////////////////////////////////////////////////////////////////////////////
module rom_boot
  (input  wire        i_wb_clk,
   input  wire        i_wb_rst,
   input  wire [31:2] i_wb_adr,
   input  wire        i_wb_cyc,
   output reg  [31:0] o_wb_rdt,
   output reg         o_wb_ack);

   // ack a 1 ciclo, come servant_ram
   always @(posedge i_wb_clk)
     if (i_wb_rst) o_wb_ack <= 1'b0;
     else          o_wb_ack <= i_wb_cyc & !o_wb_ack;

   wire [7:0] a = i_wb_adr[9:2];

   always @(posedge i_wb_clk)
     case (a)
       8'd0:    o_wb_rdt <= 32'hA00002B7;
       8'd1:    o_wb_rdt <= 32'h00121337;
       8'd2:    o_wb_rdt <= 32'h0062A023;
       8'd3:    o_wb_rdt <= 32'hA00102B7;
       8'd4:    o_wb_rdt <= 32'h00700313;
       8'd5:    o_wb_rdt <= 32'h0062A023;
       8'd6:    o_wb_rdt <= 32'hA00202B7;
       8'd7:    o_wb_rdt <= 32'h00003337;
       8'd8:    o_wb_rdt <= 32'h30030313;
       8'd9:    o_wb_rdt <= 32'h0062A023;
       8'd10:   o_wb_rdt <= 32'hA00302B7;
       8'd11:   o_wb_rdt <= 32'h00100313;
       8'd12:   o_wb_rdt <= 32'h0062A023;
       8'd13:   o_wb_rdt <= 32'hA00402B7;
       8'd14:   o_wb_rdt <= 32'h0002A303;
       8'd15:   o_wb_rdt <= 32'hFE030EE3;
       8'd16:   o_wb_rdt <= 32'h00000293;
       8'd17:   o_wb_rdt <= 32'h00028067;
       default: o_wb_rdt <= 32'h0000_0013;   // nop
     endcase

endmodule
