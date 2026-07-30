`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// spike_mem_ihp_512x16
//
// Drop-in replacement for BRAM_banked_singlePort_readFirst as instantiated by
// spike_mem_2: SAME port list, SAME 1-clock read latency (LOW_LATENCY), SAME
// read-first behaviour. The storage is ONE dual-port IHP macro instead of 8192
// flops.
//
//     512 words x 16 bit  ->  RM_IHPSG13_2P_512x16_c2_bm_bist, 1:1, no banking
//     (A_ADDR is [8:0] and addra/addrb are 9 bits: exact fit, no wrapper maths)
//
// WHY THE MACRO
//   As flops the spike mem is 8192 sg13g2_dfrbp_1 = 386 480 um2, which is 64 %
//   of the 12860 reset flops in the whole soc netlist. The macro is 402.61 x
//   219.77 = 88 481 um2, and it takes 8192 leaves off the clock tree.
//
// PORT SPLIT
//   port A = write (ena & wea), port B = read (enb). They are independent, so
//   unlike the single-port wrappers there is no write-wins-read collision: a
//   write and a read in the same cycle both go through. On the SAME address the
//   macro's behavioural core writes with a non-blocking assignment, so port B
//   returns the OLD value -> read-first, same as the flop array.
//
// THE CLEAR FSM (this is the part that does not come for free)
//   BRAM_banked had RESET_MEM=1: rst zeroed the whole array. An SRAM has no such
//   thing, and the spike mem DOES depend on powering up cleared - it is read
//   back on locations it never wrote (padding rows, partially filled words) and
//   with random content the EMG run dies after ~3k samples instead of 50k.
//
//   So after rst this wrapper walks addresses 0..511 on port A writing zeros
//   (full A_BM), 512 clocks, then releases the port. While clearing:
//     - port B is held idle and doutb is forced to 0. That is not a workaround,
//       it is the correct value: 0 is exactly what those locations are becoming.
//       So READS DURING THE CLEAR NEED NO GATING from the rest of the design.
//     - a user WRITE arriving during the clear would be dropped. It should never
//       happen (the SERV core boots from flash for thousands of cycles before
//       the accelerator is enabled), and a simulation $display fires if it does,
//       so the assumption is checked instead of assumed.
//   mem_ready is exported anyway, for whoever wants to gate on it explicitly.
//
// The unused parameters (INIT_FILE, N_BANK, RESET_MEM) are kept so the
// instantiation in spike_mem_2 stays a literal one-line swap; see the checks at
// the bottom of the file.
//////////////////////////////////////////////////////////////////////////////

module spike_mem_ihp_512x16 #(
  parameter RAM_WIDTH       = 16,                 // must be 16 (macro width)
  parameter RAM_DEPTH       = 512,                // must be 512 (macro depth)
  parameter RAM_PERFORMANCE = "LOW_LATENCY",      // "HIGH_PERFORMANCE" or "LOW_LATENCY"
  parameter INIT_FILE       = "",                 // unused, see note above
  parameter N_BANK          = 1,                  // unused, the macro is one block
  parameter RESET_MEM       = 1                   // unused, the clear FSM is always on
)
(
  input  [clogb2(RAM_DEPTH-1)-1:0] addra,  // Port A address bus (write)
  input  [clogb2(RAM_DEPTH-1)-1:0] addrb,  // Port B address bus (read)
  input  [RAM_WIDTH-1:0]           dina,   // Port A input data
  input                            clk,    // Clock
  input                            wea,    // Port A write enable
  input                            ena,    // Port A enable
  input                            enb,    // Port B enable
  input                            rst,    // starts the clear, resets the output
  input                            regceb, // Port B output register enable

  output [RAM_WIDTH-1:0]           doutb,  // Port B output data
  output                           mem_ready // 0 while the array is being cleared
);

  localparam ADDRW = clogb2(RAM_DEPTH-1);   // = 9

  // ---------------------------------------------------------------------------
  // Clear FSM: counts 0..511 then parks. The extra top bit IS the done flag, so
  // there is no separate state register and no comparator against 511.
  // ---------------------------------------------------------------------------
  reg [ADDRW:0] clr_cnt;                    // 10 bits: [8:0] address, [9] done
  wire clearing = ~clr_cnt[ADDRW];

  always @(posedge clk or posedge rst)
    if (rst)
      clr_cnt <= {(ADDRW+1){1'b0}};
    else if (clearing)
      clr_cnt <= clr_cnt + 1'b1;

  assign mem_ready = ~clearing;

  // ---------------------------------------------------------------------------
  // Port A: the clear owns it until done, then it is the user write port
  // ---------------------------------------------------------------------------
  wire                  wr_user = ena & wea;

  wire                  a_men  = clearing ? 1'b1              : wr_user;
  wire                  a_wen  = clearing ? 1'b1              : wr_user;
  wire [ADDRW-1:0]      a_addr = clearing ? clr_cnt[ADDRW-1:0] : addra;
  wire [RAM_WIDTH-1:0]  a_din  = clearing ? {RAM_WIDTH{1'b0}} : dina;

  // synthesis translate_off
  always @(posedge clk)
    if (!rst && clearing && wr_user)
      $display("[%0t] WARNING spike_mem_ihp_512x16: write to addr=%0d during the power-up clear -> DROPPED",
               $time, addra);
  // synthesis translate_on

  // ---------------------------------------------------------------------------
  // Port B: read only, idle while clearing
  // ---------------------------------------------------------------------------
  wire b_men = enb & ~clearing;

  wire [RAM_WIDTH-1:0] b_dout;

  RM_IHPSG13_2P_512x16_c2_bm_bist u_ram (
    // port A - write
    .A_CLK      (clk),
    .A_MEN      (a_men),
    .A_WEN      (a_wen),
    .A_REN      (1'b0),
    .A_ADDR     (a_addr),
    .A_DIN      (a_din),
    .A_DLY      (1'b0),
    .A_DOUT     (),                       // write port, output unused
    .A_BM       ({RAM_WIDTH{1'b1}}),      // 1 = write, whole word
    .A_BIST_CLK (1'b0),
    .A_BIST_EN  (1'b0),
    .A_BIST_MEN (1'b0),
    .A_BIST_WEN (1'b0),
    .A_BIST_REN (1'b0),
    .A_BIST_ADDR({ADDRW{1'b0}}),
    .A_BIST_DIN ({RAM_WIDTH{1'b0}}),
    .A_BIST_BM  ({RAM_WIDTH{1'b0}}),
    // port B - read
    .B_CLK      (clk),
    .B_MEN      (b_men),
    .B_WEN      (1'b0),
    .B_REN      (b_men),
    .B_ADDR     (addrb),
    .B_DIN      ({RAM_WIDTH{1'b0}}),
    .B_DLY      (1'b0),
    .B_DOUT     (b_dout),
    .B_BM       ({RAM_WIDTH{1'b0}}),
    .B_BIST_CLK (1'b0),
    .B_BIST_EN  (1'b0),
    .B_BIST_MEN (1'b0),
    .B_BIST_WEN (1'b0),
    .B_BIST_REN (1'b0),
    .B_BIST_ADDR({ADDRW{1'b0}}),
    .B_BIST_DIN ({RAM_WIDTH{1'b0}}),
    .B_BIST_BM  ({RAM_WIDTH{1'b0}})
  );

  // ---------------------------------------------------------------------------
  // Output: B_DOUT is not resettable, so reproduce what the flop array did -
  // 0 out of reset, 0 during the clear, macro data from the first real read on.
  // ---------------------------------------------------------------------------
  reg dout_valid;
  always @(posedge clk or posedge rst)
    if (rst)
      dout_valid <= 1'b0;
    else if (enb & ~clearing)
      dout_valid <= 1'b1;

  wire [RAM_WIDTH-1:0] ram_data_b = dout_valid ? b_dout : {RAM_WIDTH{1'b0}};

  generate
    if (RAM_PERFORMANCE == "LOW_LATENCY") begin: no_output_register

      // 1 clock read latency, same as the flop array in LOW_LATENCY
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
      $display("ERROR spike_mem_ihp_512x16: RAM_WIDTH=%0d, the macro is 16 bit", RAM_WIDTH);
    if (RAM_DEPTH != 512)
      $display("ERROR spike_mem_ihp_512x16: RAM_DEPTH=%0d, the macro is 512 words", RAM_DEPTH);
    if (INIT_FILE != "")
      $display("ERROR spike_mem_ihp_512x16: INIT_FILE=\"%0s\" is not supported, the 2P behavioural model has no INIT_FILE parameter", INIT_FILE);
  end
  // synthesis translate_on

  //  Address width from the RAM depth
  function integer clogb2;
    input integer depth;
      for (clogb2=0; depth>0; clogb2=clogb2+1)
        depth = depth >> 1;
  endfunction

endmodule
