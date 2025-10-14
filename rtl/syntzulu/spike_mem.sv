module spike_mem #(
    parameter SPIKE_MEM_WIDTH = 16,
    parameter SPIKE_MEM_DEPTH = 256,
    parameter MAX_SYNAPSES = 512
)(
    input clk,
    input rst,
    input layer_counter,
    input valid_encoding,
    input s1,
    input valid_s1,
    input s2,
    input valid_s2,
    input dense_enable,
    input conv_enable,
    input [4:0] next_dim_input_feature,
    input [10:0] SYNAPSES,
    input [clogb2(SPIKE_MEM_DEPTH)-1:0] spike_rd_addr_1,
    input [clogb2(SPIKE_MEM_DEPTH)-1:0] spike_rd_addr_2,
    input spike_wr_en_in_1,
    input spike_wr_en_in_2,
    input en_L2,
    input output_feature_finish,
    input last_layer,
    output spike_written,
    output spike_written_comb,
    output active_spike,
    output [12:0] spike_wr_addr,
    output [SPIKE_MEM_WIDTH-1:0] spike_mem_out_16,
    output [3:0] spike_mem_out_4,
    output valid_active_group
);  

    reg spike_wr_en_1_d, spike_wr_en_1_dd;
    reg spike_wr_en_2_d, spike_wr_en_2_dd;
    always @(posedge clk) begin
        if(rst) begin
            spike_wr_en_1_d <= 0;
            spike_wr_en_1_dd <= 0;
            spike_wr_en_2_d <= 0;
            spike_wr_en_2_dd <= 0;
        end
        else begin
            spike_wr_en_1_d <= spike_wr_en_in_1;
            spike_wr_en_1_dd <= spike_wr_en_1_d;
            spike_wr_en_2_d <= spike_wr_en_in_2;
            spike_wr_en_2_dd <= spike_wr_en_2_d;
        end
    end

    wire [clogb2(SPIKE_MEM_DEPTH)-1:0] spike_rd_addr_16_1;
    wire [clogb2(SPIKE_MEM_DEPTH)-1:0] spike_rd_addr_16_2;

    wire [clogb2(SPIKE_MEM_DEPTH)-1:0] spike_rd_addr = layer_counter ? spike_rd_addr_2 : spike_rd_addr_1;

    wire [clogb2(SPIKE_MEM_DEPTH)-1:0] spike_rd_addr_16 = conv_enable ? spike_rd_addr : spike_rd_addr >> 2;

    wire [1:0] select_spike_out;

    assign select_spike_out = spike_rd_addr[1:0];

    reg [1:0] select_spike_out_d;
    reg [1:0] select_spike_out_dd;
    always @(posedge clk) begin
        if (rst) begin
            select_spike_out_d <= 0;
            select_spike_out_dd <= 0;
        end else begin
            select_spike_out_d <= select_spike_out;
            select_spike_out_dd <= select_spike_out_d;
        end
    end

    assign spike_mem_out_16 = layer_counter ? spike_mem_out_16_2 : spike_mem_out_16_1;

    assign spike_mem_out_4 = select_spike_out_dd == 2'b00 ? spike_mem_out_16[15:12] :
                              select_spike_out_dd == 2'b01 ? spike_mem_out_16[11:8] :
                              select_spike_out_dd == 2'b10 ? spike_mem_out_16[7:4] :
                              spike_mem_out_16[3:0]; //controlla questo


    wire [15:0] spike_mem_in;
    wire spike_wr_en;

    wire [SPIKE_MEM_WIDTH-1:0] spike_mem_out_16_1_bram, spike_mem_out_16_2_bram;
    reg  [SPIKE_MEM_WIDTH-1:0] spike_mem_out_16_1, spike_mem_out_16_2;

    spike_mem_buffer spike_buffer (
        .clk(clk),
        .rst(rst),
        .dense_enable(dense_enable || valid_encoding),
        .conv_enable(conv_enable && !valid_encoding),
        .s1(s1),
        .valid_s1(valid_s1),
        .s2(s2),
        .valid_s2(valid_s2),
        .SYNAPSES(SYNAPSES),
        .active_spike(active_spike),
        .next_dim_input_feature(next_dim_input_feature),
        .output_feature_finish(output_feature_finish),
        .last_layer(last_layer),
        .en_L2(en_L2),
        .spike_mem_in(spike_mem_in),
        .spike_wr_en(spike_wr_en),
        .spike_wr_addr(spike_wr_addr),
        .spike_written(spike_written),
        .spike_written_comb(spike_written_comb),
        .valid_active_group(valid_active_group)
    );

    wire [10:0] spike_wr_addr_shift = spike_wr_addr >> 2;

    SB_RAM40_4K spike_mem_1 (
        .RDATA(spike_mem_out_16_1_bram), 
        .RADDR(spike_rd_addr_16), 
        .RCLK(clk), 
        .RCLKE(1'b1),
        .RE(1'b1), 
        .WADDR(spike_wr_addr_shift), 
        .WCLK(clk), 
        .WCLKE(1'b1),
        .WDATA(spike_mem_in), 
        .WE(spike_wr_en && spike_wr_en_1_dd),
        .MASK (16'h0000)
    );

    SB_RAM40_4K spike_mem_2 (
        .RDATA(spike_mem_out_16_2_bram), 
        .RADDR(spike_rd_addr_16), 
        .RCLK(clk), 
        .RCLKE(1'b1),
        .RE(1'b1), 
        .WADDR(spike_wr_addr_shift), 
        .WCLK(clk), 
        .WCLKE(1'b1),
        .WDATA(spike_mem_in), 
        .WE(spike_wr_en && spike_wr_en_2_dd),
        .MASK (16'h0000)
    );

    always @(posedge clk) begin
        if (rst) begin
            spike_mem_out_16_1 <= 0;
            spike_mem_out_16_2 <= 0;
        end else begin
            spike_mem_out_16_1 <= spike_mem_out_16_1_bram;
            spike_mem_out_16_2 <= spike_mem_out_16_2_bram;
        end
    end

    //  The following function calculates the address width based on specified RAM depth
    function integer clogb2;
    input integer depth;
        for (clogb2=0; depth>0; clogb2=clogb2+1)
        depth = depth >> 1;
    endfunction   

endmodule