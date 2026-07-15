`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// weight_mem_ihp_1024x64
//
// Single 1024x64 IHP SRAM (RM_IHPSG13_1P_1024x64) that holds ALL four weight
// lanes packed one per 16-bit slice of each 64-bit row:
//
//     bits [15:0]  = L1   (core 1, weight_mem_1)
//     bits [31:16] = L2   (core 1, weight_mem_2)
//     bits [47:32] = L3   (core 2, weight_mem_1)
//     bits [63:48] = L4   (core 2, weight_mem_2)
//
// This replaces the four separate ram_1024x16 that used to live inside the two
// layer_lp cores. Since both cores read at the SAME address (weight_rd_addr_mux
// in snn_lp), all four lanes can share one physical row and one read port.
//
// READ  : single port, all four lanes at rd_addr. Latency is 2 clocks
//         (1 inside the macro + 1 output register here) to MATCH the old
//         ram_1024x16 (SB_RAM40_4K 1 clk + output-mux reg 1 clk). Do NOT drop
//         the output register: the weights must stay aligned with the spike /
//         conv pipeline or the inference result changes.
//
// WRITE : the SPI weight loader (servant_spi) writes one 16-bit lane at a time,
//         one bank after another, so at most one we_L* is active per cycle.
//         The active lane is written through the macro bit-mask A_BM
//         (polarity 1 = write) without touching the other three lanes -> no
//         read-modify-write.
//
// The macro is single-port (A_ADDR shared R/W). Weight loading (SPI) and
// inference (core reads) never overlap in time, so muxing the address is safe.
//////////////////////////////////////////////////////////////////////////////

module weight_mem_ihp_1024x64 #(
    parameter INIT_FILE = ""
)(
    input             clk,

    // read: all four lanes at the same address (2-clock latency)
    input      [9:0]  rd_addr,
    output     [15:0] weights_L1,
    output     [15:0] weights_L2,
    output     [15:0] weights_L3,
    output     [15:0] weights_L4,

    // write: four independent lane ports (SPI loader, one active at a time)
    input             we_L1, input [9:0] waddr_L1, input [15:0] wdata_L1,
    input             we_L2, input [9:0] waddr_L2, input [15:0] wdata_L2,
    input             we_L3, input [9:0] waddr_L3, input [15:0] wdata_L3,
    input             we_L4, input [9:0] waddr_L4, input [15:0] wdata_L4
);

    wire wr_any = we_L1 | we_L2 | we_L3 | we_L4;

    // Pick the active write lane: address, data on the right slice, and the
    // bit-mask that enables only that 16-bit lane (A_BM: 1 = write).
    reg [9:0]  wr_addr;
    reg [63:0] wr_din;
    reg [63:0] wr_bm;
    always @(*) begin
        wr_addr = 10'd0;
        wr_din  = 64'd0;
        wr_bm   = 64'd0;
        case (1'b1)
            we_L1: begin wr_addr = waddr_L1; wr_din = {48'd0, wdata_L1};       wr_bm = 64'h0000_0000_0000_FFFF; end
            we_L2: begin wr_addr = waddr_L2; wr_din = {32'd0, wdata_L2, 16'd0}; wr_bm = 64'h0000_0000_FFFF_0000; end
            we_L3: begin wr_addr = waddr_L3; wr_din = {16'd0, wdata_L3, 32'd0}; wr_bm = 64'h0000_FFFF_0000_0000; end
            we_L4: begin wr_addr = waddr_L4; wr_din = {wdata_L4, 48'd0};        wr_bm = 64'hFFFF_0000_0000_0000; end
            default: ; // no write
        endcase
    end

    // Single-port address: write address while loading, read address otherwise.
    wire [9:0]  a_addr = wr_any ? wr_addr : rd_addr;
    wire [63:0] a_dout;

    RM_IHPSG13_1P_1024x64_c2_bm_bist #(
        .INIT_FILE(INIT_FILE)
    ) u_ram (
        .A_CLK      (clk),
        .A_MEN      (1'b1),
        .A_WEN      (wr_any),
        .A_REN      (~wr_any),
        .A_ADDR     (a_addr),
        .A_DIN      (wr_din),
        .A_DLY      (1'b0),
        .A_DOUT     (a_dout),
        .A_BM       (wr_bm),
        // BIST unused
        .A_BIST_CLK (1'b0),
        .A_BIST_EN  (1'b0),
        .A_BIST_MEN (1'b0),
        .A_BIST_WEN (1'b0),
        .A_BIST_REN (1'b0),
        .A_BIST_ADDR(10'b0),
        .A_BIST_DIN (64'b0),
        .A_BIST_BM  (64'b0)
    );

    // Extra output register: macro read is 1 clk, this makes it 2 clks total,
    // matching the old ram_1024x16 read latency.
    reg [63:0] dout_q;
    always @(posedge clk)
        dout_q <= a_dout;

    assign weights_L1 = dout_q[15:0];
    assign weights_L2 = dout_q[31:16];
    assign weights_L3 = dout_q[47:32];
    assign weights_L4 = dout_q[63:48];

endmodule
