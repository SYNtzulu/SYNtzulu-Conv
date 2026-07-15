`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// ihp_ram_1024x16 : single-port 16-bit IHP SRAM wrapper (RM_IHPSG13_1P_1024x16)
//
// Generic 1024x16 single-port SRAM with per-bit write mask. Read latency = 1
// clock (matches the iCE40 SB_RAM40_4K it can replace).
//
// SINGLE PORT: one address for read OR write. With we=1 & re=1 on the SAME
// address the macro does WRITE-THROUGH (rdata returns the just-written value,
// NOT the old one). It therefore CANNOT reproduce a 2-port read-before-write
// (e.g. the delta_modulator's delta_mem, which reads the old per-channel value
// while writing the new one in the same cycle). For that use two of these in
// ping-pong (read bank A / write bank B, swap per frame), or keep it in FF.
//
// Write mask (wbm): IHP polarity, 1 = write that bit, 0 = keep old. To write
// only the low byte (like SB_RAM40_4K MASK=16'hFF00) use wbm = 16'h00FF.
//////////////////////////////////////////////////////////////////////////////

module ihp_ram_1024x16 #(
    parameter INIT_FILE = ""
)(
    input             clk,

    // write port
    input             we,
    input      [9:0]  waddr,
    input      [15:0] wdata,
    input      [15:0] wbm,     // 1 = write bit, 0 = keep (IHP A_BM polarity)

    // read port (1-clock latency)
    input             re,
    input      [9:0]  raddr,
    output     [15:0] rdata
);

    // single physical port: address is the write address while writing,
    // the read address otherwise.
    wire [9:0] a_addr = we ? waddr : raddr;

    RM_IHPSG13_1P_1024x16_c2_bm_bist #(
        .INIT_FILE(INIT_FILE)
    ) u_ram (
        .A_CLK      (clk),
        .A_MEN      (we | re),
        .A_WEN      (we),
        .A_REN      (re),         // caller controls: re=1 & we=1 same addr -> write-through
        .A_ADDR     (a_addr),
        .A_DIN      (wdata),
        .A_DLY      (1'b0),
        .A_DOUT     (rdata),
        .A_BM       (wbm),
        // BIST unused
        .A_BIST_CLK (1'b0),
        .A_BIST_EN  (1'b0),
        .A_BIST_MEN (1'b0),
        .A_BIST_WEN (1'b0),
        .A_BIST_REN (1'b0),
        .A_BIST_ADDR(10'b0),
        .A_BIST_DIN (16'b0),
        .A_BIST_BM  (16'b0)
    );

endmodule
