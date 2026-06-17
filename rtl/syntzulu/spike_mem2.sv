module spike_mem_2#(
    parameter SPIKE_MEM_WIDTH = 16,
    parameter MAX_SYNAPSES = 512,
    parameter MAX_NUMBER_OUTPUT_FEATURE = 32
)(
    input clk,
    input rst,
    input s1,
    input valid_s1,
    input s2,
    input valid_s2,
    input dense_enable,
    input conv_enable,
    input [3:0] next_dim_input_feature,
    input [clogb2(MAX_SYNAPSES)-1:0] SYNAPSES,
    input en_L2,
    input [clogb2(MAX_SYNAPSES)-1:0] spike_rd_addr,
    input layer_counter,
    input valid_encoding,
    input [clogb2(MAX_NUMBER_OUTPUT_FEATURE)-1:0]number_output_feature,
    input last_layer,
    input first_row_padding,
    input last_row_padding,

    output spike_written,
    output [clogb2(MAX_SYNAPSES)-1:0] spike_wr_addr,
    output reg [SPIKE_MEM_WIDTH-1:0] spike_mem_out_16,
    output [3:0] spike_mem_out_4,
    output valid_active_group,
    output active_spike,
    output reg[clogb2(MAX_SYNAPSES)-2:0] spike_stack_addr,
    input recurrency,
    input layer_integrated
    
    );

    reg [SPIKE_MEM_WIDTH-1:0] spike_mem_buffer_1;
    reg [SPIKE_MEM_WIDTH-1:0] spike_mem_buffer_2;


    reg carry;
    reg s2_d;
    reg valid_s2_d;

    always @(posedge clk) begin
        if (rst) begin
            s2_d <= 0;
            valid_s2_d <= 0;
        end else begin
            s2_d <= s2;
            valid_s2_d <= valid_s2;
        end
    end
    always @(posedge clk) begin
        if (rst || last_layer) begin
            spike_mem_buffer_1 <= 16'b0;
            spike_mem_buffer_2 <= 16'b0;
        end else begin
            if(spike_wr_en)
                spike_mem_buffer_1 = 16'b0;
            if(spike_wr_en_d)
                spike_mem_buffer_2 = 16'b0;
            if(dense_enable && valid_s1) begin
                spike_mem_buffer_1 <= {s2, s1, spike_mem_buffer_1[15:2]};
            end else if(conv_enable) begin
                if(valid_s1) begin
                    if(spike_wr_en)
                        spike_mem_buffer_1 <= {s1, 15'b0};
                    else
                        spike_mem_buffer_1 <= {s1, spike_mem_buffer_1[15:1]};
                end
                if(valid_s2_d) begin
                    if(spike_wr_en_d)
                        spike_mem_buffer_2 <= {s2_d, 15'b0};
                    else 
                        spike_mem_buffer_2 <= {s2_d, spike_mem_buffer_2[15:1]};
                end
            end
        end
    end

    wire [SPIKE_MEM_WIDTH-1:0] spike_mem_in = spike_wr_en_d? spike_mem_buffer_2 : spike_mem_buffer_1;

    reg [3:0] selected_bits;
    always @(*) begin
        if(!dense_spike_counter[0])
            selected_bits = spike_mem_in[15:12];
        else
            selected_bits = 0;
    end

    assign active_spike = |selected_bits;

    reg [3:0] spike_counter_width;

    reg valid_s1_d;
    always @(posedge clk) begin
        if (rst) begin
            valid_s1_d <= 0;
        end else begin
            valid_s1_d <= valid_s1;
        end
    end

    always @(posedge clk) begin
        if (rst | spike_written) begin
            spike_counter_width <= 0;
        end else if(valid_s1 && !last_layer && spike_counter_width == next_dim_input_feature)
                spike_counter_width <= 0;
            else if (valid_s1) begin
                spike_counter_width <= spike_counter_width + 1;
        end
    end

    reg spike_wr_en;
    always @(posedge clk) begin
        if (rst) begin
            spike_wr_en <= 0;
        end else begin
            if(conv_enable && valid_s1 && spike_counter_width == next_dim_input_feature)
                spike_wr_en <= 1;
            else if(dense_enable && valid_s1 && (dense_spike_counter[2:0] == 7 || dense_spike_counter == SYNAPSES-1))
                spike_wr_en <= 1;
            else 
                spike_wr_en <= 0;
        end
    end

    reg spike_wr_en_d;
    always @(posedge clk) begin
        if (rst) begin
            spike_wr_en_d <= 0;
        end else begin
            if(!dense_enable)
                spike_wr_en_d <= spike_wr_en;
            else
                spike_wr_en_d <= 0;
        end
    end

    reg [4:0] spike_counter_height;
    reg [3:0] spike_counter_height_d;

    always @(posedge clk) begin
        if (rst | spike_finish_feature | spike_written) begin
            spike_counter_height <= 0;
        end else if (spike_wr_en) begin
            spike_counter_height <= spike_counter_height + 1;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            spike_counter_height_d <= 0;
        end else begin
            spike_counter_height_d <= spike_counter_height;
        end
    end

    reg [clogb2(MAX_SYNAPSES-1)-1:0] dense_spike_counter;
    always @(posedge clk) begin
        if(rst | spike_written) begin
            dense_spike_counter <= 0;
        end
        else
            if(valid_s1 && !last_layer)
                dense_spike_counter <= dense_spike_counter + 1;
    end

    always @(posedge clk) begin
        if (rst) begin
            spike_stack_addr <= 0;
        end
        else 
            if(dense_spike_counter + 4 <= SYNAPSES)
                spike_stack_addr <= {dense_spike_counter[clogb2(MAX_SYNAPSES-1)-1:3],!dense_spike_counter[2],!dense_spike_counter[1]};
            else
                spike_stack_addr <= {dense_spike_counter[clogb2(MAX_SYNAPSES-1)-1:3],1'b0,!dense_spike_counter[1]};
    end

    assign valid_active_group = valid_s1_d & dense_spike_counter[0] == 0;

    wire spike_finish_feature = spike_counter_height == next_dim_input_feature && spike_wr_en;

    reg spike_finish_feature_d;

    reg [clogb2(MAX_NUMBER_OUTPUT_FEATURE)-1:0] spike_counter_output_feature;

    always @(posedge clk) begin
        if (rst | spike_written) begin
            spike_counter_output_feature <= 0;
        end else if (spike_finish_feature) begin
            //spike_counter_output_feature <= spike_counter_output_feature + 1 + en_L2;
            spike_counter_output_feature <= spike_counter_output_feature + 1 + en_L2 + valid_encoding;
        end
    end

    reg [clogb2(MAX_NUMBER_OUTPUT_FEATURE)-1:0] spike_counter_output_feature_L2;
    
    always @(posedge clk) 
        if(rst)
            spike_counter_output_feature_L2 <= 0;
        else 
            spike_counter_output_feature_L2 <= spike_counter_output_feature + 1;

    assign spike_wr_addr = dense_enable? {spike_counter_height[4:0]} : 
                            spike_wr_en_d? {spike_counter_output_feature_L2, spike_counter_height_d} : {spike_counter_output_feature, spike_counter_height[3:0]};

    assign spike_written = dense_enable? dense_spike_counter == SYNAPSES : spike_counter_output_feature >= number_output_feature - 2 && spike_finish_feature;


    reg recurrency_skip;
    always @(posedge clk) begin
    	if(rst)
    		recurrency_skip <= 0;
    	else if(recurrency && layer_integrated) 
    		recurrency_skip <= recurrency_skip + 1'b1;
    end
    

    reg ping_pong_bit ;
    always @(posedge clk) begin
        if (rst) begin
            ping_pong_bit <= 0;
        end else begin
            ping_pong_bit <= (layer_counter || valid_encoding) + recurrency_skip;
        end
    end




    wire [1:0] select_spike_out = spike_rd_addr[1:0];
    wire [clogb2(MAX_SYNAPSES)-1:0] spike_rd_addr_16 = conv_enable ? spike_rd_addr : spike_rd_addr >> 2;

    reg [1:0] select_spike_out_d;
    reg [1:0] select_spike_out_dd;
    always @(posedge clk) begin
        if (rst) begin
            select_spike_out_d <= 0;
            select_spike_out_dd <= 0;
            spike_finish_feature_d <= 0;
        end else begin
            select_spike_out_d <= select_spike_out;
            select_spike_out_dd <= select_spike_out_d;
            spike_finish_feature_d <= spike_finish_feature;
        end
    end

    assign spike_mem_out_4 = select_spike_out_dd == 2'b00 ? spike_mem_out_16[15:12] :
                            select_spike_out_dd == 2'b01 ? spike_mem_out_16[11:8] :
                            select_spike_out_dd == 2'b10 ? spike_mem_out_16[7:4] :
                            spike_mem_out_16[3:0];

    localparam MEM_DEPTH_BITS = clogb2(512-1)-1;

    wire [SPIKE_MEM_WIDTH-1:0] spike_mem_out_bram;

    //reg first_row_padding_d, first_row_padding_dd;
	  reg first_row_padding_d, first_row_padding_dd;
	  reg last_row_padding_d;

// claude
/*    always @(posedge clk) begin
        if (rst) begin
            first_row_padding_d <= 0;
            first_row_padding_dd <= 0;
        end else begin
            first_row_padding_d <= first_row_padding;
            first_row_padding_dd <= first_row_padding_d;
        end
    end
*/

	  always @(posedge clk) begin
	      if (rst) begin
		  first_row_padding_d  <= 0;
		  first_row_padding_dd <= 0;
		  last_row_padding_d   <= 0;
	      end else begin
		  first_row_padding_d  <= first_row_padding;
		  first_row_padding_dd <= first_row_padding_d;
		  last_row_padding_d   <= last_row_padding;
	      end 
	  end


    always @(posedge clk) begin
        if (rst) begin
            spike_mem_out_16 <= 0;
        end else begin
            //if(first_row_padding || last_row_padding) claude
              if(first_row_padding_d || last_row_padding_d)
                spike_mem_out_16 <= 16'b0;
            else
                spike_mem_out_16 <= spike_mem_out_bram;
        end
    end

    BRAM_singlePort_readFirst
    #(
    .RAM_WIDTH(SPIKE_MEM_WIDTH),          // Specify RAM data width
    .RAM_DEPTH(512),               // Specify RAM depth (number of entries)
    .RAM_PERFORMANCE("LOW_LATENCY"), // Select "HIGH_PERFORMANCE" or "LOW_LATENCY" 
    .INIT_FILE("")                   // Specify name/location of RAM initialization file if using one (leave blank if not)
    )
    spike_mem
    (
    .addra({!ping_pong_bit , spike_wr_addr   [MEM_DEPTH_BITS-1:0]} ),                  // Port A address bus, driven by axi bus
    .addrb({ ping_pong_bit , spike_rd_addr_16[MEM_DEPTH_BITS-1:0]} ),                  // Port B address bus, it goes in the accumulator
    .dina(spike_mem_in),                       // Port A RAM input data, driven by axi bus
    .clk(clk),                       // Clock
    .wea((spike_wr_en | spike_wr_en_d) && !recurrency),                      // Port A write enable
    .ena((spike_wr_en | spike_wr_en_d) && !recurrency),                      // Port A RAM Enable, for additional power savings, disable port when not in use
    .enb(1'b1),                      // Port B RAM Enable, for additional power savings, disable port when not in use
    .rst(rst),                       // Port A and B output reset (does not affect memory contents)
    .regceb(1'b1),                   // Port B output register enable
    
    .doutb(spike_mem_out_bram)              // Port B RAM output data
        );
    
    // The following function calculates the address width based on specified RAM depth
	function integer clogb2;
	  input integer depth;
		for (clogb2=0; depth>0; clogb2=clogb2+1)
		  depth = depth >> 1;
	endfunction

endmodule
