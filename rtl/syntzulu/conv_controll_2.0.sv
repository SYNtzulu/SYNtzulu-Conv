module conv_controll_2 #(
    parameter MAX_INPUT_FEATURE = 16, // max width/height
    parameter MAX_KERNEL = 3, // max kernel size
	parameter MAX_NUMBER_INPUT_FEATURE = 32,
	parameter MAX_NUMBER_OUTPUT_FEATURE = 32,
    parameter WEIGHT_DEPTH = 8192 // weight mem depth
)(
    input clk,
    input en, // conv_en, 1 until the whole conv layer has been dispatched
    input rst,
	
	// from layer instruction
    input [1:0] stride,
    input padding,
    input conv_enable,
    input pooling_enable,
    input [1:0] layer_counter, // layer id -- not used
    input [clogb2(MAX_KERNEL)-1:0] dim_kernel,
    input [clogb2(MAX_INPUT_FEATURE):0] dim_input_feature,
    input [clogb2(MAX_NUMBER_INPUT_FEATURE)-1:0] number_input_feature,
    input [clogb2(MAX_NUMBER_OUTPUT_FEATURE)-1:0] number_output_feature,
    input [3:0] dim_output_feature,
	input [clogb2(WEIGHT_DEPTH)-1:0] base_address_weights,
	
    input [MAX_INPUT_FEATURE-1:0] input_feature_row, // riga dell'input feature letta dalla spike_mem da salvare nel "line buffer"
    input weights_buffer_ready,
    input spike_written, // to rest conv_finish after all the spikes have been written

    output spike_check, // enable neuron state/threshold comparison
    output set_fifo_neuron_address, // segnale che mi dice che devo sottrarre la dimensione dell'OF all'indirizzo della fifo dei neuroni
    output [15:0] spike_address, // indirizzi di 4 spike attivi dal PE system
    output reg convolution_finish, // say when the convolution is completed (1 between conv_finish and spike_written)
    output reg write_en_weight_buffer, // to update weight buffer
    output reg [clogb2(WEIGHT_DEPTH)-1:0] weight_rd_addr, // weights rd addr to fill weight buffer
    output reg en_L2, // enable core 2, core 2 is disabled for pooling layers and during the last OF computation if the OFs are odd
    output last_input_feature, // used for control purposes, e.g. neuron fifo pointer reset but not only...
    output first_input_feature, // used to enable potential state decay
    output output_feature_finish,
    output [12:0] spike_mem_rd_addr, // spike mem address to fill the "line buffer"
	output conv_en, // to enable synaptic current computation
    output last_spike, // last group of active spikes inside receptive field issued. used to accumulate the IF current into the neuron potential
    output pooling_spike,
    output valid_pooling_spike,
    output input_feature_finish, // IF parsing completed
    output last_row_padding, // force spike mem to return a line of zeros
    output first_row_padding // force spike mem to return a line of zeros
);
    reg en_d, en_dd;
	
	wire new_kernel; // ask for a new receptive field

    reg input_feature_finish_d;
    always @(posedge clk or posedge rst) begin
        if (rst)
            input_feature_finish_d <= 0;
        else
            input_feature_finish_d <= input_feature_finish;
    end
    
	// number_output_feature_eff is divided by 2 if two cores are used
	// it is also subtracted by one to use == in counters control
    reg [clogb2(MAX_NUMBER_OUTPUT_FEATURE)-2:0] number_output_feature_eff;
    always @(posedge clk or posedge rst)
        if(rst)
            number_output_feature_eff<=0;
        else
            if(en_L2)
                number_output_feature_eff <= (number_output_feature>>1) -1;
            else 
                number_output_feature_eff <= number_output_feature -1;

	// padding signal for spike mem
    assign last_row_padding = padding & (row_output_feature_cnt >= dim_output_feature);
    assign first_row_padding = padding & (row_output_feature_cnt == 0) && (row_sum == 0);
    
    wire convolution_enable = en && !convolution_finish; // it should be more or less the same as en_conv from snn_lp

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            en_d <= 0;
            en_dd <= 0;
        end 
        else begin
            en_d <= en;
            en_dd <= en_d;
        end
    end

	// bo non sembra stabile, sembra possa  fare ping pong strani con  if(en_L2) number_output_feature_eff <= (number_output_feature>>1) -1; etc..
    always @(posedge clk or posedge rst)
        if(rst)
            en_L2 <= 0;
        else 
            if(number_output_feature == 1 || pooling_enable)
                en_L2 <= 0;
            else
                en_L2 <= en && (output_feature_cnt <= number_output_feature_eff);

    // COUNTER 
    reg [clogb2(MAX_NUMBER_INPUT_FEATURE)-1:0] input_feature_row_cnt; 	// IF row counter
    reg [clogb2(MAX_NUMBER_OUTPUT_FEATURE)-1:0] row_output_feature_cnt; // OF row counter
    reg [clogb2(MAX_NUMBER_INPUT_FEATURE)-1:0] input_feature_cnt; 		// IF counter
	reg [clogb2(MAX_NUMBER_OUTPUT_FEATURE)-2:0] output_feature_cnt;		// OF counter
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            input_feature_row_cnt <= 0;
        end else if (input_feature_finish) begin
            input_feature_row_cnt <= 0;
        end else begin
            if (row_finish) begin
                input_feature_row_cnt <= input_feature_row_cnt + stride;
            end
        end
    end

    always @(posedge clk or posedge rst)
		if (rst)
			row_output_feature_cnt <= 0;
		else if (conv_finish)
			row_output_feature_cnt <= 0;
		else begin
			if (row_finish) begin
				if (row_output_feature_cnt != dim_output_feature) begin
                        row_output_feature_cnt <= row_output_feature_cnt + 1;
                end
				else
					row_output_feature_cnt <= 0;
			end
		end

    always @(posedge clk or posedge rst)
		if (rst)
			input_feature_cnt <= 0;
		else if (conv_finish)
			input_feature_cnt <= 0;
		else begin
			if (input_feature_finish) begin
				if (input_feature_cnt != number_input_feature) begin
                        input_feature_cnt <= input_feature_cnt + 1;
                end
				else
					input_feature_cnt <= 0;
			end
		end
    
    always @(posedge clk or posedge rst)
		if (rst)
			output_feature_cnt <= 0;
		else if (conv_finish)
			output_feature_cnt <= 0;
		else begin
			if (output_feature_finish) begin
				if (output_feature_cnt <= number_output_feature_eff) begin
                    output_feature_cnt <= output_feature_cnt + 1;
                end
				else
					output_feature_cnt <= 0;
			end
		end
    
    assign first_input_feature = (input_feature_cnt == 0);
    
    assign input_feature_finish = row_finish && row_output_feature_cnt == dim_output_feature;
    wire all_input_feature_finish = pooling_enable ? input_feature_finish : input_feature_finish && input_feature_cnt == number_input_feature;
    assign output_feature_finish = all_input_feature_finish;
    wire all_output_feature_finish = output_feature_finish && ((output_feature_cnt == number_output_feature_eff));
    wire conv_finish = all_output_feature_finish;

    assign last_input_feature = (input_feature_cnt == number_input_feature);

    assign set_fifo_neuron_address = (en && input_feature_finish); //segnale che mi dice che devo sottrarre l'indirizzo della fifo dei neuroni

    // RIEMPIMENTO INPUT_FEATURE
	
	// row finish is used to load the first 3 row into the "input buffer", e.g. row0, row1, row2, 
	// and to load rows whenever the stride is bigger than 1. Otherwise row_finish is used
    reg [1:0] row_counter;
    always @(posedge clk or posedge rst)
        if(rst)
            row_counter <= 0;
        else if(input_feature_finish)
            row_counter <= 0;
        else if(convolution_enable)
            if(row_counter != dim_kernel)
                row_counter <= row_counter + 1;
            else if(row_finish)
                row_counter <= row_counter - stride + 1;

    reg [1:0] row_counter_d, row_counter_dd;
    reg input_feature_ready_d;
    reg weights_buffer_ready_d;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            input_feature_ready_d <= 0;
            weights_buffer_ready_d <= 0;
        end 
        else begin
            input_feature_ready_d <= input_feature_ready;
            weights_buffer_ready_d <= weights_buffer_ready;
        end
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            row_counter_d <= 0;
            row_counter_dd <= 0;
        end 
        else begin
            row_counter_d <= row_counter;
            row_counter_dd <= row_counter_d;
        end
    end
    
    
    wire [MAX_INPUT_FEATURE*MAX_KERNEL-1:0] input_feature;
    reg input_feature_ready;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            input_feature_ready <= 0;
        end 
        else begin
            if(stride != 1) begin
                if(row_finish)
                    input_feature_ready <= 0;
                else if (row_counter == dim_kernel && row_counter_d == dim_kernel)
                    input_feature_ready <= 1;
            end
            else begin
                if (row_counter_dd >= 2) 
                    input_feature_ready <= 1;
                else 
                    input_feature_ready <= 0;
            end
        end
    end

    reg [MAX_INPUT_FEATURE-1:0] row0, row1, row2;

    always @(posedge clk or posedge rst) begin
        if (rst)
            {row0, row1, row2} <= 0;
        else if (convolution_finish)
            {row0, row1, row2} <= 0;
        else if (en_dd) begin
            if (row_counter_dd != dim_kernel || row_finish) 
                {row0, row1, row2} <= {row1, row2, input_feature_row};
        end
    end

     
    assign input_feature = {row0, row1, row2};

	// IF rd addr generation from spike mem
    wire [3:0] row_sum = input_feature_row_cnt + row_counter;
    assign spike_mem_rd_addr = { {(13-clogb2(MAX_NUMBER_INPUT_FEATURE)){1'b0}},input_feature_cnt, row_sum} - padding;

    // RIEMPIMENTO WEIGHTS_BUFFER
    reg [1:0] count_weights;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            weight_rd_addr <= 1'b0;
        end else if (conv_finish) begin
            weight_rd_addr <= 1'b0;
        end else begin
            // if convolution_enable is zero, weight_rd_addr does not change (last row)
			// if en still is not arrived, load the base address of the weights
			// otherwise increment the weight rd address by one
            weight_rd_addr <= (convolution_enable) ? 
                            ((!en_d) ? base_address_weights : 
                            (count_weights != 2'd3 ? weight_rd_addr + 1'b1 : weight_rd_addr)) 
							: weight_rd_addr;
        end
    end
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            count_weights <= 2'd0;
        end else if (conv_finish) begin
            count_weights <= 2'd0;
        end else begin
            // during IF initialisation, count weights is incremented by 1,2,3
            count_weights <= (convolution_enable) ? 
                            ((!en_d) ? 2'd0 : 
                            (count_weights != 2'd3 ? count_weights + 1'b1 : 
                            (input_feature_finish ? 2'd0 : count_weights))) 
                            : count_weights;
        end
    end

	// weight buffer write en
	// if IF is finished starts loading the new kernel,
	// and keep doing that while count_weights < 2
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            write_en_weight_buffer <= 1'b0;
        end else if (conv_finish) begin
            write_en_weight_buffer <= 1'b0;
        end else if (en && !convolution_finish) begin
            if (!en_d || input_feature_finish) begin
                write_en_weight_buffer <= 1'b1;
            end else if (count_weights != 2'd3) begin
                write_en_weight_buffer <= (count_weights != 2'd2);
            end else begin
                write_en_weight_buffer <= 1'b0;
            end
        end
    end

	// 1 when state/threshold comparison is required
    assign spike_check = ~conv_enable | last_input_feature;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            convolution_finish <= 0;
        end else begin
            if (conv_finish)
                convolution_finish <= 1;
            else if (spike_written)
                convolution_finish <= 0;
        end
    end

    // Priority encoder system enable signal 
	// new_kernel is generated by the PE-system once it has processed its receptive field and it is used to ask for a new RF
    wire en_PE;
    assign en_PE =  (new_kernel && !write_en_weight_buffer && input_feature_ready) ||  // to receive enables along the same row
                    (input_feature_ready && weights_buffer_ready && !weights_buffer_ready_d) || // to start IF processing (first three lines)
                    (input_feature_ready && !input_feature_ready_d && weights_buffer_ready) ; // to go after the first three lines

    wire [MAX_KERNEL*MAX_KERNEL-1:0] output_kernel;

	// initialize fsm state of of the control of the muxes who select the receptive field.
	// in general it decrements its internal state from 15/14 down to 1/0.
	// in every state generates the right selector for the mux to get the receptive field.
	// it needs initialization from the outside because depending on the presence or
	// absence of padding it starts from 15 or 14.
    reg [3:0] last_state;
    always @(posedge clk or posedge rst)
        if(rst)
            last_state <= 0;
        else
            last_state <= dim_input_feature - dim_kernel + 1 + padding;

    mux_buffer #(
        .MAX_KERNEL(MAX_KERNEL)
    ) mux_buffer (
        .clk(clk),
        .rst(rst),
        .en(new_kernel),
        .conv_enable(en),
        .stride(stride),
        .padding(padding),
        .dim_kernel(dim_kernel),
        .input_feature_ready(input_feature_ready),
        .last_state(last_state),
        .input_feature_row(input_feature),
        .output_kernel(output_kernel),
        .row_finish(row_finish)
    );

    reg new_kernel_d;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            new_kernel_d <= 0;
        end else begin
            new_kernel_d <= new_kernel;
        end
    end

    assign new_kernel = PE_finish && !input_feature_finish_d;
    wire PE_finish;

    priority_encoder #(
        .MAX_KERNEL(MAX_KERNEL)
    ) PE (
        .clk(clk),
        .rst(rst),
        .en(en_PE && !convolution_finish),
        .conv_enable(en),
        .pooling_enable(pooling_enable),
        .kernel_in(output_kernel),
        .input_feature_finish_d(input_feature_finish_d),
        .row_finish(row_finish),
        .conv_en(conv_en),
        .spike_address(spike_address),
        .PE_finish(PE_finish),
        .pooling_spike(pooling_spike),
        .valid_pooling_spike(valid_pooling_spike),
        .last_spike(last_spike)
    );

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