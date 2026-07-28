`default_nettype none
//////////////////////////////////////////////////////////////////////////////
// servant_slow_timer : single-clock-domain slow timer for ASIC / IHP130.
//
// The old design clocked mtime/o_irq on a separate slow oscillator (s_clk) and
// (ab)used "posedge wr_en" as an async clock. Both are gone. Now everything
// runs on i_clk (the always-on system clock) and advances one step per
// slow_tick enable pulse produced by clk_gen_wb's prescaler. This keeps the
// timer alive during SERV sleep so it can still raise the wake interrupt.
//////////////////////////////////////////////////////////////////////////////
module servant_slow_timer
  #(parameter WIDTH = 16,
    parameter RESET_STRATEGY = "",
    parameter DIVIDER = 0)
  (input wire        i_clk,
   input wire        slow_tick,   // single-cycle enable (was slow_clk edge)
   input wire        i_rst,
   output reg        o_irq,
   input wire [31:0] i_wb_dat,
   input wire        i_wb_we,
   input wire        i_wb_cyc,
   output reg [31:0] o_wb_rdt);

    localparam HIGH = WIDTH-1-DIVIDER;

    reg [WIDTH-1:0]   mtime;
    reg [HIGH:0]      mtimecmp;

    wire [HIGH:0]     mtimeslice = mtime[WIDTH-1:DIVIDER];

    always @(mtimeslice) begin
        o_wb_rdt = 32'd0;
        o_wb_rdt[HIGH:0] = mtimeslice;
    end

    wire wr_en = i_wb_cyc & i_wb_we;

    // Asynchronous reset (assert async / release sync) for the ASIC.
    // With RESET_STRATEGY == "NONE" rst_a is a constant 0 and the blocks fold
    // back into plain flops.
    wire rst_a = i_rst & (RESET_STRATEGY != "NONE");

    // Compare register (written by the CPU over Wishbone)
    always @(posedge i_clk or posedge rst_a) begin
        if (rst_a)
            mtimecmp <= 0;
        else if (wr_en)
            mtimecmp <= i_wb_dat[HIGH:0];
    end

    // mtime counter : one step per slow_tick
    always @(posedge i_clk or posedge rst_a) begin
        if (rst_a)
            mtime <= 0;
        else if (wr_en)
            mtime <= 0;
        else if (slow_tick) begin
            if (mtimeslice <= mtimecmp)
                mtime <= mtime + 'd1;
            else
                mtime <= 0;
        end
    end

    // Interrupt : re-evaluated at the slow rate
    always @(posedge i_clk or posedge rst_a) begin
        if (rst_a)
            o_irq <= 1'b0;
        else if (wr_en)
            o_irq <= 1'b0;
        else if (slow_tick)
            o_irq <= (mtimeslice >= mtimecmp);
    end

endmodule
