`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// ihp_ram_64x64 : single-port IHP SRAM wrapper (RM_IHPSG13_1P_64x64).
//
// 64x64 is the SMALLEST IHP SRAM macro available. This wrapper exposes only
// the DW bits actually used (default 16): it writes just the low DW bits via
// the macro bit-mask and reads back the low DW bits, leaving the rest of the
// physical 64x64 array untouched. Read latency = 1 clock (matches the
// BRAM_singlePort_readFirst LOW_LATENCY it replaces).
//
// SINGLE PORT: the address is the write address while writing (we=1), the read
// address otherwise. we=1 & re=1 on the SAME address does WRITE-THROUGH. Safe
// for buffers whose read/write never target different addresses in the same
// cycle (e.g. the SNN output buffer: writes always go to addr 0, the CPU reads
// only after the inference has finished).
//////////////////////////////////////////////////////////////////////////////

module ihp_ram_64x64 #(
    parameter DW = 16           // used data width (<= 64)
)(
    input             clk,

    // write port
    input             we,
    input      [5:0]  waddr,
    input      [DW-1:0] wdata,

    // read port (1-clock latency)
    input             re,
    input      [5:0]  raddr,
    output     [DW-1:0] rdata
);

    // single physical port: write address while writing, read address otherwise
    wire [5:0]  a_addr = we ? waddr : raddr;

    // pad the used bits up to the physical 64-bit word; write only those bits
    wire [63:0] din64  = {{(64-DW){1'b0}}, wdata};
    wire [63:0] bm64   = {{(64-DW){1'b0}}, {DW{1'b1}}};   // 1 = write (IHP polarity)
    wire [63:0] dout64;
    assign rdata = dout64[DW-1:0];

    RM_IHPSG13_1P_64x64_c2_bm_bist u_ram (
        .A_CLK      (clk),
        .A_MEN      (we | re),
        .A_WEN      (we),
        .A_REN      (re),
        .A_ADDR     (a_addr),
        .A_DIN      (din64),
        .A_DLY      (1'b0),
        .A_DOUT     (dout64),
        .A_BM       (bm64),
        // BIST unused
        .A_BIST_CLK (1'b0),
        .A_BIST_EN  (1'b0),
        .A_BIST_MEN (1'b0),
        .A_BIST_WEN (1'b0),
        .A_BIST_REN (1'b0),
        .A_BIST_ADDR(6'b0),
        .A_BIST_DIN (64'b0),
        .A_BIST_BM  (64'b0)
    );

endmodule
