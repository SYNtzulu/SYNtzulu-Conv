`timescale 1ns / 1ps

// Precisione dei bit letta da config.txt (incluso tramite `include `CONFIG_PATH).
// I default qui sotto valgono solo come fallback (es. testbench standalone che non
// includono config.txt).

`ifndef NBITS_M
  `define NBITS_M 16
`endif
`ifndef NBITS_THR
  `define NBITS_THR 16
`endif
`ifndef NBITS_DECAY
  `define NBITS_DECAY 16
`endif
`ifndef NBITS_VOLTAGE
  `define NBITS_VOLTAGE 8
`endif
`ifndef NBITS_BUFFER_CURRENT
  `define NBITS_BUFFER_CURRENT 32
`endif

module integrator_snnTorch
#(
	parameter nbits_M       = `NBITS_M,
	parameter nbits_thr     = `NBITS_THR,
	parameter nbits_decay   = `NBITS_DECAY,
	parameter nbits_voltage = `NBITS_VOLTAGE,
	parameter nbits_buffer_current = `NBITS_BUFFER_CURRENT

)(
    input clk, rst,
    
    input en, 
    input detection,
    input conv_enable,
    input pooling_spike_enable,
    //input last_input_feature,
    input recurrency,
    input recurrency_next,
    
    input signed [nbits_voltage-1:0] output_old	,
    input signed [nbits_thr    -1:0] threshold		,
    input signed [nbits_decay    :0] decay		, // only positive value
    input signed [nbits_M      -1:0] M			,
    input signed [nbits_buffer_current-1:0]              buffer_current	,
    
    output valid,
    output valid_fifo,
    output spike,
    output signed [nbits_voltage-1:0] output_new
);

    localparam bit_current_rescaled = nbits_buffer_current + nbits_M		;
    localparam bit_v_decaded        = 8  + nbits_decay		;
    ////////////////////////////////////////////////////////////
    localparam bit_comparator       = 8 + nbits_thr;
    ////////////////////////////////////////////////////////////
    localparam shift_v_decaded      = nbits_M - nbits_decay	;
    localparam round_comparator     = 1 << (nbits_M-1)		;
    localparam shift_thr            = nbits_thr - 8		;
    
    //initial begin 
    //	$display("bit_current_rescaled %d \n", bit_current_rescaled);
    //	$display("bit_v_decaded 	%d \n", bit_v_decaded);
    //	$display("shift_v_decaded 	%d \n", shift_v_decaded );
    //	$display("round_comparator 	%d \n", round_comparator );
    //	$display("shift_thr 		%d \n", shift_thr);	
    //end
    
    //wire signed [nbits_decay    :0] decay_eff;
    wire signed [bit_current_rescaled-1:0] current_rescaled	;
    wire signed [bit_v_decaded-1:0]        v_decaded		;
    wire signed [bit_current_rescaled-1:0] comparator_Nbit	;
    wire signed [15:0]                     comparator_16bit	;
    wire signed [bit_comparator-1:0]       comparator		;
    wire signed [nbits_voltage -1:0]       voltage_new		;
    
     					;
    assign current_rescaled = buffer_current * M										;
    assign v_decaded        = recurrency_next ? output_old << (shift_v_decaded + nbits_decay) : (output_old * decay) <<  shift_v_decaded 			;
    
    assign comparator_Nbit  = current_rescaled + v_decaded					;		
    assign comparator_16bit = (comparator_Nbit + round_comparator) >> nbits_M			;    
    assign comparator       = comparator_16bit << shift_thr					;
    
    assign spike            = pooling_spike_enable ? 1 :((comparator > threshold) & detection);
    
    assign voltage_new      = (comparator_16bit < -128) ? -128 : comparator_16bit		;

    assign output_new       = ( spike && ~recurrency )? 0 : voltage_new			;
    
    assign valid_fifo       = en		;
    assign valid            = en && detection	;

endmodule






