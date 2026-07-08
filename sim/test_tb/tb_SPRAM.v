`timescale 1ns / 1ps

module tb_SPRAM;

    // Parameters
    parameter RAM_WIDTH = 4;
    parameter RAM_DEPTH = 64;
    parameter RAM_PERFORMANCE = "HIGH_PERFORMANCE";
    parameter INIT_FILE = "/home/federico/Documents/syntzulu_new/weights/weights_1.txt";

    // Signals
    reg [clogb2(RAM_DEPTH-1)-1:0] addra;
    reg [clogb2(RAM_DEPTH-1)-1:0] addrb;
    reg [RAM_WIDTH-1:0] dina;
    reg clk;
    reg wea;
    reg ena;
    reg enb;
    reg rst;
    reg regceb;
    wire [RAM_WIDTH-1:0] doutb;

    // Instantiate the DUT (Device Under Test)
    SPRAM_singlePort_readFirst #(
        .RAM_WIDTH(RAM_WIDTH),
        .RAM_DEPTH(RAM_DEPTH),
        .RAM_PERFORMANCE(RAM_PERFORMANCE),
        .INIT_FILE(INIT_FILE)
    ) dut (
        .addra(addra),
        .addrb(addrb),
        .dina(dina),
        .clk(clk),
        .wea(wea),
        .ena(ena),
        .enb(enb),
        .rst(rst),
        .regceb(regceb),
        .doutb(doutb)
    );

    // Clock generation
    initial clk = 0;
    always #5 clk = ~clk;

    // Testbench logic
    initial begin
        $dumpfile("tb.vcd"); 
        $dumpvars(10,tb_SPRAM); 
        // Initialize inputs
        addra = 0;
        addrb = 0;
        dina = 0;
        wea = 0;
        ena = 0;
        enb = 0;
        rst = 0;
        regceb = 0;

        // Reset
        rst = 1;
        #10;
        rst = 0;

        // Write operation
        ena = 1;
        wea = 1;
        addra = 5;
        dina = 4'b1010;
        #10;

        // Read operation
        wea = 0;
        enb = 1;
        addrb = 5;
        regceb = 1;
        #50;

        // Check output
        $display("Read data: %b", doutb);

        // Finish simulation
        $finish;
    end

    // Function to calculate clogb2
    function integer clogb2;
        input integer depth;
        begin
            clogb2 = 0;
            while (depth > 0) begin
                clogb2 = clogb2 + 1;
                depth = depth >> 1;
            end
        end
    endfunction

endmodule