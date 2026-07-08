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
    input dense_enable, // always 1 if the accelerator is executing a dense layer
    input conv_enable,  // always 1 if the accelerator is executing a conv layer
    input [3:0] next_dim_input_feature,
    input [clogb2(MAX_SYNAPSES)-1:0] SYNAPSES, // only for dense, number of input of the dense layer
    input en_L2, // 1 if core 2 is enabled (if OF are odd, core 2 is disabled)
    input [clogb2(MAX_SYNAPSES)-1:0] spike_rd_addr,
    input layer_counter,
    input valid_encoding, // 1 when encoding slot writes input spikes
    input [clogb2(MAX_NUMBER_OUTPUT_FEATURE)-1:0] number_output_feature,
    input last_layer,		 // used to avoid writing spikes during last layer inference, since regression use case is in place
    input first_row_padding, // when padding is enabled, spike mem first and last rows are padded
    input last_row_padding,	 

    output spike_written, // layer execution completed
    output [clogb2(MAX_SYNAPSES)-1:0] spike_wr_addr,
    output reg [SPIKE_MEM_WIDTH-1:0] spike_mem_out_16, // output spike word
    output [3:0] spike_mem_out_4, // same, but for dense layers
    output valid_active_group, // it is 1 every time a new quadruplet of spike is completed in the input shift register of the spike mem, i.e. spike_mem_buffer_1
    output active_spike, // vecchio active_group, i.e. |spikes[3:0]
    output reg[clogb2(MAX_SYNAPSES)-1:0] spike_stack_addr

    
    );

	// shift registers used to collect up tp 16 spikes to be written in the spike mem
    reg [SPIKE_MEM_WIDTH-1:0] spike_mem_buffer_1;
    reg [SPIKE_MEM_WIDTH-1:0] spike_mem_buffer_2;

	// when OF width is odd, since spikes arrive in groups of two, the last spike must be written in the next line and the carry signal is set to 1
    reg carry;
    
	// spike and valid from core 2 delayed by 1 c.c.
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
	
	// in order to avoid conflicts on the write port of the spike mem,
	// spikes from core 2 are always delayed by 1 c.c.
	// 
	// spike_wr_en become 1 when spike_mem_buffer_x is ready to be written in spike memory
	// when spike_wr_en is 1, spike_mem_buffer is written in memory and can either be reset, or 
	// be set to hold the next line of the OF
    always @(posedge clk) begin
        if (rst || last_layer) begin
            spike_mem_buffer_1 <= 16'b0;
            spike_mem_buffer_2 <= 16'b0;
        end else begin
			// when spike_mem_buffer is written in spike memory is also reset
            if(spike_wr_en)
                spike_mem_buffer_1 = 16'b0;
            if(spike_wr_en_d)
                spike_mem_buffer_2 = 16'b0;
			// During dense computation, both the spikes are stored in spike_mem_buffer_1
            if(dense_enable && valid_s1) begin
                spike_mem_buffer_1 <= {s2, s1, spike_mem_buffer_1[15:2]};
			// During conv computation: 
            end else if(conv_enable) begin
                if(valid_s1) begin
					// if spike_mem_buffer is being reset, 
					// and at the same c.c. the first spike of the next OF's row is arriving:
                    if(spike_wr_en)
                        spike_mem_buffer_1 <= {s1, 15'b0};
					// otherwise, if it is only arriving a new spike..
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

	// spike mem data in mux
    wire [SPIKE_MEM_WIDTH-1:0] spike_mem_in = spike_wr_en_d? spike_mem_buffer_2 : spike_mem_buffer_1;

	// for stack update: the first group of spikes [15:12] active group signal is generated here
    reg [3:0] selected_bits;
    always @(*) begin
		// dense_spike_counter counts pair of spikes coming from the two cores,
		// therefore, when its content is even, it means a new group of 4 spikes have been loaded
        if(!dense_spike_counter[0])
            selected_bits = spike_mem_in[15:12];
        else
            selected_bits = 0;
    end

    assign active_spike = |selected_bits;

	// valid_s1 is high 1 c.c. before spike_mem_buffer_1 is updated,
	// the delayed version, i.e. valid_s1_d, works just fine as a valid signal
	// to enable stack annotation
    reg valid_s1_d;
    always @(posedge clk) begin
        if (rst) begin
            valid_s1_d <= 0;
        end else begin
            valid_s1_d <= valid_s1;
        end
    end

	// counter to keep track of the number of spikes of the OF received
	// last_layer signal disable spike writing because this hw is designed 
	// for regression output based on last layer neurons' potential.
	// edit this always for spike-rate-based output
	reg [3:0] spike_counter_width;
    always @(posedge clk) begin
        if (rst | spike_written) begin
            spike_counter_width <= 0;
        end else if(valid_s1 && !last_layer && spike_counter_width == next_dim_input_feature)
                spike_counter_width <= 0;
            else if (valid_s1) begin
                spike_counter_width <= spike_counter_width + 1;
        end
    end


	// spike_wr_en is 1 when the spike_mem_buffer_1 content must be written into spike memory
	// conv: when spike_counter_width, i.e. the number of spikes received, is equal to the width of the OF
	// dense: when dense_spike_counter is a multiple of 8, e.g. [2:0] == 8. Spikes are received in pairs, so coutner == 8 means 16 spikes have been received).
	// 		  or when the counter is equal to the overall number of synapses of the layer
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

	// spike mem write enable
    reg spike_wr_en_d;
    always @(posedge clk) begin
        if (rst) begin
            spike_wr_en_d <= 0;
        end else begin
            if(!dense_enable) begin
                spike_wr_en_d <= spike_wr_en;
            end
            else begin
                spike_wr_en_d <= 0;
            end
        end
    end

	// OF height counter
    reg [5:0] spike_counter_height;
    reg [3:0] spike_counter_height_d;

    always @(posedge clk) begin
        if (rst | spike_finish_feature | spike_written) begin
            spike_counter_height <= 0;
        end else if (spike_wr_en) begin
            spike_counter_height <= spike_counter_height + 1;
        end
    end
	// delayed version used to write OF computed by CORE2
    always @(posedge clk) begin
        if (rst) begin
            spike_counter_height_d <= 0;
        end else begin
            spike_counter_height_d <= spike_counter_height;
        end
    end

	// spike_mem_buffer_1 is filled by both the cores during dense execution.
	// when dense spike counter is a multiple of 16 (8 really, because it is 
	// incremented once each pair of spike is received) spike_mem_buffer_1
	// is saved in spike mem
    reg [clogb2(MAX_SYNAPSES)-1:0] dense_spike_counter;
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
			// if it is not the last quadruplet of spikes of the layer
			// dense_spike_counter[clogb2(MAX_SYNAPSES)-1:3] is the bram line
			// dense_spike_counter[2] and dense_spike_counter[1] identify which 
			// quadruplet of the four stored in spike_mem_buffer_1 is being written.
			// dense_spike_counter[0] is not needed because it indentifies the group of two inside the quadruplet
			// dense_spike_counter bits are complemented because they are mirrored, therefore, quadruplet 11 is 00,
			// 00 is 11, 01 is 10, and 10 is 01.
            if(dense_spike_counter + 4 <= SYNAPSES)
                spike_stack_addr <= {dense_spike_counter[clogb2(MAX_SYNAPSES)-1:3],!dense_spike_counter[2],!dense_spike_counter[1]};
            else
                spike_stack_addr <= {dense_spike_counter[clogb2(MAX_SYNAPSES)-1:3],1'b0,!dense_spike_counter[1]};
    end

	// if 1, a new quadruplet of spikes is ready for stack annotation
    assign valid_active_group = valid_s1_d & dense_spike_counter[0] == 0;

	// high for 1 c.c. during the last spike_mem_buffer writing of conv layers
    wire spike_finish_feature = spike_counter_height == next_dim_input_feature && spike_wr_en && !dense_enable;


	// OF counter, it increments by 1 if only 1 core is active,
	// by two if two cores are at work.
	// it is used to generate OF write address for core 1
	// and to understand when the layer inference is complete
    reg [clogb2(MAX_NUMBER_OUTPUT_FEATURE)-1:0] spike_counter_output_feature;

    always @(posedge clk) begin
        if (rst | spike_written) begin
            spike_counter_output_feature <= 0;
        end else if (spike_finish_feature) begin
            spike_counter_output_feature <= spike_counter_output_feature + 1 + en_L2;
        end
    end


	// used to generate OF write address of core 2, i.e. core1 wr_addr + 1
    reg [clogb2(MAX_NUMBER_OUTPUT_FEATURE)-1:0] spike_counter_output_feature_L2;
    
    always @(posedge clk) 
        if(rst)
            spike_counter_output_feature_L2 <= 0;
        else 
            spike_counter_output_feature_L2 <= spike_counter_output_feature + 1;

	// delayed version is to write OF computed by CORE2
    assign spike_wr_addr = dense_enable? {spike_counter_height[5:0]} : 
                            spike_wr_en_d? {spike_counter_output_feature_L2, spike_counter_height_d} : {spike_counter_output_feature, spike_counter_height[3:0]};

	// 1 when the layer inference is completed
    assign spike_written = dense_enable? dense_spike_counter == SYNAPSES : spike_counter_output_feature >= number_output_feature - 1 - en_L2 && spike_finish_feature;

	// spike mem is segmented in two portions read or
	// written alternatively by the layers.
	// layer_counter is the LSB of the layer counter
	// since layer is 0 both during layer 0 execution,
	// and when the encoding slot writes the input spikes,
	// valid_encoding is used to write the input spikes
	// into the write spike mem half
    reg lsb_layer_counter ;
    always @(posedge clk) begin
        if (rst) begin
            lsb_layer_counter <= 0;
        end else begin
            lsb_layer_counter <= layer_counter || valid_encoding;
        end
    end

	// quadruplet id
    wire [1:0] select_spike_out = spike_rd_addr[1:0];
	// for conv layers spike_rd_addr identifies the IF row
	// for dense layers spike_rd_addr identifies the 4-bit spike group inside the 16-bit spike mem word
    wire [clogb2(MAX_SYNAPSES)-1:0] spike_rd_addr_16 = conv_enable ? spike_rd_addr : spike_rd_addr >> 2;

	// rd_addr accesses the spike mem, 1 c.c. later the output is read from spike mem and written into spike_mem_out_16
	// select_spike_out_dd identifies the right 4-bit spike group to extract from spike_mem_out_16
    reg [1:0] select_spike_out_d;
    reg [1:0] select_spike_out_dd;
    always @(posedge clk) begin
        if (rst) begin
            select_spike_out_d <= 0;
            select_spike_out_dd <= 0;
        end else begin
            select_spike_out_d <= select_spike_out;
            select_spike_out_dd <= select_spike_out_d;
        end
    end

	// quadruplet selection
    assign spike_mem_out_4 = select_spike_out_dd == 2'b00 ? spike_mem_out_16[15:12] :
                            select_spike_out_dd == 2'b01 ? spike_mem_out_16[11:8] :
                            select_spike_out_dd == 2'b10 ? spike_mem_out_16[7:4] :
                            spike_mem_out_16[3:0];

    localparam MEM_DEPTH_BITS = clogb2(512-1)-1;

    wire [SPIKE_MEM_WIDTH-1:0] spike_mem_out_bram;

	// first and last row padding implementation
    always @(posedge clk) begin
        if (rst) begin
            spike_mem_out_16 <= 0;
        end else begin
            if(first_row_padding || last_row_padding)
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
    .addra({!lsb_layer_counter,spike_wr_addr[MEM_DEPTH_BITS-1:0]}),                  // Port A address bus, driven by axi bus
    .addrb({lsb_layer_counter,spike_rd_addr_16[MEM_DEPTH_BITS-1:0]}),                  // Port B address bus, it goes in the accumulator
    .dina(spike_mem_in),                       // Port A RAM input data, driven by axi bus
    .clk(clk),                       // Clock
    .wea(spike_wr_en | spike_wr_en_d),                      // Port A write enable
    .ena(spike_wr_en | spike_wr_en_d),                      // Port A RAM Enable, for additional power savings, disable port when not in use
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