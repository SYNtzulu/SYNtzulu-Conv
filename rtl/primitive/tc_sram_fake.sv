`timescale 1ns / 1ps
//
// tc_sram_fake.sv
//
// *iverilog-compatible* SRAM model with the SAME interface (parameters and
// ports) as the PULP/ETH tc_sram and the SAME observable behavior:
//   - registered read latency (Latency parameter),
//   - byte-enable write,
//   - output stable during writes (reads the "held" address),
//   - simulation initialization (SimInit).
//
// It serves ONLY to simulate here (iverilog). On the other system / in synthesis
// the real tc_sram is used without modifying weight_memory_sram.
//
// Differences from the real tc_sram: no SVA assertions and no
// configuration $display (not supported/needed in this flow). The
// body avoids packed-per-port arrays indexed by loop variables
// (not elaborable by iverilog) by using a generate-for with genvar.

module tc_sram_fake #(
  parameter int unsigned NumWords     = 32'd1024, // Number of Words in data array
  parameter int unsigned DataWidth    = 32'd128,  // Data signal width
  parameter int unsigned ByteWidth    = 32'd8,    // Width of a data byte
  parameter int unsigned NumPorts     = 32'd2,    // Number of read and write ports
  parameter int unsigned Latency      = 32'd1,    // Latency when the read data is available
  parameter              SimInit      = "none",   // Simulation initialization
  parameter bit          PrintSimCfg  = 1'b0,     // Print configuration
  parameter              ImplKey      = "none",   // Reference to specific implementation
  // DEPENDENT PARAMETERS, DO NOT OVERWRITE!
  parameter int unsigned AddrWidth = (NumWords > 32'd1) ? $clog2(NumWords) : 32'd1,
  parameter int unsigned BeWidth   = (DataWidth + ByteWidth - 32'd1) / ByteWidth, // ceil_div
  parameter type         addr_t    = logic [AddrWidth-1:0],
  parameter type         data_t    = logic [DataWidth-1:0],
  parameter type         be_t      = logic [BeWidth-1:0]
) (
  input  logic                 clk_i,      // Clock
  input  logic                 rst_ni,     // Asynchronous reset active low
  // input ports
  input  logic  [NumPorts-1:0] req_i,      // request
  input  logic  [NumPorts-1:0] we_i,       // write enable
  input  addr_t [NumPorts-1:0] addr_i,     // request address
  input  data_t [NumPorts-1:0] wdata_i,    // write data
  input  be_t   [NumPorts-1:0] be_i,       // write byte enable
  // output ports
  output data_t [NumPorts-1:0] rdata_o     // read data
);

  // memory array shared among the ports
  data_t sram [NumWords-1:0];

  // simulation initialization (like the real tc_sram)
  initial begin : proc_sram_init
    integer w;
    if (SimInit != "none") begin
      for (w = 0; w < NumWords; w = w + 1) begin
        case (SimInit)
          "zeros":  sram[w] = {DataWidth{1'b0}};
          "ones":   sram[w] = {DataWidth{1'b1}};
          "random": sram[w] = {DataWidth{$random}};
          default:  sram[w] = {DataWidth{1'bx}};
        endcase
      end
    end
  end

  genvar p;
  generate
    for (p = 0; p < NumPorts; p = p + 1) begin : gen_port

      // "held" read address for the cycles without a read request
      reg [AddrWidth-1:0] r_addr_q;
      integer j;

      // write (byte-enable) and update of the held address.
      // p is a genvar (constant) so addr_i[p] is a constant-index
      // select: no packed accesses with a loop index (iverilog-friendly).
      always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
          r_addr_q <= {AddrWidth{1'b0}};
        end else if (req_i[p]) begin
          if (we_i[p]) begin
            for (j = 0; j < BeWidth; j = j + 1)
              if (be_i[p][j])
                sram[addr_i[p]][j*ByteWidth +: ByteWidth] <= wdata_i[p][j*ByteWidth +: ByteWidth];
          end else begin
            // no write -> update the held read address
            r_addr_q <= addr_i[p];
          end
        end
      end

      // read pipeline: Latency registered stages. On a write the output
      // remains stable (reads r_addr_q, not the write address).
      if (Latency == 0) begin : gen_comb_out
        // combinational read (latency 0)
        assign rdata_o[p] = (req_i[p] && !we_i[p]) ? sram[addr_i[p]] : sram[r_addr_q];
      end else begin : gen_reg_out
        reg [DataWidth-1:0] rdata_pipe [0:Latency-1];
        integer k;
        always @(posedge clk_i or negedge rst_ni) begin
          if (!rst_ni) begin
            for (k = 0; k < Latency; k = k + 1)
              rdata_pipe[k] <= {DataWidth{1'b0}};
          end else begin
            // shift toward the output (stage 0)
            for (k = 0; k < Latency-1; k = k + 1)
              rdata_pipe[k] <= rdata_pipe[k+1];
            // deepest stage = read data (stable during the write)
            if (req_i[p] && !we_i[p])
              rdata_pipe[Latency-1] <= sram[addr_i[p]];
            else
              rdata_pipe[Latency-1] <= sram[r_addr_q];
          end
        end
        assign rdata_o[p] = rdata_pipe[0];
      end

    end
  endgenerate

endmodule
