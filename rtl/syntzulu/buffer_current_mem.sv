module buffer_current_mem
#(
	parameter WIDTH             = 32,
	parameter ROW               = 256,
	parameter MAX_INPUT_FEATURE = 16
)
(
	input clk, rst, en,

	// dim^2 dell'output feature: numero di posizioni (=cicli di `en`) per
	// ogni input feature. adr scorre 0..square_dim_output_feature-1
	input [7:0] square_dim_output_feature,

	// numero totale di input feature da accumulare. Usato per stabilire:
	//   - quando azzerare l'accumulo (prima input feature)
	//   - quando alzare valid_buffer_current (ultima input feature)
	input [clogb2(MAX_INPUT_FEATURE)-1:0] num_input_feature,

	input signed [15:0] stimolo,

	output reg [WIDTH-1:0] buffer_current,
	output reg             valid_buffer_current,
	input first_layer_no_spike
);

	// ----------------------------------------------------------------------
	// Counter di posizione dentro la input feature corrente.
	//   adr scorre 0,1,...,square_dim_output_feature-1 e poi torna a 0
	//   solo sui cicli in cui `en` è alto.
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
	// Counter delle input feature: indica quante "passate" di
	// square_dim_output_feature sono state completate.
	//   feat_cnt == 0                   -> stiamo elaborando la PRIMA input
	//                                       feature: accumuliamo su zero
	//                                       (mem[adr] <= stimolo).
	//   feat_cnt > 0                    -> accumuliamo (mem[adr] += stimolo).
	//   feat_cnt == num_input_feature-2 -> condizione di "valid alto" come
	//                                       richiesto: si setta
	//                                       valid_buffer_current per tutta
	//                                       la durata di questa passata.
	//   feat_cnt rolla a 0 dopo num_input_feature-1, così al giro successivo
	//   si torna ad accumulare su zero (richiesto: "al giro dopo devo
	//   sommare di nuovo a zero").
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
	// BRAM accumulatrice
	// ----------------------------------------------------------------------
	reg [WIDTH-1:0] mem [ROW-1:0];
	
	wire signed [WIDTH-1:0] stimolo_eff;
	assign stimolo_eff = first_layer_no_spike ? stimolo <<< feat_cnt[2:0] : stimolo; // [2:0] equivalente a IF%8
	

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
	// valid_buffer_current alto durante la passata indicata da is_valid_phase
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
