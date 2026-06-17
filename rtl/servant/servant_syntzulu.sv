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
    parameter MAX_SYNAPSES = 256,

    parameter LAYERS = 8, //è pari alla profondità della memoria delle istruzioni
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
/*
    input wire         wen_instr,
    input wire [clogb2(WEIGHT_DEPTH_12-1)-1:0] wr_addr_instr,
    input wire [15:0] wr_data_instr,*/

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

    assign o_cpu_ack = (i_cpu_adr_d == 8'h01) ? o_cpu_ack_d : o_cpu_ack_int;
/*
    reg instr_free;

    always @(posedge i_wb_clk)
        if (i_wb_rst)
            instr_free <= 1;
        else begin
            if (wen_instr)
                instr_free <= 0;
            else if (new_instruction)
                instr_free <= 1;
        end
    
    */always @(posedge i_wb_clk) begin
        if (i_cpu_cyc)
			case (i_cpu_adr[19:16])
                4'h0: begin							// class , valid_class, valid_inference
                    o_cpu_rdt <= {17'b0,o_data_last_layer, valid_class_reg, acc_snn_valid_mp};
                end

                4'h1: begin							// valid inference reset
                    //o_cpu_rdt <= {31'b0,snn_valid_rst};
                    if (o_cpu_ack) begin
                        snn_valid_rst <= i_cpu_dat[0];
                    end
                end/*
                4'h3: begin
                    rd_en_spike_mem <= i_cpu_cyc && !i_cpu_we;
                    i_spike_mem_adr <= i_cpu_adr[14:2];
                    if (o_cpu_ack) begin
                        o_cpu_rdt <= spike_mem;
                    end
                end*/
                //4'h2: o_cpu_rdt <= {31'b0, instr_free};
                default:
                    o_cpu_rdt <= 32'h0;
            endcase
        end
/*
    reg rd_en_spike_mem_d;
    reg rd_en_spike_mem;
    initial rd_en_spike_mem = 0;
    always @(posedge i_wb_clk)
        if(i_wb_rst | snn_valid_rst) begin
            rd_en_spike_mem_d <= 0;
        end
        else begin
            rd_en_spike_mem_d <= rd_en_spike_mem;
        end

    reg [31:0] spike_mem;
    always @(posedge i_wb_clk)
        if(i_wb_rst | snn_valid_rst) begin
            spike_mem <= 32'b0;
        end
        else begin
            if(rd_en_spike_mem_d)
                spike_mem <= o_spike_mem_dat;
        end
    
    wire [31:0] o_spike_mem_dat;
	reg [7:0] i_spike_mem_adr;
	wire [1:0] i_spike_mem_rd_en = {rd_en_spike_mem_d,rd_en_spike_mem_d};
	wire [1:0] i_spike_mem_wr_en;
	wire [3:0] i_spike_mem_dat;
*/
    wire acc_snn_valid;
    wire valid_class;
    reg acc_snn_valid_mp;
    reg valid_class_reg;
    always @(posedge i_wb_clk)
        if(i_wb_rst | snn_valid_rst) begin
            acc_snn_valid_mp <= 1'b0;
            valid_class_reg <= 1'b0;
        end
        else begin
            if(acc_snn_valid)
                acc_snn_valid_mp <= 1'b1;
            if(valid_class)
                valid_class_reg <= 1'b1;    
        end

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
        //.new_instruction(new_instruction),
        
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
/*
        .wen_instr              (wen_instr),
        .wr_addr_instr          (wr_addr_instr),
        .wr_data_instr          (wr_data_instr),

		// ACCESSIBILITY
		
        .o_spike_mem_dat(o_spike_mem_dat),
        .i_spike_mem_adr(i_spike_mem_adr),
        .i_spike_mem_rd_en(i_spike_mem_rd_en),
        .i_spike_mem_wr_en(i_spike_mem_wr_en),
        .i_spike_mem_dat(i_spike_mem_dat),
*/
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
