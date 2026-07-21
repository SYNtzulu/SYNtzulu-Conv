module spike_mem_buffer (
    input clk,
    input rst,
    input dense_enable,
    input conv_enable,
    input s1,
    input valid_s1,
    input s2,
    input valid_s2,
    input [10:0] SYNAPSES,
    input [4:0] next_dim_input_feature,
    input en_L2,
    input output_feature_finish,
    input last_layer,
    output reg [15:0] spike_mem_in,
    output active_spike,
    output spike_wr_en,
    output [12:0] spike_wr_addr,
    output reg spike_written,
    output reg spike_written_comb,
    output reg valid_active_group
);
    wire [2:0] input_buffer;

    reg s2_d;
    wire carry;
    reg valid;
    reg [3:0] spike_counter;

    reg en_L2_d;
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            en_L2_d <= 0;
        end
        else begin
            en_L2_d <= en_L2;
        end
    end
    
    wire [2:0] spike_counter_3_1 = spike_counter[3:1]; 
    wire [1:0] spike_counter_1_0 = spike_counter[1:0];

    assign carry = dense_enable && spike_counter[0] ? 1'b1 : 1'b0;

    always @(posedge clk or posedge rst) begin
        if(rst) begin
            s2_d <= 0;
        end
        else begin
            s2_d <= s2;
        end
    end

    assign input_buffer = carry ? {s2_d, s1, s2} : {s1, s2, 1'b0};

    reg [15:0] input_buffer_s2;

    reg s2_ready, s2_ready_d;
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            s2_ready <= 0;
            s2_ready_d <= 0;
        end
        else begin
            s2_ready <= en_L2 && spike_counter == next_dim_input_feature_minus_one;
            s2_ready_d <= s2_ready;
        end
    end

    wire [15:0] input_s2;

    assign input_s2 = (s2 && valid_s2) << (15 - spike_counter);

    wire [15:0] input_s1_dense = (input_buffer[2:1]) << (14-2*spike_counter_3_1);
    wire [15:0] input_s1_dense_carry = input_buffer [1:0] << (13-2*spike_counter_3_1);
    wire [15:0] input_s1_conv  = (s1 && valid_s1) << (15-spike_counter);
    
    always @(posedge clk or posedge rst) begin
        if (rst)
            input_buffer_s2 <= 16'h0000;
        else
            input_buffer_s2 <= spike_counter_equal_zero ? input_s2 : (input_buffer_s2 | input_s2);
    end

    wire spike_counter_3_1_equal_zero = spike_counter_3_1 == 0;
    wire spike_counter_equal_zero = spike_counter == 0;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            spike_mem_in <= 16'h0000;
        end else if (dense_two_valid) begin
            if (!carry) begin
                spike_mem_in <= spike_counter_3_1_equal_zero ? input_s1_dense : (spike_mem_in | input_s1_dense);
            end else begin
                if(spike_counter_3_1_equal_zero)
                    spike_mem_in <= {input_buffer [2:0], 13'b0};
                else begin
                    spike_mem_in <=  (spike_mem_in | input_s1_dense_carry);
                end
            end
        end else if (conv_enable) begin
            if (!spike_wr_en) begin
                spike_mem_in <= spike_counter_equal_zero? input_s1_conv : (spike_mem_in | input_s1_conv);
            end else if (s2_ready_d) begin
                spike_mem_in <= input_buffer_s2;
            end
        end
    end

    wire valid_one_s = valid_s1 || valid_s2;

    wire dense_two_valid = dense_enable && valid_s1 && valid_s2;
    wire conv_one_valid  = conv_enable  && valid_one_s;
    wire finish_synapses = conv_enable && spike_addr == SYNAPSES;

    always @(posedge clk) begin
        if (rst || spike_written) begin
            spike_counter <= 'd0;
            valid         <= 1'b0;

        end else if (dense_two_valid) begin
            // Caso: arrivano due valid contemporaneamente
            if (spike_counter < next_dim_input_feature_minus_two) begin
                spike_counter <= spike_counter + 2'd2;
                valid <= 0;//finish_synapses;
            end 
            else begin
                valid <= 1'b1;
                spike_counter <= (spike_counter == next_dim_input_feature_minus_one);
            end

        end else if (conv_one_valid) begin
            if (spike_counter < next_dim_input_feature) begin
                spike_counter <= spike_counter + 1'd1;
                valid <= ((spike_counter == next_dim_input_feature_minus_one)); // || finish_synapses);//|| spike_addr_d == SYNAPSES
            end else begin
                spike_counter <= 1'd1;
                valid         <= 1'b0;
            end
        end else if (conv_enable && spike_wr_en) begin
            spike_counter <= 1'd0;
            valid         <= 1'b0;
        end
        else begin
            valid <= 1'b0;
        end
    end

    reg valid_d;
    always @(posedge clk or posedge rst) begin
        if(rst)
            valid_d <= 0;
        else
            valid_d <= valid && en_L2;
    end

    assign spike_wr_en = dense_enable ? valid || finish_synapses :  valid || valid_d;

    reg spike_wr_en_d;
    always @(posedge clk or posedge rst) begin
        if(rst)
            spike_wr_en_d <= 0;
        else
            spike_wr_en_d <= spike_wr_en;
    end
/*
    always @(posedge clk or posedge rst) begin
        if(rst)
            spike_written <= 0;
        else if ((spike_wr_en_d && (spike_addr_d >= SYNAPSES)))
            spike_written <= 1;
        else if(conv_enable && !dense_enable && spike_wr_en && (spike_wr_addr >= SYNAPSES))
            spike_written <= 1;
        else
            spike_written <= 0; 
    end*/

    always @(posedge clk or posedge rst) begin
        if(rst)
            spike_written <= 0;
        else if(!spike_written)
            spike_written <= spike_written_comb;
        else
            spike_written <= 0;
    end

    always @(*) begin
        if(rst)
            spike_written_comb = 0;
        else if (!en_L2_d && (spike_wr_en_d && (spike_addr_d >= SYNAPSES)))
            spike_written_comb = 1;
        else if(en_L2_d && ((spike_wr_addr >= SYNAPSES)) && (spike_wr_en || spike_wr_en_d)) 
            spike_written_comb = 1;
        else
            spike_written_comb = 0; 
    end

    reg [3:0] selected_bits;
    always @(*) begin
        case (spike_wr_addr[1:0])
            2'b00: selected_bits = spike_mem_in[15:12];
            2'b01: selected_bits = spike_mem_in[11:8];
            2'b10: selected_bits = spike_mem_in[7:4]; 
            2'b11: selected_bits = spike_mem_in[3:0]; 
            default: selected_bits = spike_mem_in[3:0];
        endcase
    end


    assign active_spike = |selected_bits;

    reg jump_L1, jump_L2;

    always @(posedge clk or posedge rst) begin
        if(rst) begin
            jump_L1 <= 0;
            jump_L2 <= 0;
        end
        else begin
            jump_L1 <= !en_L2 && output_feature_finish && !dense_enable;
            jump_L2 <=  en_L2 && output_feature_finish && !dense_enable;
        end
    end

    wire [4:0] next_dim_input_feature_minus_two = next_dim_input_feature - 2;
    wire [4:0] next_dim_input_feature_minus_one = next_dim_input_feature - 1;

    wire end_dense = dense_enable && spike_counter >= next_dim_input_feature_minus_two;
    wire end_conv = conv_enable && spike_counter >= next_dim_input_feature_minus_one;

    wire spike_counter_1_0_equal_3 = spike_counter_1_0 == 2'b11;
    wire spike_counter_1_0_equal_2 = spike_counter_1_0 == 2'b10;
    wire spike_counter_1_0_equal_1 = spike_counter_1_0 == 2'b01;

    
    wire step_conv   = conv_enable && !dense_enable && ((en_L2 && spike_counter_1_0_equal_3) || spike_counter[2:0] == 3'b100);
    wire step_dense  = dense_enable && (spike_counter_1_0_equal_1 || spike_counter_1_0_equal_2);
    
    reg [12:0] spike_addr;
    always @(posedge clk or posedge rst) begin
        if(rst)
            spike_addr <= 0;
        else if(!last_layer && (valid_one_s)) begin
            if (end_dense || end_conv)
                spike_addr <= (spike_addr & 13'h1FFC) + 4;
            else if (step_dense || step_conv)
                spike_addr <= spike_addr + 1;
        end
        else if(spike_written || last_layer)
            spike_addr <= 0;
        else if(jump_L2)
            spike_addr <= (spike_addr & 13'h1FC0) + 128;
        else if(jump_L1)
            spike_addr <= (spike_addr & 13'h1FF0) + 64;
    end

    reg [12:0] spike_addr_d;
    reg [12:0] spike_addr_dd;

    always @(posedge clk or posedge rst) begin
        if(rst) begin
            spike_addr_d <= 0;
            spike_addr_dd <= 0;
        end
        else begin
            spike_addr_d <= spike_addr;
            spike_addr_dd <= spike_addr_d;
        end
    end

    assign spike_wr_addr = (s2_ready_d && !s2_ready) ? spike_addr_dd + 64 : spike_addr_dd;

    always @(posedge clk or posedge rst) begin
    if (rst)
        valid_active_group <= 0;
    else
        valid_active_group <= (dense_two_valid && spike_counter_1_0_equal_2) ||
                            (conv_one_valid  && spike_counter_1_0_equal_3);
    end

endmodule