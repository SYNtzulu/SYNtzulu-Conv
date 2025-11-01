// Author: Mauro Orrù
// Module: servant_estu
// Purpose: Definition of the slave module for the estu accelerator that will be controlled by the RISC-V SERV processor.
//
// Memory mapped register interface:
//   - mm_start_inference:     The start ingerence signal is pulled down in this module when the inference is done.
//     In this way the RISC-V SERV processore che wait until the inference is done before execute another inference 
//     controlling the frequency of the inference via firmware.
//
//   - num_instr:           The number of instructions to be executed by the estu accelerator. This value, in our specific case,
//     is multiplied by 6 because we have 168 bit instruction saved in parallel in two 16 bits BRAMs that needs 6 access to read
//     the whole instruction. The value is set by the RISC-V SERV processor and read by the estu accelerator
//
//   - wr_port_enable:      It is used to enable the corresponding write port of the estu accelerator for the four main data memories:
//     int_mem2, int_mem1, spike_mem2, spike_mem1. 


module servant_estu #(
    parameter SPIKE_MEM_WIDTH   = 4,
    parameter SPIKE_MEM_DEPTH   = 1024,
    parameter RAM_PERFORMANCE   = "HIGH_PERFORMANCE",
    parameter INIT_FILE_SM1     = "",
    parameter INIT_FILE_SM2     = "",
    parameter INIT_FILE_SM3     = "",
    parameter INIT_FILE_SM4     = "",
    parameter NUM_MEMS_SPIKE_MEM= 4,
    parameter DEPTH_INT_MEM     = 1024,
    parameter INIT_FILE_INTMEM1 = "scripts/Python/weights/INIT_FILE_INTMEM1.txt",
    parameter INIT_FILE_INTMEM2 = "scripts/Python/weights/INIT_FILE_INTMEM2.txt",
    parameter DIM_ADDR_SPIKE_MEM= 12,
    parameter DIM_ADDR_SPRAM    = 14,
    parameter DIM_MAX_MEM       = 14,
    parameter DIM_INPUT_NEURONS = 6,
    parameter DIM_OUTPUT_NEURONS= 10,
    parameter DIM_MAX_LOGIC_ADDRESS= 10,
    parameter DEPTH_STACK       = 3468,
    parameter INIT_STACK        = "scripts/stack_init.txt",
    parameter DATA_WIDTH        = 8,
    parameter V_COMP_K_Q        = 800,
    parameter WIDTH_BRAM        = 4,
    parameter WIDTH_SPRAM       = 16,
    parameter DIM_MODE          = 5,
    parameter DIM_GROUP_SPIKES  = 2,
    parameter DIM_SUMS_SPIKES   = 16,
    parameter NUM_MEMS          = 4,
    parameter DIM_OFFSET        = 7,
    parameter DIM_OFFSET_STACK  = 6,
    parameter DIM_TIMESTEP      = 8,
    parameter DIM_GROUP_SPIKE4  = 4,
    parameter DIM_GROUP_16      = 16,
    parameter DIM_CURRENT       = 22,
    parameter DIM_CTRL          = 7,
    parameter NEURON            = 653,
    parameter DIM_CURR_DECAY_LIF= 14,
    parameter DIM_VOLT_DECAY_LIF= 14,
    parameter WIDTH_LIF         = 20, // <----
    parameter INSTR_MEM_WIDTH   = 32,
    parameter TOT_NUM_INSTR     = 30,
    parameter DIM_INSTR         = 169,
    parameter NUM_INSTR         = (DIM_INSTR >> 5) + 1, // 6 di default
    parameter DIM_NUM_INSTR     = 8,
    parameter INSTR_MEM_DEPTH   = ((DIM_INSTR >> 5) + 1)*TOT_NUM_INSTR,
    parameter INIT_INSTR_MEM    = "scripts/Python/InstructionGenerator/instr_mem.txt",
    parameter CHANNELS         = 16 // Number of channels for the encoding slot
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
    output wire         wen_intmem1_spi,
    output wire [DIM_ADDR_SPRAM-1:0] wr_addr_intmem1_spi,
    output wire [WIDTH_SPRAM-1:0] wr_data_intmem1_spi,
    output wire         wen_intmem2_spi,
    output wire [DIM_ADDR_SPRAM-1:0] wr_addr_intmem2_spi,
    output wire [WIDTH_SPRAM-1:0] wr_data_intmem2_spi,
    // SPI signals
    input  wire [15:0]  i_sample_mem_spi,
    input  wire i_en_encoding_slot,
    output wire [12:0] o_data_last_layer
    
);

// =========================================================================
// Internal memory mapped register
// =========================================================================
(* keep *) reg mm_start_inference;
reg mm_end_inference;
reg [DIM_NUM_INSTR-1:0] mm_num_instr; 
// Spike mem1
reg [DIM_ADDR_SPIKE_MEM-1 : 0] spike_mem1_wr_addr;
reg [SPIKE_MEM_WIDTH-1:0] spike_mem1_data;
reg spike_mem1_wr_en; 
// Spike mem2
reg [DIM_ADDR_SPIKE_MEM-1 : 0] spike_mem2_wr_addr;
reg [SPIKE_MEM_WIDTH-1:0] spike_mem2_data;
reg spike_mem2_wr_en; 
/*
mm_external_wren: This signal is used to enable the writing to some memories of the ESTU accelerator from
the bus. In our specific case the two integer memories are written from the bus.
mm_external_wren[0]: enable writing to int_mem1
mm_external_wren[1]: enable writing to int_mem2
*/
reg [1:0] mm_external_wren;
reg mm_encoding_bypass;


// =========================================================================
// Other input signals of ESTU
// =========================================================================
/* 
clr_valid_ll_ext: This signal is used to clear the valid last layer external signal.
It is set to 1 when the CPU access to the valid last layer signal.
In other words: suppose that you want to access to the intermediate results of the inference,
the valid last layer signal is setted to one when the feed forward in the timestep is done.
The clr_valid_ll_ext signal performs the reset of the valid last layer signal and also of the 
output data last layer signal.
*/
reg valid_ll;
wire end_inference, valid_last_layer, clr_valid_ll_ext, clr_start_inference;
wire [12:0] data_last_layer;
wire [15:0] o_sample_mem_dat; 
reg [15:0] mm_sample_mem_dat; // Memory mapped sample memory data
wire sample_mem_wr_en, sample_mem_rd_en;

// =========================================================================
// Other control signals
// =========================================================================

wire cyc_we_pulse;
reg cyc_we_d;
always @(posedge i_wb_clk) begin
    if (i_wb_rst) begin
        cyc_we_d <= 1'b0;
    end 
    else begin
        cyc_we_d <= i_cpu_we; 
    end
end
// impulso: diventa 1 solo nel clock in cui cyc_we_now passa da 0 a 1
assign cyc_we_pulse = i_cpu_we & ~cyc_we_d;




// bram read requires an extra clock cycle (sample mem) or two (spike mem) 
// => ack is delayed by 2 c.c if spike mems are accessed, and by 1 c.c. otherwise 
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
	assign o_cpu_ack = (i_cpu_adr_d == 8'h03) ? o_cpu_ack_d : o_cpu_ack_int ;	



// =========================================================================
// Address decoding for the memory mapped register interface
// =========================================================================
always @(posedge i_wb_clk) begin
    if (i_wb_rst) begin
        // Reset of the memory mapped registers
        mm_start_inference <= 1'b0;
        mm_encoding_bypass <= 1'b0;
        mm_num_instr <= {DIM_NUM_INSTR{1'b0}};
        mm_external_wren <= 2'b00; // No external write enable
    end 

    else if (clr_start_inference) begin
        mm_start_inference <= 1'b0; // Reset the signal when the inference is done
    end

    else begin
        case(i_cpu_adr[19:16]) 
        // ---------------------------- Start Inference ----------------------------
        4'h0: begin 
            if (i_cpu_cyc & i_cpu_we) begin
                mm_start_inference <= i_cpu_dat[0];
            end    
        end

        // ------------------------- Number of instruction -------------------------
        4'h1: begin // Number of instructions multiplied by 6
            if (i_cpu_cyc & i_cpu_we) begin
                mm_num_instr <= i_cpu_dat[DIM_NUM_INSTR-1:0];
            end    
        end

        // ------------------------- Write external enable-----------------------------------
        4'h2: begin 
            if (i_cpu_cyc & i_cpu_we) begin // Write only
                mm_external_wren <= i_cpu_dat[1:0]; 
            end
        end

        // ------------------------- Access to Sample Mem -----------------------------------
        4'h3: begin
            if (i_cpu_cyc & i_cpu_we) begin // Write only
                mm_sample_mem_dat <= i_cpu_dat[15:0]; 
            end 
            else if (i_cpu_cyc & ~i_cpu_we) begin // Read only
                o_cpu_rdt <= {16'h0, o_sample_mem_dat}; // Read sample memory data
            end
        end

        `ifdef ACCESSIBILITY
        4'h4: begin
            if (i_cpu_cyc & i_cpu_we) begin // Write only
                mm_encoding_bypass <= i_cpu_dat[0]; 
            end
        end
        `endif

        // ------------------------ Data ------------------------------------
        /*
            The first bit is used to indicate a valid data.
            The next 13 bits are used to indicate the data of the last layer.
        */
        4'h5: begin
            if (i_cpu_cyc & ~i_cpu_we) begin // Read only
                o_cpu_rdt <= {18'h0, data_last_layer, valid_ll}; // Read data last layer
            end
        end
        
        default: begin
            o_cpu_rdt <= 32'h0;
        end
        endcase
    end
end

assign clr_valid_ll_ext = ((i_cpu_adr[19:16] == 4'h5) & i_cpu_cyc & ~i_cpu_we)&valid_ll&~o_cpu_ack_d;
reg clr_valid_ll_d;
always @(posedge i_wb_clk) begin
    if (i_wb_rst) begin
        clr_valid_ll_d <= 1'b0;
    end
    else begin
        clr_valid_ll_d <= clr_valid_ll_ext; // Store the clear valid last layer signal
    end
end
always @(posedge i_wb_clk) begin
    if (i_wb_rst | clr_valid_ll_d) begin
        valid_ll <= 1'b0; // Reset end inference signal
    end 
    else if (valid_last_layer)
        valid_ll <= 1'b1;  
end

////////////////////////////////
//  _____ ____ _____ _   _    //
// | ____/ ___|_   _| | | |   //
// |  _| \___ \ | | | | | |   //
// | |___ ___) || | | |_| |   //
// |_____|____/ |_|  \___/    //
//                            //
////////////////////////////////
localparam CH_LOGB2 = clogb2(CHANNELS-1); // Calculate the log base 2 of the number of channels
assign sample_mem_wr_en = i_cpu_cyc & i_cpu_we & (i_cpu_adr[27:20] == 8'h03); // Write enable for sample memory
assign sample_mem_rd_en = i_cpu_cyc & ~i_cpu_we & (i_cpu_adr[27:20] == 8'h03); // Read enable for sample memory
estu #(
    .SPIKE_MEM_WIDTH   (SPIKE_MEM_WIDTH),
    .SPIKE_MEM_DEPTH   (SPIKE_MEM_DEPTH),
    .RAM_PERFORMANCE   (RAM_PERFORMANCE),
    .INIT_FILE_SM1     (INIT_FILE_SM1),
    .INIT_FILE_SM2     (INIT_FILE_SM2),
    .INIT_FILE_SM3     (INIT_FILE_SM3),
    .INIT_FILE_SM4     (INIT_FILE_SM4),
    .NUM_MEMS_SPIKE_MEM(NUM_MEMS_SPIKE_MEM),
    .DEPTH_INT_MEM     (DEPTH_INT_MEM),
    .INIT_FILE_INTMEM1 (INIT_FILE_INTMEM1),
    .INIT_FILE_INTMEM2 (INIT_FILE_INTMEM2),
    .DIM_ADDR_SPIKE_MEM(DIM_ADDR_SPIKE_MEM),
    .DIM_ADDR_SPRAM    (DIM_ADDR_SPRAM),
    .DIM_MAX_MEM       (DIM_MAX_MEM),
    .DIM_INPUT_NEURONS (DIM_INPUT_NEURONS),
    .DIM_OUTPUT_NEURONS(DIM_OUTPUT_NEURONS),
    .DIM_MAX_LOGIC_ADDRESS(DIM_MAX_LOGIC_ADDRESS),
    .DEPTH_STACK       (DEPTH_STACK),
    .INIT_STACK        (INIT_STACK),
    .DATA_WIDTH        (DATA_WIDTH),
    .V_COMP_K_Q        (V_COMP_K_Q),
    .WIDTH_BRAM        (WIDTH_BRAM),
    .WIDTH_SPRAM       (WIDTH_SPRAM),
    .DIM_MODE          (DIM_MODE),
    .DIM_GROUP_SPIKES  (DIM_GROUP_SPIKES),
    .DIM_SUMS_SPIKES   (DIM_SUMS_SPIKES),
    .NUM_MEMS          (NUM_MEMS),
    .DIM_OFFSET        (DIM_OFFSET),
    .DIM_OFFSET_STACK  (DIM_OFFSET_STACK),
    .DIM_TIMESTEP      (DIM_TIMESTEP),
    .DIM_GROUP_SPIKE4  (DIM_GROUP_SPIKE4),
    .DIM_GROUP_16      (DIM_GROUP_16),
    .DIM_CURRENT       (DIM_CURRENT),
    .DIM_CTRL          (DIM_CTRL),
    .NEURON            (NEURON),
    .DIM_CURR_DECAY_LIF(DIM_CURR_DECAY_LIF),
    .DIM_VOLT_DECAY_LIF(DIM_VOLT_DECAY_LIF),
    .WIDTH_LIF         (WIDTH_LIF),
    .INSTR_MEM_WIDTH   (INSTR_MEM_WIDTH),
    .TOT_NUM_INSTR     (TOT_NUM_INSTR),
    .DIM_INSTR         (DIM_INSTR),
    .NUM_INSTR         (NUM_INSTR),
    .DIM_NUM_INSTR     (DIM_NUM_INSTR),
    .INSTR_MEM_DEPTH   (INSTR_MEM_DEPTH),
    .INIT_INSTR_MEM    (INIT_INSTR_MEM),
    .CHANNELS          (CHANNELS) // Number of channels for the encoding slot
) inst_estu(
    .clk                    (i_wb_clk),
    .rst                    (i_wb_rst),
    .i_start_inference      (mm_start_inference), // Start inference signal
    .num_instr              (mm_num_instr),
    .i_clr_valid_ll_ext     (clr_valid_ll_ext),
    /*
    // Spike memory 1
    .i_spike_mem1           (spike_mem1_data),
    .i_spike_mem1_wr_addr   (spike_mem1_wr_addr),
    .i_wr_en_sm1            (spike_mem1_wr_en),
    // Spike memory 2
    .i_spike_mem2           (spike_mem2_data),
    .i_spike_mem2_wr_addr   (spike_mem2_wr_addr),
    .i_wr_en_sm2            (spike_mem2_wr_en), */
    // Int memory 1
    .i_int_mem1             (wr_data_intmem1_spi),
    .i_int_mem1_wr_addr     (wr_addr_intmem2_spi),
    .i_wr_en_intmem1        (wen_intmem1_spi),
    // Int memory 2
    .i_int_mem2             (wr_data_intmem2_spi),
    .i_int_mem2_wr_addr     (wr_addr_intmem2_spi), 
    .i_wr_en_intmem2        (wen_intmem2_spi),
    // External write enable
    .i_external_wren        (mm_external_wren),
    // Outputs
    .o_data_last_layer      (data_last_layer),
    .end_inference          (end_inference),
    .o_valid_last_layer     (valid_last_layer),
    .i_clk_enc              (i_wb_clk), // Clock for encoding slot
    .o_sample_mem_dat       (o_sample_mem_dat), // Output data for sample memory
    .i_sample_mem_adr       (i_cpu_adr[CH_LOGB2+1:1]), // Address for sample
    .i_sample_mem_rd_en     (sample_mem_rd_en), // Read enable for sample memory
    .i_sample_mem_wr_en     (sample_mem_wr_en), // Write enable for
    .i_sample_mem_dat       (mm_sample_mem_dat),  // Data for sample memory
    .i_sample_mem_spi       (i_sample_mem_spi),
    .i_en_encoding_slot     (i_en_encoding_slot),
    .i_encoding_bypass      (mm_encoding_bypass),
    .o_clr_start_inf        (clr_start_inference)
);
assign o_data_last_layer = data_last_layer; // Output data last layer
//  The following function calculates the address width based on specified RAM depth
function integer clogb2;
    input integer depth;
    for (clogb2=0; depth>0; clogb2=clogb2+1)
        depth = depth >> 1;
endfunction 

endmodule