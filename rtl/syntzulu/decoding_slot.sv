module decoding_slot #(
    parameter MAX_NEURONS = 128,
    parameter N_CLASSES   = 10,
    parameter INFERENCES  = 48,
    parameter BUFFER_WIDTH = 32,
    parameter OUTPUT_BUFFER_DEPTH = MAX_NEURONS/8
)(
    input  wire clk, rst,
    input  wire valid_snn,
    input  wire s1, s2,
    input  wire last_layer,
    input  wire valid_spike_in,
    input  wire [clogb2(MAX_NEURONS/2)-1:0] integrated_neurons_cnt,
    input  wire integrated_neuron,
    input  wire [15:0] voltage_1, voltage_2,
    output wire reset_potential,
    output wire [BUFFER_WIDTH-1:0] output_buffer_din,
    output wire output_buffer_wr_en,
    output wire [clogb2(OUTPUT_BUFFER_DEPTH)-1:0] output_buffer_wr_addr
);
`ifdef MNIST

    wire [3:0] class_out;
    wire       class_valid;
    wire inference_done;

    decoding_slot_mnist #(
        .MAX_NEURONS (MAX_NEURONS),
        .N_CLASSES   (N_CLASSES),
        .INFERENCES  (INFERENCES)
    ) decoder_mnist (
        .clk(clk),
        .rst(rst),
        .valid_snn(valid_snn),
        .s1(s1),
        .s2(s2),
        .valid_spike_in(valid_spike_in),
        .integrated_neuron_cnt(integrated_neurons_cnt),
        .class_out(class_out),
        .class_valid(class_valid),
        .first_inference(reset_potential)
    );

    assign output_buffer_din = {28'b0,class_out};
    assign output_buffer_wr_en = class_valid;
    assign output_buffer_wr_addr = 0;

`endif

`ifdef EMG

    assign output_buffer_din = {voltage_2, voltage_1};
    assign output_buffer_wr_en = integrated_neuron && last_layer;
    assign output_buffer_wr_addr = integrated_neurons_cnt;
    assign reset_potential = 0;

`endif

    function integer clogb2;
	  input integer depth;
		for (clogb2=0; depth>0; clogb2=clogb2+1)
		  depth = depth >> 1;
	endfunction 

endmodule
