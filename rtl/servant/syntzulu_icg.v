`default_nettype none
//////////////////////////////////////////////////////////////////////////////
//  syntzulu_icg - integrated clock gate del SoC.
//
//  Un solo file per simulazione e sintesi, letto da entrambe (sta in
//  rtl/servant/, che compare sia nella riga iverilog del Makefile sia in
//  VERILOG_FILES di orfs_setup/soc/config_soc.mk).
//
//  PERCHE' NON SI CHIAMA PIU' OPENROAD_CLKGATE.
//  Quel nome e' di ORFS: synth_preamble.tcl legge sempre
//  platforms/ihp-sg13g2/cells_clkgate.v, che e' scritto cosi'
//
//      module OPENROAD_CLKGATE (CK, E, GCK);
//      `ifdef OPENROAD_CLKGATE
//        sg13g2_lgcp_1 latch (.CLK(CK), .GATE(E), .GCLK(GCK));
//      `else
//        assign GCK = CK;
//      `endif
//
//  e lo legge con un "read_verilog -defer" senza nessun -D. Il ramo che passa
//  e' quindi sempre il secondo: il gate spariva e la netlist sintetizzata
//  usciva con tutti e 4617 i flop appesi a i_clk. Non bastava definire
//  CLKGATE_MAP_FILE nel config del design, perche' il config.mk della
//  piattaforma lo riassegna con "=" DOPO (flow/Makefile:93 include il design,
//  scripts/variables.mk:51 include la piattaforma). Con un nome nostro il
//  problema non esiste: ORFS continua a definire il suo OPENROAD_CLKGATE,
//  inutilizzato, e noi istanziamo questo.
//
//  I DUE MODELLI.
//  In sintesi (nessuna define) si istanzia la cella vera. In simulazione, che
//  gira sempre con -DFUNCTIONAL, si usa il modello comportamentale: la cella
//  IHP e' scritta cosi'
//
//      wire delayed_GATE, delayed_CLK;
//      not (int_fwire_clk, delayed_CLK);
//      ihp_latch (int_fwire_int_GATE, notifier, int_fwire_clk, delayed_GATE);
//      and (GCLK, delayed_CLK, int_fwire_int_GATE);
//      `ifndef FUNCTIONAL
//      specify ... $setuphold (..., delayed_CLK, delayed_GATE); ... endspecify
//      `endif
//
//  e delayed_CLK / delayed_GATE non hanno driver propri: li pilota il
//  meccanismo dei delayed-net di $setuphold, che vive dentro lo specify. Con
//  -DFUNCTIONAL quello specify sparisce, le due wire restano scollegate e GCLK
//  esce X per sempre. (Nelle simulazioni di netlist la cella vera c'e' per
//  forza: per quelle il modello in std_cells/sg13g2_stdcell.v ha ora un
//  fallback che lega i delayed-net agli ingressi.)
//
//  NO_CLKGATE: bypass esplicito, GCK = CK, il core non dorme mai. E' il
//  comportamento con cui ha girato tutto fino alla variante 4, utile per
//  isolare il gating da un bug funzionale.
//////////////////////////////////////////////////////////////////////////////

module syntzulu_icg (
    input  wire CK,
    input  wire E,
    output wire GCK
);

`ifdef NO_CLKGATE

    assign GCK = CK;

`elsif FUNCTIONAL

    // Latch trasparente mentre CK e' basso: E puo' cambiare in qualunque
    // momento senza generare impulsi spuri sul clock gated.
    reg E_lat = 1'b1;
    always @(*)
        if (!CK)
            E_lat = E;

    assign GCK = CK & E_lat;

`else

    sg13g2_lgcp_1 u_lgcp (.CLK(CK), .GATE(E), .GCLK(GCK));

`endif

endmodule

`default_nettype wire
