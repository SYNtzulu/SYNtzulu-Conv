`timescale 1ns / 1ps

module encoding_spike_buffer
#(
    parameter CHANNELS = 128,
    parameter DW = 15
)
(
    input clk, rst,
    input en,
    input signed [15:0] data_in,
    
    output valid,
    output signed [DW-1:0] data_out,
	
    input external_access_en,
    input [clogb2(CHANNELS-1)-1:0] external_addr,
    output signed [15:0] external_data_out,
    input external_access_wren,
    input signed [15:0] external_data_in,

    // Uscite streaming 2-bit
    output reg s1_encoding,
    output reg s2_encoding,
    output valid_encoding
);
    // Con DW=15 usi half-rate -> 32 word da 16 bit se CHANNELS=64
    localparam CHANNELS_INT = CHANNELS/2;

    reg [clogb2(CHANNELS_INT-1)-1:0] pointer;
    reg read_flag;

    reg slow_stream_out;
    always @(posedge clk)
        slow_stream_out <= 1;

    wire [15:0] data_in_mux = external_access_wren ? external_data_in : data_in;
    wire        wr_en       = en | external_access_wren;
    wire [15:0] mem_out;

    reg  streaming; 
    reg  [clogb2(CHANNELS_INT-1)-1:0] word_idx;

    wire [clogb2(CHANNELS_INT-1)-1:0] adr =
        (external_access_en | external_access_wren) ? external_addr :
        (streaming ? word_idx : pointer);

    BRAM_singlePort_readFirst #(
        .RAM_WIDTH(16),
        .RAM_DEPTH(CHANNELS_INT),
        .RAM_PERFORMANCE("LOW_LATENCY"),
        .INIT_FILE("")
    )
    buffer (
        .addra(adr),
        .addrb(adr),
        .dina(data_in_mux),
        .clk(clk),
        .wea(wr_en),
        .ena(1'b1),
        .enb(1'b1),
        .rst(rst),
        .regceb(1'b1),
        .doutb(mem_out)
    );

    always @(posedge clk) begin
        if (rst) begin
            read_flag         <= 1'b0;
        end else if (wr_en && pointer == CHANNELS_INT-1) begin
            read_flag         <= 1'b1;
        end else if (stream_done) begin
            read_flag         <= 1'b0;
        end
    end

    always @(posedge clk) begin
        if (rst)
            pointer <= 0;
        else if (wr_en) begin
            if (pointer < CHANNELS_INT-1)
                pointer <= pointer + 1'b1;
            else
                pointer <= 0;
        end
    end

    reg valid_encoding_real, valid_encoding_real_d, valid_encoding_real_dd;
    always @(posedge clk)
        if(rst) begin
            valid_encoding_real_d <= 0;
            valid_encoding_real_dd <= 0;
        end
        else begin
            valid_encoding_real_d <= valid_encoding_real;
            valid_encoding_real_dd <= valid_encoding_real_d;
        end

    assign valid_encoding = valid_encoding_real_dd || valid_encoding_real_d;

    reg stream_done;

    assign valid = valid_encoding;

    assign data_out = mem_out;

    assign external_data_out = mem_out;

    always @(posedge clk)
        if(rst)
            bit_pair_idx_d <= 0;
        else
            bit_pair_idx_d <= bit_pair_idx;

    reg [2:0] bit_pair_idx, bit_pair_idx_d;      // 0..7 (8 coppie per word)

    always @(posedge clk) begin
        if (rst) begin
            bit_pair_idx   <= 0;
            word_idx       <= 0;
            streaming      <= 0;
            valid_encoding_real <= 0;
            s1_encoding    <= 0;
            s2_encoding    <= 0;
            stream_done    <= 0;
        end else begin
            stream_done <= 0;

            // Avvio streaming quando il buffer è pieno
            if (read_flag && !stream_done && !streaming) begin
                streaming      <= 1'b1;
                word_idx       <= 0;
                bit_pair_idx   <= 0;
                end
            if (streaming) begin
                valid_encoding_real <= 1'b1;

                // Lettura dal MSB: coppie (15,14), (13,12), ... (1,0)
                s1_encoding <= mem_out[15 - 2*bit_pair_idx_d];
                s2_encoding <= mem_out[14 - 2*bit_pair_idx_d];

                // Avanza la coppia
                if (bit_pair_idx == 3'd7) begin
                    bit_pair_idx <= 0;

                    // Avanza alla prossima word
                    if (word_idx < CHANNELS_INT-1) begin
                        word_idx  <= word_idx + 1'b1; // cambia indirizzo BRAM ora
                    end else begin
                        // Finite tutte le word
                        streaming      <= 1'b0;
                        valid_encoding_real <= 1'b0;
                        stream_done    <= 1'b1;
                    end
                end else begin
                    bit_pair_idx <= bit_pair_idx + 1'b1;
                end
            end else begin
                valid_encoding_real <= 1'b0;
            end
        end
    end

    function integer clogb2;
        input integer depth;
        for (clogb2=0; depth>0; clogb2=clogb2+1)
            depth = depth >> 1;
    endfunction

endmodule
