`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06.03.2024 16:14:13
// Design Name: 
// Module Name: delta_modulator_multichannel
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module delta_modulator_multichannel #(
	parameter CHANNELS = 16,    
	parameter WIDTH = 16
    )
(
  input wire clk,           // Clock input
  input wire rst,           // Reset input
  input wire en,
  input wire signed [WIDTH-1:0] samples, // Analog input samples (8-bit resolution)
  // Caricamento delta mem da SPI a boot (soglie per canale). Su ASIC sostituisce
  // l'init da file: la CPU scrive qui via il SPI-slave, come per i pesi.
  input wire        spi_wen,
  input wire [9:0]  spi_waddr,
  input wire [15:0] spi_wdata,
  output reg pos_spike, neg_spike,     // Delta modulation output
  output reg valid
);

    reg signed [WIDTH-1:0] data_in_pipe;
	wire signed [WIDTH-1:0] delta;   

    reg [clogb2(CHANNELS-1)-1:0] channel_cnt; //, r_channel_cnt, rr_channel_cnt;
    always @(posedge clk or posedge rst)
        if (rst) begin
            channel_cnt <= 0;
            //r_channel_cnt <= 0;
			//rr_channel_cnt <= 0;
          end
        else begin
            if(en_dd)
                channel_cnt <= channel_cnt + 1'b1;  
            //r_channel_cnt <= channel_cnt;
			//rr_channel_cnt <= r_channel_cnt;
          end
    
    wire signed [WIDTH-1:0] data_old; // old sample



    // Per-channel state [ delta | prev_sample ] on a single-port 16-bit IHP SRAM.
    // Reads and writes the SAME address (channel_cnt) every active cycle -> the
    // macro does WRITE-THROUGH (rdata returns the just-written value). Only the
    // low byte (prev_sample) is written (wbm=00FF); the high byte (delta, the
    // per-channel threshold from the init file) is preserved.
    wire [9:0] delta_addr = channel_cnt;
    
    // In LOAD (spi_wen, a boot con en=0) la CPU scrive la parola completa
    // {delta, prev_init} via SPI (wbm=FFFF). A regime: solo il byte basso
    // (prev_sample) con wbm=00FF, il byte alto (soglia delta) e' preservato.
    ihp_ram_1024x16 #(
        .INIT_FILE("")           // ASIC: caricata via SPI, non da file
    ) delta_mem (
        .clk   (clk),
        .we    (spi_wen | en_dd),
        .waddr (spi_wen ? spi_waddr : delta_addr),
        .wdata (spi_wen ? spi_wdata : {8'b0, prev_sample}),
        .wbm   (spi_wen ? 16'hFFFF : 16'h00FF),
        .re    (1'b1),
        .raddr (delta_addr),
        .rdata ({delta, data_old})
    );


  reg signed [WIDTH-1:0] prev_sample;    // next value to store
  reg signed [WIDTH-1:0] samples_d;
  always @(posedge clk or posedge rst)
    if (rst)
      samples_d <= 0;
    else
      samples_d <= samples;

  wire signed [WIDTH:0] cond_spike_neg = (data_old - delta);
  wire signed [WIDTH:0] cond_spike_pos = (data_old + delta);

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      prev_sample <= 0;
      {pos_spike, neg_spike} <= 0;
    end else begin
      if (samples_d < cond_spike_neg) begin
			  {pos_spike, neg_spike} <= 2'b01;
        prev_sample <= cond_spike_neg;
		  end
      else if (samples_d > cond_spike_pos) begin
				{pos_spike, neg_spike} <= 2'b10;
				prev_sample <= cond_spike_pos;
			end
		  else begin
				{pos_spike, neg_spike} <= 2'b00;
				prev_sample <= data_old;
			end
    end
  end
  
  // ASIC: senza reset, en_dd (write-enable della delta mem) e valid (enable
  // della catena SNN) partono a X/valore casuale al power-up.
  reg en_d, en_dd;
  always @(posedge clk or posedge rst)
		if (rst) begin
			en_d  <= 0;
			en_dd <= 0;
			valid <= 0;
		end
		else begin
			en_d  <= en;
			en_dd <= en_d;
			valid <= en_d;
		end

////////////////////////////
//  _               ____  //
// | | ___   __ _  |___ \ //
// | |/ _ \ / _` |   __)  //
// | | (_) | (_| |  / __/ //
// |_|\___/ \__, | |_____ //
//          |___/         //
////////////////////////////
   
//  The following function calculates the address width based on specified RAM depth
function integer clogb2;
  input integer depth;
    for (clogb2=0; depth>0; clogb2=clogb2+1)
      depth = depth >> 1;
endfunction 
  
endmodule
