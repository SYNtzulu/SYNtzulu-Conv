
// ihp_ram: 1024 x 32-bit CPU RAM built from TWO 1024x16 IHP macros side by side.
//
// Was a single RM_IHPSG13_1P_1024x64: the CPU word is only 32 bit (we[3:0] =
// 4 byte-enables), so the upper 32 bit of the 64-bit macro were never written
// -> half the macro (32 Kbit) wasted. Two 1024x16 macros give exactly 1024x32.
//
//   ram_lo -> bits [15:0]  (bytes 0,1 -> we[0],we[1])
//   ram_hi -> bits [31:16] (bytes 2,3 -> we[2],we[3])
//
// INIT: the firmware exe.hex is 32-bit/word, so it is split into two 16-bit
// hex files (firmware/exe_lo.hex = bits[15:0], firmware/exe_hi.hex = bits[31:16])
// and each half inits its bank. See firmware/Makefile (split-hex step).
//
// Ports are unchanged (dina/dout stay [63:0]; only [31:0] are meaningful).

module ihp_ram # (
	parameter memfile    = "",   // kept for compatibility (unused for init)
	parameter memfile_lo = "",   // ASIC: nessun init da file, il firmware
	parameter memfile_hi = ""    //       arriva via SPI (porta boot_*)
)
(
	input wire clk,
	input wire [3:0] we,
	input wire [9:0] addr,
	input wire [63:0] dina,
	output wire [63:0] dout,
	input wire enb_debug,

	// porta di scrittura boot: il SPI-slave carica qui il firmware (32-bit/word)
	// prima che la CPU salti in RAM. A boot la CPU non accede alla RAM -> nessun
	// conflitto; la porta boot ha priorita' sulla porta CPU.
	input wire        boot_wen,
	input wire [9:0]  boot_addr,
	input wire [31:0] boot_data
);

	wire wea = (|we);

	// bitmask per-byte (1 = scrivi): COMBINATORIA, cosi' e' allineata a
	// we/eff_wen nello stesso ciclo. Prima era un blocco @(posedge clk): le
	// maschere erano flop mentre A_WEN e' combinatorio, quindi sul primo
	// fronte di ogni scrittura la macro usava la maschera della transazione
	// precedente (in sim il blocking mascherava il problema con una race).
	wire [7:0] B1 = we[0] ? 8'hFF : 8'h00;
	wire [7:0] B2 = we[1] ? 8'hFF : 8'h00;
	wire [7:0] B3 = we[2] ? 8'hFF : 8'h00;
	wire [7:0] B4 = we[3] ? 8'hFF : 8'h00;

	// mask a 16 bit per ciascun banco
	wire [15:0] BM_lo = {B2, B1};   // bytes 1,0 -> [15:0]
	wire [15:0] BM_hi = {B4, B3};   // bytes 3,2 -> [31:16]

	// mux porta CPU / porta boot (boot ha priorita')
	wire        eff_wen  = boot_wen | wea;
	wire [9:0]  eff_addr = boot_wen ? boot_addr        : addr;
	wire [15:0] din_lo   = boot_wen ? boot_data[15:0]  : dina[15:0];
	wire [15:0] din_hi   = boot_wen ? boot_data[31:16] : dina[31:16];
	wire [15:0] bm_lo    = boot_wen ? 16'hFFFF         : BM_lo;
	wire [15:0] bm_hi    = boot_wen ? 16'hFFFF         : BM_hi;

	wire [15:0] dout_lo, dout_hi;
	assign dout = {32'b0, dout_hi, dout_lo};

	// banco basso: bit [15:0]
	// INIT_FILE esiste solo sul modello comportamentale (rtl/behavioural_ihp);
	// in sintesi la macro e' una blackbox da liberty e non ha parametri, quindi
	// l'override va omesso testualmente.
	RM_IHPSG13_1P_1024x16_c2_bm_bist
`ifdef SIM
	#(.INIT_FILE(memfile_lo))
`endif
	ram_lo (
	    .A_CLK(clk),
	    .A_MEN(enb_debug),
	    .A_WEN(eff_wen),
	    .A_REN(enb_debug),
	    .A_ADDR(eff_addr),
	    .A_DIN(din_lo),
	    .A_DLY(1'b0),
	    .A_DOUT(dout_lo),
	    .A_BM(bm_lo),
	    .A_BIST_CLK(1'b0),
	    .A_BIST_EN(1'b0),
	    .A_BIST_MEN(1'b0),
	    .A_BIST_WEN(1'b0),
	    .A_BIST_REN(1'b0),
	    .A_BIST_ADDR(10'b0),
	    .A_BIST_DIN(16'b0),
	    .A_BIST_BM(16'b0)
	);

	// banco alto: bit [31:16]
	RM_IHPSG13_1P_1024x16_c2_bm_bist
`ifdef SIM
	#(.INIT_FILE(memfile_hi))
`endif
	ram_hi (
	    .A_CLK(clk),
	    .A_MEN(enb_debug),
	    .A_WEN(eff_wen),
	    .A_REN(enb_debug),
	    .A_ADDR(eff_addr),
	    .A_DIN(din_hi),
	    .A_DLY(1'b0),
	    .A_DOUT(dout_hi),
	    .A_BM(bm_hi),
	    .A_BIST_CLK(1'b0),
	    .A_BIST_EN(1'b0),
	    .A_BIST_MEN(1'b0),
	    .A_BIST_WEN(1'b0),
	    .A_BIST_REN(1'b0),
	    .A_BIST_ADDR(10'b0),
	    .A_BIST_DIN(16'b0),
	    .A_BIST_BM(16'b0)
	);

endmodule
