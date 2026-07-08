module lif_pipe (
    input clk,
    input rst,
    input pooling_enable,
    input detection,
    input first_input_feature,
    input input_feature_finish,
    input last_input_feature,
    input en_L2,
    output detection_out,
    output first_input_feature_out,
    output last_input_feature_out,
    output input_feature_finish_out,
    output en_L2_out
);

    // Pipeline registers for detection
    reg [10:0] pipe_detection;
    // Pipeline registers for first_input_feature
    reg [6:0] pipe_first_input_feature;

    reg [10:0] pipe_last_input_feature;
    reg [10:0] pipe_input_feature_finish;

    reg [10:0] pipe_en_L2;

    always @(posedge clk) begin
        if (rst) begin
            pipe_detection <= 11'b0;
            pipe_first_input_feature <= 7'b0;
            pipe_last_input_feature <= 11'b0;
            pipe_en_L2 <= 11'b0;
            pipe_input_feature_finish <= 11'b0;
        end else begin
            pipe_detection <= {pipe_detection[10:0], detection};
            pipe_first_input_feature <= {pipe_first_input_feature[6:0], first_input_feature};
            pipe_last_input_feature <= {pipe_last_input_feature[10:0], last_input_feature};
            pipe_en_L2 <= {pipe_en_L2[10:0], en_L2};
            pipe_input_feature_finish <= {pipe_input_feature_finish, input_feature_finish};
        end
    end

    assign detection_out = pipe_detection[10];
    assign first_input_feature_out = pipe_first_input_feature[6];
    assign last_input_feature_out = pooling_enable ? pipe_last_input_feature[0] : pipe_last_input_feature[10];
    assign en_L2_out = pooling_enable ? pipe_en_L2[0] : pipe_en_L2[10];
    assign input_feature_finish_out = pipe_input_feature_finish[10];

endmodule