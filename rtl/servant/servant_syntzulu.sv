`include `CONFIG_PATH
module servant_syntzulu#(
    parameter ENCODING_BYPASS = 0,
    parameter CHANNELS = `INPUT_CHANNELS,
    parameter ORDER = 2,
    parameter WINDOW = 8192,
    parameter REF_PERIOD = 1024,
    parameter DW = `DW,
    
    parameter WIDTH = 16,
    parameter BUFFER_WIDTH = 32,
    parameter N_CLASSES = 10,
    parameter TIME_STEPS = 48,
	
	parameter MAX_NEURONS = 128,
	parameter MAX_SYNAPSES = 128,

    parameter LAYERS = 4, //è pari alla profondità della memoria delle istruzioni
    parameter MAX_DECAY = 4096,
    parameter MAX_THRESHOLD = 65536,

    parameter INSTR_WIDTH = 80,
    parameter INSTR_FILE = "flash/src/mnist/instruction.hex",

    parameter WEIGHTS_FILE_1 = "flash/src/mnist/weights_1.txt",
    parameter WEIGHTS_FILE_2 = "flash/src/mnist/weights_2.txt",
    parameter WEIGHTS_FILE_3 = "flash/src/mnist/weights_3.txt",
    parameter WEIGHTS_FILE_4 = "flash/src/mnist/weights_4.txt",

    parameter WEIGHT_DEPTH_12 = 8192,
    parameter WEIGHT_DEPTH_34 = 8192
)(
    input  wire         i_wb_clk,
    input  wire         i_wb_rst,
    input  wire [31:0]  i_cpu_adr,
    input  wire [31:0]  i_cpu_dat,
    input  wire         i_cpu_we,
    input  wire         i_cpu_cyc,
    output reg [31:0]  o_cpu_rdt,
	output  wire 		o_cpu_ack,

    // SPRAM signals
    input wire         wen_intmem1_spi,
    input wire [clogb2(WEIGHT_DEPTH_12-1)-1:0] wr_addr_intmem1_spi,
    input wire [15:0] wr_data_intmem1_spi,

    input wire         wen_intmem2_spi,
    input wire [clogb2(WEIGHT_DEPTH_12-1)-1:0] wr_addr_intmem2_spi,
    input wire [15:0] wr_data_intmem2_spi,

    input wire         wen_intmem3_spi,
    input wire [clogb2(WEIGHT_DEPTH_12-1)-1:0] wr_addr_intmem3_spi,
    input wire [15:0] wr_data_intmem3_spi,

    input wire         wen_intmem4_spi,
    input wire [clogb2(WEIGHT_DEPTH_12-1)-1:0] wr_addr_intmem4_spi,
    input wire [15:0] wr_data_intmem4_spi,

    // SPI signals
    input  wire [15:0]  i_sample_mem_spi,
    input  wire [13:0] i_wr_addr_inputbuffer,
    input  wire i_en_encoding_slot,
    output wire [12:0] o_data_last_layer
);
    reg snn_valid_rst;

    initial snn_valid_rst = 0;
    initial o_cpu_rdt = 0;

    reg o_cpu_ack_int, o_cpu_ack_d, o_cpu_ack_dd; 
    reg [7:0] i_cpu_adr_d;

    always @(posedge i_wb_clk) begin
      o_cpu_ack_int <= 1'b0;
	  o_cpu_ack_d <= o_cpu_ack_int;
	  o_cpu_ack_dd <= o_cpu_ack_d;
	  i_cpu_adr_d <= i_cpu_adr[27:20];
      if (i_cpu_cyc & !o_cpu_ack & !o_cpu_ack_d & !o_cpu_ack_dd)
	      o_cpu_ack_int <= 1'b1;
      if (i_wb_rst) begin
	      o_cpu_ack_int <= 1'b0;
		  o_cpu_ack_d <= 1'b0;
		  o_cpu_ack_dd <= 1'b0;
		  i_cpu_adr_d <= 0;
	  end
   end

    assign o_cpu_ack = (i_cpu_adr_d == 8'h01) ? o_cpu_ack_d : o_cpu_ack_int ;	
    
    always @(posedge i_wb_clk) begin
            //////// OUTPUT BUFFER ///////
        if (i_cpu_cyc)
			case (i_cpu_adr[19:16])
                4'h0: begin							// class , valid_class, valid_inference
                    o_cpu_rdt <= {17'b0,o_data_last_layer, valid_class_reg, acc_snn_valid_mp};
                end

                4'h1: begin							// valid inference reset
                    o_cpu_rdt <= {31'b0,snn_valid_rst};
                    if (i_cpu_cyc & o_cpu_ack) begin
                        snn_valid_rst <= i_cpu_dat[0];
                    end
                end
                default:
                    o_cpu_rdt <= 32'h0;
            endcase
        end

    wire acc_snn_valid;
    wire valid_class;
    reg acc_snn_valid_mp;
    reg valid_class_reg;
    always @(posedge i_wb_clk)
        if(i_wb_rst | snn_valid_rst)
            acc_snn_valid_mp <= 1'b0;
        else
            if(acc_snn_valid)
                acc_snn_valid_mp <= 1'b1;
    
    always @(posedge i_wb_clk)
        if(i_wb_rst | snn_valid_rst)
            valid_class_reg <= 1'b0;
        else
            if(valid_class)
                valid_class_reg <= 1'b1;

    Syntzulu #(
		.ENCODING_BYPASS(ENCODING_BYPASS),
        .WIDTH(WIDTH),
		.MAX_NEURONS(MAX_NEURONS),
		.MAX_SYNAPSES(MAX_SYNAPSES),
        
        .CHANNELS(CHANNELS),
        .ORDER(ORDER),
        .WINDOW(WINDOW),
        .REF_PERIOD(REF_PERIOD),
        .DW(DW),
            
        .WIDTH(WIDTH),
        .N_CLASSES(N_CLASSES),
        .TIME_STEPS(TIME_STEPS),

        .MAX_NEURONS(MAX_NEURONS),
        .MAX_SYNAPSES(MAX_SYNAPSES),

        .LAYERS(LAYERS),
        .MAX_DECAY(MAX_DECAY),
        .MAX_THRESHOLD(MAX_THRESHOLD),

        .INSTR_WIDTH(INSTR_WIDTH),
        .INSTR_FILE(INSTR_FILE),
        .WEIGHTS_FILE_1(WEIGHTS_FILE_1),
        .WEIGHTS_FILE_2(WEIGHTS_FILE_2),
        .WEIGHTS_FILE_3(WEIGHTS_FILE_3),
        .WEIGHTS_FILE_4(WEIGHTS_FILE_4),

        .WEIGHT_DEPTH_12(WEIGHT_DEPTH_12),
        .WEIGHT_DEPTH_34(WEIGHT_DEPTH_34),

        .BUFFER_WIDTH(BUFFER_WIDTH)
    )
    mosquito
    (
        .clk_enc    (i_wb_clk),
		.clk_snn	(i_wb_clk), 
        .rst        (i_wb_rst),
        .en         (i_en_encoding_slot),
        .data_in    (i_sample_mem_spi),
        .detect     (1'b1),
		.encoding_bypass(),
        
        .valid  (acc_snn_valid),
        .valid_class (valid_class),
        
        .weight_mem_L1_wren     (wen_intmem1_spi),
        .weight_mem_L1_wr_addr  (wr_addr_intmem1_spi),
        .weight_mem_L1_data_in  (wr_data_intmem1_spi),
        .weight_mem_L1_ena      (wen_intmem1_spi),
        
        .weight_mem_L2_wren     (wen_intmem2_spi),
        .weight_mem_L2_wr_addr  (wr_addr_intmem2_spi),
        .weight_mem_L2_data_in  (wr_data_intmem2_spi),
        .weight_mem_L2_ena      (wen_intmem2_spi),
        
        .weight_mem_L3_wren     (wen_intmem3_spi),
        .weight_mem_L3_wr_addr  (wr_addr_intmem3_spi),
        .weight_mem_L3_data_in  (wr_data_intmem3_spi),
        .weight_mem_L3_ena      (wen_intmem3_spi),
        
        .weight_mem_L4_wren     (wen_intmem4_spi),
        .weight_mem_L4_wr_addr  (wr_addr_intmem4_spi),
        .weight_mem_L4_data_in  (wr_data_intmem4_spi),
        .weight_mem_L4_ena      (wen_intmem4_spi),
		
		// ACCESSIBILITY
		.o_spike_mem_dat(),
		.i_spike_mem_adr(),
		.i_spike_mem_rd_en(),

		.o_sample_mem_dat(),	
		.i_sample_mem_adr(),
		.i_sample_mem_rd_en(),
		.i_sample_mem_wr_en(),
		.i_sample_mem_dat(),

		// OUTPUT BUFFER ACCESS
		
		.output_buffer_ren(1'b1),
		.output_buffer_addr(1'b0),
		.output_buffer_out(o_data_last_layer)
    );

    function integer clogb2;
    input integer depth;
        for (clogb2=0; depth>0; clogb2=clogb2+1)
        depth = depth >> 1;
    endfunction 

endmodule