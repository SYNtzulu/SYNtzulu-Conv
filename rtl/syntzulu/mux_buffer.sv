module mux_buffer#(
    parameter MAX_INPUT_FEATURE = 16,
    parameter MAX_KERNEL = 3
)(
    input clk,
    input en,
    input rst,
    input [1:0] stride,
    input padding,
    input input_feature_ready,
    input conv_enable,
    input [3:0] last_state,
    input wire [MAX_INPUT_FEATURE*MAX_KERNEL-1:0] input_feature_row,
    output wire [MAX_KERNEL*MAX_KERNEL-1:0] output_kernel,
    output row_finish
);  
    localparam SAFE_LOG2_A = (MAX_INPUT_FEATURE/3 > 1) ? $clog2(MAX_INPUT_FEATURE/3) : 1;
    localparam SAFE_LOG2_K = (MAX_KERNEL > 1) ? $clog2(MAX_KERNEL) : 1;
    
    wire [SAFE_LOG2_A-1:0] sel_A;
    wire [SAFE_LOG2_A-1:0] sel_B;
    wire [SAFE_LOG2_A-1:0] sel_C;
    wire [SAFE_LOG2_K-1:0] sel_k0;
    wire [SAFE_LOG2_K-1:0] sel_k1;
    wire [SAFE_LOG2_K-1:0] sel_k2;

    controll_mux #(
        .MAX_INPUT_FEATURE(MAX_INPUT_FEATURE),
        .MAX_KERNEL(MAX_KERNEL)
    )
    controll_mux (
        .clk(clk),
        .en(en),
        .rst(rst),
        .stride(stride),
        .padding(padding),
        .conv_enable(conv_enable),
        .last_state(last_state),
        .input_feature_ready(input_feature_ready),
        .sel_A(sel_A),
        .sel_B(sel_B),
        .sel_C(sel_C),
        .sel_k0(sel_k0),
        .sel_k1(sel_k1),
        .sel_k2(sel_k2),
        .row_finish(row_finish)
    );

    mux_row #(
        .MAX_INPUT_FEATURE(MAX_INPUT_FEATURE), 
        .MAX_KERNEL(MAX_KERNEL)
    ) mux_row_0 (
        .input_feature_row(input_feature_row[15:0]), 
        .sel_A(sel_A), 
        .sel_B(sel_B), 
        .sel_C(sel_C), 
        .sel_k0(sel_k0), 
        .sel_k1(sel_k1), 
        .sel_k2(sel_k2), 
        .output_kernel(output_kernel[2:0])
    );

    mux_row #(
        .MAX_INPUT_FEATURE(MAX_INPUT_FEATURE), 
        .MAX_KERNEL(MAX_KERNEL)
    ) mux_row_1 (
        .input_feature_row(input_feature_row[31:16]), 
        .sel_A(sel_A), 
        .sel_B(sel_B), 
        .sel_C(sel_C), 
        .sel_k0(sel_k0), 
        .sel_k1(sel_k1), 
        .sel_k2(sel_k2), 
        .output_kernel(output_kernel[5:3])
    );

    mux_row #(
        .MAX_INPUT_FEATURE(MAX_INPUT_FEATURE), 
        .MAX_KERNEL(MAX_KERNEL)
    ) mux_row_2 (
        .input_feature_row(input_feature_row[47:32]), 
                .sel_A(sel_A), 
                .sel_B(sel_B), 
                .sel_C(sel_C), 
                .sel_k0(sel_k0), 
                .sel_k1(sel_k1), 
                .sel_k2(sel_k2), 
        .output_kernel(output_kernel[8:6])
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


module mux_row#(
    parameter MAX_INPUT_FEATURE = 16,
    parameter MAX_KERNEL = 3
)(
    input  wire [MAX_INPUT_FEATURE-1:0] input_feature_row,
    input  wire [$clog2(MAX_INPUT_FEATURE/3)-1:0] sel_A,
    input  wire [$clog2(MAX_INPUT_FEATURE/3)-1:0] sel_B,
    input  wire [$clog2(MAX_INPUT_FEATURE/3)-1:0] sel_C,
    input  wire [$clog2(MAX_KERNEL)-1:0] sel_k0,
    input  wire [$clog2(MAX_KERNEL)-1:0] sel_k1,
    input  wire [$clog2(MAX_KERNEL)-1:0] sel_k2,
    output wire [MAX_KERNEL-1:0] output_kernel
);
    wire y_A, y_B, y_C;

    assign y_A = get_col_A(input_feature_row, sel_A);
    assign y_B = get_col_B(input_feature_row, sel_B);
    assign y_C = get_col_C(input_feature_row, sel_C);

    assign output_kernel[2] = sel3(sel_k0, y_A, y_B, y_C);
    assign output_kernel[1] = sel3(sel_k1, y_A, y_B, y_C);
    assign output_kernel[0] = sel3(sel_k2, y_A, y_B, y_C);

    function get_col_A;
        input [MAX_INPUT_FEATURE-1:0] row;
        input [2:0] idx;
        begin
            case (idx)
                3'd0: get_col_A = row[0];
                3'd1: get_col_A = row[3];
                3'd2: get_col_A = row[6];
                3'd3: get_col_A = row[9];
                3'd4: get_col_A = row[12];
                default: get_col_A = row[15];
            endcase
        end
    endfunction

    function get_col_B;
        input [MAX_INPUT_FEATURE-1:0] row;
        input [2:0] idx;
        begin
            case (idx)
                3'd0: get_col_B = row[2];
                3'd1: get_col_B = row[5];
                3'd2: get_col_B = row[8];
                3'd3: get_col_B = row[11];
                3'd4: get_col_B = row[14];
                default: get_col_B = row[14];
            endcase
        end
    endfunction

    function get_col_C;
        input [MAX_INPUT_FEATURE-1:0] row;
        input [2:0] idx;
        begin
            case (idx)
                3'd0: get_col_C = row[1];
                3'd1: get_col_C = row[4];
                3'd2: get_col_C = row[7];
                3'd3: get_col_C = row[10];
                3'd4: get_col_C = row[13];
                default: get_col_C = row[13];
            endcase
        end
    endfunction

    function sel3;
        input [1:0] s;
        input a, b, c;
        begin
            case (s)
                2'd0: sel3 = c;
                2'd1: sel3 = b;
                2'd2: sel3 = a;
                3'd3: sel3 = 1'b0;
                default: sel3 = a;
            endcase
        end
    endfunction
endmodule


