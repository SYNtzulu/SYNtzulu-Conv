`default_nettype none
//////////////////////////////////////////////////////////////////////////////
// clk_gen_wb : ASIC / IHP130 clock & reset generation
//
// Clock and reset now come from EXTERNAL pads (i_clk, i_rst). The iCE40
// oscillator hard macros (SB_HFOSC / SB_LFOSC) are gone.
//
//   i_clk        : free-running system clock (always on). The reset
//                  synchronizer, the wake path, the clkgen WB register and the
//                  slow-tick prescaler all run on it.
//   o_clk        : GATED system clock (i_clk gated by a real ICG). Feeds
//                  CPU / RAM / peripherals; it is held during SERV sleep,
//                  exactly like the old "oscillator off" behaviour but
//                  glitch-free through a proper clock-gate cell.
//   o_rst        : reset synchronizer + stretcher, asserted async on i_rst,
//                  released synchronously to i_clk, held RESET_LENGTH cycles.
//   o_slow_tick  : single-cycle enable pulse (replaces the old slow LFOSC
//                  clock) for servant_slow_timer, now single-clock-domain.
//////////////////////////////////////////////////////////////////////////////

module clk_gen_wb #(
    parameter HFOSC        = "0b01", // kept for port-compat, unused on ASIC
    parameter RESET_LENGTH = 12,     // o_rst stretch, in i_clk cycles
    parameter SLOW_DIV     = 2400    // i_clk / SLOW_DIV = slow-tick rate
)(
    input             i_clk, i_rst,
    output            o_clk, o_slow_tick, o_rst,
    input             timer_irq,
    input      [31:0] i_wb_clkgen_adr,
    input      [31:0] i_wb_clkgen_dat,
    input             i_wb_clkgen_we,
    input             i_wb_clkgen_cyc,
    output reg [31:0] o_wb_clkgen_rdt,
    output reg        o_wb_clkgen_ack
);

    // ---------------------------------------------------------------------
    // RESET SYNCHRONIZER + STRETCHER  (runs on the always-on i_clk)
    //   Async assert on i_rst, synchronous release, held RESET_LENGTH cycles.
    //   No "initial" and no dependency on a clock that can stop.
    // ---------------------------------------------------------------------
    reg [RESET_LENGTH-1:0] rst_reg;
    always @(posedge i_clk or posedge i_rst)
        if (i_rst)
            rst_reg <= {RESET_LENGTH{1'b0}};
        else
            rst_reg <= {rst_reg[RESET_LENGTH-2:0], 1'b1};
    assign o_rst = ~rst_reg[RESET_LENGTH-1];

    // ---------------------------------------------------------------------
    // WAKE PATH : timer_irq resynchronized into the i_clk domain (2-FF).
    //   Replaces the old "always @(posedge timer_irq)" (data used as clock).
    // ---------------------------------------------------------------------
    reg irq_meta, irq_sync;
    always @(posedge i_clk) begin
        irq_meta <= timer_irq;
        irq_sync <= irq_meta;
    end

    // ---------------------------------------------------------------------
    // CLOCK-ENABLE / SLEEP CONTROL  (runs on i_clk)
    //   clk_en = 1 -> o_clk toggles ; clk_en = 0 -> o_clk held (SERV asleep).
    //   Firmware arms sleep by writing bit0 of the clkgen WB register; a
    //   timer interrupt (or reset) wakes the core back up.
    // ---------------------------------------------------------------------
    reg clk_en;
    reg gate_arm;
    always @(posedge i_clk)
        if (o_rst)
            clk_en <= 1'b1;
        else if (irq_sync)
            clk_en <= 1'b1;
        else if (gate_arm)
            clk_en <= 1'b0;

    // ---------------------------------------------------------------------
    // Wishbone register : arm sleep (write bit0) / read back gate state (bit0)
    // ---------------------------------------------------------------------
    always @(posedge i_clk)
        if (o_rst) begin
            gate_arm        <= 1'b0;
            o_wb_clkgen_rdt <= 32'b0;
        end else begin
            gate_arm <= 1'b0;
            if (i_wb_clkgen_cyc) begin
                o_wb_clkgen_rdt <= {31'b0, ~clk_en};
                if (i_wb_clkgen_we)
                    gate_arm <= i_wb_clkgen_dat[0];
            end
        end

    always @(posedge i_clk)
        if (o_rst)
            o_wb_clkgen_ack <= 1'b0;
        else
            o_wb_clkgen_ack <= i_wb_clkgen_cyc;

    // ---------------------------------------------------------------------
    // GATED SYSTEM CLOCK
    //   Cella di clock gating condivisa (std_cells/cells_clkgate.v): con
    //   `define OPENROAD_CLKGATE mappa sulla cella reale sg13g2_lgcp_1,
    //   altrimenti e' un pass-through (GCK = CK) -> in sim il clock NON viene
    //   gated e il core non dorme mai (funzionalmente equivalente).
    // ---------------------------------------------------------------------
    OPENROAD_CLKGATE u_icg (
        .CK  (i_clk),
        .E   (clk_en),
        .GCK (o_clk)
    );

    // ---------------------------------------------------------------------
    // SLOW TICK : prescaler on the always-on i_clk producing a single-cycle
    //   enable pulse. Replaces the LFOSC slow clock -> single clock domain,
    //   no fast/slow CDC. Stays alive during sleep to wake the core.
    // ---------------------------------------------------------------------
    localparam PW = (SLOW_DIV <= 2) ? 1 : $clog2(SLOW_DIV);
    reg [PW-1:0] slow_cnt;
    reg          slow_tick_r;
    always @(posedge i_clk)
        if (o_rst) begin
            slow_cnt    <= {PW{1'b0}};
            slow_tick_r <= 1'b0;
        end else if (slow_cnt == SLOW_DIV-1) begin
            slow_cnt    <= {PW{1'b0}};
            slow_tick_r <= 1'b1;
        end else begin
            slow_cnt    <= slow_cnt + 1'b1;
            slow_tick_r <= 1'b0;
        end
    assign o_slow_tick = slow_tick_r;

endmodule
