module instruction_decoder #(
    parameter INSTR_WIDTH = 64
)(
    input  wire [INSTR_WIDTH-1:0] instr,

    // comuni
    output wire [1:0]  layer_type,               // [63:62]

    // DENSE (00)
    output wire [6:0]  neuron,                   // [61:55]
    output wire [6:0]  synapses,                 // [54:48]
    output wire [4:0]  next_dim_input_feature,   // [19:15]
    output wire [11:0] voltage_decay,            // [47:36]
    output wire [15:0] threshold,                // [35:20]
    output wire [2:0]  bit_for_spike,            // [14:12]

    // CONV (01)
    output wire [5:0]  number_input_feature,     
    output wire [5:0]  number_output_feature,    
    output wire [3:0]  size_input_feature,       // [14:11]
    output wire [1:0]  stride,                   // [8:7]
    output wire [1:0]  kernel_size,              // [10:9]
    output wire        address_input_feature,    // [6]
    output wire        dense_next,                // [5]
    output wire [10:0] SYNAPSES
);

    // === CAMPI COMUNI ===
    assign layer_type             = (instr[63:62]==2'b11) ? 2'b01 : instr[63:62];
    assign neuron                 = instr[61:55];
    assign synapses               = instr[54:48];
    assign voltage_decay          = instr[47:36];
    assign threshold              = instr[35:20];
    assign next_dim_input_feature = instr[19:15];
    assign bit_for_spike          = instr[14:12];

    // === SOLO CONV ===
    assign number_input_feature   = instr[59:55] + 1;   
    assign number_output_feature  = instr[52:48] + 1;   
    assign size_input_feature     = instr[14:11];   

    
    assign kernel_size            = instr[61:60];
    assign stride                 = instr[54:53];
    assign dense_next             = instr[63];

    assign SYNAPSES               = instr[10:0];
endmodule
