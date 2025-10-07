// Testbench for lif_pipe module
module lif_pipe_tb;

    // Testbench signals
    reg clk;
    reg rst;
    reg detection;
    reg first_input_feature;
    wire detection_out;
    wire first_input_feature_out;

    // Instantiate the lif_pipe module
    lif_pipe uut (
        .clk(clk),
        .rst(rst),
        .detection(detection),
        .first_input_feature(first_input_feature),
        .detection_out(detection_out),
        .first_input_feature_out(first_input_feature_out)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 10 time units clock period
    end

    // Test sequence
    initial begin
        $dumpfile("tb_lif.vcd"); 
        $dumpvars(10,lif_pipe_tb); 
        // Initialize inputs
        rst = 0;
        detection = 0;
        first_input_feature = 0;

        // Apply reset
        #10 rst = 1;

        // Test pipeline behavior
        #10 detection = 1; first_input_feature = 1;
        #10 detection = 0; first_input_feature = 0;
        #10 detection = 1; first_input_feature = 0;
        #10 detection = 0; first_input_feature = 1;

        // Wait for pipeline to propagate
        #50;

        // End simulation
        $finish;
    end
endmodule