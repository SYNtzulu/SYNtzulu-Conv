`timescale 1ns / 1ps

module stack_new #(
    parameter DATA_WIDTH = 4,
    parameter DEPTH = 24
)(
    input  wire clk, rst,
    input  wire [DATA_WIDTH-1:0] din,
    input  wire wr_en, clear,
    input  wire stream_out,
    output wire [DATA_WIDTH-1:0] dout,
    output reg  done,
    output wire [clogb2(DEPTH-1)-1:0] active_entries,
    output wire empty
);

    reg [clogb2(DEPTH-1):0] entries_cnt;
    reg [clogb2(DEPTH-1)-1:0] stream_cnt;
    wire [DATA_WIDTH-1:0] dout_old;

    SB_RAM40_4K #(
    ) bram (
        .RDATA(dout), 
        .RADDR(stream_cnt), 
        .RCLK(clk), 
        .RCLKE(1'b1),
        .RE(1'b1), 
        .WADDR(entries_cnt), 
        .WCLK(clk), 
        .WCLKE(1'b1),
        .WDATA(din), 
        .WE(wr_en),
        .MASK(16'h0000)
    );

    always @(posedge clk) begin
        if (rst || clear)
            entries_cnt <= 0;
        else if (wr_en)
            entries_cnt <= entries_cnt + 1'b1;
    end

    always @(posedge clk) begin
        if (rst)
            stream_cnt <= 0;
        else if (stream_out && (entries_cnt != 0))
            stream_cnt <= entries_cnt - 1'b1;
        else if (stream_cnt != 0)
            stream_cnt <= stream_cnt - 1'b1;
    end

    always @(posedge clk)
        if (rst)
            done <= 0;
        else if ((stream_cnt == 1) ||
                 (stream_out && ((entries_cnt == 1) || (entries_cnt == 0))))
            done <= 1;
        else
            done <= 0;

    assign active_entries = (entries_cnt == 0) ? 0 : entries_cnt - 1'b1;
    assign empty = (entries_cnt == 0);

    function integer clogb2;
        input integer depth;
        begin
            for (clogb2 = 0; depth > 0; clogb2 = clogb2 + 1)
                depth = depth >> 1;
        end
    endfunction

endmodule
