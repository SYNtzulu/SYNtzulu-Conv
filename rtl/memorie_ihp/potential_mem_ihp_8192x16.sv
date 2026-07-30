`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// potential_mem_ihp_8192x16
//
// Drop-in replacement for IHP3_singlePort_readFirst as instantiated by
// bram_fifo: SAME port list, SAME 1-clock read latency (LOW_LATENCY). Built out
// of DUAL-PORT macros whose row is exactly one word wide, which is where both
// the correctness fix and the power saving come from.
//
//     8192 words x 16 bit  ->  8 x RM_IHPSG13_2P_1024x16_c2_bm_bist
//     (1024 rows of 16 bit per macro, 8 macros = 8192 words, 1:1, no packing)
//
// WHAT CHANGES vs IHP3_singlePort_readFirst
//
//   1. NO MORE LOST READS. The old wrapper drove one single-port macro per bank:
//      when a write and a read hit the same bank in the same cycle the write won
//      and THE READ WAS SILENTLY DROPPED (its $display fired, nothing else). In
//      bram_fifo rd_cnt and wr_cnt are independent counters and rden/wren are
//      independent, so that case is reachable. Here port A is the write port and
//      port B the read port of the same macro: both always complete. On the same
//      address the macro's behavioural core writes non-blocking, so port B
//      returns the OLD value -> read-first, which is what bram_fifo expects.
//
//   2. FULL DEPTH. The old wrapper was 6 banks x 256 rows x 4 lanes = 6144 words
//      while RAM_DEPTH came in as 8192 (DEPTH_FIFO in snn_lp) and bram_fifo's
//      wr_cnt counts to DEPTH-1 = 8191. Above 6143 wrow overflowed ROWW=8 bits
//      and aliased back onto low rows, silently. 8 x 1024 = 8192 exactly.
//
//   3. HALF THE ENERGY PER ACCESS. This is why the row is 16 bit and not wider.
//      From the typ 1p20V 25C liberty, pJ per clock edge:
//
//                              read     write    area        n   area/layer
//        1P_256x64  (before)   49.63    63.44     93 180 um2  6   0.559 mm2
//        2P_1024x32            48.27    58.92    264 167 um2  4   1.057 mm2
//        2P_1024x16  (here)    26.49    32.92    155 154 um2  8   1.241 mm2
//
//      A 64-bit or 32-bit row costs the same whether you use all of it or 16
//      bits of it, so packing several words per row buys area and pays for it in
//      energy on EVERY access. At 24 MHz (clk_period 41.667 in constraint_soc)
//      with a read and a write per cycle over the two layer_lp that is 2.85 mW
//      here against 5.43 mW before. The 2P_1024x32 would have doubled the area
//      for no energy gain at all.
//
//      The price is +0.18 mm2 per layer against the 32-bit option and 8 macros
//      to place instead of 4.
//
// ADDRESS DECODE - pure bit slicing, no dividers, no lanes
//   addr[9:0]   row   (0..1023 inside the macro)
//   addr[12:10] macro (0..7)
//   The old wrapper used % and / by 6, which is a real divider in silicon. With
//   powers of two everywhere this is wiring. Putting the macro select on the TOP
//   bits also means a sequential sweep stays inside one macro for 1024 accesses
//   with the other seven at MEN=0 - and MEN=0 costs 0 pJ in the liberty - instead
//   of hopping across all of them every cycle as the interleaved decode did.
//
// Writes are full-word, so A_BM is all ones and there is no read-modify-write
// and no lane mask. No INIT_FILE: the 2P behavioural model has no such parameter
// (the old wrapper did not connect it either).
//////////////////////////////////////////////////////////////////////////////

module potential_mem_ihp_8192x16 #(
  parameter RAM_WIDTH       = 16,                 // must be 16 (macro row width)
  parameter RAM_DEPTH       = 8192,               // total words
  parameter RAM_PERFORMANCE = "LOW_LATENCY",      // "HIGH_PERFORMANCE" or "LOW_LATENCY"
  parameter INIT_FILE       = ""                  // unused, see note above
)
(
  input  [clogb2(RAM_DEPTH-1)-1:0] addra,  // write address (port A)
  input  [clogb2(RAM_DEPTH-1)-1:0] addrb,  // read address  (port B)
  input  [RAM_WIDTH-1:0]           dina,   // input data
  input                            clk,
  input                            wea,    // write enable
  input                            ena,    // port A enable (write)
  input                            enb,    // port B enable (read)
  input                            rst,    // output register reset
  input                            regceb, // output register enable
  output [RAM_WIDTH-1:0]           doutb
);

  localparam MACRO_ROWS = 1024;                   // words in one macro
  localparam N_MACRO    = RAM_DEPTH / MACRO_ROWS; // macros needed (=8)

  localparam ROWW   = clogb2(MACRO_ROWS-1);       // =10
  localparam MACROW = clogb2(N_MACRO-1);          // =3
  localparam ADDRW  = clogb2(RAM_DEPTH-1);        // =13

  // ---------------------------------------------------------------------------
  // Address split (see the header): row on the low bits, macro on the high ones
  // ---------------------------------------------------------------------------
  wire [ROWW-1:0]   wrow   = addra[ROWW-1:0];
  wire [MACROW-1:0] wmacro = addra[ADDRW-1 -: MACROW];

  wire [ROWW-1:0]   rrow   = addrb[ROWW-1:0];
  wire [MACROW-1:0] rmacro = addrb[ADDRW-1 -: MACROW];

  wire wr_user = ena & wea;

  // ---------------------------------------------------------------------------
  // The macro array. Only the addressed macro sees MEN=1 on either port; the
  // others burn 0 pJ on that edge.
  // ---------------------------------------------------------------------------
  wire [RAM_WIDTH-1:0] b_dout [0:N_MACRO-1];

  genvar i;
  generate
    for (i = 0; i < N_MACRO; i = i + 1) begin : mac

      wire wr_i = wr_user & (wmacro == i);   // write goes to this macro
      wire rd_i = enb     & (rmacro == i);   // read  goes to this macro

      RM_IHPSG13_2P_1024x16_c2_bm_bist u_ram (
        // port A - write
        .A_CLK      (clk),
        .A_MEN      (wr_i),
        .A_WEN      (wr_i),
        .A_REN      (1'b0),
        .A_ADDR     (wrow),
        .A_DIN      (dina),
        .A_DLY      (1'b0),
        .A_DOUT     (),                       // write port, output unused
        .A_BM       ({RAM_WIDTH{1'b1}}),      // 1 = write, whole word
        .A_BIST_CLK (1'b0),
        .A_BIST_EN  (1'b0),
        .A_BIST_MEN (1'b0),
        .A_BIST_WEN (1'b0),
        .A_BIST_REN (1'b0),
        .A_BIST_ADDR({ROWW{1'b0}}),
        .A_BIST_DIN ({RAM_WIDTH{1'b0}}),
        .A_BIST_BM  ({RAM_WIDTH{1'b0}}),
        // port B - read
        .B_CLK      (clk),
        .B_MEN      (rd_i),
        .B_WEN      (1'b0),
        .B_REN      (rd_i),
        .B_ADDR     (rrow),
        .B_DIN      ({RAM_WIDTH{1'b0}}),
        .B_DLY      (1'b0),
        .B_DOUT     (b_dout[i]),
        .B_BM       ({RAM_WIDTH{1'b0}}),
        .B_BIST_CLK (1'b0),
        .B_BIST_EN  (1'b0),
        .B_BIST_MEN (1'b0),
        .B_BIST_WEN (1'b0),
        .B_BIST_REN (1'b0),
        .B_BIST_ADDR({ROWW{1'b0}}),
        .B_BIST_DIN ({RAM_WIDTH{1'b0}}),
        .B_BIST_BM  ({RAM_WIDTH{1'b0}})
      );
    end
  endgenerate

  // ---------------------------------------------------------------------------
  // Output select: B_DOUT is valid one clock after the read, so the macro number
  // has to be delayed by one clock too, updated with enb - exactly what
  // IHP3_singlePort_readFirst did with rbank_d.
  // ---------------------------------------------------------------------------
  reg [MACROW-1:0] rmacro_d;
  always @(posedge clk)
    if (enb)
      rmacro_d <= rmacro;

  wire [RAM_WIDTH-1:0] ram_data_b = b_dout[rmacro_d];

  generate
    if (RAM_PERFORMANCE == "LOW_LATENCY") begin: no_output_register

      // 1 clock read latency
      assign doutb = ram_data_b;

    end else begin: output_register

      // 2 clock read latency
      reg [RAM_WIDTH-1:0] doutb_reg = {RAM_WIDTH{1'b0}};

      always @(posedge clk or posedge rst)
        if (rst)
          doutb_reg <= {RAM_WIDTH{1'b0}};
        else if (regceb)
          doutb_reg <= ram_data_b;

      assign doutb = doutb_reg;

    end
  endgenerate

  // synthesis translate_off
  initial begin
    if (RAM_WIDTH != 16)
      $display("ERROR potential_mem_ihp_8192x16: RAM_WIDTH=%0d, the macro row is 16 bit", RAM_WIDTH);
    if (N_MACRO * MACRO_ROWS != RAM_DEPTH)
      $display("ERROR potential_mem_ihp_8192x16: RAM_DEPTH=%0d is not a multiple of %0d words per macro", RAM_DEPTH, MACRO_ROWS);
    if (ADDRW != ROWW + MACROW)
      $display("ERROR potential_mem_ihp_8192x16: address split %0d+%0d does not cover %0d bits", ROWW, MACROW, ADDRW);
    if (INIT_FILE != "")
      $display("ERROR potential_mem_ihp_8192x16: INIT_FILE=\"%0s\" is not supported, the 2P behavioural model has no INIT_FILE parameter", INIT_FILE);
  end
  // synthesis translate_on

  //  Address width from the RAM depth
  function integer clogb2;
    input integer depth;
      for (clogb2=0; depth>0; clogb2=clogb2+1)
        depth = depth >> 1;
  endfunction

endmodule
