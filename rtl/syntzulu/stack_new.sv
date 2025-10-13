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


    BRAM_singlePort_readFirst #(
        .RAM_WIDTH(DATA_WIDTH),
        .RAM_DEPTH(DEPTH),
        .RAM_PERFORMANCE("LOW_LATENCY")
    ) mem_inst (
        .addra(entries_cnt[clogb2(DEPTH-1)-1:0]), // write address
        .addrb(stream_cnt),                        // read address
        .dina(din),                                // write data
        .clk(clk),
        .wea(wr_en),                               // write enable
        .ena(wr_en | clear),                       // enable port A when writing
        .enb(1'b1),                                // always enable read port
        .rst(rst),
        .regceb(1'b1),
        .doutb(dout)
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
