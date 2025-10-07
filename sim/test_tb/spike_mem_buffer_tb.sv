`timescale 1ns/1ps

module tb_spike_mem_buffer;

    reg clk;
    reg rst;
    reg dense_enable;
    reg conv_enable;
    reg s1, s2;
    reg valid_s1, valid_s2;
    reg [4:0] next_dim_input_feature;

    wire [15:0] spike_mem_in;
    wire spike_wr_en;

    // DUT
    spike_mem_buffer dut (
        .clk(clk),
        .rst(rst),
        .dense_enable(dense_enable),
        .conv_enable(conv_enable),
        .SYNAPSES(15),
        .s1(s1),
        .valid_s1(valid_s1),
        .s2(s2),
        .valid_s2(valid_s2),
        .next_dim_input_feature(next_dim_input_feature),
        .spike_mem_in(spike_mem_in),
        .spike_wr_en(spike_wr_en)
    );

    // clock
    always #5 clk = ~clk;

    integer i;

    // stimoli
    initial begin
        $dumpfile("tb_lif.vcd");
        $dumpvars(10, tb_spike_mem_buffer);

        clk = 0;
        rst = 1;
        dense_enable = 1;
        conv_enable  = 0;
        s1 = 0; s2 = 0;
        valid_s1 = 0; valid_s2 = 0;
        next_dim_input_feature = 5'd0;

        // reset
        #20 rst = 0;

        // Prova con dimensione = 5
        next_dim_input_feature = 5;
        $display("\n=== Test dim_input=5 ===");
        for (i = 0; i < 20; i = i + 1) begin
            @(posedge clk);
            s1 = $random % 2;
            s2 = $random % 2;
            valid_s1 = 1;
            valid_s2 = 1;
            @(posedge clk);
            if (spike_wr_en) begin
                $display("time=%0t word=%b",$time, spike_mem_in);
            end
        end

        // Prova con dimensione = 6
        next_dim_input_feature = 6;
        $display("\n=== Test dim_input=6 ===");
        for (i = 0; i < 20; i = i + 1) begin
            @(posedge clk);
            s1 = $random % 2;
            s2 = $random % 2;
            valid_s1 = 1;
            valid_s2 = 1;
            @(posedge clk);
            if (spike_wr_en) begin
                $display("time=%0t word=%b",$time, spike_mem_in);
            end
        end

        // Prova con dimensione = 7
        next_dim_input_feature = 7;
        $display("\n=== Test dim_input=7 ===");
        for (i = 0; i < 20; i = i + 1) begin
            @(posedge clk);
            s1 = $random % 2;
            s2 = $random % 2;
            valid_s1 = 1;
            valid_s2 = 1;
            @(posedge clk);
            if (spike_wr_en) begin
                $display("time=%0t word=%b",$time, spike_mem_in);
            end
        end

        // Prova con dimensione = 8
        next_dim_input_feature = 8;
        $display("\n=== Test dim_input=8 ===");
        for (i = 0; i < 20; i = i + 1) begin
            @(posedge clk);
            s1 = $random % 2;
            s2 = $random % 2;
            valid_s1 = 1;
            valid_s2 = 1;
            @(posedge clk);
            if (spike_wr_en) begin
                $display("time=%0t word=%b",$time, spike_mem_in);
            end
        end

        $finish;
    end

endmodule
