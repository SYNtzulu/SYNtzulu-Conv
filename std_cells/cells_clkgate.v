//////////////////////////////////////////////////////////////////////////////
//  OPENROAD_CLKGATE - modello di simulazione dell'integrated clock gate.
//
//  Questo file e' SOLO per la simulazione: in sintesi ORFS legge il proprio
//  platforms/ihp-sg13g2/cells_clkgate.v (CLKGATE_MAP_FILE), non questo.
//
//  PERCHE' NON SI ISTANZIA sg13g2_lgcp_1 QUI.
//  La cella IHP e' scritta cosi':
//
//      wire delayed_GATE, delayed_CLK;
//      not (int_fwire_clk, delayed_CLK);
//      ihp_latch (int_fwire_int_GATE, notifier, int_fwire_clk, delayed_GATE);
//      and (GCLK, delayed_CLK, int_fwire_int_GATE);
//      `ifndef FUNCTIONAL
//      specify ... $setuphold (..., delayed_CLK, delayed_GATE); ... endspecify
//      `endif
//
//  delayed_CLK e delayed_GATE non hanno driver propri: le pilota il meccanismo
//  dei delayed-net di $setuphold, che vive dentro lo specify. Tutte le
//  simulazioni di questo repo girano con -DFUNCTIONAL, che quello specify lo
//  cancella, quindi le due wire restano scollegate e GCLK esce X per sempre.
//  Verificato a parte: con -DFUNCTIONAL la cella da' GCK = x a ogni fronte, e
//  di conseguenza wb_clk = x e il SoC non parte.
//
//  Il modello qui sotto e' funzionalmente la stessa cella - latch di E sulla
//  fase bassa di CK, GCK = CK & E_latched - ma non dipende dallo specify.
//////////////////////////////////////////////////////////////////////////////
module OPENROAD_CLKGATE (CK, E, GCK);
  input CK;
  input E;
  output GCK;

`ifdef OPENROAD_CLKGATE

  // Latch trasparente mentre CK e' basso: E puo' cambiare in qualunque momento
  // senza generare impulsi spuri sul clock gated.
  reg E_lat = 1'b1;
  always @(*)
    if (!CK)
      E_lat = E;

  assign GCK = CK & E_lat;

`else

  // Senza la define il gate non esiste e il core non dorme mai: e' il
  // comportamento con cui ha girato tutto fino alla variante 4.
  assign GCK = CK;

`endif

endmodule
