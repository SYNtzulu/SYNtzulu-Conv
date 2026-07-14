// Fake dual-port (1R + 1W) su singolo macro single-port RM_IHPSG13_1P_2048x64.
// 4 parole da 16 bit impacchettate in ogni riga da 64 bit -> 8192 parole in 2048 righe.
//
// Perche' basta un solo macro (niente ping-pong):
//   rd_cnt e wr_cnt hanno offset fisso di 5 (5 mod 4 = 1) in steady-state, quindi
//   il fetch di lettura (rd[1:0]==3) e il commit di scrittura (wr[1:0]==3) non
//   cadono mai sullo stesso ciclo -> un solo port serve entrambi i flussi.
//
// fix_cnt (salto all'indietro dei puntatori):
//   - SCRITTURA: la riga in accumulo puo' restare a meta'. Committo la riga corrente
//     al cambio riga usando il byte-mask A_BM (solo le lane "dirty") -> nessuna perdita.
//   - LETTURA: buffer_r diventa stale. Su fix_cnt (rden basso -> porta libera) faccio
//     un reload della riga target in buffer_r.

module ihp_fake_dualport #(
  parameter RAM_WIDTH = 4,
  parameter RAM_DEPTH = 64,
  parameter RAM_PERFORMANCE = "HIGH_PERFORMANCE",
  parameter INIT_FILE = ""
)
(
  input  [12:0] addra,     // indirizzo parola di SCRITTURA
  input  [12:0] addrb,     // indirizzo parola di LETTURA
  input  [15:0] dina,
  input         clk,
  input         wea,
  input         ena,
  input         enb,
  input         rst,
  input         regceb,
  input         pre_stb,   // = fix_cnt: richiedi il reload della riga di lettura
  input  [12:0] pre_addr,  // riga (parola) target di lettura dopo il salto
  output [15:0] doutb
);

  // ---- glue verso il macro ----
  wire [63:0] A_DOUT;
  reg  [63:0] A_DIN;
  reg  [63:0] A_BM;
  reg  [10:0] A_ADDR;
  wire        REN, WEN, MEN;

  // =====================================================================
  // SCRITTURA: accumulo per riga + commit al cambio riga (con byte-mask)
  // =====================================================================
  reg  [63:0] wrowbuf;      // lane accumulate della riga corrente
  reg  [3:0]  wdirty;       // quali lane sono state scritte
  reg  [10:0] cur_wrow;     // riga attualmente in accumulo
  reg         wrow_valid;   // cur_wrow contiene dati

  wire        wfire = ena && wea;
  wire [10:0] wrow  = addra[12:2];
  wire [1:0]  wlane = addra[1:0];

  wire same_row = wrow_valid && (wrow == cur_wrow);
  wire rowchg   = wfire && wrow_valid && (wrow != cur_wrow);              // nuova riga/salto -> flush della vecchia
  wire willfull = wfire && same_row && (&(wdirty | (4'b0001 << wlane)));  // completo la riga

  assign WEN = rowchg || willfull;

  // dato e maschera del commit
  always @(*) begin
    if (willfull) begin
      // riga piena: wrowbuf con la parola corrente inserita, mask = tutte
      A_DIN = wrowbuf;
      A_DIN[16*wlane +: 16] = dina;
      A_BM  = 64'hFFFF_FFFF_FFFF_FFFF;
    end else begin
      // flush parziale: solo le lane gia' scritte (le altre restano intatte nel macro)
      A_DIN = wrowbuf;
      A_BM  = { {16{wdirty[3]}}, {16{wdirty[2]}}, {16{wdirty[1]}}, {16{wdirty[0]}} };
    end
  end

  // aggiornamento accumulatore
  always @(posedge clk) begin
    if (rst) begin
      wrowbuf    <= 0;
      wdirty     <= 0;
      cur_wrow   <= 0;
      wrow_valid <= 0;
    end else if (wfire) begin
      if (!wrow_valid || rowchg) begin
        // primo write o riga nuova dopo un salto: riparto pulito con la parola corrente
        wrowbuf <= 64'b0;
        wrowbuf[16*wlane +: 16] <= dina;
        wdirty     <= (4'b0001 << wlane);
        cur_wrow   <= wrow;
        wrow_valid <= 1'b1;
      end else if (willfull) begin
        // riga completata e committata questo ciclo: riparto vuoto alla prossima
        wdirty     <= 4'b0;
        wrow_valid <= 1'b0;
      end else begin
        // stessa riga: aggiungo la lane corrente
        wrowbuf[16*wlane +: 16] <= dina;
        wdirty[wlane] <= 1'b1;
      end
    end
  end

  // =====================================================================
  // LETTURA: prefetch sequenziale (buffer_r) + reload su fix_cnt
  // =====================================================================
  reg  [63:0] buffer_r;
  reg         REN_D;                  // pipeline del REN combinato -> carica buffer_r
  reg         fsm_ren_d, fsm_ren_dd;  // pipeline del solo prefetch sequenziale -> override doutb
  reg  [15:0] out_buff_r;
  reg  [15:0] doutb_d;
  wire [10:0] read_addr;
  wire        fsm_ren;

  // richiesta di reload pendente (servita appena la porta e' libera da scritture)
  reg         reload_pend;
  reg  [10:0] reload_row;
  wire        reload_go = reload_pend & ~WEN;   // posso leggere solo se la scrittura non usa la porta

  always @(posedge clk) begin
    if (rst) begin
      reload_pend <= 1'b0;
      reload_row  <= 11'b0;
    end else if (pre_stb) begin
      reload_pend <= 1'b1;
      reload_row  <= pre_addr[12:2];
    end else if (reload_go) begin
      reload_pend <= 1'b0;
    end
  end

  fsm fsm_read(clk, rst, addra, addrb, enb, fsm_ren, read_addr);

  // il macro puo' fare 1 accesso/ciclo: la scrittura (WEN) ha priorita', la lettura
  // avviene solo se non c'e' scrittura. Grazie all'offset 5 le due non collidono in
  // steady-state; il reload cade quando rden e' basso, quindi trova la porta libera.
  assign REN = (fsm_ren | reload_pend) & ~WEN;
  assign MEN = REN | WEN;

  always @(*) begin
    if (WEN)
      A_ADDR = cur_wrow;              // commit/flush della riga di scrittura
    else if (reload_pend)
      A_ADDR = reload_row;            // reload forzato della riga target (fix_cnt)
    else
      A_ADDR = read_addr;            // prefetch sequenziale
  end

  always @(posedge clk) begin
    if (rst) begin
      REN_D      <= 1'b0;
      fsm_ren_d  <= 1'b0;
      fsm_ren_dd <= 1'b0;
    end else begin
      REN_D      <= REN;              // carica buffer_r sia su prefetch che su reload
      fsm_ren_d  <= fsm_ren & ~WEN;   // solo prefetch sequenziale -> override doutb
      fsm_ren_dd <= fsm_ren_d;
    end
  end

  always @(posedge clk) begin
    if (rst)
      buffer_r <= 64'b0;
    else if (REN_D)
      buffer_r <= A_DOUT;
  end

  always @(*) begin
    case (addrb[1:0])
      2'b00: out_buff_r = buffer_r[15:0];
      2'b01: out_buff_r = buffer_r[31:16];
      2'b10: out_buff_r = buffer_r[47:32];
      2'b11: out_buff_r = buffer_r[63:48];
    endcase
  end

  always @(posedge clk) begin
    if (rst)
      doutb_d <= 16'b0;
    else if (enb)
      doutb_d <= out_buff_r;
  end

  assign doutb = (fsm_ren_dd && enb) ? buffer_r[15:0] : doutb_d;

  // =====================================================================
  // Macro IHP single-port 2048x64
  // =====================================================================
  RM_IHPSG13_1P_2048x64_c2_bm_bist mem0(
      .A_CLK(clk),
      .A_MEN(MEN),
      .A_WEN(WEN),
      .A_REN(REN),
      .A_ADDR(A_ADDR),
      .A_DIN(A_DIN),
      .A_DLY(1'b0),
      .A_DOUT(A_DOUT),
      .A_BM(A_BM),

      .A_BIST_CLK(1'b0),
      .A_BIST_EN(1'b0),
      .A_BIST_MEN(1'b0),
      .A_BIST_WEN(1'b0),
      .A_BIST_REN(1'b0),
      .A_BIST_ADDR(1'b0),
      .A_BIST_DIN(1'b0),
      .A_BIST_BM(1'b0)
  );

endmodule



module fsm(
	input clk, rst,
	input [12:0] addra, addrb,
	input enb,
	output reg REN,
	output reg[10:0] read_addr
);

	parameter START = 0, WAIT = 1, WORK = 2;
	reg [1:0] state, state_nxt;

	wire check_r, check_w;

	assign check_r = (addrb == 0);
	assign check_w = (addra == 0);

	always@(posedge clk) begin
		if(rst)
			state <= START;
		else
			state <= state_nxt;
	end


	always@(*) begin
		case(state)
			START: state_nxt = WAIT;
			WAIT:  state_nxt = (check_r && check_w) ?  WAIT : WORK;
			WORK:  state_nxt = (check_r && check_w) ? START : WORK;
			default: state_nxt = START;
		endcase
	end

	always@(*) begin
		case(state)
			START:   begin read_addr = 0;               REN = 1;                           end
			WAIT:    begin read_addr = 0;               REN = 0;                           end
			WORK:    begin read_addr = addrb[12:2] + 1 ; REN = addrb[1] && addrb[0] && enb; end
			default: begin read_addr = 0;               REN = 0;	                        end
		endcase
	end
endmodule
