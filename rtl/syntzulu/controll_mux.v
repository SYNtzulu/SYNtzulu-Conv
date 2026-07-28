// mux logic to extract the receptive field is generated here
// the extraction start from the right-side because the IF is
// mirrored
module controll_mux#(
    parameter MAX_INPUT_FEATURE=16,
    parameter MAX_KERNEL=3
) (
	input clk,
	input en, // it arrives from the P.E., it enable the selection of the next receptive field
	input rst,
	input [1:0] stride,
	input padding,
	input input_feature_ready, // l'IF is loaded, the first receptive field can be selected. It stays high for the whole duration
	input conv_enable,
    input [3:0] last_state, // generated from conv_control; used to initialize the fsm, equal to 14 if padding is not enabled, 15 if padding enabled
	output wire [2:0] sel_A,
	output wire [2:0] sel_B,
	output wire [2:0] sel_C,
	output wire [1:0] sel_k0,
	output wire [1:0] sel_k1,
	output wire [1:0] sel_k2, 
	output wire row_finish
);

	reg [3:0] state;
	reg [3:0] next_state;

	assign row_finish = (next_state <= stride - padding) && en && input_feature_ready;

	reg input_feature_ready_d;
	always @(posedge clk or posedge rst) begin
		if(rst) begin
			input_feature_ready_d <= 0;
		end else begin
			input_feature_ready_d <= input_feature_ready;
		end
	end

	// Calcolo combinatorio del prossimo stato. Era un blocking "=" su
	// next_state dentro il blocco sequenziale, seguito da "state <= next_state":
	// race in simulazione con tutti i lettori di next_state/row_finish.
	wire [3:0] next_state_calc = (state <= stride - padding) ? last_state : state - stride;

	always @(posedge clk or posedge rst) begin
		if (rst) begin
			state <= 0;
			next_state <= 0;
		end else if(conv_enable) begin
			if (en && input_feature_ready) begin
				next_state <= next_state_calc;
				state <= next_state_calc;
			end
			else if (input_feature_ready && !input_feature_ready_d) begin
				// Se input_feature_ready è appena diventato alto, aggiorna stato
				state <= last_state;
				next_state <= last_state;
			end
		end
		else begin
			state <= last_state;
			next_state <= last_state;
		end
	end

	assign {sel_A, sel_B, sel_C, sel_k0, sel_k1, sel_k2} = 
		(next_state == 0) ? {3'd5, 3'd4, 3'd4, 2'd3, 2'd2, 2'd1} :
		(next_state == 1) ? {3'd5, 3'd4, 3'd4, 2'd2, 2'd1, 2'd0} :
		(next_state == 2) ? {3'd4, 3'd4, 3'd4, 2'd1, 2'd0, 2'd2} :
		(next_state == 3) ? {3'd4, 3'd3, 3'd4, 2'd0, 2'd2, 2'd1} :
		(next_state == 4) ? {3'd4, 3'd3, 3'd3, 2'd2, 2'd1, 2'd0} :
		(next_state == 5) ? {3'd3, 3'd3, 3'd3, 2'd1, 2'd0, 2'd2} :
		(next_state == 6) ? {3'd3, 3'd2, 3'd3, 2'd0, 2'd2, 2'd1} :
		(next_state == 7) ? {3'd3, 3'd2, 3'd2, 2'd2, 2'd1, 2'd0} :
		(next_state == 8) ? {3'd2, 3'd2, 3'd2, 2'd1, 2'd0, 2'd2} :
		(next_state == 9) ? {3'd2, 3'd1, 3'd2, 2'd0, 2'd2, 2'd1} :
		(next_state == 10) ? {3'd2, 3'd1, 3'd1, 2'd2, 2'd1, 2'd0} :
		(next_state == 11) ? {3'd1, 3'd1, 3'd1, 2'd1, 2'd0, 2'd2} :
		(next_state == 12) ? {3'd1, 3'd0, 3'd1, 2'd0, 2'd2, 2'd1} :
		(next_state == 13) ? {3'd1, 3'd0, 3'd0, 2'd2, 2'd1, 2'd0} :
		(next_state == 14) ? {3'd0, 3'd0, 3'd0, 2'd1, 2'd0, 2'd2} :
		(next_state == 15) ? {3'd0, 3'd0, 3'd0, 2'd0, 2'd2, 2'd3} :
		                     15'd0;
	function integer clogb2(input integer value);
        integer i;
        begin
            value = value - 1;
            for (i = 0; value > 0; i = i + 1)
                value = value >> 1;
            clogb2 = i;
        end
    endfunction

endmodule