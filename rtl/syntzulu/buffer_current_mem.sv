module buffer_current_mem
#(
	parameter WIDTH             = 32,
	parameter ROW               = 256,
	parameter MAX_INPUT_FEATURE = 16
)
(
	input clk, rst, en,

	// dim^2 of the output feature: number of positions (= `en` cycles) per
	// each input feature. adr runs 0..square_dim_output_feature-1
	input [7:0] square_dim_output_feature,

	// total number of input features to accumulate. Used to establish:
	//   - when to zero the accumulation (first input feature)
	//   - when to raise valid_buffer_current (last input feature)
	input [clogb2(MAX_INPUT_FEATURE)-1:0] num_input_feature,

	input signed [15:0] stimolo,

	output reg [WIDTH-1:0] buffer_current,
	output reg             valid_buffer_current,
	input first_layer_no_spike
);

	// ----------------------------------------------------------------------
	// Position counter within the current input feature.
	//   adr runs 0,1,...,square_dim_output_feature-1 and then returns to 0
	//   only on the cycles when `en` is high.
	// ----------------------------------------------------------------------
	reg [7:0] adr;
	wire pos_wrap = (adr == square_dim_output_feature);

	always @(posedge clk) begin
		if (rst)
			adr <= 0;
		else if (en) begin
			if (pos_wrap)
				adr <= 0;
			else
				adr <= adr + 1'b1;
		end
	end

	// ----------------------------------------------------------------------
	// Input feature counter: indicates how many "passes" of
	// square_dim_output_feature have been completed.
	//   feat_cnt == 0                   -> we are processing the FIRST input
	//                                       feature: we accumulate onto zero
	//                                       (mem[adr] <= stimolo).
	//   feat_cnt > 0                    -> we accumulate (mem[adr] += stimolo).
	//   feat_cnt == num_input_feature-2 -> "valid high" condition as
	//                                       required: valid_buffer_current is
	//                                       set for the whole
	//                                       duration of this pass.
	//   feat_cnt rolls to 0 after num_input_feature-1, so on the next round
	//   we go back to accumulating onto zero (required: "on the next round I
	//   must sum onto zero again").
	// ----------------------------------------------------------------------
	reg [clogb2(MAX_INPUT_FEATURE)-1:0] feat_cnt;

	always @(posedge clk) begin
		if (rst)
			feat_cnt <= 0;
		else if (en && pos_wrap) begin
			if (feat_cnt == num_input_feature)
				feat_cnt <= 0;
			else
				feat_cnt <= feat_cnt + 1'b1;
		end
	end

	wire is_first_feature = (feat_cnt == 0);
	wire is_valid_phase   = (feat_cnt == num_input_feature);

	// ----------------------------------------------------------------------
	// Accumulator BRAM
	// ----------------------------------------------------------------------
	reg [WIDTH-1:0] mem [ROW-1:0];
	
	wire signed [WIDTH-1:0] stimolo_eff;
	assign stimolo_eff = first_layer_no_spike ? stimolo <<< feat_cnt[2:0] : stimolo; // [2:0] equivalent to IF%8
	

	always @(posedge clk) begin
		if (en) begin
			if (is_first_feature) begin
				mem[adr]       <= stimolo_eff;
				buffer_current <= stimolo_eff;
			end
			else begin
				mem[adr]       <= mem[adr] + stimolo_eff;
				buffer_current <= mem[adr] + stimolo_eff;
			end
		end
	end

	// ----------------------------------------------------------------------
	// valid_buffer_current high during the pass indicated by is_valid_phase
	// (= feat_cnt == num_input_feature - 2).
	// ----------------------------------------------------------------------
	always @(posedge clk) begin
		valid_buffer_current <= en && is_valid_phase;
	end


	// ----------------------------------------------------------------------
	// log2 ceiling
	// ----------------------------------------------------------------------
	function integer clogb2;
		input integer depth;
		for (clogb2 = 0; depth > 0; clogb2 = clogb2 + 1)
			depth = depth >> 1;
	endfunction

endmodule
