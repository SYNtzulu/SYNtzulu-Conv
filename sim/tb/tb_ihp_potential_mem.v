`timescale 1ns/1ps
//============================================================================
// Testbench per ihp_potential_mem (fake dual-port su single-port 2048x64)
//
// Idea di debug:
//   - la RAM fisica viene PRE-CARICATA a valori noti via riferimento gerarchico
//     (parola all'indirizzo a  ==  a) -> in lettura doutb deve "seguire" addrb.
//   - un modello shadow model[] rispecchia il contenuto atteso e viene aggiornato
//     ad ogni commit/flush, cosi' il confronto e' automatico.
//
// Test:
//   1) lettura sequenziale dei valori pre-caricati
//   2) scrittura di righe COMPLETE via porta A + rilettura
//   3) fix_cnt a meta' riga (flush parziale con byte-mask) + rilettura
//
// Compilazione (dalla root del repo):
//   iverilog -g2012 -DFUNCTIONAL -o tb_mem.out \
//       sim/tb/tb_ihp_potential_mem.v \
//       rtl/memorie_ihp/dual_port_ihp.v \
//       rtl/behavioural_ihp/RM_IHPSG13_1P_2048x64_c2_bm_bist.v \
//       rtl/behavioural_ihp/RM_IHPSG13_1P_core_behavioral_bm_bist.v
//   vvp tb_mem.out
//============================================================================
module tb_ihp_potential_mem;

	// ---- segnali verso il DUT ----
	reg         clk = 0;
	reg         rst = 1;
	reg  [12:0] addra = 0;
	reg  [12:0] addrb = 0;
	reg  [15:0] dina  = 0;
	reg         wea = 0, ena = 0, enb = 0, regceb = 1;
	reg         fix_cnt = 0;
	wire [15:0] doutb;
	wire        wen_fsm;

	// ---- modello di riferimento (word-addressed) ----
	reg  [15:0] model [0:8191];

	integer errors = 0, checks = 0;
	integer i;

	// clock 10 ns
	always #5 clk = ~clk;

	// path gerarchico all'array fisico da 64 bit
	// dut.mem0.i_SRAM_1P_behavioral_bm_bist.memory[row]

	ihp_potential_mem dut (
		.addra(addra), .addrb(addrb), .dina(dina), .clk(clk),
		.wea(wea), .ena(ena), .enb(enb), .rst(rst), .regceb(regceb),
		.doutb(doutb), .fix_cnt(fix_cnt), .wen_fsm(wen_fsm)
	);

	//------------------------------------------------------------------
	// Pre-carico RAM fisica + modello con valori noti: word(a) = a
	//   memory[r] = { word(4r+3), word(4r+2), word(4r+1), word(4r+0) }
	//   lane0 -> [15:0], lane1 -> [31:16], lane2 -> [47:32], lane3 -> [63:48]
	//------------------------------------------------------------------
	task preload_known;
		integer r, a;
		begin
			for (r = 0; r < 2048; r = r + 1) begin
				dut.mem0.i_SRAM_1P_behavioral_bm_bist.memory[r] = {
					{3'b0, 13'(4*r+3)},
					{3'b0, 13'(4*r+2)},
					{3'b0, 13'(4*r+1)},
					{3'b0, 13'(4*r+0)} };
			end
			for (a = 0; a < 8192; a = a + 1)
				model[a] = a[15:0];
		end
	endtask

	//------------------------------------------------------------------
	// Scrittura di una riga COMPLETA (4 lane consecutive -> commit pieno)
	//------------------------------------------------------------------
	task write_full_row(input integer r,
	                    input [15:0] d0, input [15:0] d1,
	                    input [15:0] d2, input [15:0] d3);
		begin
			@(negedge clk); ena=1; wea=1; addra = 4*r+0; dina = d0;
			@(negedge clk);              addra = 4*r+1; dina = d1;
			@(negedge clk);              addra = 4*r+2; dina = d2;
			@(negedge clk);              addra = 4*r+3; dina = d3; // commit al prox fronte
			@(negedge clk); ena=0; wea=0; addra = 0; dina = 0;
			model[4*r+0]=d0; model[4*r+1]=d1; model[4*r+2]=d2; model[4*r+3]=d3;
			$display("[WRITE] riga %0d completa: %h %h %h %h", r, d0,d1,d2,d3);
		end
	endtask

	//------------------------------------------------------------------
	// Scrittura PARZIALE (2 lane) + fix_cnt -> flush con byte-mask
	//------------------------------------------------------------------
	task write_partial_flush(input integer r,
	                         input [15:0] d0, input [15:0] d1);
		begin
			@(negedge clk); ena=1; wea=1; addra = 4*r+0; dina = d0; // lane0
			@(negedge clk);              addra = 4*r+1; dina = d1; // lane1 (niente lane2/3 -> no commit)
			@(negedge clk); ena=0; wea=0; dina = 0;
			// fix_cnt con addra dentro la riga r: latcha flush_row=r, flush_mask=0011
			addra = 4*r+1; fix_cnt = 1;
			@(negedge clk); fix_cnt = 0; addra = 0;
			// attendo il flush: WAIT (REN=fix_cnt_d) -> FLUSH (wen_fsm) -> write fisica
			repeat (6) @(negedge clk);
			model[4*r+0]=d0; model[4*r+1]=d1;   // solo lane0/1; lane2/3 restano pre-caricate
			$display("[FLUSH] riga %0d parziale: lane0=%h lane1=%h (lane2/3 preservate)", r, d0, d1);
		end
	endtask

	//------------------------------------------------------------------
	// Rilettura sequenziale 0..n-1 con confronto vs model[]
	//  - reset breve per ri-innescare il prefetch (la RAM fisica NON si resetta)
	//  - latenza attesa: 1 ciclo (doutb del ciclo dopo l'indirizzo)
	//------------------------------------------------------------------
	task read_and_check(input integer n, input integer warmup);
		integer k;
		reg [12:0] a;
		begin
			// re-prime
			@(negedge clk); rst=1; enb=0; wea=0; ena=0; addra=0; addrb=0; dina=0; fix_cnt=0;
			@(negedge clk);
			@(negedge clk); rst=0;
			@(negedge clk);            // START: prefetch riga 0
			@(negedge clk);            // buffer_r carica riga 0
			enb = 1;
			addrb = 0;
			@(negedge clk);            // presento addr 0
			$display("[READ ] sweep 0..%0d", n-1);
			for (k = 0; k < n; k = k + 1) begin
				a = k[12:0];
				@(posedge clk); #1;    // doutb ora riflette addr = a
				checks = checks + 1;
				if (doutb !== model[a]) begin
					if (k < warmup) begin
						$display("   [warm] addr=%0d got=%h exp=%h (startup, ignorato)", a, doutb, model[a]);
					end else begin
						errors = errors + 1;
						$display("   [FAIL] addr=%0d got=%h exp=%h", a, doutb, model[a]);
					end
				end else begin
					$display("   [ ok ] addr=%0d got=%h exp=%h", a, doutb, model[a]);
				end
				@(negedge clk); addrb = (k+1) < n ? (k+1) : 0;  // presento il prossimo
			end
			enb = 0; addrb = 0;
		end
	endtask

	//------------------------------------------------------------------
	// Sequenza principale
	//------------------------------------------------------------------
	initial begin
		$dumpfile("tb_ihp_potential_mem.vcd");
		$dumpvars(0, tb_ihp_potential_mem);

		// reset iniziale
		rst=1; enb=0; wea=0; ena=0; addra=0; addrb=0; dina=0; fix_cnt=0;
		#12;                 // oltre il time-0: le initial interne (zero-init) sono gia' passate
		preload_known;       // carico valori noti nella RAM fisica + modello
		repeat (2) @(negedge clk);
		rst=0;

		$display("\n===== TEST 1: lettura valori pre-caricati =====");
		read_and_check(32, 2);

		$display("\n===== TEST 2: scrittura righe complete + rilettura =====");
		write_full_row(2, 16'hA008, 16'hA009, 16'hA00A, 16'hA00B); // addr 8..11
		write_full_row(3, 16'hA00C, 16'hA00D, 16'hA00E, 16'hA00F); // addr 12..15
		read_and_check(16, 2);

		$display("\n===== TEST 3: fix_cnt a meta' riga (flush parziale) =====");
		write_partial_flush(4, 16'hB010, 16'hB011);                // addr 16,17 ; 18,19 restano 18,19
		read_and_check(20, 2);

		$display("\n===================================================");
		if (errors == 0)
			$display(" RISULTATO: PASS  (%0d controlli, 0 errori)", checks);
		else
			$display(" RISULTATO: FAIL  (%0d controlli, %0d errori)", checks, errors);
		$display("===================================================\n");
		$finish;
	end

	// timeout di sicurezza
	initial begin
		#200000;
		$display("TIMEOUT");
		$finish;
	end

endmodule
