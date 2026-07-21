`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: IHP3_singlePort_readFirst
//
// Descrizione:
//   Wrapper con la STESSA interfaccia di BRAM_singlePort_readFirst, ma costruito
//   con N_BANK SRAM IHP da 256x64 (RM_IHPSG13_1P_256x64_c2_bm_bist).
//
//   PACKING: ogni riga da 64 bit contiene LANES = 64/RAM_WIDTH parole.
//   Con RAM_WIDTH=16 -> LANES=4 (4 parole da 2 byte per riga, tutti gli 8 byte usati).
//
//   Decodifica indirizzo a due livelli:
//        banco    = addr % N_BANK              (1a selezione: quale banco)
//        word_idx = addr / N_BANK              (parola dentro al banco)
//          riga  = word_idx / LANES           (2a selezione: quale riga da 64 bit)
//          lane  = word_idx % LANES           (2a selezione: posizione nella riga)
//   Lane j occupa i bit [RAM_WIDTH*j +: RAM_WIDTH] della parola da 64 bit.
//
//   SCRITTURA: si usa la byte-mask A_BM del macro per scrivere SOLO i bit della
//   lane target -> niente read-modify-write, le altre lane restano intatte.
//   LETTURA: si legge tutta la riga da 64 bit e si seleziona la lane (ritardata
//   di 1 ciclo per allinearsi ad A_DOUT).
//
//   COLLISIONI (SRAM single-port): un banco fa 1 solo accesso/ciclo. Se write e
//   read cadono sullo stesso banco (addra%N == addrb%N) la scrittura ha priorita'
//   e la lettura viene persa. Con offset costante 'k' tra i puntatori la
//   collisione e' sistematica sse (k mod N == 0): scegliere N che NON divide
//   l'offset. Un $display di WARNING (solo simulazione) segnala ogni collisione.
//
//   Dinamica IDENTICA a BRAM_singlePort_readFirst:
//     - la SRAM IHP ha lettura registrata (A_DOUT valido 1 ciclo dopo REN),
//       equivalente allo stadio ram_data_b della BRAM.
//     - LOW_LATENCY      -> 1 ciclo di latenza (nessun registro d'uscita)
//     - HIGH_PERFORMANCE -> 2 cicli di latenza (registro d'uscita + regceb/rst)
//////////////////////////////////////////////////////////////////////////////////

module IHP3_singlePort_readFirst #(
  parameter RAM_WIDTH       = 16,                 // larghezza parola (deve dividere 64)
  parameter RAM_DEPTH       = 6144,               // solo per la larghezza indirizzo
  parameter RAM_PERFORMANCE = "HIGH_PERFORMANCE", // "HIGH_PERFORMANCE" o "LOW_LATENCY"
  parameter INIT_FILE       = "",                 // vedi nota init in fondo
  parameter N_BANK          = 6                   // numero di banchi interleaved
)
(
  input  [clogb2(RAM_DEPTH-1)-1:0] addra,  // indirizzo di scrittura (porta A)
  input  [clogb2(RAM_DEPTH-1)-1:0] addrb,  // indirizzo di lettura   (porta B)
  input  [RAM_WIDTH-1:0]           dina,   // dato in ingresso
  input                            clk,
  input                            wea,    // write enable
  input                            ena,    // enable porta A (scrittura)
  input                            enb,    // enable porta B (lettura)
  input                            rst,    // reset del registro d'uscita
  input                            regceb, // output register enable
  output [RAM_WIDTH-1:0]           doutb   // dato in uscita
);

  localparam MEM_ROWS = 256;               // righe fisiche del macro (256x64)
  localparam ROWW  = clogb2(MEM_ROWS-1);   // larghezza indirizzo riga del macro (=8)
  localparam LANES = 64 / RAM_WIDTH;       // parole per riga (=4 con RAM_WIDTH=16)
  localparam LANEW = clogb2(LANES-1);      // bit per indicizzare la lane
  localparam BANKW = clogb2(N_BANK-1);     // bit per indicizzare i banchi
  localparam ADDRW = clogb2(RAM_DEPTH-1);  // larghezza indirizzo

  // -------------------------------------------------------------------------
  // Decodifica indirizzi
  //   banco -> word_idx nel banco -> riga + lane
  // -------------------------------------------------------------------------
  wire [BANKW-1:0] wbank = addra % N_BANK;
  wire [BANKW-1:0] rbank = addrb % N_BANK;
  wire [ADDRW-1:0] wword = addra / N_BANK;   // parola dentro al banco (scrittura)
  wire [ADDRW-1:0] rword = addrb / N_BANK;   // parola dentro al banco (lettura)

  wire [ROWW-1:0]  wrow  = wword / LANES;     // riga fisica (0..255)
  wire [ROWW-1:0]  rrow  = rword / LANES;
  wire [LANEW-1:0] wlane = wword % LANES;     // lane dentro la riga
  wire [LANEW-1:0] rlane = rword % LANES;

  // maschera di scrittura: RAM_WIDTH bit a 1 in corrispondenza della lane target
  wire [63:0] lane_mask = { {(64-RAM_WIDTH){1'b0}}, {RAM_WIDTH{1'b1}} } << (RAM_WIDTH * wlane);

  // -------------------------------------------------------------------------
  // WARNING (solo simulazione): write e read sullo stesso banco -> lettura persa
  // -------------------------------------------------------------------------
  // synthesis translate_off
  always @(posedge clk)
    if (!rst && ena && wea && enb && (wbank == rbank))
      $display("[%0t] WARNING IHP3_singlePort_readFirst: collisione banco %0d - write addr=%0d, read addr=%0d -> lettura persa",
               $time, wbank, addra, addrb);
  // synthesis translate_on

  // -------------------------------------------------------------------------
  // N_BANK banchi SRAM IHP 2048x64
  // -------------------------------------------------------------------------
  wire [63:0] A_DOUT [0:N_BANK-1];

  genvar i;
  generate
    for (i = 0; i < N_BANK; i = i + 1) begin : bank

      // scrittura su questo banco
      wire wr_i = ena && wea && (wbank == i);
      // lettura su questo banco (la scrittura ha priorita': la SRAM e' single-port)
      wire rd_i = enb && (rbank == i) && !wr_i;

      wire            A_MEN_i  = wr_i || rd_i;
      wire            A_WEN_i  = wr_i;
      wire            A_REN_i  = rd_i;
      wire [ROWW-1:0] A_ADDR_i = wr_i ? wrow : rrow;
      // dina replicato su tutte le lane: la A_BM seleziona quella giusta
      wire [63:0] A_DIN_i  = {LANES{dina}};
      wire [63:0] A_BM_i   = lane_mask;   // usata solo quando A_WEN_i=1

      RM_IHPSG13_1P_256x64_c2_bm_bist mem_i (
        .A_CLK      (clk),
        .A_MEN      (A_MEN_i),
        .A_WEN      (A_WEN_i),
        .A_REN      (A_REN_i),
        .A_ADDR     (A_ADDR_i),
        .A_DIN      (A_DIN_i),
        .A_DLY      (1'b0),
        .A_DOUT     (A_DOUT[i]),
        .A_BM       (A_BM_i),
        .A_BIST_CLK (1'b0),
        .A_BIST_EN  (1'b0),
        .A_BIST_MEN (1'b0),
        .A_BIST_WEN (1'b0),
        .A_BIST_REN (1'b0),
        .A_BIST_ADDR(8'b0),
        .A_BIST_DIN (64'b0),
        .A_BIST_BM  (64'b0)
      );
    end
  endgenerate

  // -------------------------------------------------------------------------
  // Selezione dell'uscita: A_DOUT valido 1 ciclo dopo la lettura, quindi banco
  // E lane vanno ritardati di 1 ciclo (aggiornati con enb, come lo stadio
  // ram_data_b <= ram[addrb] della BRAM).
  // -------------------------------------------------------------------------
  reg [BANKW-1:0] rbank_d;
  reg [LANEW-1:0] rlane_d;
  always @(posedge clk)
    if (enb) begin
      rbank_d <= rbank;
      rlane_d <= rlane;
    end

  // riga da 64 bit del banco letto -> estrai la lane selezionata
  wire [63:0]          row_data_b = A_DOUT[rbank_d];
  wire [RAM_WIDTH-1:0] ram_data_b = row_data_b[RAM_WIDTH*rlane_d +: RAM_WIDTH];

  // -------------------------------------------------------------------------
  // Stadio d'uscita: stessa struttura di BRAM_singlePort_readFirst
  // -------------------------------------------------------------------------
  generate
    if (RAM_PERFORMANCE == "LOW_LATENCY") begin: no_output_register

      // 1 ciclo di latenza
      assign doutb = ram_data_b;

    end else begin: output_register

      // 2 cicli di latenza (registro d'uscita con rst/regceb)
      reg [RAM_WIDTH-1:0] doutb_reg = {RAM_WIDTH{1'b0}};

      always @(posedge clk or posedge rst)
        if (rst)
          doutb_reg <= {RAM_WIDTH{1'b0}};
        else if (regceb)
          doutb_reg <= ram_data_b;

      assign doutb = doutb_reg;

    end
  endgenerate

  // Larghezza indirizzo dalla profondita' della RAM
  function integer clogb2;
    input integer depth;
      for (clogb2 = 0; depth > 0; clogb2 = clogb2 + 1)
        depth = depth >> 1;
  endfunction

  // -------------------------------------------------------------------------
  // NOTA su INIT_FILE:
  //   Con interleaving sui banchi + packing sulle lane, un singolo file .hex non
  //   mappa 1:1 sui banchi. Il parametro e' mantenuto solo per compatibilita' di
  //   interfaccia e non e' collegato.
  // -------------------------------------------------------------------------

endmodule
