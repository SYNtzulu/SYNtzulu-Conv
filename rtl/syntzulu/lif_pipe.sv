module lif_pipe (
    input clk,
    input rst,
    input detection,
    input first_input_feature,
    input last_input_feature,
    input en_L2,
    output detection_out,
    output first_input_feature_out,
    output last_input_feature_out,
    output en_L2_out
);

    // Pipeline registers for detection
    reg [9:0] pipe_detection;
    // Pipeline registers for first_input_feature
    reg [5:0] pipe_first_input_feature;

    reg [9:0] pipe_last_input_feature;

    reg [9:0] pipe_en_L2;

    always @(posedge clk) begin
        if (rst) begin
            pipe_detection <= 10'b0;
            pipe_first_input_feature <= 6'b0;
            pipe_last_input_feature <= 10'b0;
            pipe_en_L2 <= 10'b0;
        end else begin
            pipe_detection <= {pipe_detection[9:0], detection};
            pipe_first_input_feature <= {pipe_first_input_feature[5:0], first_input_feature};
            pipe_last_input_feature <= {pipe_last_input_feature[9:0], last_input_feature};
            pipe_en_L2 <= {pipe_en_L2[9:0], en_L2};
        end
    end

    assign detection_out = pipe_detection[9];
    assign first_input_feature_out = pipe_first_input_feature[5];
    assign last_input_feature_out = pipe_last_input_feature[9];
    assign en_L2_out = pipe_en_L2[9];

endmodule