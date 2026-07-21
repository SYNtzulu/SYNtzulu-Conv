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

    // RAM inferita / FF su ASIC (era SB_RAM40_4K su iCE40).
    // Simple-dual-port: scrittura @ entries_cnt (porta A), lettura @ stream_cnt
    // (porta B). LOW_LATENCY = 1 ciclo di lettura, come SB_RAM40_4K.
    BRAM_singlePort_readFirst #(
        .RAM_WIDTH(DATA_WIDTH),
        .RAM_DEPTH(DEPTH),
        .RAM_PERFORMANCE("LOW_LATENCY"),
        .INIT_FILE("")
    ) bram (
        .addra(entries_cnt[clogb2(DEPTH-1)-1:0]),
        .addrb(stream_cnt),
        .dina(din),
        .clk(clk),
        .wea(wr_en),
        .ena(1'b1),
        .enb(1'b1),
        .rst(rst),
        .regceb(1'b1),
        .doutb(dout)
    );

    always @(posedge clk or posedge rst) begin
        if (rst)
            entries_cnt <= 0;
        else if (clear)
            entries_cnt <= 0;
        else if (wr_en)
            entries_cnt <= entries_cnt + 1'b1;
    end

    always @(posedge clk or posedge rst) begin
        if (rst)
            stream_cnt <= 0;
        else if (stream_out && (entries_cnt != 0))
            stream_cnt <= entries_cnt - 1'b1;
        else if (stream_cnt != 0)
            stream_cnt <= stream_cnt - 1'b1;
    end

    always @(posedge clk or posedge rst)
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
