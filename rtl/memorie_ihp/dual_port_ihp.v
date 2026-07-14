module ihp_potential_mem #(
  parameter RAM_WIDTH = 4,
  parameter RAM_DEPTH = 64,
  parameter RAM_PERFORMANCE = "HIGH_PERFORMANCE",
  parameter INIT_FILE = ""
)
(
  input [12:0] addra,
  input [12:0] addrb,
  input [15:0] dina,
  input clk,
  input wea,
  input ena,
  input enb,
  input rst,
  input regceb,

  output [15:0] doutb,


  input fix_cnt,
  output wen_fsm
);

	wire [63:0] A_DOUT, A_DIN, A_BM;
	wire REN, WEN, MEN;
	reg [10:0] A_ADDR;
	// wen_fsm e' ora una porta di output del modulo (dal fsm_write: alto SOLO nel ciclo di flush parziale)
	reg [10:0] flush_row;      // riga fisica catturata al fronte di fix_cnt (vedi WRITE LOGIC)

	//assign REN = addrb[1] && addrb[0] && enb;
	assign WEN = (addra[1] && addra[0] && ena && wea) || wen_fsm;
	assign MEN = REN || WEN;

	always@(*) begin
		if (wen_fsm)
			A_ADDR = flush_row;        // flush parziale -> riga PRE-salto latchata
		else if (WEN)
			A_ADDR = addra[12:2];      // commit pieno -> riga corrente
		else
			A_ADDR = read_addr;        // lettura (prefetch fsm_read)
	end



	//READ LOGIC

	reg [63:0] buffer_r;
	reg REN_D, REN_DD;
	reg [15:0] out_buff_r;
	reg [15:0] doutb_d;
	wire [10:0] read_addr;
	wire REN_FSM;
	reg fix_cnt_d;

	always@(posedge clk or posedge rst) begin
		if(rst)
			fix_cnt_d <= 0;
		else
			fix_cnt_d <= fix_cnt;
	end

	assign REN = REN_FSM || fix_cnt_d;

	fsm_read fsm_read_i
	(
		.clk(clk),
		.rst(rst),
		.addra(addra),
		.addrb(addrb),
		.enb(enb),
		.fix_cnt_d(fix_cnt_d),
		.REN(REN_FSM),
		.read_addr(read_addr)
	);

	always@(posedge clk) begin
		if(rst) begin
			REN_D  <= 0;
			REN_DD <= 0;
		end
		else begin
			REN_D  <= REN;
			REN_DD <= REN_D;
		end
	end

	always@(posedge clk) begin
		if(rst)
			buffer_r <= 0;
		else if (REN_D)
			buffer_r <= A_DOUT;
	end

	always@(*) begin
		case(addrb[1:0])
			2'b00: out_buff_r = buffer_r[15:0];
			2'b01: out_buff_r = buffer_r[31:16];
			2'b10: out_buff_r = buffer_r[47:32];
			2'b11: out_buff_r = buffer_r[63:48];
		endcase
	end

	always@(posedge clk) begin
		if(rst)
			doutb_d <= 0;
		else if (enb)
			doutb_d <= out_buff_r;
	end

	assign doutb = (REN_DD ) ? buffer_r[15:0] : doutb_d;

	//WRITE LOGIC  --  row buffer per-lane + flush parziale su fix_cnt

	reg [15:0] row0, row1, row2, row3;   // una parola per lane (0..3)
	reg [3:0]  dirty;                     // lane scritte dall'ultimo commit

	wire       wfire      = ena && wea;
	wire [1:0] wlane      = addra[1:0];
	wire       commit_now = wfire && (wlane == 2'b11);   // = commit pieno (vecchio WEN)

	// accumulo per-lane: sul commit pieno equivale a {dina,buffer_w0,buffer_w1,buffer_w2}
	always@(posedge clk) begin
		if(rst) begin
			row0 <= 0; row1 <= 0; row2 <= 0; row3 <= 0;
		end
		else if (wfire) begin
			case (wlane)
				2'b00: row0 <= dina;
				2'b01: row1 <= dina;
				2'b10: row2 <= dina;
				2'b11: row3 <= dina;
			endcase
		end
	end

	// maschera delle lane "pending": set su ogni write, azzerata al commit e ad ogni fix_cnt
	always@(posedge clk) begin
		if(rst)              dirty <= 4'b0;
		else if (commit_now) dirty <= 4'b0;   // riga completa committata -> pulita
		else if (fix_cnt)    dirty <= 4'b0;   // dopo il salto riparto sulla riga nuova
		else if (wfire)      dirty[wlane] <= 1'b1;
	end

	// stato "effettivo" comprensivo dell'eventuale scrittura di QUESTO ciclo
	// (se fix_cnt non coincide mai con una write, dirty_eff==dirty e lN==rowN)
	wire [3:0]  dirty_eff = commit_now ? 4'b0
	                      : wfire      ? (dirty | (4'b0001 << wlane))
	                      :               dirty;
	wire [15:0] l0 = (wfire && wlane == 2'b00) ? dina : row0;
	wire [15:0] l1 = (wfire && wlane == 2'b01) ? dina : row1;
	wire [15:0] l2 = (wfire && wlane == 2'b10) ? dina : row2;
	wire [15:0] l3 = (wfire && wlane == 2'b11) ? dina : row3;

	// cattura FLIP-FLOP (enable = fix_cnt, NON un latch): congela cosa flushare,
	// perche' wen_fsm arriva parecchi cicli dopo fix_cnt.
	reg [63:0] flush_din;
	reg [3:0]  flush_mask;
	always@(posedge clk) begin
		if(rst) begin
			flush_din  <= 0;
			flush_mask <= 0;
			flush_row  <= 0;
		end
		else if (fix_cnt) begin
			flush_din  <= {l3, l2, l1, l0};   // riga PRE-salto, gia' allineata per lane
			flush_mask <= dirty_eff;          // quali/quante lane sono pending
			flush_row  <= addra[12:2];        // riga fisica pre-salto
		end
	end

	// dato: flush parziale (latchato) oppure commit pieno (live, lane3 da dina)
	assign A_DIN = wen_fsm ? flush_din
	                       : {dina, row2, row1, row0};

	// byte-mask: scrivo SOLO le lane effettivamente toccate in questo pass, le altre
	// restano intatte nel macro (necessario: con i salti di fix_cnt la stessa riga puo'
	// ricevere lane diverse in pass diversi -> all-ones cancellerebbe le lane precedenti).
	//  - flush : lane pending latchate (flush_mask)
	//  - commit: lane accumulate (dirty) + lane3, che sto scrivendo ora da dina
	//            (riga sequenziale completa: dirty=0111 -> mask=1111 = come prima)
	wire [3:0] commit_mask = dirty | 4'b1000;
	assign A_BM  = wen_fsm ? {{16{flush_mask[3]}},  {16{flush_mask[2]}},  {16{flush_mask[1]}},  {16{flush_mask[0]}}}
	                       : {{16{commit_mask[3]}}, {16{commit_mask[2]}}, {16{commit_mask[1]}}, {16{commit_mask[0]}}};

	fsm_write fsm_write_i
	(
		.clk(clk),
		.rst(rst),
		.fix_cnt(fix_cnt),
		.REN(REN),
		.wen_fsm(wen_fsm)
	);


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



module fsm_read(
	input clk, rst,
	input [12:0] addra, addrb,
	input enb,
	input fix_cnt_d,
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
			START:   begin read_addr = 0;                REN = 1;                           end
			WAIT:    begin read_addr = 0;                REN = 0;                           end
			WORK:    begin read_addr = addrb[12:2] + (1'b1 - fix_cnt_d) ; REN = addrb[1] && addrb[0] && enb; end
			default: begin read_addr = 0;                REN = 0;                           end
		endcase
	end
endmodule



module fsm_write(
	input clk, rst, fix_cnt, REN,
	output wen_fsm
);
	parameter START = 0, WAIT = 1, FLUSH = 2;
	reg [1:0] state, state_nxt;

	always@(posedge clk) begin
		if(rst)
			state <= START;
		else
			state <= state_nxt;
	end


	always@(*) begin
		case(state)
			START:   state_nxt   = fix_cnt ? WAIT  : START ;
			WAIT:    state_nxt   = REN     ? FLUSH :  WAIT ;
			FLUSH:   state_nxt   = START                   ;
			default: state_nxt   = START                   ;
		endcase
	end

	assign wen_fsm = (state == FLUSH) ? 1 : 0;

endmodule
