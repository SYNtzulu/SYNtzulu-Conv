`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03.11.2022 14:26:36
// Design Name: 
// Module Name: integrator
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


module integrator_old #(parameter WIDTH = 16)
    (
    input clk, rst, en, detection,
    input [WIDTH-1:0] output_old,
    input [13:0] decay,
    input [WIDTH-1:0] stimolo,
    input [WIDTH-1:0] threshold,
    input first_input_feature,
    input conv_enable,
    
    output valid,
    output valid_fifo,
    output spike,
    output [WIDTH-1:0] output_new
    );

localparam P_SIZE = WIDTH+13;
    
reg signed [WIDTH-1:0] r_output_old;  
reg signed [13:0] r_decay; 
reg signed [P_SIZE-1:0] p;
reg signed [WIDTH-1:0] p_shift;
reg signed [WIDTH-1:0] r_stimolo[2:0];
reg signed [WIDTH-1:0] r_threshold [3:0];
(* use_dsp = "yes" *)
reg signed [WIDTH-1:0] comparator_in;
reg [3:0] en_shift;

reg [P_SIZE-1:0] supporto_1, supporto_2;

wire [13:0] decay_new;
assign decay_new = conv_enable ? (first_input_feature ? { {2{decay[13]}}, decay } : 4096) : { {2{decay[13]}}, decay };

integer i;
always @(posedge clk)
    if(rst) begin
        en_shift <= 0;
        r_output_old <= 0;
        r_decay <= 0;
        p <= 0;
        p_shift <= 0;
        comparator_in <= 0;
         for(i=0;i<4;i=i+1)
            r_threshold[i] <= 0;
        
        for(i=0;i<3;i=i+1)
            r_stimolo[i] <= 0;
    end
    else begin
        en_shift[0] <= en;
        r_output_old <= output_old;
        r_decay <= decay_new;
        r_stimolo[0] <= stimolo;
        r_threshold[0] <= threshold;
        
        en_shift[1] <= en_shift[0];
        p <= r_output_old*r_decay;
        r_stimolo[1] <= r_stimolo[0];
        r_threshold[1] <= r_threshold[0];
        
        en_shift[2] <= en_shift[1];
        if(p[P_SIZE-1]) begin
            supporto_1 = ~p+1'b1;            
            supporto_2 = supporto_1[P_SIZE-1:12];
            p_shift <= ~supporto_2+1'b1;
        end
        else
            p_shift <= p[P_SIZE-1:12];
        
        r_stimolo[2] <= r_stimolo[1];
        r_threshold[2] <= r_threshold[1];
        
        en_shift[3] <= en_shift[2];
        comparator_in <= p_shift + r_stimolo[2];
        r_threshold[3] <= r_threshold[2];
    end

assign spike = (comparator_in >= r_threshold[3]) & detection; 
assign output_new = spike? 0 : comparator_in;     
assign valid_fifo = en_shift[3];
assign valid = en_shift[3] && detection;
    
endmodule