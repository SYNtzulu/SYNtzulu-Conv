`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: BRAM_banked_singlePort_readFirst
//
// Drop-in replacement for BRAM_singlePort_readFirst: SAME port list, SAME read
// latency (LOW_LATENCY = 1 clock, HIGH_PERFORMANCE = 2 clocks), SAME read-first
// behaviour on a write/read collision. The only difference is internal: instead
// of ONE array of RAM_DEPTH x RAM_WIDTH words, the storage is split into N_BANK
// arrays of (RAM_DEPTH/N_BANK) x RAM_WIDTH words.
//
// N_BANK = 1 reproduces the flat array exactly, so the parameter can be swept
// (1, 2, 4, 8, ...) without touching anything else.
//
// WHY BANK IT
//   On the ASIC these memories are not macros, they are inferred flops (the
//   spike mem alone is 512x16 = 8192 FF). A single flat array gives the
//   synthesizer one RAM_DEPTH:1 read mux and one RAM_DEPTH-way write decoder in
//   a single cone. Splitting it:
//     - shortens the read path: a (RAM_DEPTH/N_BANK):1 mux feeds the bank
//       output register, and only a small N_BANK:1 mux sits after it;
//     - cuts read power: only the addressed bank's output register is enabled,
//       the other N_BANK-1 banks hold their value (one clock gate per bank);
//     - gives synthesis/placement N_BANK independent blocks instead of one
//       monolithic cone.
//
// BANK SELECT = HIGH ADDRESS BITS (block partitioning, NOT interleaving)
//     bank = addr[ADDRW-1 -: BANKW]      word = addr[WORDW-1:0]
//   Deliberate: in spike_mem_2 the MSB of both addresses is the layer ping-pong
//   bit (write half = !lsb_layer_counter, read half = lsb_layer_counter), so
//   with high-order banking write and read ALWAYS fall in different banks. No
//   bank ever sees a read and a write in the same cycle, which keeps the door
//   open to mapping the banks onto single-port SRAM macros later on.
//   (Functionally the banks are dual-port here - they are flops - so the
//   read-first semantics hold in every case anyway.)
//
// RESET_MEM: the flat BRAM only looks initialized because of the `initial`
// block that zeroes its array - simulation only, it does not exist in silicon.
// The spike memory DOES depend on that zero: reading it back with an X/random
// power-up content breaks the inference (the EMG run stops after ~3k valid
// samples instead of 50k). RESET_MEM=1 clears the array from rst, which is what
// the hardware needs. It costs no extra cells: the array already maps onto
// sg13g2_dfrbp flops whose RESET_B pin was simply tied high.
//
// CONSTRAINTS: RAM_DEPTH and N_BANK must be powers of two and RAM_DEPTH must be
// a multiple of N_BANK (checked in simulation).
//////////////////////////////////////////////////////////////////////////////////

module BRAM_banked_singlePort_readFirst #(
  parameter RAM_WIDTH       = 16,                 // Specify RAM data width
  parameter RAM_DEPTH       = 512,                // Specify RAM depth (number of entries)
  parameter RAM_PERFORMANCE = "HIGH_PERFORMANCE", // Select "HIGH_PERFORMANCE" or "LOW_LATENCY"
  parameter INIT_FILE       = "",                 // RAM initialization file (leave blank if not used)
  parameter N_BANK          = 4,                  // Number of banks (power of two, 1 = flat array)
  // 1 = the whole array is cleared by rst. Needed when the design reads
  // locations it never wrote (see the note at the bottom of the file);
  // 0 = array left untouched by rst, bit-exact with BRAM_singlePort_readFirst.
  parameter RESET_MEM       = 0
)
(
  input  [clogb2(RAM_DEPTH-1)-1:0] addra,  // Port A address bus, width determined from RAM_DEPTH
  input  [clogb2(RAM_DEPTH-1)-1:0] addrb,  // Port B address bus, width determined from RAM_DEPTH
  input  [RAM_WIDTH-1:0]           dina,   // Port A RAM input data
  input                            clk,    // Clock
  input                            wea,    // Port A write enable
  input                            ena,    // Port A RAM Enable
  input                            enb,    // Port B RAM Enable
  input                            rst,    // Port B output reset (does not affect memory contents)
  input                            regceb, // Port B output register enable

  output [RAM_WIDTH-1:0]           doutb   // Port B RAM output data
);

  localparam BANK_DEPTH = RAM_DEPTH / N_BANK;        // words per bank
  localparam ADDRW      = clogb2(RAM_DEPTH-1);       // full address width
  localparam WORDW      = clogb2(BANK_DEPTH-1);      // address bits inside a bank
  // with N_BANK=1 there is no bank field: keep the vector 1 bit wide (tied to 0)
  localparam BANKW      = (N_BANK == 1) ? 1 : (ADDRW - WORDW);

  // ---------------------------------------------------------------------------
  // Address split: high bits pick the bank, low bits pick the word inside it
  // ---------------------------------------------------------------------------
  wire [BANKW-1:0] wbank = (N_BANK == 1) ? {BANKW{1'b0}} : addra[ADDRW-1 -: BANKW];
  wire [BANKW-1:0] rbank = (N_BANK == 1) ? {BANKW{1'b0}} : addrb[ADDRW-1 -: BANKW];
  wire [WORDW-1:0] wword = addra[WORDW-1:0];
  wire [WORDW-1:0] rword = addrb[WORDW-1:0];

  // synthesis translate_off
  initial begin
    if (BANK_DEPTH * N_BANK != RAM_DEPTH)
      $display("ERROR BRAM_banked_singlePort_readFirst: RAM_DEPTH=%0d is not a multiple of N_BANK=%0d", RAM_DEPTH, N_BANK);
    if (N_BANK != 1 && (ADDRW != WORDW + BANKW))
      $display("ERROR BRAM_banked_singlePort_readFirst: RAM_DEPTH=%0d / N_BANK=%0d are not powers of two", RAM_DEPTH, N_BANK);
  end
  // synthesis translate_on

  // one 16-bit read register per bank, packed in a flat bus so it can be
  // indexed by the (registered) bank number
  wire [N_BANK*RAM_WIDTH-1:0] bank_dout;

  genvar i;
  generate
    for (i = 0; i < N_BANK; i = i + 1) begin : bank

      reg [RAM_WIDTH-1:0] ram [BANK_DEPTH-1:0];

      // this bank is the one addressed by port A / port B
      wire sel_wr = (N_BANK == 1) ? 1'b1 : (wbank == i);
      wire sel_rd = (N_BANK == 1) ? 1'b1 : (rbank == i);

      // The following code either initializes the memory values to a specified file or to all zeros to match hardware
      if (INIT_FILE != "") begin: use_init_file
        // the file describes the whole memory: this bank keeps its own slice
        reg [RAM_WIDTH-1:0] init_mem [RAM_DEPTH-1:0];
        integer ram_index;
        initial begin
          $readmemh(INIT_FILE, init_mem, 0, RAM_DEPTH-1);
          for (ram_index = 0; ram_index < BANK_DEPTH; ram_index = ram_index + 1)
            ram[ram_index] = init_mem[i*BANK_DEPTH + ram_index];
        end
      end else begin: init_bram_to_zero
        integer ram_index;
        initial
          for (ram_index = 0; ram_index < BANK_DEPTH; ram_index = ram_index + 1)
            ram[ram_index] = {RAM_WIDTH{1'b0}};
      end

      // write port: only the addressed bank sees the write enable
      if (RESET_MEM) begin: mem_with_reset
        integer wr_index;
        always @(posedge clk or posedge rst)
          if (rst)
            for (wr_index = 0; wr_index < BANK_DEPTH; wr_index = wr_index + 1)
              ram[wr_index] <= {RAM_WIDTH{1'b0}};
          else if (ena && wea && sel_wr)
            ram[wword] <= dina;
      end else begin: mem_no_reset
        always @(posedge clk)
          if (ena && wea && sel_wr)
            ram[wword] <= dina;
      end

      // read port: same read-first behaviour as the flat array (the write above
      // is non-blocking, so a same-address access returns the OLD value).
      // Non-addressed banks hold -> the register acts as a clock-gate enable.
      reg [RAM_WIDTH-1:0] ram_data_bank;
      always @(posedge clk or posedge rst)
        if (rst)
          ram_data_bank <= {RAM_WIDTH{1'b0}};
        else if (enb && sel_rd)
          ram_data_bank <= ram[rword];

      assign bank_dout[i*RAM_WIDTH +: RAM_WIDTH] = ram_data_bank;
    end
  endgenerate

  // the bank number must be delayed by one clock to match its own read register
  reg [BANKW-1:0] rbank_d;
  always @(posedge clk or posedge rst)
    if (rst)
      rbank_d <= {BANKW{1'b0}};
    else if (enb)
      rbank_d <= rbank;

  wire [RAM_WIDTH-1:0] ram_data_b = bank_dout[rbank_d*RAM_WIDTH +: RAM_WIDTH];

  //  The following code generates HIGH_PERFORMANCE (use output register) or LOW_LATENCY (no output register)
  generate
    if (RAM_PERFORMANCE == "LOW_LATENCY") begin: no_output_register

      // The following is a 1 clock cycle read latency at the cost of a longer clock-to-out timing
      assign doutb = ram_data_b;

    end else begin: output_register

      // The following is a 2 clock cycle read latency with improve clock-to-out timing
      reg [RAM_WIDTH-1:0] doutb_reg = {RAM_WIDTH{1'b0}};

      always @(posedge clk or posedge rst)
        if (rst)
          doutb_reg <= {RAM_WIDTH{1'b0}};
        else if (regceb)
          doutb_reg <= ram_data_b;

      assign doutb = doutb_reg;

    end
  endgenerate

  //  The following function calculates the address width based on specified RAM depth
  function integer clogb2;
    input integer depth;
      for (clogb2=0; depth>0; clogb2=clogb2+1)
        depth = depth >> 1;
  endfunction

endmodule
