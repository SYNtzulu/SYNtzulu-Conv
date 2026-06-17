module instruction_decoder #(
    parameter INSTR_WIDTH = 80,
    parameter MAX_SYNAPSES = 256
)(
    input  wire [INSTR_WIDTH-1:0] instr,

    // --- campi comuni ---
    output wire [1:0]  layer_type,               // [79:78]
    output wire [6:0]  neuron,                   // [77:71]
    output wire [6:0]  synapses,                 // [70:64]
    output wire [11:0] voltage_decay,            // [63:52]
    output wire [15:0] threshold,                // [51:36]
    output wire [3:0]  next_dim_input_feature,   // [35:31]
    output wire [2:0]  bit_for_spike,            // [30:28]

    // --- campi CONV ---
    output wire [5:0]  number_input_feature,     // [75:71]
    output wire [5:0]  number_output_feature,    // [68:64]
    output wire        padding,      
    output wire [4:0]  size_input_feature,       // [30:27]
    output wire [1:0]  stride,                   // [70:69]
    output wire [1:0]  kernel_size,              // [77:76]
    output wire        dense_next,               // [79]
    output wire [clogb2(MAX_SYNAPSES-1)-1:0] SYNAPSES,
    output wire [3:0] size_output_feature,
    output wire [7:0] square_dim_output_feature,
    output wire recurrency,
    output wire recurrency_next   ,
    output wire [11:0] M ,
    output wire [15:0] reset_recurrency,
    output wire first_layer_no_spike
);

    // === CAMPI COMUNI ===
    assign layer_type             = (instr[79:78]==2'b11) ? 2'b01 : instr[79:78];
    assign neuron                 = instr[77:71];
    assign bit_for_spike          = instr[66:64];
    assign voltage_decay          = 0 ;//instr[63:52];  //unused
    assign M                      = instr[63:52];  	
    assign threshold              = 0; //instr[51:36];  //unused
    assign reset_recurrency       = instr[51:36];  
    assign next_dim_input_feature = instr[35:32];
    
    // === SOLO CONV ===
    assign number_input_feature      = instr[75:71];   
    assign number_output_feature     = instr[68:64] + 1;   
    assign padding                   = instr[31];
    assign size_input_feature        = instr[30:27] + 1;   
    assign kernel_size               = instr[77:76];
    assign stride                    = instr[70:69];
    assign dense_next                = instr[79];
    assign square_dim_output_feature = instr[15:8];
    assign size_output_feature       = instr[7:4];  
    
    assign recurrency                = instr[3]; 
    assign recurrency_next           = instr[2];
    assign first_layer_no_spike      = instr[1];

    assign SYNAPSES                  = instr[26:19];

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
