module weight_buffer(
	input clk,
	input rst,
	input write_en, // 1 when the weights are received from weight memory
	input conv_enable,	// 1 during convolutional layer execution
	input [31:0] weight_in, // input weights from weight mem
	input [15:0] spike_address, // active spikes pointers in the receptive field
	output [31:0] weight_out,	// weights associated to the active spikes
	output reg weights_ready	// used to enable the synaptic current computation module
);
 	
	reg [7:0] kernel [11:0];
	reg[1:0] count=0;
	
	generate
		genvar idx;
		for(idx = 0; idx < 9; idx = idx+1) begin
			wire [7:0] tmp;
			assign tmp = kernel[idx];
		end
	endgenerate

	reg [1:0] write_en_pipe;

	always @(posedge clk) begin
		if (rst) begin
			write_en_pipe <= 2'b0;
		end 
		else begin
			write_en_pipe <= {write_en_pipe[0], write_en};
		end
	end


	// Riempimento buffer
	always @(posedge clk) begin
		if (rst) begin
			count <= 0;
			weights_ready <= 0;
		end 
		else if(conv_enable) begin
			if (write_en_pipe[1]) begin
				if (count == 0) begin
					kernel[0] <= weight_in[31:24]; 
					kernel[1] <= weight_in[23:16];
					kernel[2] <= weight_in[15:8];
					kernel[3] <= weight_in[7:0];
					weights_ready <= 0;
					count <= 2'b01;
				end 
				else if (count == 1) begin
					kernel[4] <= weight_in[31:24];
					kernel[5] <= weight_in[23:16];
					kernel[6] <= weight_in[15:8];
					kernel[7] <= weight_in[7:0];
					weights_ready <= 0;
					count <= 2'b10;
				end 
				else begin
					kernel[8] <= weight_in[31:24];
					kernel[9] <= 0;
					kernel[10] <= 0;
					kernel[11] <= 0;
					weights_ready <= 1;
					count <= 2'b0;
				end
			end
			else if(write_en)
				weights_ready <= 0;
		end
		else begin
			count <= 0;
			weights_ready <= 0;
		end
	end

	wire [3:0] spike_address_4, spike_address_3, spike_address_2, spike_address_1;

	assign spike_address_1 = spike_address[15:12];
	assign spike_address_2 = spike_address[11:8];
	assign spike_address_3 = spike_address[7:4];
	assign spike_address_4 = spike_address[3:0];

	assign weight_out[31:24] = kernel[spike_address_1];
	assign weight_out[23:16] = kernel[spike_address_2];
	assign weight_out[15:8]  = kernel[spike_address_3];
	assign weight_out[7:0]   = kernel[spike_address_4];

endmodule    



