module conv_controll #(
    parameter MAX_INPUT_FEATURE = 16,
    parameter MAX_KERNEL = 3,
	parameter MAX_NUMBER_INPUT_FEATURE = 32,
	parameter MAX_NUMBER_OUTPUT_FEATURE = 32,
    parameter WEIGHT_DEPTH = 8192
)(
    input clk,
    input en,
    input rst,
    input [1:0] stride,
    input conv_enable,
    input polling_enable,

    input [clogb2(MAX_KERNEL)-1:0] dim_kernel,
    input [clogb2(MAX_INPUT_FEATURE)-1:0] dim_input_feature,
    input [clogb2(MAX_NUMBER_INPUT_FEATURE):0] number_input_feature,
    input [clogb2(MAX_NUMBER_OUTPUT_FEATURE):0] number_output_feature,
    input [3:0] dim_output_feature,

    input [MAX_INPUT_FEATURE-1:0] input_feature_row, //riga dell'input feature letta dalla spike_mem
    input [clogb2(WEIGHT_DEPTH)-1:0]base_address_weights,
    input weights_buffer_ready,
    input spike_written,

    output new_kernel,
    output spike_check,
    output set_fifo_neuron_address, //segnale che mi dice che devo settare l'indirizzo della fifo dei neuroni
    output [15:0] spike_address, //indirizzi di 4 spike attivi
    output reg convolution_finish,
    output reg write_en_weight_buffer,
    output reg [clogb2(WEIGHT_DEPTH)-1:0] weight_rd_addr,
    output en_L1,
    output reg en_L2,
    output last_input_feature,
    output first_input_feature,
    output output_feature_finish,
    output last_output_feature,
    output [12:0] spike_mem_rd_addr,
	output conv_en,
    output last_spike,
    output polling_spike,
    output valid_polling_spike,
    output input_feature_finish
);
    wire convolution_enable;

    assign convolution_enable = ((en && conv_enable) ||polling_enable) && !convolution_finish ; //segnale che mi dice che la convoluzione è abilitata
    wire [MAX_KERNEL*MAX_KERNEL-1:0] output_kernel;
    reg new_conv; 

    assign en_L1 = convolution_enable;
    //assign en_L2 = number_output_feature == 1 ? 0 : convolution_enable && (output_feature_cnt <= number_output_feature_minus_two);
    always @(posedge clk)
        if(rst)
            en_L2 <= 0;
        else 
            if(number_output_feature == 1)
                en_L2 <= 0;
            else
                en_L2 <= convolution_enable && (output_feature_cnt <= number_output_feature_minus_two);

    assign first_input_feature = (input_feature_cnt == 0);

    assign set_fifo_neuron_address = (convolution_enable && input_feature_finish); //segnale che mi dice che devo settare l'indirizzo della fifo dei neuroni

    wire [clogb2(MAX_NUMBER_INPUT_FEATURE):0] number_input_feature_minus_one = number_input_feature - 1;
    wire [clogb2(MAX_NUMBER_OUTPUT_FEATURE):0] number_output_feature_minus_one = number_output_feature - 1;
    wire [clogb2(MAX_NUMBER_OUTPUT_FEATURE):0] number_output_feature_minus_two = number_output_feature - 2;

    assign last_input_feature = (input_feature_cnt == number_input_feature_minus_one);

    assign last_output_feature = (output_feature_cnt <= number_output_feature_minus_two);

    reg [clogb2(MAX_KERNEL)-1:0] row_counter;
    reg [MAX_INPUT_FEATURE*MAX_KERNEL-1:0] input_feature;
    reg input_feature_ready;
    wire row_finish;
    wire row_finish_new_kernel = row_finish && new_kernel;
    reg [clogb2(MAX_INPUT_FEATURE)-1:0] input_feature_row_cnt;

    reg [clogb2(MAX_NUMBER_INPUT_FEATURE)-1:0] input_feature_cnt;
	reg [clogb2(MAX_NUMBER_OUTPUT_FEATURE)-1:0] output_feature_cnt;
    wire all_input_feature_finish;
    reg [clogb2(MAX_KERNEL)-1:0]weight_buffer_cnt;
    
    reg [1:0] count_weights;

    wire [3:0] row_sum = input_feature_row_cnt + row_counter;

    assign spike_mem_rd_addr = { {(13-clogb2(MAX_NUMBER_INPUT_FEATURE)){1'b0}},
                             input_feature_cnt, row_sum};

    always @(posedge clk) begin
        if (rst) begin
            weight_rd_addr <= 1'b0;
            count_weights  <= 1'b0;
            write_en_weight_buffer <= 1'b0;
        end else if (convolution_enable && !conv_finish) begin
            if (!convolution_enable_d) begin
                weight_rd_addr <= base_address_weights;
                count_weights  <= 2'd0;
                write_en_weight_buffer <= 1'b1;
            end else if (count_weights != 2'd3) begin
                weight_rd_addr <= weight_rd_addr + 1'b1;
                count_weights  <= count_weights + 1'b1;
                write_en_weight_buffer <= (count_weights != 2'd2);
            end else if (input_feature_finish) begin
                count_weights  <= 2'd0;
                write_en_weight_buffer <= 1'b1;
            end else begin
                write_en_weight_buffer <= 1'b0;
            end
        end else begin
            weight_rd_addr <= 0;
            count_weights  <= 2'd0;
            write_en_weight_buffer <= 1'b0;
        end
    end

    assign spike_check = ~conv_enable | last_input_feature;

    always @(posedge clk) begin
        if (rst) begin
            new_conv <= 0;
        end else if (convolution_enable) begin
            if (conv_finish) begin
                new_conv <= 1;
            end else if (new_kernel) begin
                new_conv <= 0;
            end
        end else begin
            new_conv <= 0;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            convolution_finish <= 0;
        end else begin
            if (conv_finish)
                convolution_finish <= 1;
            else if (spike_written)
                convolution_finish <= 0;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            weight_buffer_cnt <= 0;
        end else begin 
            if (output_feature_finish)
                weight_buffer_cnt <= 0;
            else if(weight_buffer_cnt < dim_kernel)
                weight_buffer_cnt <= weight_buffer_cnt + 1;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            input_feature_row_cnt <= 0;
        end else begin 
            if (input_feature_finish)
                input_feature_row_cnt <= 0;
            else if (row_finish_new_kernel) begin
                input_feature_row_cnt <= input_feature_row_cnt + stride;
            end
        end
    end

	always @(posedge clk)
		if (rst)
			input_feature_cnt <= 0;
		else begin
			if (input_feature_finish) begin
				if (input_feature_cnt < number_input_feature_minus_one) begin
                        input_feature_cnt <= input_feature_cnt + 1;
                end
				else
					input_feature_cnt <= 0;
			end
		end

	always @(posedge clk)
		if (rst)
			output_feature_cnt <= 0;
		else if (convolution_enable)begin
			if (all_input_feature_finish) begin
				if (output_feature_cnt < number_output_feature)
                    if (en_L2)
					    output_feature_cnt <= output_feature_cnt + 2;
                    else 
                        output_feature_cnt <= output_feature_cnt + 1;
				else 
					output_feature_cnt <= 0;
			end
		end
        else
            output_feature_cnt <= 0;

    wire [3:0] dim_input_feature_minus_kernel = dim_input_feature - dim_kernel;
    assign input_feature_finish = row_finish_new_kernel && (input_feature_row_cnt + stride >= dim_input_feature_minus_kernel + 1);
    assign all_input_feature_finish = input_feature_finish && (input_feature_cnt == number_input_feature_minus_one);
    assign output_feature_finish = all_input_feature_finish;
    wire conv_finish = output_feature_finish && ((output_feature_cnt >= number_output_feature_minus_two) || number_output_feature ==1);

    //assign input_feature_ready = convolution_enable && (row_counter_dd == dim_kernel);
    always @(posedge clk)
        if(rst)
            input_feature_ready <= 0;
        else if(stride != 1) begin
            if(row_finish)
                input_feature_ready <= 0;
            else if (row_counter == dim_kernel && row_counter_d == dim_kernel)
                input_feature_ready <= 1;
        end
        else 
            input_feature_ready <= convolution_enable && (row_counter_dd == dim_kernel);

    wire en_PE;
    reg input_feature_ready_d;
    reg weights_buffer_ready_d;

    always @(posedge clk) begin
        if (rst) begin
            weights_buffer_ready_d <= 0;
            input_feature_ready_d <= 0;
        end else begin
            weights_buffer_ready_d <= weights_buffer_ready;
            input_feature_ready_d <= input_feature_ready;
        end
    end

    assign en_PE = (new_kernel_d && !write_en_weight_buffer && input_feature_ready) || (input_feature_ready && weights_buffer_ready && !weights_buffer_ready_d) || (input_feature_ready && !input_feature_ready_d && weights_buffer_ready) ; //impulso di un ciclo

    always @(posedge clk) begin
        if (rst) begin
            row_counter <= 0;
        end 
        else if (convolution_enable) begin
            if (row_counter < dim_kernel)
                row_counter <= row_counter + 1;
            else if(input_feature_finish)
                row_counter <= 0;
            else if(row_finish && stride != 1)
                row_counter <= row_counter - stride + 1;
            end
        else begin
            row_counter <= 0;
        end
    end

    reg [clogb2(MAX_KERNEL)-1:0] row_counter_d;
    reg [clogb2(MAX_KERNEL)-1:0] row_counter_dd;

    always @(posedge clk) begin
        if (rst) begin
            row_counter_d <= 0;
            row_counter_dd <= 0;
        end else begin
            row_counter_d <= row_counter;
            row_counter_dd <= row_counter_d;
        end
    end

    reg convolution_enable_d;
    reg convolution_enable_dd;

    always @(posedge clk) begin
        if (rst) begin
            convolution_enable_d <= 0;
            convolution_enable_dd <= 0;
        end else begin
            convolution_enable_d <= convolution_enable;
            convolution_enable_dd <= convolution_enable_d;
        end
    end

    wire [1:0] dim_kernel_minus_one = dim_kernel - 1;
    reg [1:0] head; //puntatore circolare
    reg [MAX_INPUT_FEATURE-1:0] row_buffer [0:MAX_KERNEL-1]; //registro che contiene le 3 righe dell'input feature

    always @(posedge clk) begin
        if (rst) begin
            head <= 0;
        end 
        else if(convolution_enable_dd)begin
            if ((row_counter_dd < dim_kernel)||(row_finish_new_kernel)) begin
                row_buffer[head] <= input_feature_row;
                head <= (head == dim_kernel_minus_one) ? 0 : head + 1;
            end
        end
        else begin
            head <= 0;
        end
    end

    wire [1:0] idx0, idx1, idx2;

    assign idx2 = head;
    assign idx1 = (head == 0) ? dim_kernel_minus_one : head - 1;
    assign idx0 = (idx1 == 0) ? dim_kernel_minus_one : idx1 - 1;

    always @(*) begin
        input_feature = {row_buffer[idx2], row_buffer[idx0], row_buffer[idx1]};
    end

    mux_buffer #(
        .MAX_KERNEL(MAX_KERNEL)
    ) mux_buffer (
        .clk(clk),
        .rst(rst),
        .en(new_kernel),
        .conv_enable(convolution_enable),
        .stride(stride),
        .input_feature_ready(input_feature_ready),
        .dim_input_feature_minus_kernel(dim_input_feature_minus_kernel),
        .input_feature_row(input_feature),
        .output_kernel(output_kernel),
        .row_finish(row_finish)
    );

    reg new_kernel_d;

    always @(posedge clk) begin
        if (rst) begin
            new_kernel_d <= 0;
        end else begin
            new_kernel_d <= new_kernel;
        end
    end

    priority_encoder #(
        .MAX_KERNEL(MAX_KERNEL)
    ) PE (
        .clk(clk),
        .rst(rst),
        .en(en_PE && !convolution_finish),
        .conv_enable(convolution_enable),
        .polling_enable(polling_enable),
        .input_feature_ready(input_feature_ready_d),
        .weights_buffer_ready(weights_buffer_ready),
        .kernel_in(output_kernel),
        .conv_en(conv_en),
        .spike_address(spike_address),
        .PE_finish_pulse(new_kernel),
        .polling_spike(polling_spike),
        .valid_polling_spike(valid_polling_spike),
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