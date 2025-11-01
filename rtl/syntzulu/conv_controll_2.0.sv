module conv_controll_2 #(
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

    //input [clogb2(MAX_KERNEL)-1:0] dim_kernel,
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
    localparam DIM_KERNEL = 3;
    reg en_d, en_dd;

    wire convolution_enable = en && !convolution_finish;

    always @(posedge clk) begin
        if (rst) begin
            en_d <= 0;
            en_dd <= 0;
        end 
        else begin
            en_d <= en;
            en_dd <= en_d;
        end
    end

    always @(posedge clk)
        if(rst)
            en_L2 <= 0;
        else 
            if(number_output_feature == 1)
                en_L2 <= 0;
            else
                en_L2 <= en && (output_feature_cnt <= number_output_feature - 2);

    // COUNTER 
    reg [clogb2(MAX_NUMBER_INPUT_FEATURE)-1:0] input_feature_row_cnt;
    reg [clogb2(MAX_NUMBER_OUTPUT_FEATURE)-1:0] row_output_feature_cnt;
    reg [clogb2(MAX_NUMBER_INPUT_FEATURE)-1:0] input_feature_cnt;
	reg [clogb2(MAX_NUMBER_OUTPUT_FEATURE)-1:0] output_feature_cnt;
    always @(posedge clk) begin
        if (rst || input_feature_finish) begin
            input_feature_row_cnt <= 0;
        end else begin 
            if (row_finish) begin
                input_feature_row_cnt <= input_feature_row_cnt + stride;
            end
        end
    end

    always @(posedge clk)
		if (rst || conv_finish)
			row_output_feature_cnt <= 0;
		else begin
			if (row_finish) begin
				if (row_output_feature_cnt < dim_output_feature - 1) begin
                        row_output_feature_cnt <= row_output_feature_cnt + 1;
                end
				else
					row_output_feature_cnt <= 0;
			end
		end

    always @(posedge clk)
		if (rst || conv_finish)
			input_feature_cnt <= 0;
		else begin
			if (input_feature_finish) begin
				if (input_feature_cnt < number_input_feature) begin
                        input_feature_cnt <= input_feature_cnt + 1;
                end
				else
					input_feature_cnt <= 0;
			end
		end
    
    always @(posedge clk)
		if (rst || conv_finish)
			output_feature_cnt <= 0;
		else begin
			if (output_feature_finish) begin
				if (output_feature_cnt < number_output_feature) begin
                    if(en_L2)
                        output_feature_cnt <= output_feature_cnt + 2;
                    else
                        output_feature_cnt <= output_feature_cnt + 1;
                end
				else
					output_feature_cnt <= 0;
			end
		end
    
    assign first_input_feature = (input_feature_cnt == 0);
    
    assign input_feature_finish = row_finish && row_output_feature_cnt == dim_output_feature - 1;
    wire all_input_feature_finish = input_feature_finish && input_feature_cnt == number_input_feature;
    assign output_feature_finish = all_input_feature_finish;
    wire all_output_feature_finish = output_feature_finish && ((output_feature_cnt >= number_output_feature - 2) || number_output_feature ==1);
    wire conv_finish = all_output_feature_finish;

    assign last_input_feature = (input_feature_cnt == number_input_feature);
    assign last_output_feature = (output_feature_cnt <= number_output_feature - 2);

    assign set_fifo_neuron_address = (en && input_feature_finish); //segnale che mi dice che devo settare l'indirizzo della fifo dei neuroni

    // RIEMPIMENTO INPUT_FEATURE

    reg [1:0] row_counter;
    always @(posedge clk)
        if(rst || input_feature_finish)
            row_counter <= 0;
        else if(convolution_enable)
            if(row_counter < DIM_KERNEL)
                row_counter <= row_counter + 1;
            else if(row_finish)
                row_counter <= row_counter - stride + 1;

    reg [1:0] row_counter_d, row_counter_dd;
    reg input_feature_ready_d;
    reg weights_buffer_ready_d;
    always @(posedge clk) begin
        if (rst) begin
            input_feature_ready_d <= 0;
            weights_buffer_ready_d <= 0;
        end 
        else begin
            input_feature_ready_d <= input_feature_ready;
            weights_buffer_ready_d <= weights_buffer_ready;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            row_counter_d <= 0;
            row_counter_dd <= 0;
        end 
        else begin
            row_counter_d <= row_counter;
            row_counter_dd <= row_counter_d;
        end
    end
    
    
    reg [MAX_INPUT_FEATURE*MAX_KERNEL-1:0] input_feature;
    reg [1:0] head;
    reg [MAX_INPUT_FEATURE-1:0] row_buffer [0:MAX_KERNEL-1];



    reg input_feature_ready;

    always @(posedge clk) begin
        if (rst) begin
            input_feature_ready <= 0;
        end 
        else begin
            if(stride != 1) begin
                if(row_finish)
                    input_feature_ready <= 0;
                else if (row_counter == DIM_KERNEL && row_counter_d == DIM_KERNEL)
                    input_feature_ready <= 1;
            end
            else if (row_counter_dd >= 2) begin
                input_feature_ready <= 1;
            end
        end
    end
    /*
    always @(posedge clk) begin
        if (rst || conv_finish) begin
            head <= 0;
        end 
        else if(en_dd)begin
            if ((row_counter_dd < DIM_KERNEL)||row_finish) begin
                row_buffer[head] <= input_feature_row;
                head <= (head == 2) ? 0 : head + 1;
            end
        end
    end
    wire [1:0] idx0, idx1, idx2;

    assign idx2 = head;
    assign idx1 = (head == 0) ? 2 : head - 1;
    assign idx0 = (idx1 == 0) ? 2 : idx1 - 1;

    always @(*) begin
        input_feature = {row_buffer[idx2], row_buffer[idx0], row_buffer[idx1]};
    end
*/
    reg [MAX_INPUT_FEATURE-1:0] row0, row1, row2;

    always @(posedge clk) begin
        if (rst || conv_finish)
            {row0, row1, row2} <= 0;
        else if (en_dd) begin
            if (row_counter_dd < DIM_KERNEL || row_finish)
                {row0, row1, row2} <= {row1, row2, input_feature_row};
        end
    end

    always @(*) 
        input_feature = {row0, row1, row2};

    wire [3:0] row_sum = input_feature_row_cnt + row_counter;

    assign spike_mem_rd_addr = { {(13-clogb2(MAX_NUMBER_INPUT_FEATURE)){1'b0}},
                             input_feature_cnt, row_sum};

    // RIEMPIMENTO WEIGHTS_BUFFER
    reg [1:0] count_weights;
    
    always @(posedge clk) begin
        if (rst || conv_finish) begin
            weight_rd_addr <= 1'b0;
            count_weights  <= 1'b0;
            write_en_weight_buffer <= 1'b0;
        end else if (convolution_enable) begin
            if (!en_d) begin
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
        end
    end

    assign spike_check = ~conv_enable | last_input_feature;

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

    //EN_PE 
    wire en_PE;
    assign en_PE = (new_kernel_d && !write_en_weight_buffer && input_feature_ready) || 
                    (input_feature_ready && weights_buffer_ready && !weights_buffer_ready_d) || 
                    (input_feature_ready && !input_feature_ready_d && weights_buffer_ready) ; //impulso di un ciclo

    wire [MAX_KERNEL*MAX_KERNEL-1:0] output_kernel;

    reg [3:0] last_state;
    always @(posedge clk)
        if(rst)
            last_state <= 0;
        else
            last_state <= dim_input_feature - DIM_KERNEL - stride + 1;

    mux_buffer #(
        .MAX_KERNEL(MAX_KERNEL)
    ) mux_buffer (
        .clk(clk),
        .rst(rst),
        .en(new_kernel),
        .conv_enable(en),
        .stride(stride),
        .input_feature_ready(input_feature_ready),
        .last_state(last_state),
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
        .conv_enable(en),
        .polling_enable(polling_enable),
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